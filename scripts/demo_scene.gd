extends Node3D
# Original procedural presentation: metre-scale humans, tabletop and staging trays.
var people:Array=[]
func shape(parent,p:Vector3,size:Vector3,color:Color,round_shape:bool=false):
 var mesh=MeshInstance3D.new();var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.87
 if round_shape:
  var sphere=SphereMesh.new();sphere.radius=.5;sphere.height=1;mesh.mesh=sphere;mesh.scale=size
 else:
  var box=BoxMesh.new();box.size=size;mesh.mesh=box
 mesh.material_override=mat;parent.add_child(mesh);mesh.position=p;return mesh
func limb(parent,a:Vector3,b:Vector3,width:float,color:Color):
 var m=MeshInstance3D.new();var cylinder=CylinderMesh.new();cylinder.top_radius=width*.85;cylinder.bottom_radius=width;cylinder.height=a.distance_to(b);cylinder.radial_segments=12;m.mesh=cylinder
 var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.9;m.material_override=mat;parent.add_child(m);m.position=(a+b)*.5
 m.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
func human(p:Vector3,yaw:float,shirt:Color):
 var root=Node3D.new();add_child(root);root.position=p;root.rotation.y=yaw;people.append(root)
 var skin=Color('#c5a68d');var pants=Color('#404742');var shoes=Color('#252b28')
 for side in [-1,1]:
  var x:float=.105*side
  shape(root,Vector3(x,.055,-.05),Vector3(.13,.11,.27),shoes,true)
  limb(root,Vector3(x,.13,0),Vector3(x,.52,.025),.075,pants)
  limb(root,Vector3(x,.52,.025),Vector3(x,.91,.015),.095,pants)
 shape(root,Vector3(0,.93,0),Vector3(.36,.23,.23),pants,true)
 shape(root,Vector3(0,1.18,0),Vector3(.47,.53,.29),shirt,true)
 limb(root,Vector3(0,1.4,0),Vector3(0,1.5,0),.064,skin)
 shape(root,Vector3(0,1.61,-.008),Vector3(.21,.28,.23),skin,true)
 shape(root,Vector3(0,1.715,.005),Vector3(.22,.095,.235),Color('#413a32'),true)
 shape(root,Vector3(0,1.62,-.127),Vector3(.043,.057,.04),skin,true)
 for side in [-1,1]:
  shape(root,Vector3(side*.049,1.654,-.115),Vector3(.018,.012,.009),Color('#34332d'),true)
  limb(root,Vector3(side*.21,1.37,0),Vector3(side*.27,1.12,-.08),.07,shirt)
  limb(root,Vector3(side*.27,1.12,-.08),Vector3(side*.24,.99,-.30),.055,shirt)
  shape(root,Vector3(side*.24,.975,-.34),Vector3(.084,.05,.13),skin,true)
 return root
func setup(bounds:Array):
 var cx:float=(bounds[0]+bounds[2])*.5;var cz:float=(bounds[1]+bounds[3])*.5
 var width:float=bounds[2]-bounds[0]+.72;var depth:float=bounds[3]-bounds[1]+.36
 shape(self,Vector3(cx,.787,cz),Vector3(width,.075,depth),Color('#c2c8b5'))
 for x in [-1,1]:
  for z in [-1,1]:shape(self,Vector3(cx+x*(width*.5-.12),.385,cz+z*(depth*.5-.13)),Vector3(.09,.77,.09),Color('#5c685d'))
 shape(self,Vector3(cx,-.045,cz),Vector3(8,.08,8),Color('#686e61'))
 for x in [-1,1]:
  shape(self,Vector3(cx+x*(width*.5-.14),.833,cz),Vector3(.22,.025,depth-.3),Color('#818c76') if x<0 else Color('#a88472'))
 human(Vector3(cx-width*.5-.36,0,cz),-PI/2,Color('#607966'))
 human(Vector3(cx+width*.5+.36,0,cz),PI/2,Color('#977260'))
func _process(_delta):
 for i in range(people.size()):
  people[i].rotation.z=sin(Time.get_ticks_msec()*.00055+i)*.008
