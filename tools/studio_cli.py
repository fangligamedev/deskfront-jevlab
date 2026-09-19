#!/usr/bin/env python3
"""Small stdlib client for model-created levels and evidence-backed reports."""
import argparse,json,time,urllib.request,urllib.error

def main():
 p=argparse.ArgumentParser(description='Deskfront AI create/play/reflect client');p.add_argument('--url',default='http://127.0.0.1:8768');p.add_argument('action',choices=['status','generate','import','play','analyze','report','get']);p.add_argument('--brief');p.add_argument('--file');p.add_argument('--id');p.add_argument('--kind',choices=['scenarios','reports','jobs'],default='scenarios');p.add_argument('--player',choices=['green','blue','red','none'],default='green');p.add_argument('--opponent',choices=['game_ai','lm','agent'],default='game_ai');a=p.parse_args()
 def req(path,value=None):
  request=urllib.request.Request(a.url.rstrip('/')+path,data=json.dumps(value).encode() if value is not None else None,headers={'Content-Type':'application/json'})
  with urllib.request.urlopen(request,timeout=30) as r:return json.load(r)
 try:
  if a.action=='status':result=req('/api/studio/status')
  elif a.action=='get':
   if not a.id:p.error('--id is required')
   result=req('/api/studio/'+a.kind+'/'+a.id)
  else:
   if a.action=='generate':
    if not a.brief:p.error('--brief is required')
    payload={'brief':a.brief}
   elif a.action=='import':
    if not a.file:p.error('--file is required')
    with open(a.file) as f:payload={'scenario':json.load(f)}
   else:
    context=req('/api/state');payload={'run_id':context['state']['run_id']}
    if a.action=='play':
     if not a.id:p.error('--id is required')
     payload.update(instance_id=context['instance_id'],scenario_id=a.id,player_faction=a.player,opponent_mode=a.opponent)
   result=req('/api/studio/'+a.action,payload)
   if a.action!='play':
    deadline=time.monotonic()+150
    while result['phase']=='running' and time.monotonic()<deadline:time.sleep(1);result=req('/api/studio/jobs/'+result['id'])
   else:
    deadline=time.monotonic()+20
    while 'accepted' not in result and time.monotonic()<deadline:time.sleep(.2);result=req('/api/result/'+result['id'])
  print(json.dumps(result,ensure_ascii=False,indent=2))
 except (urllib.error.URLError,KeyError,ValueError,OSError) as e:p.exit(1,'请求失败：'+str(e)+'\n')
if __name__=='__main__':main()
