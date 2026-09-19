extends RefCounted
## Shared conversion used by production maps and preflight navigation validation.
static func apply(config:Dictionary, level:Dictionary, height:float=.838) -> void:
 config.bounds=level.bounds.duplicate();config.table_height=height
 config.objective=level.objective.duplicate()
 if level.id=="river":config.objective=[.54,2.38]
 config.covers=[];config.obstacles=[];config["water"]=[];config["bridges"]=[]
 for i in range(config.factions.size()):
  config.factions[i].spawn=level.spawns[i].duplicate();config.factions[i].goal=config.objective.duplicate()
 for o in level.objects:
  if o.kind=="water":config.water.append(o);continue
  if o.kind=="bridge":config.bridges.append(o);continue
  if not o.collision:continue
  var yaw=deg_to_rad(o.yaw)
  var sx=absf(cos(yaw))*o.size[0]+absf(sin(yaw))*o.size[2]
  var sz=absf(sin(yaw))*o.size[0]+absf(cos(yaw))*o.size[2]
  config.covers.append({"id":o.id,"position":o.position,"size":[sx,sz],"normal":[0,1] if sx>sz else [1,0],"height":o.size[1],"hp":(-1 if level.get("surface","")=="desk" and not o.destructible else config.destruction.get(o.kind,180)),"label":o.get("asset",o.kind),"ray_size":o.size.duplicate(),"yaw":yaw,"bottom":height+o.get("elevation",0),"kind":"hard" if o.size[1]>.09 else o.kind})
 if level.has("hold_seconds"):config.rules.hold_seconds=level.hold_seconds;config.rules.score_to_win=level.hold_seconds
