extends RefCounted
## Mirror of the public typed plan contract. Validate before allocating game nodes.
static func validate(p,template:String)->String:
 if not p is Dictionary or p.size()!=(7 if p.has("layout") else 6):return "invalid_battle_plan"
 for key in ["template","defenders","defense","construction","armor","reason"]:
  if not p.has(key):return "invalid_battle_plan"
 if p.template!=template or not p.reason is String or p.reason.length()<1 or p.reason.length()>160:return "invalid_plan_template"
 if p.defense not in ["entrench","crossfire","fallback"] or p.construction not in ["balanced","north_first","south_first","dig_first","sandbag_first"]:return "invalid_plan_policy"
 if not p.defenders is Array or p.defenders.size()<2 or p.defenders.size()>3:return "invalid_defenders"
 var stations:Array=[];var anti:bool=false
 for row in p.defenders:
  if not row is Dictionary or row.size()!=2 or not row.has("weapon") or not row.has("station"):return "invalid_defenders"
  if row.weapon not in ["rifle","smg","rocket"] or not (row.station is int or row.station is float):return "invalid_defenders"
  if int(row.station)!=row.station or row.station<0 or row.station>2 or stations.has(int(row.station)):return "invalid_defender_station"
  stations.append(int(row.station));anti=anti or row.weapon=="rocket"
 if not p.armor is Dictionary or p.armor.size()!=2:return "invalid_armor_plan"
 for team in ["green","red"]:
  var a=p.armor.get(team,{})
  if not a is Dictionary or a.size()!=3 or not a.get("enabled") is bool or a.get("role") not in ["support","push"]:return "invalid_armor_plan"
  if not (a.get("delay") is int or a.get("delay") is float):return "invalid_armor_plan"
  if not is_finite(float(a.delay)) or a.delay<0 or a.delay>20:return "invalid_armor_plan"
 if p.armor.green.enabled and not anti:return "defenders_need_anti_armor"
 if p.has("layout"):return validate_layout(p.layout)
 return ""

static func validate_layout(layout)->String:
 var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/eastfront.json"))
 var limits:Dictionary=rules.layout_limits
 var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/frontier_components.json"))
 if not layout is Dictionary or layout.size()!=3 or layout.get("theme") not in ["meadow","dust","ruins","trench","supply","ridge","village","industrial","forest"]:return "invalid_layout"
 if not number(layout.get("objective_z")) or absf(layout.objective_z)>.9:return "invalid_objective_z"
 var rows=layout.get("components")
 if not rows is Array or rows.size()<3 or rows.size()>int(limits.max_components):return "invalid_component_count"
 for i in range(rows.size()):
  var c=rows[i]
  if not c is Dictionary or c.size()!=5 or not catalog.has(c.get("kind","")):return "invalid_component"
  for key in ["x","z","width","depth"]:
   if not number(c.get(key)):return "invalid_component_bounds"
  if c.width<.04 or c.width>float(limits.max_component_width) or c.depth<.04 or c.depth>float(limits.max_component_depth) or c.x<.25 or c.x>float(rules.width)-.20 or c.x-c.width/2<.12 or c.x+c.width/2>float(rules.width)-.10 or absf(c.z)+c.depth/2>1.32:return "invalid_component_bounds"
  if absf(c.x-(float(rules.width)-.22))<c.width/2+.13 and absf(c.z-layout.objective_z)<c.depth/2+.13:return "blocked_objective"
  for b in rows.slice(0,i):
   if absf(c.x-b.x)<(c.width+b.width)/2+.04 and absf(c.z-b.z)<(c.depth+b.depth)/2+.04:return "overlapping_components"
 if rows.filter(func(c):return not catalog[c.kind].get("no_slots",false) and c.kind!="fuel_depot").size()<3:return "unsafe_defender_station"
 return ""
static func number(v)->bool:return (v is int or v is float) and is_finite(float(v))
