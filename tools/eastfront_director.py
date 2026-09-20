"""Server-side bounded frontier choices. Continues when the presentation view changes."""
import copy
import json
import threading
import time
import urllib.request
import urllib.error
from lm_controller import NoRedirect, ProviderError, ArkClient
from jev_client import checked_choice
from eastfront_brains import DualBrain

class EastfrontDirector:
    def __init__(self,state,lm):
        self.state=state;self.lm=lm;self.stop=threading.Event();self.thread=None
        self.brains=DualBrain(state,lm)
        self.run='';self.seen=set();self.used=0;self.disabled=False;self.receipts={}
    def start(self):
        self.thread=threading.Thread(target=self.loop,daemon=True,name='eastfront-director');self.thread.start()
    def close(self):
        self.stop.set();self.brains.close()
        if self.thread:self.thread.join(timeout=1)
    def loop(self):
        while not self.stop.wait(.25):
            try:self.tick()
            except Exception:pass  # Engine owns the deadline and explicit local fallback.
    def tick(self):
        with self.state.lock:
            s=copy.deepcopy(self.state.state);instance=self.state.instance_id;age=time.monotonic()-self.state.updated;acks=copy.deepcopy(self.state.results)
        for command,call in list(self.receipts.items()):
            if command in acks:
                self.lm.call_log.update(call,phase='executed' if acks[command]['accepted'] else 'rejected',receipt=acks[command]);del self.receipts[command]
        f=s.get('eastfront',{});r=f.get('request',{})
        if f.get('enabled') and age<=3:self.brains.tick(s,instance,acks)
        if not f.get('enabled') or f.get('backend') not in ('model','typesafe_jev','volcengine_ark') or not r or age>3 or s.get('paused') or s.get('winner'):return
        if self.run!=s['run_id']:self.run=s['run_id'];self.seen=set();self.used=0;self.disabled=False
        seq=r['sequence']
        if seq in self.seen or self.used>=128 or self.disabled:return
        self.seen.add(seq);self.used+=1
        cfg=self.lm.config if f.get('backend')=='model' else self.lm.profiles.get(f.get('backend'),{});log=self.lm.call_log
        if not cfg.get('key') or not cfg.get('model'):return
        value={'mission':'Build the next eastward toy RTS defense. Vary cover and counterplay; never alter occupied terrain.',
               'frontier':r,'recent_sectors':f.get('chunks',[]),'squad':[u for u in s['units'] if u['faction']=='green' and u['hp']>0]}
        criteria={x['id']:x['name'] for x in r['candidates']}
        instruction='为玩具兵向东推进选择下一段合法防线。选择一个模板 ID，考虑本队剩余兵种与近几段避免重复；这些是游戏组件，实际位置和可达性由 Godot 验证。'
        if cfg.get('provider')=='typesafe_jev':
            payload={'model':cfg['model'],'state':value,'questions':{'layout':{'type':'choice','instructions':instruction,'criteria':criteria}}}
        else:
            payload={'model':cfg['model'],'messages':[{'role':'system','content':instruction+'只输出 JSON {"template":"合法模板ID"}。'},{'role':'user','content':json.dumps(value,ensure_ascii=False)}],'max_tokens':64,'thinking':{'type':'disabled'},'response_format':{'type':'json_object'}}
        call=log.start(unit_id='eastfront-director',faction='studio',run_id=s['run_id'],tick=s['tick'],model=cfg['model'],provider=cfg['provider'],request=payload)
        trace=lambda **fields:log.update(call,**fields)
        try:
            if cfg.get('provider')=='typesafe_jev':
                req=urllib.request.Request('https://api.typesafe.ai/v1/systemone',data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+cfg['key'],'Content-Type':'application/json'})
                with urllib.request.build_opener(NoRedirect()).open(req,timeout=min(5,cfg['timeout'])) as response:raw=response.read(131073)
                trace(http_status=response.status,response_text=raw[:131072].decode(errors='replace'))
                if len(raw)>131072:raise ProviderError('response_too_large')
                result=json.loads(raw);selected=checked_choice(result['answers']['layout'],criteria)
            else:
                result,usage=ArkClient(dict(cfg,timeout=min(5,cfg['timeout']))).complete(payload,trace);selected=result['template']
            if selected not in criteria:raise ProviderError('unknown_frontier_template')
            with self.state.lock:
                current=self.state.state
                valid=current.get('run_id')==s['run_id'] and current.get('eastfront',{}).get('request',{}).get('sequence')==seq
            if not valid:trace(phase='discarded',error='frontier_state_changed');return
            status,receipt=self.state.submit({'action':'eastfront_propose','sequence':seq,'template':selected,'provider':('deepseek_json_frontier' if cfg['provider']=='deepseek_logprobs' else cfg['provider'])+':'+cfg['model'],'instance_id':instance,'run_id':s['run_id']})
            trace(parsed_response=result,phase='submitted' if status==202 else 'rejected',receipt=receipt)
            if status==202:self.receipts[receipt['id']]=call
        except urllib.error.HTTPError as e:
            trace(phase='error',http_status=e.code,response_text=e.read(131072).decode(errors='replace'),error='provider_http_'+str(e.code))
            if e.code in (401,402,403):self.disabled=True
        except (ProviderError,ValueError,KeyError,TypeError,OSError) as error:
            trace(phase='error',error=str(error) if isinstance(error,ProviderError) else 'frontier_provider_or_schema_error')
            if str(error) in ('provider_account_overdue','provider_http_401','provider_http_403'):self.disabled=True
