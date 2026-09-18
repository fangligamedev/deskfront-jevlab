extends Node3D
# Open-roof inspection building, metre-scale components with separate collision.
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
func tank_target()->Vector3:
 return Vector3(spec.center[0],.944,spec.center[1]-spec.size[1]/2-.015)
func damage(amount:int):
 if collapsed:return
 hp=maxi(0,hp-amount)
 if not breached:
  breached=true
  for row in parts:
   if row.id=='rear_wall_0':break_part(row)
 if hp==0:
  collapsed=true;stair.collision_layer=0;stair.hide()
  for row in parts:
   if row.destructible and row.node.visible:break_part(row)
func break_part(row:Dictionary):
 row.node.hide();row.node.collision_layer=0
 # Limit active debris: visible low-mass chunks, no invisible intact wall collider.
 if row.size.length()<.08:return
 for i in 3:
  var rb=RigidBody3D.new();add_child(rb);rb.position=row.node.position+Vector3((i-1)*row.size.x*.27,0,0);rb.mass=.03;rb.collision_layer=4;rb.collision_mask=1;rb.gravity_scale=.6
  var size=Vector3(minf(.07,row.size.x*.35),minf(.03,row.size.y*.4),minf(.06,row.size.z*.5))
  size=size.max(Vector3.ONE*.012)
  var mi=MeshInstance3D.new();var box=BoxMesh.new();box.size=size;mi.mesh=box;var mat=StandardMaterial3D.new();mat.albedo_color=row.color;mi.material_override=mat;rb.add_child(mi)
  var cs=CollisionShape3D.new();var bs=BoxShape3D.new();bs.size=size;cs.shape=bs;rb.add_child(cs)
  rb.apply_central_impulse(Vector3((i-1)*.005,.004,.006))
  get_tree().create_timer(6).timeout.connect(settle_debris.bind(rb))

func settle_debris(body:RigidBody3D):
 if is_instance_valid(body):body.freeze=true
