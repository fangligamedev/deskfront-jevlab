import sys,unittest,copy,time,concurrent.futures
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from eastfront_brains import DualBrain,validate_plan
from lm_controller import ProviderError
from test_lm import state,controller
from server import validate_command
class BrainsContract(unittest.TestCase):
 def test_dual_brain_accepts_model_squad_authority(self):
  for backend in ['dual_brain','dual_brain_laya']:
   for mode in ['lm','game_ai','player','agent']:self.assertIsNone(validate_command({'action':'eastfront_start','backend':backend,'mode':mode}))
 def test_model_squad_does_not_launch_competing_per_unit_calls(self):
  for backend in ['dual_brain','dual_brain_laya']:
   s=state();s.state['eastfront']={'backend':backend};seen=[]
   c=controller(s,lambda o:seen.append(o))
   try:
    c.tick();self.assertEqual(c.pending,{});self.assertEqual(seen,[]);self.assertEqual(s.pending,{})
   finally:c.close()
 def test_plan_is_bounded_and_varied(self):
  def plan(t):return {'template':t,'defenders':[{'weapon':'rifle','station':0},{'weapon':'rocket','station':2}],'defense':'entrench','construction':'dig_first','armor':{t:{'enabled':True,'delay':2,'role':'support'} for t in ('green','red')},'reason':'分工据壕'}
  good={'sectors':[plan(t) for t in ('a','b','c')]}
  self.assertEqual(validate_plan(good,['a','b','c'])['sectors'],good['sectors'])
  bads=[{'sectors':['a','b','c']},{'sectors':[plan('a')]*3},None]
  for field,value in [('station',0),('station',True),('weapon','teleport')]:
   bad=copy.deepcopy(good);bad['sectors'][0]['defenders'][1][field]=value;bads.append(bad)
  for delay in [float('nan'),-1,99,True]:
   bad=copy.deepcopy(good);bad['sectors'][0]['armor']['red']['delay']=delay;bads.append(bad)
  bad=copy.deepcopy(good);bad['sectors'][0]['armor']['red']['enabled']=False;bads.append(bad)
  for v in bads:
   with self.assertRaises(ProviderError):validate_plan(v,['a','b','c'])
  self.assertIsNone(validate_command({'action':'eastfront_propose','sequence':1,'template':'a','battle_plan':plan('a')}))
  self.assertIsNotNone(validate_command({'action':'eastfront_propose','sequence':1,'template':'b','battle_plan':plan('a')}))
 def test_rejected_slow_plan_is_replanned(self):
  s=state();c=controller(s,lambda o:({},{}));b=DualBrain(s,c)
  try:
   s.state['eastfront']={'backend':'local','active_sector':1,'chunks':[]};b.run=s.state['run_id']
   call=c.call_log.start(unit_id='test',run_id=b.run,model='test',request={})
   b.plan={1:{'template':'a'}};b.submitted={7};b.plan_receipts={'cmd':{'call':call,'sequence':7,'index':1}}
   b.tick(copy.deepcopy(s.state),None,{'cmd':{'accepted':False,'reason':'frontier_unreachable'}})
   self.assertEqual(b.plan,{});self.assertEqual(b.submitted,set());self.assertEqual(c.call_log.get(call)['phase'],'rejected')
  finally:b.close();c.close()
 def test_fast_directive_is_not_agent_admin_authority(self):
  c={'action':'eastfront_directive','sector':1,'intent':'advance','construction':'north_first'}
  self.assertIsNone(validate_command(c));self.assertEqual(validate_command(c,True),'unknown_or_forbidden_action')
  self.assertIsNotNone(validate_command(dict(c,intent='teleport')))
  self.assertIsNone(validate_command(dict(c,construction='dig_first')))
  self.assertIsNone(validate_command(dict(c,construction='sandbag_first')))
 def test_late_plan_from_old_run_is_discarded(self):
  s=state();c=controller(s,lambda o:({},{}));b=DualBrain(s,c)
  try:
   s.state['eastfront']={'backend':'local','active_sector':1,'chunks':[]}
   call=c.call_log.start(unit_id='test',run_id='old',model='test',request={})
   future=concurrent.futures.Future();future.set_result({'sectors':['a','b','c']})
   b.pending['slow']={'future':future,'run':'old','call':call,'key':{'index':1,'allowed':['a','b','c']}}
   b.tick(copy.deepcopy(s.state),None,{})
   self.assertEqual(b.plan,{});self.assertEqual(c.call_log.get(call)['phase'],'discarded')
  finally:b.close();c.close()
 def test_busy_fast_model_backs_off_without_submitting_orders(self):
  s=state();c=controller(s,lambda o:({},{}));b=DualBrain(s,c)
  try:
   s.state['eastfront']={'backend':'dual_brain_laya','active_sector':1,'chunks':[]}
   b.run=s.state['run_id'];b.next_fast=0
   call=c.call_log.start(unit_id='test',run_id=b.run,model='test',request={})
   future=concurrent.futures.Future();future.set_exception(ProviderError('laya_http_429'))
   b.pending['fast']={'future':future,'run':b.run,'call':call,'key':1,'started':time.monotonic()}
   before=time.monotonic();b.tick(copy.deepcopy(s.state),None,{})
   self.assertGreaterEqual(b.next_fast,before+3.9);self.assertEqual(s.pending,{})
   self.assertEqual(b.latest['fast']['error'],'laya_http_429')
  finally:b.close();c.close()
 def test_pending_fast_request_prevents_overlap(self):
  s=state();c=controller(s,lambda o:({},{}));b=DualBrain(s,c)
  try:
   b.pending['fast']={'future':concurrent.futures.Future()};b.used['fast']=1
   b.launch('fast',s.state,{}, {},1)
   self.assertEqual(b.used['fast'],1)
  finally:b.close();c.close()
 def test_slow_brain_prefetches_before_current_batch_exhausted(self):
  s=state();c=controller(s,lambda o:({},{}));b=DualBrain(s,c)
  try:
   f={'active_sector':1,'template_catalog':[{'id':'a'},{'id':'b'},{'id':'c'}]}
   b.plan={i:{'template':t} for i,t in enumerate(['a','b','c'],1)}
   self.assertIsNone(b.planning_request(f,{}))
   f['active_sector']=2
   self.assertEqual(b.planning_request(f,{})['index'],4)
   self.assertTrue(b.planning_request(f,{})['prefetch'])
   required={'index':2,'candidates':f['template_catalog'],'sequence':8}
   b.plan.pop(2)
   self.assertIs(b.planning_request(f,required),required)
  finally:b.close();c.close()
 def test_prefetched_batch_keeps_unconsumed_plans_and_call_origins(self):
  from frontier_plan import campaign_plan
  s=state();c=controller(s,lambda o:({},{}));b=DualBrain(s,c)
  try:
   s.state['eastfront']={'backend':'dual_brain_laya','active_sector':2,'chunks':[]}
   b.run=s.state['run_id'];b.next_fast=time.monotonic()+60
   b.plan={i:{'template':'old'} for i in range(1,4)};b.plan_calls={i:42 for i in range(1,4)}
   call=c.call_log.start(unit_id='slow',run_id=b.run,model='test',request={})
   def p(t):return {'template':t,'defenders':[{'weapon':'rifle','station':0},{'weapon':'rocket','station':2}],'defense':'entrench','construction':'dig_first','armor':{team:{'enabled':True,'delay':2,'role':'support'} for team in ('green','red')},'reason':'据壕'}
   future=concurrent.futures.Future();future.set_result({'sectors':[p(t) for t in ['a','b','c']]})
   b.pending['slow']={'future':future,'run':b.run,'call':call,'key':{'index':4,'allowed':['a','b','c']}}
   b.tick(copy.deepcopy(s.state),None,{})
   self.assertEqual(sorted(b.plan),[1,2,3,4,5,6]);self.assertEqual(b.plan[3]['template'],'old');self.assertEqual(b.plan_calls[4],call);self.assertEqual(b.plan_calls[3],42)
   s.state['eastfront']['active_sector']=5;b.tick(copy.deepcopy(s.state),None,{})
   self.assertEqual(sorted(b.plan),[4,5,6]);self.assertEqual(sorted(b.plan_calls),[4,5,6])
  finally:b.close();c.close()

