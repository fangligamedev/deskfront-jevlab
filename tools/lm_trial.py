#!/usr/bin/env python3
"""Real Godot + real Ark trials. No fake model responses, no gameplay reimplementation."""
import argparse,collections,json,os,pathlib,socket,subprocess,sys,time,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('--seconds',type=float,default=40);p.add_argument('--maps',default='0,1,2');p.add_argument('--modes',default='game_ai,lm');p.add_argument('--prefix',default='live');p.add_argument('--tank',action='store_true');a=p.parse_args()
    out=ROOT/'output/v06';out.mkdir(parents=True,exist_ok=True)
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    base=f'http://127.0.0.1:{port}'
    def request(path,payload=None):
        data=None if payload is None else json.dumps(payload).encode()
        req=urllib.request.Request(base+path,data=data,headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=4) as r:return json.load(r)
    def wait(fn,seconds=15):
        start=time.monotonic()
        while time.monotonic()-start<seconds:
            try:
                d=request('/api/state')
                if fn(d):return d
            except OSError:pass
            time.sleep(.15)
        raise RuntimeError('Timed out waiting for real engine state')
    def command(c):
        session=request('/api/state')
        q=request('/api/command',dict(instance_id=session['instance_id'],run_id=session['state']['run_id'],**c));start=time.monotonic()
        while time.monotonic()-start<10:
            ack=request('/api/result/'+q['id'])
            if 'accepted' in ack:
                if not ack['accepted']:raise RuntimeError('Rejected command: '+ack['message'])
                return ack
            time.sleep(.12)
        raise RuntimeError('No engine receipt')
    serverlog=(out/(a.prefix+'-server.log')).open('w')
    server=subprocess.Popen([sys.executable,'tools/server.py','--port',str(port)],cwd=ROOT,stdout=serverlog,stderr=subprocess.STDOUT)
    game=None;reports=[]
    try:
        wait(lambda d:True)
        for map_index in map(int,a.maps.split(',')):
            for mode in a.modes.split(','):
                prior=request('/api/state')['state'].get('run_id')
                session=request('/api/session',{})
                env=dict(os.environ,DESKFRONT_URL=base,DESKFRONT_HEADLESS_BRIDGE='1',DESKFRONT_INSTANCE_ID=session['instance_id'])
                log=(out/f'{a.prefix}-{mode}-map{map_index}.log').open('w')
                from project import binary
                game=subprocess.Popen([binary('godot'),'--headless','--path',str(ROOT),'--max-fps','60','--','--paused',f'--map={map_index}'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
                d=wait(lambda d:d['engine_live'] and d['state'].get('run_id')!=prior and d['state'].get('paused'))
                if mode=='lm' and not d['lm']['configured']:raise RuntimeError('Real Ark configuration is required')
                for faction in ['green','blue','red']:command({'action':'control','faction':faction,'mode':mode})
                if a.tank:command({'action':'reinforce'})
                command({'action':'pause','value':False});started=time.monotonic();samples=[]
                while time.monotonic()-started<a.seconds+30:
                    d=request('/api/state');s=d['state'];alive=[u for u in s['units'] if u['hp']>0]
                    samples.append({'time':s['time'],'alive':len(alive),'infantry_alive':sum(u['kind']=='infantry' for u in alive),'hp':sum(u['hp'] for u in alive if u['kind']=='infantry'),'covered':sum(u['in_cover'] for u in alive),'prone':sum(u['posture']=='prone' for u in alive),'shots':s['shots'],'destroyed':s['destruction_count'],'lm_requests':d['lm']['used_requests'],'units':[{k:u[k] for k in ['id','hp','position','posture','order_mode','locomotion','in_cover','lm_intent','survival_reason']} for u in alive]})
                    if s['time']>=a.seconds or s['winner']:break
                    if game.poll() is not None:raise RuntimeError('Godot exited early')
                    time.sleep(.5)
                command({'action':'pause','value':True})
                wait(lambda d:d['lm']['in_flight']==0,15);d=request('/api/state');s=d['state'];lm=d['lm']
                metrics={'duration':s['time'],'infantry_alive':sum(u['kind']=='infantry' and u['hp']>0 for u in s['units']),'infantry_hp':round(sum(u['hp'] for u in s['units'] if u['kind']=='infantry'),1),'shots':s['shots'],'destroyed':s['destruction_count'],'cover_sample_ratio':round(sum(x['covered'] for x in samples)/max(1,sum(x['alive'] for x in samples)),3),'scores':s['scores'],'winner':s['winner']}
                result={'map':s['map'],'mode':mode,'real_api':mode=='lm','forced_tank_reinforcement':a.tank,'metrics':metrics,'lm':lm,'samples':samples,'final_state':s}
                reports.append(result);(out/(a.prefix+'-trials.json')).write_text(json.dumps({'version':'0.6.0','model':lm['model'],'runs':reports,'note':'三方同模式短时对照，固定游戏初始种子；LM 响应、网络延迟和变帧率不可逐帧复现。非胜率基准。'},ensure_ascii=False,indent=2))
                print(json.dumps({'map':s['map'],'mode':mode,'metrics':metrics,'lm':lm['metrics']},ensure_ascii=False),flush=True)
                game.terminate();game.wait(timeout=8);game=None;log.close()
        if a.tank and not all(r['lm']['metrics'].get('unit_decisions',{}).get('red-tank',0)>0 for r in reports if r['mode']=='lm'):raise RuntimeError('Tank did not receive an actual LM decision')
        if 'lm' in a.modes and not all(len(r['lm']['metrics'].get('unit_decisions',{}))>=9 for r in reports if r['mode']=='lm'):raise RuntimeError('Not every initial soldier received a real LM decision; inspect report')
    finally:
        if game and game.poll() is None:game.terminate();game.wait(timeout=8)
        server.terminate();server.wait(timeout=8);serverlog.close()
if __name__=='__main__':main()
