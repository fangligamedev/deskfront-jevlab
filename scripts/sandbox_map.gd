extends Node3D
var data=JSON.parse_string(FileAccess.get_file_as_string('res://data/sandbox-maps.json'))
var index=0
var map_root:Node3D
var current:Dictionary
var props:Array=[]
func load_level(i:int):
 index=posmod(i,data.levels.size());current=data.levels[index];props.clear()
 if is_instance_valid(map_root):remove_child(map_root);map_root.queue_free()
 map_root=Node3D.new();map_root.name='Map_'+current.id;add_child(map_root)
 var b=current.bounds
 box('map_surface',Vector3((b[0]+b[2])/2,.829,(b[1]+b[3])/2),Vector3(b[2]-b[0],.018,b[3]-b[1]),Color(current.floor_color),true)
 # Thin removable tray edging visually separates the map from the office desk.
 for x in [b[0]-.01,b[2]+.01]:box('rim',Vector3(x,.835,(b[1]+b[3])/2),Vector3(.018,.025,b[3]-b[1]+.045),Color('#747e6b'),false)
 for z in [b[1]-.01,b[3]+.01]:box('rim',Vector3((b[0]+b[2])/2,.835,z),Vector3(b[2]-b[0]+.045,.025,.018),Color('#747e6b'),false)
 for spec in current.objects:
  var sz=Vector3(spec.size[0],spec.size[1],spec.size[2]);var p=Vector3(spec.position[0],.838+sz.y/2+spec.get('elevation',0),spec.position[1])
  var n=box(spec.id,p,sz,Color(spec.color),spec.collision and spec.kind!="bridge");n.rotation_degrees.y=spec.yaw
  props.append({'node':n,'spec':spec})
  if spec.kind=='sandbag':
   n.get_child(0).visible=false
   var count=maxi(2,int(sz.x/.05))
   for layer in range(3):
    for j in range(count):
     var bag=load('res://assets/models/sandbag.glb').instantiate();n.add_child(bag);bag.position=Vector3(-sz.x/2+.025+j*.05,-sz.y/2+layer*.016,0);bag.scale=Vector3(.75,1.2,.75)
  if spec.kind=='building':
   for j in [-1,1]:box('window',Vector3(p.x+j*sz.x*.25,p.y+.02,p.z+sz.z*.501),Vector3(.045,.03,.002),Color('#576c63'),false)
 var objective=[.54,2.38] if current.id=="river" else current.objective;var disc=MeshInstance3D.new();var m=CylinderMesh.new();m.top_radius=.057;m.bottom_radius=.057;m.height=.003;disc.mesh=m;var mat=StandardMaterial3D.new();mat.albedo_color=Color('#c2a765');mat.roughness=.8;disc.material_override=mat;map_root.add_child(disc);disc.position=Vector3(objective[0],.848,objective[1])
func box(id,p,sz,c,solid):
 var node=StaticBody3D.new();node.name=id;map_root.add_child(node);node.position=p;node.collision_layer=1 if solid else 0;node.collision_mask=0
 var mesh=MeshInstance3D.new();var shape=BoxMesh.new();shape.size=sz;mesh.mesh=shape;var mat=StandardMaterial3D.new();mat.albedo_color=c;mat.roughness=.8;mesh.material_override=mat;node.add_child(mesh)
 if solid:
  var col=CollisionShape3D.new();var s=BoxShape3D.new();s.size=sz;col.shape=s;node.add_child(col)
 return node
func hit(p:Vector3,r:float):
 for row in props:
  if row.spec.destructible and row.node.visible and row.node.position.distance_to(p)<r:
   row.node.visible=false;row.node.collision_layer=0
