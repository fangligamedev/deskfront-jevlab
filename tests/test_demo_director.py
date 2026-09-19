import json,unittest
from types import SimpleNamespace
from unittest.mock import patch
from test_lm import state
from test_lm_call_log import Response
from lm_call_log import CallLog
from demo_director import DemoDirector
class DemoTests(unittest.TestCase):
 def setup_director(self):
  s=state();s.instance_id='engine';s.state['demo']={'enabled':True,'running':True,'phase':'building','steps':[{'id':'cover-1','action':'place_cover'}]}
  log=CallLog();cfg={'provider':'typesafe_jev','model':'jev-test','key':'SECRET'}
  st=SimpleNamespace(state=s,lm=SimpleNamespace(config=cfg,call_log=log,ready=True),ready=False)
  return DemoDirector(st),s,log
 def test_stale_or_unavailable_editor_commands_rejected_before_call(self):
  director,s,_=self.setup_director()
  with self.assertRaisesRegex(ValueError,'stale_run'):director.choose({'instance_id':'wrong','run_id':'r'})
  s.state['demo']['steps']=[]
  with self.assertRaisesRegex(ValueError,'demo_no_available_step'):director.choose({'instance_id':'engine','run_id':'r'})
 def test_jev_choice_is_logged_and_not_claimed_as_execution(self):
  director,_,log=self.setup_director()
  response={'answers':{'step':{'type':'choice','choice':'cover-1','confidence':1,'probabilities':{'cover-1':1}}}}
  with patch('urllib.request.OpenerDirector.open',return_value=Response(json.dumps(response).encode())):
   result=director.choose({'instance_id':'engine','run_id':'r'})
  self.assertEqual(result['step_id'],'cover-1');row=log.get(result['call_id'])
  self.assertEqual(row['phase'],'validated');self.assertIn('not_yet_executed',row['receipt']['message'])
 def test_invalid_model_step_cannot_escape_legal_editor_options(self):
  director,_,log=self.setup_director()
  response={'answers':{'step':{'type':'choice','choice':'execute-code','confidence':1,'probabilities':{'execute-code':1}}}}
  with patch('urllib.request.OpenerDirector.open',return_value=Response(json.dumps(response).encode())):
   with self.assertRaises(ValueError):director.choose({'instance_id':'engine','run_id':'r'})
  self.assertEqual(log.list()['items'][0]['phase'],'error')
