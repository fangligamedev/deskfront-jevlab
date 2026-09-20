import unittest,sys,json,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from server import State,validate_command

class ControlContract(unittest.TestCase):
    def test_agent_cannot_run_admin(self):
        for action in ['reset','config','control','reinforce','pause']:
            self.assertIsNotNone(validate_command({'action':action},True))
    def test_types_and_nan(self):
        for position in [[0,float('nan')],['a',0],[1],{},True]:
            self.assertEqual(validate_command({'action':'move','position':position}),'invalid_position')
        self.assertEqual(validate_command({'action':'move'}),'position_required')
        self.assertEqual(validate_command({'action':'speed','value':'fast'}),'invalid_value')
    def test_freshness_required(self):
        self.assertEqual(validate_command({'action':'capture'},True),'observation_required')
        self.assertIsNone(validate_command({'action':'capture','run_id':'test','seen_tick':50},True))
    def test_posture_contract(self):
        self.assertIsNone(validate_command({'action':'posture','posture':'prone','run_id':'r','seen_tick':1},True))
        self.assertEqual(validate_command({'action':'posture','posture':'fly'}),'invalid_posture')
        catalog=json.loads((Path(__file__).resolve().parents[1]/'data/action-catalog.json').read_text())
        self.assertEqual(set(catalog['commands']),{'move','capture','cover','flank','retreat','hold','attack','grenade','posture','man_at_gun','leave_gun','garrison','leave_building','debug_visualize','possess','release_unit','eastfront_start','eastfront_propose','eastfront_follow','eastfront_directive'})
        self.assertEqual(validate_command({'action':'debug_visualize','value':True,'run_id':'r','seen_tick':1},True),'unknown_or_forbidden_action')
    def test_queue_is_not_ack(self):
        s=State();s.record=lambda *a:None
        self.assertEqual(s.submit({'action':'hold'})[0],409)
        self.assertEqual(s.sync({'state':{'schema_version':1,'units':[],'run_id':'a'},'acks':[]})[0],200)
        status,command=s.submit({'action':'hold'})
        self.assertEqual(status,202);self.assertNotIn(command['id'],s.results)
        _,r=s.sync({'state':s.state,'acks':[]});self.assertEqual(r['commands'][0]['id'],command['id'])
        _,r=s.sync({'state':s.state,'acks':[{'id':command['id'],'accepted':True}]})
        self.assertEqual(r['commands'],[]);self.assertTrue(s.results[command['id']]['accepted'])
    def test_new_run_expires_old_moves(self):
        s=State();s.record=lambda *a:None;s.updated=time.monotonic();s.state={'run_id':'a'}
        _,c=s.submit({'action':'hold'})
        s.sync({'state':{'schema_version':1,'units':[],'run_id':'b'}})
        self.assertFalse(s.results[c['id']]['accepted']);self.assertEqual(len(s.pending),0)
    def test_new_run_does_not_invent_reset_success(self):
        s=State();s.record=lambda *a:None;s.updated=time.monotonic();s.state={'run_id':'a'}
        _,c=s.submit({'action':'reset'})
        s.sync({'state':{'schema_version':1,'units':[],'run_id':'b'}})
        self.assertFalse(s.results[c['id']]['accepted'])
        self.assertEqual(s.results[c['id']]['message'],'stale_run')
    def test_scene_reload_keeps_real_reset_and_map_ack(self):
        for action in [{'action':'reset'},{'action':'map','index':1}]:
            s=State();s.record=lambda *a:None
            token=s.open_session()[1]['instance_id']
            s.sync({'instance_id':token,'state':{'schema_version':1,'units':[],'run_id':'a'}})
            _,c=s.submit(dict(action,instance_id=token,run_id='a'))
            s.sync({'instance_id':token,'state':{'schema_version':1,'units':[],'run_id':'b'},'acks':[{'id':c['id'],'accepted':True,'message':'applied'}]})
            self.assertTrue(s.results[c['id']]['accepted']);self.assertFalse(s.pending)
    def test_old_instance_cannot_replace_state_consume_commands_or_forge_ack(self):
        s=State();s.record=lambda *a:None
        old=s.open_session()[1]['instance_id'];new=s.open_session()[1]['instance_id']
        state={'schema_version':1,'units':[],'run_id':'new'}
        s.sync({'instance_id':new,'state':state})
        _,c=s.submit({'action':'equip','weapon':'smg','instance_id':new,'run_id':'new'})
        for payload in [{'instance_id':old,'state':dict(state,run_id='old')},{'state':dict(state,run_id='legacy')}]:
            payload['acks']=[{'id':c['id'],'accepted':True}]
            self.assertEqual(s.sync(payload)[0],409)
            self.assertEqual(s.state['run_id'],'new');self.assertIn(c['id'],s.pending)
            self.assertNotIn(c['id'],s.results)
        self.assertEqual(s.submit({'action':'reset','instance_id':old})[1]['error'],'session_replaced')
        self.assertEqual(s.submit({'action':'reset'})[1]['error'],'session_replaced')
    def test_replaced_session_expires_queue_and_stale_console_observation(self):
        s=State();s.record=lambda *a:None;old=s.open_session()[1]['instance_id']
        s.sync({'instance_id':old,'state':{'schema_version':1,'units':[],'run_id':'a'}})
        self.assertEqual(s.submit({'action':'reset','instance_id':old,'run_id':'old'})[1]['error'],'stale_run')
        _,c=s.submit({'action':'reset','instance_id':old,'run_id':'a'})
        s.open_session()
        self.assertFalse(s.results[c['id']]['accepted']);self.assertEqual(s.results[c['id']]['message'],'session_replaced')
        self.assertEqual(s.state,{});self.assertFalse(s.pending)
if __name__=='__main__':unittest.main()
