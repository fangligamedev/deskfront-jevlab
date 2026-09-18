#!/usr/bin/env python3
"""MIT. Loopback-only control plane; Godot is the only simulation authority."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import argparse, json, time, threading, uuid, collections, urllib.parse, math

ROOT=Path(__file__).resolve().parents[1]
ALLOWED={'control','move','capture','flank','cover','hold','retreat','attack','pause','speed','camera','reinforce','config','reset','map','equip','grenade','posture','man_at_gun','leave_gun','garrison','leave_building'}
TACTICS={'move','capture','flank','cover','hold','retreat','attack','grenade','posture','man_at_gun','leave_gun','garrison','leave_building'}
TEAMS={'green','blue','red'}

def validate_command(c, agent=False):
    if not isinstance(c,dict):return 'command_must_be_object'
    if c.get('action') not in (TACTICS if agent else ALLOWED):return 'unknown_or_forbidden_action'
    if c.get('faction','green') not in TEAMS:return 'unknown_faction'
    if 'unit_ids' in c and (not isinstance(c['unit_ids'],list) or len(c['unit_ids'])>10 or not all(isinstance(x,str) for x in c['unit_ids'])):return 'invalid_unit_ids'
    if 'position' in c:
        p=c['position']
        if not isinstance(p,list) or len(p)!=2 or not all(type(x) in (int,float) and math.isfinite(x) for x in p):return 'invalid_position'
    if c['action']=='move' and 'position' not in c:return 'position_required'
    if c['action'] in {'speed','config'} and (type(c.get('value')) not in (int,float) or not math.isfinite(c['value'])):return 'invalid_value'
    if c['action']=='pause' and 'value' in c and type(c['value']) is not bool:return 'invalid_pause'
    if c['action']=='control' and c.get('mode') not in {'game_ai','player','agent','lm'}:return 'invalid_mode'
    if 'floor' in c and (type(c['floor']) is not int or c['floor'] not in (1,2)):return 'invalid_floor'
    if 'gun_id' in c and not isinstance(c['gun_id'],str):return 'invalid_gun_id'
    if c['action']=='attack' and not isinstance(c.get('target_id'),str):return 'target_required'
    if c['action']=='map' and (type(c.get('index')) is not int or c['index'] not in range(3)):return 'invalid_map'
    if c['action']=='posture' and c.get('posture') not in {'auto','stand','crouch','prone'}:return 'invalid_posture'
    if c['action']=='equip' and c.get('weapon') not in {'rifle','smg','rocket','pistol'}:return 'invalid_weapon'
    if agent and (not isinstance(c.get('run_id'),str) or type(c.get('seen_tick')) is not int):return 'observation_required'
    return None

class State:
    def __init__(self):
        self.lock=threading.Lock();self.state={};self.updated=0;self.pending={};self.results=collections.OrderedDict();self.recorded=0
        (ROOT/'output').mkdir(exist_ok=True)
    def record(self,kind,data):
        with (ROOT/'output/session.jsonl').open('a') as f:f.write(json.dumps({'at':time.time(),'kind':kind,'data':data},ensure_ascii=False)+'\n')
    def submit(self,command,agent=False,source=None):
        error=validate_command(command,agent or source=='lm')
        if error:return 400,{'error':error}
        with self.lock:
            if not self.state or not self.updated or time.monotonic()-self.updated>5:return 409,{'error':'engine_offline'}
            if len(self.pending)>=64:return 429,{'error':'queue_full'}
            c=dict(command);c['source']=source if source=='lm' else ('agent' if agent else 'console')
            if source=='lm':
                team=c.get('faction','green')
                if self.state.get('control',{}).get(team)!='lm' or c.get('control_epoch')!=self.state.get('control_epochs',{}).get(team,0):return 409,{'error':'lm_authority_changed'}
                if len(c.get('unit_ids',[]))!=1:return 400,{'error':'lm_single_unit_required'}
            c['id']=str(uuid.uuid4());c['_queued']=time.monotonic();c['_run']=self.state.get('run_id')
            self.pending[c['id']]=c
            self.record('command',c)
            return 202,{'id':c['id'],'status':'queued','note':'Wait for Godot acknowledgement'}
    def sync(self,payload):
        if not isinstance(payload,dict) or not isinstance(payload.get('state'),dict):return 400,{'error':'invalid_state'}
        s=payload['state']
        if s.get('schema_version')!=1 or not isinstance(s.get('units'),list):return 400,{'error':'invalid_schema'}
        with self.lock:
            for ack in payload.get('acks',[]):
                if not isinstance(ack,dict):continue
                self.pending.pop(ack.get('id'),None);self.results[ack.get('id')]=ack;self.record('ack',ack)
            for id,c in list(self.pending.items()):
                if c['_run']!=s.get('run_id') or time.monotonic()-c['_queued']>10:
                    applied=c['action']=='reset' and c['_run']!=s.get('run_id')
                    self.results[id]={'id':id,'accepted':applied,'message':'reset_applied' if applied else 'expired_or_new_run'};del self.pending[id]
            self.state=s;self.updated=time.monotonic()
            if self.updated-self.recorded>1:self.record('snapshot',s);self.recorded=self.updated
            while len(self.results)>256:self.results.popitem(last=False)
            return 200,{'commands':[{k:v for k,v in c.items() if not k.startswith('_')} for c in self.pending.values()]}

STATE=State()
LM=None

class Handler(SimpleHTTPRequestHandler):
    def log_message(self,fmt,*args):
        if args and '/api/' not in str(args[0]):super().log_message(fmt,*args)
    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        super().end_headers()
    def json(self,status,payload):
        body=json.dumps(payload,ensure_ascii=False,allow_nan=False).encode()
        self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def do_GET(self):
        path=urllib.parse.urlsplit(self.path).path
        if path=='/api/state':
            with STATE.lock:payload={'engine_live':bool(STATE.updated) and time.monotonic()-STATE.updated<3,'age_seconds':round(time.monotonic()-STATE.updated,2) if STATE.updated else None,'state':STATE.state,'pending':len(STATE.pending),'acks':list(STATE.results.values())[-12:]}
            payload['lm']=LM.snapshot() if LM else {'configured':False}
            self.json(200,payload)
        elif path=='/api/health':self.json(200,{'service':'deskfront-control','version':'0.6.0','schema_version':1,'engine_live':bool(STATE.updated) and time.monotonic()-STATE.updated<3})
        elif path.startswith('/api/result/'):
            id=path.rsplit('/',1)[-1]
            with STATE.lock:self.json(200,STATE.results.get(id,{'id':id,'status':'queued' if id in STATE.pending else 'unknown'}))
        elif path=='/api/lm/status':self.json(200,LM.snapshot() if LM else {'configured':False})
        elif path=='/api/action-catalog':self.json(200,json.loads((ROOT/'data/action-catalog.json').read_text()))
        elif path=='/api/schema':self.json(200,{'schema_version':1,'actions':sorted(ALLOWED),'agent_actions':sorted(TACTICS),'factions':sorted(TEAMS),'coordinates':'Godot meters [x,z], +Y up','agent_required':['faction','action','run_id','seen_tick'],'authority':'Godot validates team ownership, units, bounds and observation freshness'})
        else:
            allowed=ROOT/'build/web' if path.startswith('/play/') else ROOT/'dashboard'
            relative=path.removeprefix('/play/') if path.startswith('/play/') else path.lstrip('/')
            target=(allowed/(relative or 'index.html')).resolve()
            if not target.is_relative_to(allowed.resolve()) or not target.is_file():self.send_error(404);return
            self.path='/'+str(target.relative_to(ROOT));super().do_GET()
    def translate_path(self,path):return str(ROOT/urllib.parse.unquote(path).lstrip('/'))
    def do_POST(self):
        origin=self.headers.get('Origin')
        if origin and origin!=f'http://{self.headers.get("Host")}':self.json(403,{'error':'origin_denied'});return
        try:
            length=int(self.headers.get('Content-Length','0'))
            if length<1 or length>262144:raise ValueError('invalid_length')
            payload=json.loads(self.rfile.read(length))
        except (ValueError,TypeError):self.json(400,{'error':'invalid_json'});return
        if self.path=='/api/sync':status,result=STATE.sync(payload)
        elif self.path in {'/api/command','/api/agent/command'}:
            if isinstance(payload,dict) and payload.get('action')=='control' and payload.get('mode')=='lm' and (not LM or not LM.ready):status,result=409,{'error':'lm_not_configured'}
            else:status,result=STATE.submit(payload,self.path=='/api/agent/command')
        else:status,result=404,{'error':'not_found'}
        self.json(status,result)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=8768);parser.add_argument('--lm-env',help='External dotenv path; secrets remain server-side');args=parser.parse_args()
    global LM
    from lm_controller import LMController,load_config
    LM=LMController(STATE,load_config(args.lm_env));LM.start()
    server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler)
    print(f'Deskfront: http://127.0.0.1:{args.port}',flush=True)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:LM.close();server.server_close()
if __name__=='__main__':main()
