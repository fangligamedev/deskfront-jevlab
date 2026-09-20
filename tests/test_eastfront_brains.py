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
  self.assertEqual(validate_plan({'sectors':['a','b','c']},['a','b','c'])['sectors'],['a','b','c'])
  for v in [{'sectors':['a','a','b']},{'sectors':['a','b','execute_code']},{'sectors':['a']},None]:
   with self.assertRaises(ProviderError):validate_plan(v,['a','b','c'])
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
