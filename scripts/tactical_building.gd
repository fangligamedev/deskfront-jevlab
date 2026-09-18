extends Node3D
# Open-roof inspection building, metre-scale components with separate collision.
var game
var stations:Dictionary={}
var exit_queue:Array=[]
var spec:Dictionary
var hp=240
var parts:Array=[]
var breached=false
var collapsed=false
var floor_y=1.028
var stair:StaticBody3D
func setup(config:Dictionary):
 spec=config;hp=int(spec.health);floor_y=.838+float(spec.floor_height)
 var x=float(spec.center[0]);var z=float(spec.center[1]);var w=float(spec.size[0]);var d=float(spec.size[1])
 var plaster=Color('#c1bca2');var timber=Color('#79725b');var base=.838
 # Ground slab, upper floor, rear wall and right wall, all visible as separate storeys.
 part('ground',Vector3(x,base+.007,z),Vector3(w,.014,d),Color('#a8a58c'),false)
 part('upper_floor',Vector3(x,floor_y-.008,z),Vector3(w,.016,d),timber,true)
 for story in 2:
  var y=base+story*float(spec.floor_height)
  part('rear_wall_'+str(story),Vector3(x,y+.083,z-d/2),Vector3(w,.166,.018),plaster,true)
  # Outer (east) wall is blank; the upper landing door is on the rear side.
  if story==0:
   part('outer_wall',Vector3(x+w/2,y+.083,z),Vector3(.018,.166,d),plaster,true)
  else:
   for dz in [-.185,.185]:part('outer_wall_door_side',Vector3(x+w/2,y+.083,z+dz),Vector3(.018,.166,.19),plaster,true)
  # Battlefield-facing west windows: sill, narrow piers, lintel, three clear firing apertures.
  part('field_window_sill',Vector3(x-w/2,y+.025,z),Vector3(.018,.05,d),plaster,true)
  part('field_window_lintel',Vector3(x-w/2,y+.159,z),Vector3(.023,.025,d),plaster,true)
  for dz in [-.265,-.09,.09,.265]:part('field_window_pier',Vector3(x-w/2,y+.097,z+dz),Vector3(.021,.144,.018),plaster,true)
  for dx in [-w/2,w/2]:part('front_post',Vector3(x+dx,y+.085,z+d/2),Vector3(.028,.17,.028),timber,true)
  part('front_beam',Vector3(x,y+.176,z+d/2),Vector3(w+.025,.021,.027),timber,true)
 # Twelve visible treads; a continuous wedge collider avoids tiny-scale step snagging.
 var sx=float(spec.stair_x);var back=float(spec.stair_back);var front=float(spec.stair_front)
 for i in 12:
  var step_depth=(front-back)/12;var height=float(spec.floor_height)*(i+1)/12
  part('stair_tread',Vector3(sx,base+height/2,front-(i+.5)*step_depth),Vector3(.13,height,step_depth+.002),timber,true,false)
 stair=StaticBody3D.new();stair.name='StairRamp';add_child(stair);stair.collision_layer=1
 var shape=ConvexPolygonShape3D.new();var pts=PackedVector3Array()
 for dx in [-.065,.065]:
  pts.append(Vector3(sx+dx,base,front));pts.append(Vector3(sx+dx,base,back));pts.append(Vector3(sx+dx,floor_y,back))
 shape.points=pts;var col=CollisionShape3D.new();col.shape=shape;stair.add_child(col)
 part('upper_landing',Vector3(x+w/2+.035,floor_y-.008,back-.06),Vector3(.14,.016,.12),timber,true)
 # Bridge the 1 cm gap between floor edge and ramp without covering its slope.
 part('landing_threshold',Vector3(x+w/2+.0075,floor_y-.008,back),Vector3(.022,.016,.16),timber,true)
 # Broken plaster courses and framing are geometry, not texture text.
 for i in 7:
  part('rear_course',Vector3(x,base+.024+i*.047,z-d/2-.010),Vector3(w,.003,.002),Color('#9b9882'),true,false)
func part(id:String,p:Vector3,size:Vector3,color:Color,destructible:bool,solid=true):
 var node=StaticBody3D.new();node.name=id;add_child(node);node.position=p;node.collision_layer=1 if solid else 0;node.collision_mask=0
 var mesh=MeshInstance3D.new();var box=BoxMesh.new();box.size=size;mesh.mesh=box;var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.85;mesh.material_override=mat;node.add_child(mesh)
 if solid:
  var cs=CollisionShape3D.new();var bs=BoxShape3D.new();bs.size=size;cs.shape=bs;node.add_child(cs)
 parts.append({'id':id,'node':node,'size':size,'color':color,'destructible':destructible})
 return node

func connect_game(g):
 game=g
 for i in range(parts.size()):
  var row:Dictionary=parts[i];var p:Vector3=row.node.position;var sz:Vector3=row.size
  # Upper storey geometry must block elevated bullets without blocking the ground grid.
  var blocks:bool=p.y-sz.y/2<.87 and row.id not in ["ground","stair_tread"]
  var entry={"id":"blue-house-"+str(i),"position":[p.x,p.z],"size":[sz.x,sz.z],"height":sz.y,"bottom":p.y-sz.y/2,"ray_size":[sz.x,sz.y,sz.z],"normal":[1,0],"kind":"building","hp":320 if row.id=="upper_floor" else 180,"max_hp":320 if row.id=="upper_floor" else 180,"alive":true,"node":row.node,"damage_stage":"intact","nav_block":blocks,"no_slots":true}
  row["cover"]=entry
  game.field.covers.append(entry)
 game.field.rebuild()

