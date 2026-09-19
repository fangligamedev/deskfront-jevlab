extends Node3D
## Normalize source rest geometry independently from its centimeter armature conversion.
## The original GLB remains intact. Runtime hull placement and turret yaw have one owner.
var turret: Node3D
var muzzle: Node3D
var hull_bounds: AABB
func setup(material: Material) -> void:
 var imported=load("res://assets/models/tank.glb").instantiate()
 var geometry=Node3D.new();add_child(geometry)
 var parts: Dictionary={};var bounds:=AABB();var first:bool=true
 for source in imported.find_children("*","MeshInstance3D",true,false):
  var part=MeshInstance3D.new();part.name=source.name;part.mesh=source.mesh;part.material_override=material
  # These meshes already contain baked rest vertices. Applying the armature's
  # conversion again makes their bounds 100x larger than gun/turret geometry.
  part.transform=Transform3D.IDENTITY if source.skin!=null else source.transform
  geometry.add_child(part);parts[str(source.name)]=part
  var box: AABB=part.transform*part.get_aabb()
  bounds=box if first else bounds.merge(box);first=false
 var factor: float=.30/maxf(bounds.size.x,bounds.size.z)
 geometry.scale=Vector3.ONE*factor;geometry.rotation.y=-PI/2
 var centering=Node3D.new();geometry.add_child(centering)
 centering.position=Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)
 for part in parts.values():part.reparent(centering,false)
 turret=Node3D.new();turret.name="TurretPivot";add_child(turret)
 var head=parts.get("Tank_Turret");var gun=parts.get("Tank_Gun")
 if head:turret.global_position=head.global_transform*head.get_aabb().get_center();head.reparent(turret,true)
 if gun:gun.reparent(turret,true)
 muzzle=Node3D.new();muzzle.name="Muzzle";turret.add_child(muzzle)
 if gun:
  var box: AABB=gun.get_aabb();muzzle.global_position=gun.global_transform*Vector3(box.position.x,box.get_center().y,box.get_center().z)
 else:muzzle.position=Vector3(0,0,-.15)
 hull_bounds=AABB(Vector3(-.15,0,-.15),Vector3(.3,bounds.size.y*factor,.3))
 imported.free()
