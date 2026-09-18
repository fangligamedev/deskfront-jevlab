#!/usr/bin/env python3
"""Provider-neutral example, NOT an implementation of the private Jev API.
First assign one faction to Agent in the dashboard. Each turn uses a fresh state.
Replace choose_action only when an actual Jev SDK/API contract is available.
"""
import json,urllib.request,time,argparse
def get(base,path):
    with urllib.request.urlopen(base+path) as r:return json.load(r)
def choose_action(state,team):
    squad=[u for u in state['units'] if u['faction']==team and u['hp']>0]
    if not squad:return 'hold'
    ratio=sum(u['hp']/u['max_hp'] for u in squad)/len(squad)
    return 'cover' if ratio<.45 else 'capture'
def main():
    p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:8768');p.add_argument('--faction',choices=['green','blue','red'],default='green');p.add_argument('--once',action='store_true');a=p.parse_args()
    while True:
        response=get(a.url,'/api/state');s=response['state']
        if not response['engine_live']:raise SystemExit('Game engine is offline')
        if s['control'][a.faction]!='agent':raise SystemExit('Assign this faction to Agent in the dashboard first')
        body={'action':choose_action(s,a.faction),'faction':a.faction,'run_id':s['run_id'],'seen_tick':s['tick']}
        req=urllib.request.Request(a.url+'/api/agent/command',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req) as r:queued=json.load(r)
        for _ in range(30):
            result=get(a.url,'/api/result/'+queued['id'])
            if 'accepted' in result:print(json.dumps(result,ensure_ascii=False));break
            time.sleep(.1)
        if a.once:break
        time.sleep(2)
if __name__=='__main__':main()
