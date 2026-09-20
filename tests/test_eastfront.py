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