func approach()->Vector2:return Vector2(spec.center[0]+.10,spec.center[1]+.61)
func floor_route(member:int,floor_number:int)->Array[Vector3]:
 var x:float=spec.center[0];var z:float=spec.center[1];var high:float=floor_y+.004
 var result:Array[Vector3]=[Vector3(x+.10,.856,z+.61)]
 if floor_number==1:
  result.append(Vector3(x+.10,.856,z+.21));result.append(Vector3(x-.13,.856,z-.17+member*.17))
 else:
  result.append(Vector3(spec.stair_x,.852,z+.51));result.append(Vector3(spec.stair_x,.852,spec.stair_front))
  result.append(Vector3(spec.stair_x,high,spec.stair_back));result.append(Vector3(spec.stair_x,high,spec.stair_back-.06))
  result.append(Vector3(x+.11,high,spec.stair_back-.06));result.append(Vector3(x+.02,high,z))
  result.append(Vector3(x-.15,high,z-.17+member*.17))
 return result
func enter(u,floor_number:int)->bool:
 if collapsed or u.tank or u.faction!="blue" or u.gun_id!="" or u.hp/u.max_hp<.45 or u.suppression>.65:return false
 if u.garrison_phase!="":return u.garrison_floor==floor_number
 var path:PackedVector2Array=game.field.path(u.pos(),approach())
 if path.is_empty() or path[-1].distance_to(approach())>.04:return false
 u.garrison_floor=floor_number;u.garrison_phase="approaching";u.garrison_path.clear();u.garrison_history.clear()
 for p in path:u.garrison_path.append(Vector3(p.x,game.field.ground_height(p),p.y))
 for p in floor_route(int(u.id.get_slice("-",1))-1,floor_number):u.garrison_path.append(p)
 u.garrison_history.append(u.global_position)
 u.route.clear();u.cover_id="";u.cover_slot={};game.field.release(u.id);u.target_id="";u.order_mode="garrison"
 stations[u.id]={"floor":floor_number,"phase":"approaching"}
 return true
func leave(u):
 if u.garrison_phase=="" or u.garrison_phase=="exiting":return
 if not exit_queue.has(u.id):exit_queue.append(u.id)
 u.garrison_path=u.garrison_history.duplicate();u.garrison_path.reverse();u.garrison_phase="exiting";u.order_mode="evacuate_building";u.target_id=""
 if stations.has(u.id):stations[u.id].phase="exiting"
func tick(_dt:float):
 exit_queue=exit_queue.filter(func(id):return game.living("blue").any(func(u):return u.id==id and u.garrison_phase=="exiting"))
 if collapsed:return
 for row in parts:
  if row.id=="upper_floor" and not row.cover.alive:
   collapsed=true;stair.collision_layer=0;stair.hide()
   for other in parts:
    if other.destructible and other.cover.alive:game.field.damage_cover(other.cover.id,9999)
   for u in game.units:
    if u.garrison_phase!="":u.garrison_phase="falling";u.garrison_path.clear();u.hit(25,.6)
   break
 for u in game.living("blue"):
  if u.garrison_phase not in ["","exiting","falling"] and (u.hp/u.max_hp<.45 or u.suppression>.75):leave(u)
func drive(u,dt:float)->bool:
 if u.garrison_phase=="falling":
  u.position.y=maxf(game.field.height,u.position.y-1.2*dt);u.actor.global_position=u.global_position
  if u.position.y<=game.field.height:u.garrison_phase="";u.garrison_floor=0;stations.erase(u.id)
  return true
 if u.garrison_phase=="stationed":return false
 if u.garrison_phase=="exiting" and not exit_queue.is_empty() and exit_queue[0]!=u.id:
  u.state="waiting_on_stairs";u.locomotion="idle";u.animate("idle");return true
 if u.garrison_path.is_empty():
  if u.garrison_phase=="exiting":
   u.garrison_phase="";u.garrison_floor=0;u.order_mode="hold";stations.erase(u.id);exit_queue.erase(u.id)
  else:
   u.garrison_phase="stationed";u.order_mode="guard_window";stations[u.id].phase="stationed"
  u.locomotion="idle";u.goal=u.pos();return true
 var target:Vector3=u.garrison_path[0]
 if u.global_position.distance_to(target)<.015:
  if u.garrison_phase!="exiting":u.garrison_history.append(target)
  u.garrison_path.remove_at(0);return true
 # Keep people separated on the one-person staircase; never skip a corner through a wall.
 for other in game.living("blue"):
  if other!=u and (other.garrison_phase!="exiting" or exit_queue.find(other.id)<exit_queue.find(u.id)) and other.global_position.distance_to(u.global_position)<.035 and other.global_position.distance_to(target)<u.global_position.distance_to(target):u.state="waiting_on_stairs";u.animate("idle");return true
 var delta:Vector3=target-u.global_position
 u.rotation.y=atan2(-delta.x,-delta.z);u.actor.rotation.y=u.rotation.y+PI
 u.actor.surface_target=target
 u.actor.advance_drive(target,.095,dt,false,"run")
 u.actor.surface_target=Vector3.INF
 u.global_position=u.actor.global_position;u.actor_advanced=true;u.posture="stand";u.locomotion="stairs" if absf(delta.y)>.012 else "run";u.state="garrison_move"
 if u.actor.last_blocker!="":
  u.garrison_stall+=dt
  if u.garrison_stall>3:leave(u);u.garrison_stall=0;u.path_failure="building_path_blocked"
 else:u.garrison_stall=0
 return true
func snapshot()->Dictionary:
 return {"id":"blue-house","faction":"blue","position":spec.center,"floors":2,"collapsed":collapsed,"stations":stations,"parts_alive":parts.filter(func(p):return p.cover.alive).size(),"parts_total":parts.size(),"actions":["garrison","leave_building"]}
