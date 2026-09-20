extends RefCounted
## Mirror of the public typed plan contract. Validate before allocating game nodes.
static func validate(p,template:String)->String:
 if not p is Dictionary or p.size()!=6:return "invalid_battle_plan"
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
 return ""
