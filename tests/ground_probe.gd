extends Node3D
var vertices=[]
var rows=[]
var failures=[]
func cache_skin(a):
 vertices=[]
 for m in a.model.find_children('*','MeshInstance3D',true,false):
  if not m.skin:continue
  var binds=[]
  for i in m.skin.get_bind_count():
   var name=m.skin.get_bind_name(i)
   var bone=a.skeleton.find_bone(name) if name!="" else m.skin.get_bind_bone(i)
   binds.append([bone,m.skin.get_bind_pose(i)])
  for surface in m.mesh.get_surface_count():
   var arrays=m.mesh.surface_get_arrays(surface)
   var points=arrays[Mesh.ARRAY_VERTEX];var bones=arrays[Mesh.ARRAY_BONES];var weights=arrays[Mesh.ARRAY_WEIGHTS]
   var stride=weights.size()/points.size()
   for i in points.size():
    var influences=[]
    for j in stride:
     var index=i*stride+j
     if weights[index]>.00001:
      var bind=binds[bones[index]];influences.append([bind[0],bind[1]*points[i],weights[index]])
    vertices.append(influences)
func bottom(a):
 var poses=[]
 for i in a.skeleton.get_bone_count():poses.append(a.skeleton.get_bone_global_pose(i))
 var low=INF
 for vertex in vertices:
  var p=Vector3.ZERO
  for influence in vertex:p+=(poses[influence[0]]*influence[1])*influence[2]
  low=minf(low,(a.skeleton.global_transform*p).y-a.global_position.y)
 return low
func _ready():
 var a=preload('res://scripts/toy_actor.gd').new();add_child(a);a.setup(Color.GREEN);cache_skin(a)
 for clip in a.anim.get_animation_list():
  if clip=="RESET":continue
  var lo=INF;var hi=-INF
  for i in range(31):
   a.model.position.y=0;a.skeleton.clear_bones_global_pose_override();a.clip=clip;a.playback.start(clip,true);a.tree.advance(0);a.tree.advance(a.anim.get_animation(clip).length*i/30.0);a.skeleton.force_update_all_bone_transforms();a.contacts=[false,false];a.settle_ground()
   var value=bottom(a);lo=minf(lo,value);hi=maxf(hi,value)
  var flight=clip in ['rifle_jog_rm','rifle_sprint_rm']
  var row={'clip':clip,'min_m':lo,'max_m':hi,'flight_allowed':flight};rows.append(row)
  if lo<-.002 or (not flight and hi>.002):failures.append(row)
 for mode in ['walk','run','sprint','crouch_run']:
  a.foot_locks.clear();a.foot_previous.clear();var lo=INF;var hi=-INF;var support_hi=-INF
  for i in 180:
   a.advance_drive(a.position+Vector3(0,0,1),.30 if mode=='sprint' else .07,1.0/60,false,mode)
   var y=bottom(a);lo=minf(lo,y);hi=maxf(hi,y)
   if a.contacts.any(func(c):return c):support_hi=maxf(support_hi,y)
  var row={'mode':mode,'min_m':lo,'max_m':hi,'support_max_m':support_hi};rows.append(row)
  if lo<-.001 or support_hi>.001:failures.append(row)
 var arena=preload("res://scripts/sandbox_map.gd").new();add_child(arena)
 for map_id in 3:
  arena.load_level(map_id)
  var surface=arena.map_root.get_node("map_surface")
  var mesh=surface.get_child(0)
  var top=surface.position.y+mesh.mesh.size.y*.5
  if absf(top-.838)>.000001:failures.append({"surface":top,"map":map_id})
 var report={'passed':failures.is_empty(),'vertex_count':vertices.size(),'rows':rows,'failures':failures}
 FileAccess.open('res://docs/evidence/grounding/contracts.json',FileAccess.WRITE).store_string(JSON.stringify(report,'  '));print('GROUND_CONTRACTS ',JSON.stringify(report));get_tree().quit(0 if failures.is_empty() else 1)
