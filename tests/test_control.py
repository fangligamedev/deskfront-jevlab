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
    def test_reset_ack_on_new_run(self):
        s=State();s.record=lambda *a:None;s.updated=time.monotonic();s.state={'run_id':'a'}
        _,c=s.submit({'action':'reset'})
        s.sync({'state':{'schema_version':1,'units':[],'run_id':'b'}})
        self.assertTrue(s.results[c['id']]['accepted'])
if __name__=='__main__':unittest.main()