class StartupPrefixContract(unittest.TestCase):
 def plans(self):
  from test_frontier_components import layout
  geometry=layout()
  for c in geometry['components']:c['x']*=3
  geometry['components'][1]['depth']=.9
  geometry['components'][2]['x']=3.5
  return {'strategy':'分段设防','sectors':[{'template':t,'defenders':[{'weapon':'rifle','station':0},{'weapon':'rocket','station':2}],'defense':'entrench','construction':'dig_first','armor':{team:{'enabled':True,'delay':2,'role':'support'} for team in ('green','red')},'reason':'纵深工位','layout':copy.deepcopy(geometry)} for t in ['a','b','c']]}
 def test_invalid_future_does_not_discard_valid_opening(self):
  from frontier_plan import prepare_campaign_prefix
  original=self.plans();original['sectors'][1]['layout']['components'][1]['depth']=.3
  before=copy.deepcopy(original)
  plan,edits,deferred=prepare_campaign_prefix(original,['a','b','c'],True)
  self.assertEqual(original,before);self.assertEqual(len(plan['sectors']),1)
  self.assertEqual(plan['sectors'][0],original['sectors'][0]);self.assertEqual(deferred['sector_offset'],1)
  self.assertEqual(deferred['error'],'need_continuous_fortification_at_least_0.65m')
 def test_invalid_opening_never_skips_to_later_sector(self):
  from frontier_plan import prepare_campaign_prefix
  value=self.plans();value['sectors'][0]['layout']['components'][1]['depth']=.3
  with self.assertRaises(ValueError):prepare_campaign_prefix(value,['a','b','c'],True)
 def test_valid_campaign_still_keeps_all_three_sectors(self):
  from frontier_plan import prepare_campaign_prefix
  value=self.plans();plan,edits,deferred=prepare_campaign_prefix(value,['a','b','c'],True)
  self.assertEqual(plan,value);self.assertIsNone(deferred)
 def test_partial_result_is_queued_and_replanning_starts_after_it(self):
  s=state();c=controller(s,lambda o:({},{}));b=DualBrain(s,c);b.launch=lambda *args:None
  try:
   s.state['eastfront']={'backend':'dual_brain_laya','active_sector':1,'chunks':[], 'request':{'index':1,'sequence':1,'candidates':[{'id':t} for t in ['a','b','c']]}}
   b.run=s.state['run_id'];call=c.call_log.start(unit_id='test',run_id=b.run,model='test',request={})
   value=self.plans();value['sectors'][1]['layout']['components'][1]['depth']=.3
   future=concurrent.futures.Future();future.set_result(value)
   b.pending['slow']={'future':future,'run':b.run,'call':call,'key':{'index':1,'allowed':['a','b','c'],'compose':True}}
   b.tick(copy.deepcopy(s.state),None,{})
   self.assertEqual(sorted(b.plan),[1]);self.assertEqual(sorted(b.plan_calls),[1])
   self.assertTrue(any(v.get('action')=='eastfront_propose' for v in s.pending.values()))
   self.assertEqual(b.planning_request(s.state['eastfront'],s.state['eastfront']['request'])['index'],2)
   self.assertEqual(c.call_log.get(call)['deferred_validation']['sector_offset'],1)
  finally:b.close();c.close()
