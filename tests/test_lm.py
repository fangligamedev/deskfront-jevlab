import copy,json,sys,time,threading,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from server import State,validate_command
from lm_controller import LMController,validate_decision,ArkClient,ProviderError,observation,load_config


def unit(id='green-1',team='green'):
    return {'id':id,'faction':team,'kind':'infantry','hp':100,'max_hp':100,'position':[0,0],'goal':[0,0],'available_actions':['move','capture','cover','flank','retreat','hold','attack','posture','grenade'],'in_cover':False,'suppression':0,'weapon':'rifle'}

def state():
    s=State();s.record=lambda *a:None;s.updated=time.monotonic()
    s.state={'schema_version':1,'run_id':'r','tick':10,'time':0,'bounds':[-1,-1,1,1],'control':{'green':'lm','red':'game_ai'},'control_epochs':{'green':1,'red':0},'units':[unit(),unit('green-2'),unit('red-1','red')],'objective':{'position':[.2,.2],'radius':.1},'covers':[],'paused':False,'winner':''}
    return s


def controller(s,client,**extra):
    cfg={'key':'TEST_SECRET_MUST_NOT_LEAK','model':'test-model','base_url':'https://ark.cn-beijing.volces.com/api/v3','interval':3,'timeout':1,'max_requests':6,'concurrency':2};cfg.update(extra)
    return LMController(s,cfg,client)


def settle(c):
    for _ in range(100):
        if all(t['future'].done() for t in c.pending.values()):break
        time.sleep(.005)
    c.tick()


