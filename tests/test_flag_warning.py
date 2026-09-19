import copy,time,threading,unittest
from test_lm import state,unit,controller,settle
from lm_controller import observation,build_payload

def warn(s, owner='red', epoch=1, seconds=30, contested=False):
    alerts={f:({'active':True,'type':'flag_defeat_warning','priority':'critical','capture_epoch':epoch,'owner':owner,'remaining_seconds':seconds,'countdown_seconds':seconds,'contested':contested,'accept_casualties':True,'must_retake':True,'message':f'紧急：剩余 {seconds} 秒，必须夺旗，否则战败'} if f!=owner else {'active':False}) for f in ['green','blue','red']}
    s.state['objective']['flag']={'owner':owner,'capture_epoch':epoch,'remaining_seconds':seconds,'countdown_seconds':seconds,'contested':contested,'alerts':alerts}

class FlagWarningContract(unittest.TestCase):
    def test_both_opponents_get_explicit_warning_but_owner_does_not(self):
        s=state();s.state['units'].append(unit('blue-1','blue'));warn(s)
        for u in s.state['units']:
            o=observation(s.state,u,[])
            self.assertEqual(o['flag_warning']['active'],u['faction']!='red')
            if u['faction']!='red':
                self.assertEqual(o['mission']['priority'],'critical')
                self.assertTrue(o['mission']['accept_casualties'])
                payload=build_payload({'model':'test'},o)
                self.assertIn('战败',payload['messages'][1]['content'])
                self.assertIn('不惜伤亡',payload['messages'][0]['content'])
        s.state['winner']='red';self.assertFalse(observation(s.state,s.state['units'][0],[])['flag_warning']['active'])

    def test_claim_interrupts_normal_think_interval_without_per_tick_spam(self):
        seen=[]
        def client(o):seen.append(copy.deepcopy(o));return {'action':'wait','intent':'observe'},{}
        s=state();c=controller(s,client,interval=30,max_requests=20)
        try:
            c.tick();settle(c);self.assertEqual(len(seen),2)
            warn(s);c.tick();settle(c)
            self.assertEqual(len(seen),4);self.assertTrue(all(o['flag_warning']['active'] for o in seen[2:]))
            for _ in range(10):c.tick()
            self.assertEqual(len(seen),4)
            warn(s,seconds=10);c.tick();settle(c)
            self.assertEqual(len(seen),6);self.assertEqual(seen[-1]['flag_warning']['remaining_seconds'],10)
        finally:c.close()

    def test_inflight_pre_capture_hold_is_discarded_then_warning_sent(self):
        release=threading.Event();seen=[]
        def client(o):
            seen.append(copy.deepcopy(o))
            if not o['flag_warning']['active']:release.wait(1)
            return {'action':'capture' if o['flag_warning']['active'] else 'hold','intent':'capture'},{}
        s=state();c=controller(s,client,max_requests=20)
        try:
            c.tick();warn(s);release.set();settle(c);settle(c)
            self.assertEqual(c.metrics.get('discarded'),2)
            self.assertTrue(any(o['flag_warning']['active'] for o in seen))
            self.assertTrue(s.pending)
            self.assertTrue(all(q['action']=='capture' and q['flag_epoch']==1 for q in s.pending.values()))
        finally:release.set();c.close()

    def test_budget_fallback_counterattacks_and_never_claims_model_success(self):
        s=state();warn(s);c=controller(s,lambda o:({'action':'wait','intent':'observe'},{}),max_requests=0)
        try:
            c.tick();self.assertEqual(c.used,0)
            self.assertTrue(all(q['action']=='capture' for q in s.pending.values()))
            self.assertTrue(all(u['origin']=='local_fallback' and u['phase']=='fallback' for u in c.units.values()))
            self.assertEqual(c.metrics.get('responses',0),0)
        finally:c.close()

    def test_equipment_fallback_exits_before_capture(self):
        s=state();warn(s)
        s.state['units'][0].update(building_phase='stationed',available_actions=['leave_building'])
        s.state['units'][1].update(gun_id='green-at',available_actions=['leave_gun'])
        c=controller(s,lambda o:({},{}),max_requests=0)
        try:c.tick();self.assertEqual({q['action'] for q in s.pending.values()},{'leave_building','leave_gun'})
        finally:c.close()

    def test_contested_warning_preserves_engine_countdown(self):
        s=state();warn(s,seconds=9,contested=True)
        o=observation(s.state,s.state['units'][0],[])
        self.assertTrue(o['flag_warning']['contested']);self.assertEqual(o['flag_warning']['remaining_seconds'],9)

if __name__=='__main__':unittest.main()
