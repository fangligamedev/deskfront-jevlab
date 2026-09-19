import json, unittest, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from server import validate_command
class OfficeBattlefield(unittest.TestCase):
 def test_new_default_and_map_authority(self):
  maps=json.loads((ROOT/'data/sandbox-maps.json').read_text())
  self.assertEqual(maps['levels'][maps['default_level']]['surface'],'desk')
  self.assertIsNone(validate_command({'action':'map','index':maps['default_level']}))
  self.assertEqual(validate_command({'action':'map','index':len(maps['levels'])}),'invalid_map')
  self.assertEqual(validate_command({'action':'map','index':maps['default_level']},True),'unknown_or_forbidden_action')
 def test_office_footprints_on_expanded_desk(self):
  maps=json.loads((ROOT/'data/sandbox-maps.json').read_text());level=maps['levels'][maps['default_level']]
  self.assertEqual(level['design']['table_width_after'],level['design']['table_width_before']*2)
  self.assertAlmostEqual(level['design']['table_right']-level['design']['table_left'],level['design']['table_width_after'])
  for o in level['objects']:
   self.assertTrue((ROOT/'assets/models'/str(o['asset']+'.glb')).exists())
   self.assertGreaterEqual(o['position'][0]-max(o['size'][0],o['size'][2])*.5,level['bounds'][0])
   self.assertLessEqual(o['position'][0]+max(o['size'][0],o['size'][2])*.5,level['bounds'][2])
