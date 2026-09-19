import copy
import json
import os
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from test_lm import state
from studio import Studio
from scenario_authoring import example,compile_scenario,preflight
from lm_call_log import CallLog


def report(e):
    return {'summary':'本局依据旗点与兵力观察。','factions':[{'faction':t,'strengths':['具备反坦克能力'],'weaknesses':['占旗时暴露风险']} for t in ['green','blue','red']],'winning_keys':['保持旗圈内接替'],'evidence':[{'tick':tick,'fact':'此 Tick 有真实状态采样'} for tick in e['allowed_ticks'][:2]],'uncertainties':['不能把射击次数当作命中']}


class StudioContract(unittest.TestCase):
    def test_data_contract_rejects_code_and_invalid_deployments(self):
        for changes in [{'script':'os.execute(...)'},{'base_map':True},{'hold_seconds':float('nan')},{'spawns':[[0,0]]},{'loadouts':{'green':['rifle']}}]:
            s=example();s.update(changes)
            with self.assertRaises(ValueError):compile_scenario(s,'test')
        s=example();s['covers'][0]['position']=[100,100]
        with self.assertRaises(ValueError):compile_scenario(s,'test')
        level=compile_scenario(example(),'test');self.assertEqual(len(level['spawns']),3);self.assertEqual(level['hold_seconds'],30)
        self.assertNotIn('sandbag.glb',json.dumps(example()))

    @unittest.skipIf(os.environ.get('DESKFRONT_PYTHON_ONLY')=='1', 'Godot navigation is tested in the mandatory Godot CI job')
    def test_godot_rejects_blocked_flag_and_accepts_valid_design(self):
        valid=compile_scenario(example(),'test');self.assertTrue(preflight(valid)['passed'])
        bad=copy.deepcopy(valid)
        for o in bad['objects']:
            if o['id'].startswith('studio-cover'):o['position']=bad['objective'];break
        self.assertFalse(preflight(bad)['passed'])

    def test_report_rejects_invented_ticks_and_requires_all_sides(self):
        evidence={'allowed_ticks':[10,20]};r=report(evidence);Studio.validate_report(r,evidence)
        r['evidence'][0]['tick']=900
        with self.assertRaises(ValueError):Studio.validate_report(r,evidence)
        r=report(evidence);r['factions'][0]['faction']='unknown'
        with self.assertRaises(ValueError):Studio.validate_report(r,evidence)

    def test_generate_repair_archive_and_logged_roles(self):
        with tempfile.TemporaryDirectory() as d:
            s=state();lm=SimpleNamespace(ready=True,config={'key':'TEST_SECRET','model':'test','base_url':'https://ark.cn-beijing.volces.com/api/v3'},call_log=CallLog(secret='TEST_SECRET'))
            calls=[]
            class Client:
                def complete(self,payload,trace):
                    calls.append(payload);value=example()
                    if len(calls)==1:value['hold_seconds']=0
                    else:value['covers'][0]['position'][0]+=.02
                    trace(http_status=200,response_text=json.dumps(value));return value,{'total_tokens':12}
            studio=Studio(s,lm,path=Path(d)/'studio.db',client=Client(),validator=lambda l:{'passed':True,'open_approaches':4,'spawn_routes':[1]*9})
            try:
                job=studio.launch('generate',{'brief':'交替掩护的战术关卡'})
                for _ in range(100):
                    saved=studio.store.get('job',job['id'])
                    if saved['phase']!='running':break
                    time.sleep(.01)
                self.assertEqual(saved['phase'],'complete');self.assertEqual(len(calls),2)
                artifact=studio.store.get('scenario',job['id']);self.assertEqual(artifact['origin'],'llm')
                self.assertEqual([r['phase'] for r in lm.call_log.list()['items']],['validated','rejected'])
                self.assertTrue(all(r['unit_id']=='level-designer' for r in lm.call_log.list()['items']))
                self.assertNotIn('TEST_SECRET',json.dumps(artifact))
            finally:studio.close()

    def test_battle_evidence_stays_with_its_run_and_auto_report_deduplicates(self):
        with tempfile.TemporaryDirectory() as d:
            s=state();lm=SimpleNamespace(ready=True,config={'key':'x','model':'test','base_url':'https://ark.cn-beijing.volces.com/api/v3'},call_log=CallLog())
            calls=[]
            class Client:
                def complete(self,payload,trace):
                    value=json.loads(payload['messages'][1]['content']);calls.append(value);r=report(value['evidence_input']);trace(response_text=json.dumps(r));return r,{}
            studio=Studio(s,lm,path=Path(d)/'studio.db',client=Client())
            try:
                s.state['scenario']={'id':'custom','briefing':'未经证实的战术描述'};studio.observe(s.state)
                s.state.update(time=4,tick=20,winner='green');studio.observe(s.state)
                studio.maybe_report();studio.maybe_report()
                for _ in range(100):
                    if not studio.pending:break
                    time.sleep(.01)
                self.assertEqual(len(calls),1)
                artifact=studio.store.list('report')[0];self.assertEqual(artifact['winner'],'green');self.assertEqual(artifact['evidence_input']['allowed_ticks'],[10,20])
                evidence=artifact['evidence_input'];self.assertNotIn('briefing',evidence['scenario']);self.assertTrue(evidence['design_intent']['unverified']);self.assertEqual(evidence['coordinate_frame']['down'],'+z')
                s.state.update(run_id='next',tick=1,time=0,winner='');studio.observe(s.state)
                self.assertEqual(studio.evidence(s.state)['allowed_ticks'],[1]);self.assertEqual(artifact['run_id'],'r')
                studio.last_request=0
                with self.assertRaisesRegex(ValueError,'stale_run'):studio.launch('analyze',{'run_id':'r'})
            finally:studio.close()
