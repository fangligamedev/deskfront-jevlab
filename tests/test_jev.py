import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from lm_controller import load_config, observation, validate_decision, ProviderError
from jev_client import JevClient, candidates, checked_choice
from test_lm import state, controller, settle
from test_lm_call_log import Response
from studio import Studio


def config():return {'provider':'typesafe_jev','model':'jev-1.13.0','key':'TEST_JEV_SECRET','base_url':'https://api.typesafe.ai/v1','timeout':2}


def response(payload,selected='capture_flag'):
    answers={}
    for key,q in payload['questions'].items():
        if q['type']=='noul':answers[key]={'type':'noul','noul':.2}
        else:
            picked=selected if key=='tactic' else 'auto'
            answers[key]={'type':'choice','choice':picked,'confidence':.9,'probabilities':{k:float(k==picked) for k in q['criteria']}}
    return {'model':'jev-1.13.0','answers':answers,'usage':{'input_tokens':100,'output_tokens':15}}


class JevContract(unittest.TestCase):
    def test_provider_credentials_and_text_model_are_separate(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'.env';p.write_text('DESKFRONT_LM_PROVIDER=typesafe_jev\nTYPESAFE_API_KEY=JEV_KEY\nARK_API_KEY=ARK_KEY\nDESKFRONT_LM_MODEL=deepseek-test\n')
            with patch.dict('os.environ',{},clear=True):cfg=load_config(p)
            self.assertEqual(cfg['key'],'JEV_KEY');self.assertEqual(cfg['text_config']['key'],'ARK_KEY');self.assertEqual(cfg['model'],'jev-1.13.0');self.assertEqual(cfg['text_config']['model'],'deepseek-test')
            s=state();c=controller(s,lambda o:({},{}),**cfg)
            try:
                studio=Studio(s,c,path=Path(d)/'studio.db');self.assertEqual(studio.config['model'],'deepseek-test');self.assertNotIn('JEV_KEY',json.dumps(studio.status()));studio.close()
            finally:c.close()

    def test_endpoint_refuses_untrusted_host(self):
        for base in ['http://api.typesafe.ai/v1','https://example.com/v1','https://api.typesafe.ai.evil.test/v1']:
            with self.assertRaises(ValueError):JevClient(dict(config(),base_url=base))

    def test_candidates_are_valid_concrete_commands(self):
        s=state().state;u=s['units'][0];obs=observation(s,u,[])
        for candidate in candidates(obs).values():validate_decision(candidate['command'],s,u)
        self.assertIn('capture_flag',candidates(obs));self.assertIn('advance_step',candidates(obs))

    def test_rifles_do_not_target_tanks_and_tanks_do_not_take_postures(self):
        s=state().state;s['units'][-1]['kind']='tank';u=s['units'][0];obs=observation(s,u,[])
        self.assertNotIn('attack_red-1',candidates(obs));u.update(kind='tank',weapon='cannon')
        p=JevClient(config()).build_payload(observation(s,u,[]));self.assertNotIn('posture',p['questions'])
        u['combat_ready']=False;p=JevClient(config()).build_payload(observation(s,u,[]));self.assertEqual(list(p['state']['command_candidates']),['continue_task'])

    def test_unknown_actions_and_invalid_distributions_rejected(self):
        for a in [{'type':'choice','choice':'delete'},{'type':'choice','choice':'capture','confidence':float('nan'),'probabilities':{'capture':1}},{'type':'choice','choice':'capture','confidence':.8,'probabilities':{'capture':.2}}]:
            with self.assertRaises(ProviderError):checked_choice(a,{'capture'})

    def test_explicit_choice_survives_rounded_probability_order(self):
        answer={'type':'choice','choice':'advance','confidence':.36,'probabilities':{'advance':.49,'capture':.51}}
        self.assertEqual(checked_choice(answer,{'advance','capture'}),'advance')

    def test_typed_reply_maps_to_engine_command_and_keeps_raw_evidence(self):
        s=state().state;u=s['units'][0];obs=observation(s,u,[]);client=JevClient(config());data=response(client.build_payload(obs));trace=[]
        with patch('urllib.request.OpenerDirector.open',return_value=Response(json.dumps(data).encode())):
            value,usage=client(obs,trace=lambda **d:trace.append(d))
        self.assertEqual(validate_decision(value,s,u)['action'],'capture');self.assertEqual(usage['total_tokens'],115)
        self.assertTrue(any(d.get('provider_response')==data for d in trace));self.assertNotIn('TEST_JEV_SECRET',json.dumps(trace))

    def test_jev_decision_has_own_origin_and_receipt_metrics(self):
        s=state();c=controller(s,lambda o:({'action':'capture','intent':'capture','reason':'JEV'},{}),provider='typesafe_jev')
        try:
            c.tick();settle(c);self.assertEqual(c.units['green-1']['origin'],'typesafe_jev');self.assertEqual(c.metrics['responses'],2)
            self.assertEqual(c.metrics['model_actions']['capture'],2);self.assertEqual(c.snapshot()['display_name'],'TypeSafe JEV')
            self.assertEqual(c.call_log.list()['items'][0]['phase'],'submitted')
        finally:c.close()
