import sys, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from server import validate_command
from lm_call_log import CallLog

class DebugVisualizeContract(unittest.TestCase):
    def test_console_only(self):
        c={'action':'debug_visualize','value':True,'unit':'green-1'}
        self.assertIsNone(validate_command(c))
        self.assertEqual(validate_command(c,agent=True),'unknown_or_forbidden_action')
        self.assertEqual(validate_command(dict(c,value='true')),'invalid_debug_options')
        self.assertEqual(validate_command(dict(c,unit=3)),'invalid_debug_options')
    def test_current_run_filter(self):
        log=CallLog()
        old=log.start(unit_id='green-1',run_id='old',tick=1)
        new=log.start(unit_id='green-1',run_id='new',tick=2)
        blue=log.start(unit_id='blue-1',run_id='new',tick=3)
        self.assertEqual([r['id'] for r in log.list(run='new')['items']],[blue,new])
        self.assertEqual([r['id'] for r in log.list(run='new',unit='green-1')['items']],[new])
        self.assertEqual([r['id'] for r in log.list(run='old')['items']],[old])
        self.assertEqual(log.list(run='never')['items'],[])

    def test_recovered_provider_warning_clears(self):
        from test_lm import state, controller, settle
        c=controller(state(),lambda obs: ({'action':'hold','intent':'observe','reason':'recovered'}, {}),log_path=':memory:')
        try:
            c.tick()
            c.metrics['last_error']='provider_account_overdue'
            settle(c)
            self.assertGreater(c.metrics.get('responses',0),0)
            self.assertNotIn('last_error',c.metrics)
        finally:c.close()
