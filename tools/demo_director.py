"""Bounded model choice over real editor/deployment operations exposed by Godot."""
import json,time,threading,urllib.request,urllib.error
from lm_controller import NoRedirect,ProviderError
from jev_client import checked_choice

class DemoDirector:
 def __init__(self,studio):self.studio=studio;self.lock=threading.Lock();self.last=float("-inf");self.count={}
 def choose(self,payload):
  st=self.studio
  with st.state.lock:s=json.loads(json.dumps(st.state.state));instance=st.state.instance_id;age=time.monotonic()-st.state.updated
  if age>5:raise ValueError('engine_offline')
  if payload.get('instance_id')!=instance or payload.get('run_id')!=s.get('run_id'):raise ValueError('stale_run')
  demo=s.get('demo',{});options=demo.get('steps',[])
  if not demo.get('enabled') or not demo.get('running') or not options:raise ValueError('demo_no_available_step')
  with self.lock:
   if time.monotonic()-self.last<1:raise ValueError('demo_rate_limited')
   if self.count.get(s['run_id'],0)>=64:raise ValueError('demo_call_budget_reached')
   self.last=time.monotonic();self.count[s['run_id']]=self.count.get(s['run_id'],0)+1
  value={'player_intent':s.get('scenario',{}).get('briefing',''),'phase':demo['phase'],'legal_steps':options,'timeline':demo.get('timeline',[])[-8:]}
  instruction='你是虚拟玩具兵游戏演示的导演。根据玩家意图，从合法步骤中选择下一次编辑器放置或派兵。仅能选择给出的步骤ID。兼顾双方反制与可读的先后顺序；这不是现实作战。'
  cfg=st.lm.config;log=st.lm.call_log
  if cfg.get('provider')=='typesafe_jev':
   if not st.lm.ready:raise ValueError('llm_not_configured')
   criteria={x['id']:json.dumps(x,ensure_ascii=False) for x in options}
   request={'model':cfg['model'],'state':value,'questions':{'step':{'type':'choice','instructions':instruction,'criteria':criteria}}}
   call=log.start(unit_id='demo-director',faction='studio',run_id=s['run_id'],tick=s['tick'],model=cfg['model'],provider='typesafe_jev',request=request)
   try:
    req=urllib.request.Request('https://api.typesafe.ai/v1/systemone',data=json.dumps(request).encode(),headers={'Authorization':'Bearer '+cfg['key'],'Content-Type':'application/json'})
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=20) as response:raw=response.read(131073)
    log.update(call,http_status=response.status,response_text=raw[:131072].decode(errors='replace'))
    if len(raw)>131072:raise ValueError('response_too_large')
    result=json.loads(raw);step=checked_choice(result['answers']['step'],criteria);reason='JEV 从引擎合法步骤中选择 '+step
    log.update(call,parsed_response=result)
   except urllib.error.HTTPError as e:
    log.update(call,phase='error',http_status=e.code,response_text=e.read(131072).decode(errors='replace'),error='provider_http_'+str(e.code));raise ValueError('provider_http_'+str(e.code)) from None
   except Exception:
    log.update(call,phase='error',error='demo_provider_or_schema_error');raise ValueError('demo_provider_or_schema_error') from None
  else:
   if not st.ready:raise ValueError('llm_not_configured')
   result,call=st._completion('demo-director',instruction+'只输出 JSON: {"step_id":"合法ID","reason":"简短理由"}。',value,s['run_id'],400)
   if not isinstance(result,dict) or result.get('step_id') not in [o['id'] for o in options]:
    log.update(call,phase='rejected',error='invalid_demo_step');raise ValueError('invalid_demo_step')
   step=result['step_id'];reason=str(result.get('reason',''))[:240]
  with st.state.lock:
   current=st.state.state
   valid=current.get('run_id')==s['run_id'] and any(o['id']==step for o in current.get('demo',{}).get('steps',[]))
  if not valid:log.update(call,phase='discarded',error='demo_state_changed');raise ValueError('demo_state_changed')
  log.update(call,phase='validated',receipt={'message':'editor_choice_validated_not_yet_executed'})
  return {'step_id':step,'reason':reason,'call_id':call,'provider':cfg.get('provider'),'model':cfg['model']}
