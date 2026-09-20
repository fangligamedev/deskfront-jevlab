import json,tempfile,unittest,urllib.error
from pathlib import Path
from unittest.mock import patch
from lm_controller import load_config,configured,observation,validate_decision,ProviderError
from laya_client import LayaClient,complete,frontier_payload
from test_lm import state
from test_lm_call_log import Response
from server import validate_command

def cfg():return {'provider':'laya','model':'laya-multilingual','key':'','base_url':'http://127.0.0.1:9400','timeout':3}
def response(payload):
 answers={}
 for k,q in payload['questions'].items():
  if q['type']=='noul':answers[k]={'type':'noul','noul':.3}
  else:
   choices=q['criteria'];choice=next(iter(choices))
   answers[k]={'type':'choice','choice':choice,'confidence':.7,'probabilities':{x:float(x==choice) for x in choices}}
 return {'answers':answers,'usage':{'input_tokens':300,'output_tokens':0},'meta':{'warnings':[]}}
class LayaContract(unittest.TestCase):
 def test_local_profile_needs_no_cloud_key(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'.env';p.write_text('DESKFRONT_LM_PROVIDER=laya\n')
   with patch.dict('os.environ',{},clear=True):c=load_config(p)
   self.assertTrue(configured(c));self.assertEqual(c['key'],'');self.assertEqual(c['concurrency'],1);self.assertEqual(c['text_config']['provider'],'volcengine_ark')
 def test_endpoint_refuses_remote_or_credential_urls(self):
  for x in ['https://example.com','http://127.0.0.1.evil.test:9400','http://user:pw@localhost:9400','http://localhost:9400/secret','http://localhost:9400?key=x']:
   with self.assertRaises(ValueError):LayaClient(dict(cfg(),base_url=x))
 def test_exact_wire_contract_and_no_authorization(self):
  p={'model':'jev','state':{'game':'toy'},'questions':{'intent':{'type':'choice','instructions':'Choose','criteria':{'a':'Advance','b':'Retreat'}}}}
  with patch('urllib.request.OpenerDirector.open',return_value=Response(json.dumps(response(p)).encode())) as send:
   complete(cfg(),p)
   req=send.call_args.args[0];wire=json.loads(req.data)
   self.assertNotIn('model',wire);self.assertFalse(wire['allow_truncation']);self.assertIsNone(req.get_header('Authorization'))
 def test_truncated_model_input_cannot_execute(self):
  with patch('urllib.request.OpenerDirector.open',return_value=Response(json.dumps({'answers':{},'meta':{'warnings':['input truncated']}}).encode())):
   with self.assertRaisesRegex(ProviderError,'laya_input_truncated'):complete(cfg(),{'state':'toy','questions':{}})
 def test_legal_infantry_and_tank_actions(self):
  s=state().state
  for kind in ['soldier','tank']:
   u=s['units'][0];u['kind']=kind;c=LayaClient(cfg());o=observation(s,u,[]);p=c.build_payload(o)
   with patch('urllib.request.OpenerDirector.open',return_value=Response(json.dumps(response(p)).encode())):
    action,usage=c(o);validate_decision(action,s,u);self.assertEqual(usage['output_tokens'],0);self.assertEqual(usage['total_tokens'],300)
   if kind=='tank':self.assertNotIn('posture',p['questions'])
 def test_unknown_model_choice_rejected(self):
  s=state().state;o=observation(s,s['units'][0],[]);c=LayaClient(cfg());p=c.build_payload(o);r=response(p);r['answers']['tactic']['choice']='teleport'
  with patch('urllib.request.OpenerDirector.open',return_value=Response(json.dumps(r).encode())):
   with self.assertRaises(ProviderError):c(o)
 def test_frontier_payload_bounds_state(self):
  p=frontier_payload({'units':[{'id':str(i),'hp':100,'huge':'x'*20000} for i in range(50)],'strategy':{'sectors':['a','b','c'],'strategy':'x'*10000}}, {})
  self.assertEqual(len(p['state']['units']),9);self.assertLess(len(json.dumps(p)),1000)
 def test_backend_validation(self):
  for backend in ['laya','dual_brain_laya']:self.assertIsNone(validate_command({'action':'eastfront_start','backend':backend}))
  self.assertIsNotNone(validate_command({'action':'eastfront_start','backend':'unregistered'}))
 def test_busy_model_error_remains_visible(self):
  from io import BytesIO
  err=urllib.error.HTTPError('http://127.0.0.1:9400/v1/systemone',429,'busy',{},BytesIO(b'busy'))
  with patch('urllib.request.OpenerDirector.open',side_effect=err):
   with self.assertRaisesRegex(ProviderError,'laya_http_429'):complete(cfg(),{'state':'toy','questions':{}})
