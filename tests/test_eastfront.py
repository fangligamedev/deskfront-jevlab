import sys,json,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from server import validate_command,ROOT
class FrontierContract(unittest.TestCase):
    def test_editor_actions_not_agent_tactical_authority(self):
        for c in [{'action':'eastfront_start'},{'action':'eastfront_propose','sequence':1,'template':'staggered'},{'action':'eastfront_follow','value':True}]:
            self.assertIsNone(validate_command(c));self.assertEqual(validate_command(c,True),'unknown_or_forbidden_action')
    def test_invalid_inputs(self):
        for c in [{'action':'eastfront_start','seed':True},{'action':'eastfront_start','seed':-1},{'action':'eastfront_start','mode':'root'},{'action':'eastfront_propose','sequence':True,'template':'x'},{'action':'eastfront_follow','value':'false'}]:self.assertIsNotNone(validate_command(c))
    def test_component_catalog_bounds_and_weapons(self):
        r=json.loads((ROOT/'data/eastfront.json').read_text());weapons=json.loads((ROOT/'data/battle.json').read_text())['weapons']
        self.assertEqual(len({t['id'] for t in r['templates']}),len(r['templates']))
        for t in r['templates']:
            for x,z,w,d in t['covers']:
                self.assertGreater(w,0);self.assertGreater(d,0);self.assertLess(x+w/2,r['width']);self.assertLess(abs(z)+d/2,r['half_depth'])
            for x,z,weapon in t['enemies']:self.assertIn(weapon,weapons)

class ModelSelectionContract(unittest.TestCase):
    def test_profiles_do_not_expose_secrets_and_reject_unconfigured(self):
        from test_lm import state,controller
        s=state();c=controller(s,lambda o:({},{}))
        c.profiles['typesafe_jev']={'key':'','model':'jev-1.13.0'}
        try:
            with self.assertRaisesRegex(ValueError,'provider_not_configured'):c.select_provider('typesafe_jev',None,'r')
            self.assertNotIn('TEST_SECRET',json.dumps(c.snapshot()))
            self.assertFalse(c.snapshot()['providers']['typesafe_jev']['configured'])
        finally:c.close()
    def test_switch_invalidates_pending_and_preserves_budget(self):
        import threading
        from test_lm import state,controller,settle
        release=threading.Event();s=state()
        def old(o):release.wait(2);return {'action':'capture','intent':'capture'},{}
        c=controller(s,old)
        c.profiles['typesafe_jev']=dict(c.config,provider='typesafe_jev',key='OTHER_TEST_SECRET',model='jev-1.13.0',base_url='https://api.typesafe.ai/v1')
        try:
            c.tick();used=c.used
            with self.assertRaisesRegex(ValueError,'release_model_control_first'):c.select_provider('typesafe_jev',None,'r')
            s.state['control']['green']='game_ai'
            with self.assertRaisesRegex(ValueError,'stale_run'):c.select_provider('typesafe_jev',None,'old')
            c.select_provider('typesafe_jev',None,'r');release.set();settle(c)
            self.assertEqual(c.provider,'typesafe_jev');self.assertEqual(c.used,used)
            self.assertEqual(c.metrics['discarded'],2);self.assertEqual(len(s.pending),0)
        finally:release.set();c.close()
    def test_explicit_builders_are_valid(self):
        for provider in ['typesafe_jev','volcengine_ark']:
            self.assertIsNone(validate_command({'action':'eastfront_start','backend':provider,'mode':'lm'}))
