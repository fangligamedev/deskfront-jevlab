import copy, json, sys, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from frontier_plan import validate_layout, sector_plan, COMPONENTS, fit_campaign_layouts
from server import validate_command

def layout():
 return {'theme':'village','objective_z':0,'components':[
  {'kind':'house','x':.42,'z':-.8,'width':.30,'depth':.36},
  {'kind':'trench','x':.65,'z':0,'width':.075,'depth':.34},
  {'kind':'bunker','x':.97,'z':.78,'width':.30,'depth':.32},
  {'kind':'fuel_depot','x':.85,'z':-.75,'width':.15,'depth':.20},
  {'kind':'mud','x':.40,'z':.65,'width':.25,'depth':.40},
  {'kind':'water','x':.78,'z':-1.18,'width':.40,'depth':.15}]}

class ComponentPlans(unittest.TestCase):
 def test_typed_composition_and_command(self):
  p={'template':'staggered','defenders':[{'weapon':'rifle','station':0},{'weapon':'rocket','station':2}],'defense':'entrench','construction':'balanced','armor':{t:{'enabled':True,'delay':2,'role':'support'} for t in ('green','red')},'reason':'分散设防','layout':layout()}
  self.assertEqual(sector_plan(p),p)
  self.assertIsNone(validate_command({'action':'eastfront_propose','sequence':1,'template':'staggered','battle_plan':p}))
 def test_bad_geometry_is_rejected_before_engine(self):
  for key,value in [('kind','script'),('kind',[]),('x',float('nan')),('depth',float('inf')),('width',True),('width',2),('z',1.35)]:
   v=layout();v['components'][0][key]=value
   with self.assertRaises(ValueError):validate_layout(v)
  v=layout();v['components'][1]=v['components'][0].copy()
  with self.assertRaisesRegex(ValueError,'overlapping'):validate_layout(v)
  v=layout();v['components'][0].update(x=1.2,z=0,width=.15)
  with self.assertRaisesRegex(ValueError,'blocked_objective'):validate_layout(v)
  for kind in ['mud','road','water','fuel_depot']:
   v=layout();v['components'][0]['kind']=kind
   with self.assertRaisesRegex(ValueError,'unsafe_defender_station'):validate_layout(v)
 def test_catalog_and_real_width(self):
  rules=json.loads((Path(__file__).resolve().parents[1]/'data/eastfront.json').read_text())
  self.assertEqual(rules['half_depth']*2,2.8)
  self.assertEqual(len(COMPONENTS),11)
  self.assertTrue(COMPONENTS['trench']['crushable'])
  self.assertFalse(COMPONENTS['house'].get('crushable',False))
  self.assertGreater(COMPONENTS['fuel_depot']['blast_radius'],0)

class EditorPacking(unittest.TestCase):
 def test_overlap_is_snapped_locally_without_changing_model_materials(self):
  original=layout();original['components'][3]['x']=.5;original['components'][3]['z']=-.8
  value={'sectors':[{'layout':original}]}
  fitted,edits=fit_campaign_layouts(value)
  self.assertTrue(edits);validate_layout(fitted['sectors'][0]['layout'])
  self.assertEqual(value['sectors'][0]['layout'],original)
  for a,b in zip(original['components'],fitted['sectors'][0]['layout']['components']):
   self.assertEqual([a[k] for k in ('kind','width','depth')],[b[k] for k in ('kind','width','depth')])
   self.assertLessEqual((a['x']-b['x'])**2+(a['z']-b['z'])**2,.35**2+1e-8)
 def test_terrain_order_does_not_turn_fuel_into_a_defender_station(self):
  v=layout();v['components'].insert(0,v['components'].pop(3))
  self.assertEqual(validate_layout(v),v)
 def test_packing_never_relabels_unsafe_station(self):
  original=layout();original['components'][0]['kind']='fuel_depot'
  with self.assertRaises(ValueError):fit_campaign_layouts({'sectors':[{'layout':original}]})
