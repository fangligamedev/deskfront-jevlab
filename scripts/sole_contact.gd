extends RefCounted
# Imported skin vertices, not ankle origins. Cache only boot vertices for live checks.
static var cached_vertices={}
var vertices={"Left":[],"Right":[]}
func setup(model:Node3D,skeleton:Skeleton3D):
 if not cached_vertices.is_empty():
  vertices=cached_vertices
  return
 var seen={}
 for m in model.find_children('*','MeshInstance3D',true,false):
  if not m.skin:continue
  var binds=[]
  for i in m.skin.get_bind_count():
   var name=m.skin.get_bind_name(i)
   var bone=skeleton.find_bone(name) if name!="" else m.skin.get_bind_bone(i)
   binds.append([bone,m.skin.get_bind_pose(i),skeleton.get_bone_name(bone)])
  for surface in m.mesh.get_surface_count():
   var arrays=m.mesh.surface_get_arrays(surface);var points=arrays[Mesh.ARRAY_VERTEX];var bones=arrays[Mesh.ARRAY_BONES];var weights=arrays[Mesh.ARRAY_WEIGHTS]
   var stride=weights.size()/points.size()
   for i in points.size():
    var influences=[];var side=""
    for j in stride:
     var index=i*stride+j
     if weights[index]>.00001:
      var bind=binds[bones[index]];influences.append([bind[0],bind[1]*points[i],weights[index]])
      if weights[index]>.5 and (bind[2].ends_with('Foot') or bind[2].ends_with('ToeBase')):side="Left" if bind[2].begins_with('Left') else "Right"
    var key=str(influences)
    if side!="" and not seen.has(key):vertices[side].append(influences);seen[key]=true
 # A boot's lower support hull needs only extremal sole points, not every seam vertex.
 # Keep nine downward directions; full-skin regression verifies the approximation.
 for side in vertices:
  var positions=[]
  for vertex in vertices[side]:
   var p=Vector3.ZERO
   for v in vertex:p+=(skeleton.get_bone_global_rest(v[0])*v[1])*v[2]
   positions.append(p)
  var indices={}
  for x in [-1,0,1]:
   for z in [-1,0,1]:
    var direction=Vector3(x,-1,z);var best=-INF;var chosen=0
    for i in positions.size():
     var score=positions[i].dot(direction)
     if score>best:best=score;chosen=i
    indices[chosen]=true
  var support=[]
  for i in indices:support.append(vertices[side][i])
  vertices[side]=support
 cached_vertices=vertices
func heights(skeleton:Skeleton3D)->Dictionary:
 var poses={};var result={"Left":INF,"Right":INF}
 for side in vertices:
  for vertex in vertices[side]:
   var p=Vector3.ZERO
   for v in vertex:
    if not poses.has(v[0]):poses[v[0]]=skeleton.get_bone_global_pose(v[0])
    p+=(poses[v[0]]*v[1])*v[2]
   result[side]=minf(result[side],(skeleton.global_transform*p).y)
 return result