class LMContract(unittest.TestCase):
    def test_possessed_infantry_is_excluded_while_teammates_continue(self):
        seen=[]
        def client(o):seen.append(o['self']['id']);return {'action':'hold','intent':'observe'},{}
        s=state();s.state['units'][0]['direct_controlled']=True;c=controller(s,client)
        try:
            c.tick();settle(c)
            self.assertEqual(seen,['green-2'])
            self.assertTrue(all(q['unit_ids']==['green-2'] for q in s.pending.values()))
        finally:c.close()
    def test_four_modes_and_public_source_cannot_spoof_lm(self):
        for mode in ['game_ai','lm','agent','player']:self.assertIsNone(validate_command({'action':'control','mode':mode}))
        s=state();_,r=s.submit({'action':'hold','source':'lm'});self.assertEqual(s.pending[r['id']]['source'],'console')
    def test_decision_rejects_cross_unit_fields_admin_and_bad_values(self):
        s=state().state;u=s['units'][0]
        for bad in [{'action':'config','intent':'survive'}, {'action':'move','intent':'advance','position':[float('nan'),0]}, {'action':'move','intent':'advance','position':[8,0]}, {'action':'attack','intent':'engage','target_id':'green-2'}, {'action':'cover','intent':'survive','unit_ids':['green-2']}, {'action':'posture','intent':'survive'}]:
            with self.assertRaises(ValueError):validate_decision(bad,s,u)
        u['kind']='tank'
        with self.assertRaises(ValueError):validate_decision({'action':'hold','intent':'survive','posture':'prone'},s,u)
    def test_per_unit_requests_commands_and_secret_redaction(self):
        seen=[]
        def client(o):seen.append(o['self']['id']);return {'action':'cover','intent':'survive','reason':'找掩体'}, {'total_tokens':20}
        s=state();c=controller(s,client)
        try:
            c.tick();settle(c)
            self.assertEqual(set(seen),{'green-1','green-2'});self.assertEqual(len(s.pending),2)
            self.assertEqual({tuple(q['unit_ids']) for q in s.pending.values()},{('green-1',),('green-2',)})
            self.assertTrue(all(q['source']=='lm' for q in s.pending.values()))
            self.assertNotIn('TEST_SECRET',json.dumps(c.snapshot()));self.assertEqual(c.metrics['tokens'],40)
            commands=list(s.pending);s.sync({'state':s.state,'acks':[{'id':i,'accepted':True} for i in commands]});c.tick()
            self.assertEqual(c.metrics['accepted'],2)
        finally:c.close()
    def test_switch_away_and_back_invalidates_inflight_result(self):
        release=threading.Event()
        def client(o):release.wait(2);return {'action':'capture','intent':'capture'},{}
        s=state();c=controller(s,client)
        try:
            c.tick();s.state['control_epochs']['green']=3;release.set();settle(c)
            self.assertEqual(len(s.pending),0);self.assertEqual(c.metrics['discarded'],2)
        finally:release.set();c.close()
    def test_reset_and_death_discard_inflight(self):
        release=threading.Event()
        def client(o):release.wait(2);return {'action':'attack','intent':'engage','target_id':'red-1'},{}
        s=state();c=controller(s,client)
        try:
            c.tick();s.state['run_id']='new';s.state['paused']=True;s.state['units'][0]['hp']=0;release.set();settle(c)
            self.assertEqual(len(s.pending),0);self.assertEqual(c.metrics['discarded'],2)
        finally:release.set();c.close()
    def test_errors_fall_back_without_freezing_engine(self):
        def client(o):raise ProviderError('provider_http_401')
        s=state();c=controller(s,client)
        try:
            c.tick();settle(c);self.assertEqual(c.metrics['errors'],2)
            self.assertTrue(all(q['action']=='cover' for q in s.pending.values()))
            self.assertTrue(all(v['origin']=='local_fallback' for v in c.units.values()))
        finally:c.close()
    def test_budget_and_wait_are_not_fake_engine_acks(self):
        def client(o):return {'action':'wait','intent':'observe','reason':'保持路线'},{}
        s=state();c=controller(s,client,max_requests=1)
        try:
            c.tick();settle(c);self.assertEqual(c.used,1)
            self.assertEqual(c.units['green-1']['phase'],'waiting');self.assertNotIn('command_id',c.units['green-1'])
            self.assertTrue(all(q['unit_ids']==['green-2'] for q in s.pending.values()))
        finally:c.close()
    def test_unconfigured_and_paused_never_calls_provider(self):
        seen=[];s=state();c=controller(s,lambda o:seen.append(o),key='')
        try:
            s.state['paused']=True;c.tick();self.assertEqual(s.pending,{})
            s.state['paused']=False;c.tick();self.assertEqual(seen,[]);self.assertEqual(c.used,0)
        finally:c.close()
    def test_provider_host_is_exact_and_never_redirects_keys(self):
        for base in ['http://ark.cn-beijing.volces.com/api/v3','https://evil.example/api/v3','https://ark.cn-beijing.volces.com.evil/api/v3','https://ark.cn-beijing.volces.com/api/v3?key=secret']:
            with self.assertRaises(ValueError):ArkClient({'base_url':base})
    def test_lm_queue_rejects_multi_unit_or_changed_epoch(self):
        s=state();cmd={'action':'hold','faction':'green','run_id':'r','seen_tick':10,'control_epoch':1,'unit_ids':['green-1','green-2']}
        self.assertEqual(s.submit(cmd,source='lm')[1]['error'],'lm_single_unit_required')
        cmd['unit_ids']=['green-1'];cmd['control_epoch']=0;self.assertEqual(s.submit(cmd,source='lm')[1]['error'],'lm_authority_changed')
    def test_equipment_actions_and_light_weapon_safety(self):
        s=state().state;u=s['units'][0];u['available_actions']+=['man_at_gun','garrison']
        s['at_guns']=[{'id':'green-at','faction':'green'}]
        self.assertEqual(validate_decision({'action':'man_at_gun','intent':'survive','gun_id':'green-at'},s,u)['gun_id'],'green-at')
        self.assertEqual(validate_decision({'action':'garrison','intent':'support','floor':2},s,u)['floor'],2)
        for bad in [{'action':'garrison','intent':'support','floor':3},{'action':'man_at_gun','intent':'survive','gun_id':'red-at'},{'action':'hold','intent':'observe','floor':2}]:
            with self.assertRaises(ValueError):validate_decision(bad,s,u)
        s['units'][-1]['kind']='tank'
        with self.assertRaisesRegex(ValueError,'anti_armor_required'):validate_decision({'action':'attack','intent':'engage','target_id':'red-1'},s,u)
        u['weapon']='rocket';self.assertEqual(validate_decision({'action':'attack','intent':'engage','target_id':'red-1'},s,u)['target_id'],'red-1')
    def test_fallback_preserves_active_equipment_job(self):
        s=state();s.state['units'][0]['gun_id']='green-at';s.state['units'][1]['building_phase']='approaching'
        c=controller(s,lambda o:None,key='')
        try:
            c.tick();self.assertEqual(len(s.pending),0);self.assertTrue(all(v['action']=='wait' for v in c.units.values()))
        finally:c.close()
    def test_observation_contains_only_game_state(self):
        s=state().state;o=observation(s,s['units'][0],[])
        self.assertEqual(o['self']['id'],'green-1');self.assertEqual(len(o['allies']),1);self.assertEqual(len(o['enemies']),1)
        self.assertNotIn('key',o);self.assertNotIn('screen_position',o['self'])
    def test_mission_excludes_wounded_equipment_crew_and_tanks(self):
        s=state().state
        s['units'][1]['tactical_role']='assault'
        s['units'][0]['combat']={'engageable_targets':['red-1'],'incoming_threats':[],'path_active':False}
        o=observation(s,s['units'][0],[])
        self.assertEqual(o['mission']['advance_unit_id'],'green-2')
        self.assertEqual(o['self']['combat']['engageable_targets'],['red-1'])
        for change in [{'hp':10},{'gun_id':'green-at'},{'kind':'tank'},{'building_phase':'stationed'}]:
            variant=copy.deepcopy(s);variant['units'][1].update(change)
            self.assertEqual(observation(variant,variant['units'][0],[])['mission']['advance_unit_id'],'green-1')
    def test_status_and_model_action_counts_distinguish_budget_fallback(self):
        seen=[]
        def client(o):seen.append(o);return {'action':'capture','intent':'capture'},{}
        s=state();c=controller(s,client,max_requests=1)
        try:
            c.tick();settle(c)
            self.assertEqual(c.snapshot()['status'],'budget_exhausted')
            self.assertEqual(c.metrics['model_actions'],{'capture':1})
            self.assertIn('idle_seconds',seen[0]['progress'])
            self.assertTrue(any(u['origin']=='local_fallback' for u in c.units.values()))
            s.state['paused']=True;c.tick();self.assertEqual(c.snapshot()['status'],'paused')
            s.state['control']['green']='player';c.tick();self.assertEqual(c.snapshot()['status'],'idle')
        finally:c.close()

if __name__=='__main__':unittest.main()
