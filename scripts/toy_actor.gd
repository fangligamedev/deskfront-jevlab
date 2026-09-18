extends CharacterBody3D
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var color: Color
var clip="rifle_idle"
var dead=false
var roots_travelled=0.0
var bodies: Array=[]
var rag_world:Node3D
const RAG_SCALE=20.0
var weapon:Node3D
var weapon_mode="rifle"
var root_speed=1.0
var cover_target=Vector3.INF
var gait=JSON.parse_string(FileAccess.get_file_as_string("res://data/gait.json"))
var stepping=false
var step_time=0.0
var step_count=0
var step_scale=1.0
var step_direction=1.0
var step_feet={}
var blocked_steps=0
var last_blocker: String=""
var stop_after_step=false
var foot_locks={}
var contacts=[false,false]
var contact_slip_max=0.0
var foot_previous={}
var queued_clip=""
var drive_goal=Vector3.INF
var drive_limit=INF
var walk_speed=.12
var clip_speeds: Dictionary={}
var surface_target:Vector3=Vector3.INF
var navigation_guard:Callable
const STEP_LENGTH=.033
func stop_cover_move():
 cover_target=Vector3.INF
 stop_after_step=true
func foot_world(side:String)->Transform3D:
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(side+"Foot"))
func begin_cover_step()->bool:
 var delta=global_basis.inverse()*(cover_target-global_position)
 if absf(delta.x)<.0005:
  cover_target=Vector3.INF
  return false
 var direction=signf(delta.x)
 step_scale=minf(1,absf(delta.x)/STEP_LENGTH);step_direction=direction
 # Reject the entire step if its swept capsule would hit cover. No blocked treadmill.
 var travel=global_basis*Vector3(direction*STEP_LENGTH*step_scale,0,0)
 var nav_ok=true
 if navigation_guard.is_valid():
  for i in range(1,5):
   if not navigation_guard.call(global_position+travel*i/4.0):nav_ok=false
 if not nav_ok or test_move(global_transform,travel):
  blocked_steps+=1;cover_target=Vector3.INF
  return false
 step_feet={"Left":foot_world("Left"),"Right":foot_world("Right")}
 clip="cover_shuffle_left" if direction>0 else "cover_shuffle_right"
 playback.start(clip,true);tree.advance(0)
 stepping=true;step_time=0;stop_after_step=false;step_count+=1
 return true
func rotate_bone_to(id:int,from:Vector3,to:Vector3,pose:Transform3D):
 if from.length_squared()<.00000001 or to.length_squared()<.00000001:return
 pose.basis=Basis(Quaternion(from.normalized(),to.normalized()))*pose.basis
 skeleton.set_bone_global_pose_override(id,pose,1,true)
func plant_leg(side:String,world:Transform3D):
 var target=skeleton.global_transform.affine_inverse()*world
 var upper=skeleton.find_bone(side+"UpLeg");var lower=skeleton.find_bone(side+"Leg");var foot=skeleton.find_bone(side+"Foot")
 var a=skeleton.get_bone_global_pose(upper);var b=skeleton.get_bone_global_pose(lower);var f=skeleton.get_bone_global_pose(foot)
 var l1=a.origin.distance_to(b.origin);var l2=b.origin.distance_to(f.origin)
 var v=target.origin-a.origin;var dist=clampf(v.length(),.00001,(l1+l2)*.9999);var axis=v.normalized()
 var pole=b.origin-a.origin;pole-=axis*pole.dot(axis)
 if pole.length_squared()<.00000001:pole=Vector3.FORWARD-axis*Vector3.FORWARD.dot(axis)
 pole= pole.normalized()
 var along=(l1*l1-l2*l2+dist*dist)/(2*dist)
 var knee=a.origin+axis*along+pole*sqrt(maxf(0,l1*l1-along*along))
 rotate_bone_to(upper,b.origin-a.origin,knee-a.origin,a)
 var lower_axis=f.origin-b.origin
 b.origin=knee
 rotate_bone_to(lower,lower_axis,target.origin-knee,b)
 # Keep the sole's orientation and contact point, including the toes.
 skeleton.set_bone_global_pose_override(foot,target,1,true)
func step_ease(t:float)->float:
 return t*t*t*(t*(t*6-15)+10)
func apply_foot_contacts():
 var info=gait.clips.get(clip,{})
 var supported=clip.begins_with("cover_") and clip not in ["cover_enter","cover_exit"]
 if not supported:
  foot_locks.clear();foot_previous.clear();contacts=[false,false];return
 var samples=info.get("contacts",[[true,true]])
 var phase=clampf(playback.get_current_play_position()/maxf(info.get("duration",1),.001),0,1)
 contacts=samples[mini(samples.size()-1,int(round(phase*(samples.size()-1))))]
 for i in range(2):
  var side=["Left","Right"][i]
  if stepping:
   var leading=(side=="Left")== (step_direction>0)
   var start=.06 if leading else .55;var end=.44 if leading else .93
   var u=clampf((phase-start)/(end-start),0,1)
   var goal:Transform3D=step_feet[side]
   goal.origin+=global_basis*Vector3(step_direction*STEP_LENGTH*step_scale*step_ease(u),.0075*sin(PI*u)*sin(PI*u)*sqrt(step_scale),0)
   plant_leg(side,goal)
  if contacts[i]:
   if not foot_locks.has(side):foot_locks[side]=foot_world(side)
   plant_leg(side,foot_locks[side])
   if foot_previous.has(side):contact_slip_max=maxf(contact_slip_max,foot_world(side).origin.distance_to(foot_previous[side]))
   foot_previous[side]=foot_world(side).origin
  else:
   foot_locks.erase(side);foot_previous.erase(side)

func setup(c:Color,weapon_id="rifle"):
 color=c;weapon_mode=weapon_id
 set_physics_process(false)
 model=load('res://assets/models/toy-soldier.glb').instantiate();add_child(model)
 skeleton=model.find_children('*','Skeleton3D',true,false)[0]
 anim=model.find_children('*','AnimationPlayer',true,false)[0]
 var mat=StandardMaterial3D.new();mat.albedo_color=c;mat.roughness=.32;mat.metallic=0;mat.rim_enabled=true;mat.rim=.12
 for m in model.find_children('*','MeshInstance3D',true,false):m.material_override=mat
 var sm=AnimationNodeStateMachine.new()
 for n in anim.get_animation_list():
  var an=AnimationNodeAnimation.new();an.animation=n;sm.add_node(n,an)
  if n in ['rifle_idle','rifle_walk_rm','rifle_jog_rm','rifle_crouch_rm','cover_idle','rocket_aim','crawl','prone_idle']:
   anim.get_animation(n).loop_mode=Animation.LOOP_LINEAR
 for a in anim.get_animation_list():
  for b in anim.get_animation_list():
   if a==b:continue
   var t=AnimationNodeStateMachineTransition.new();t.xfade_time=.15;sm.add_transition(a,b,t)
 tree=AnimationTree.new();model.add_child(tree);tree.anim_player=tree.get_path_to(anim);tree.tree_root=sm
 tree.root_motion_track=NodePath('ToyRig/Skeleton3D:Root');tree.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;tree.active=true
 playback=tree.get('parameters/playback');playback.start(clip)
 for key in ["rifle_walk_rm","rifle_jog_rm","rifle_crouch_rm","crawl"]:
  var walk=anim.get_animation(key)
  for i in range(walk.get_track_count()):
   if str(walk.track_get_path(i)).ends_with(':Root') and walk.track_get_type(i)==Animation.TYPE_POSITION_3D:
    var last=walk.track_get_key_count(i)-1
    clip_speeds[key]=maxf(.001,walk.track_get_key_value(i,last).distance_to(walk.track_get_key_value(i,0))/walk.length)
 walk_speed=clip_speeds.rifle_walk_rm
 tree.advance(0)
 var shape=CollisionShape3D.new();var cap=CapsuleShape3D.new();cap.radius=.016;cap.height=.115;shape.shape=cap;shape.position.y=.065;add_child(shape)
 collision_layer=2;collision_mask=1
 # Weapon follows both hand anchors; no guessed imported bone-space orientation.
 weapon=load('res://assets/models/'+weapon_id+'.glb').instantiate();add_child(weapon)
 for m in weapon.find_children('*','MeshInstance3D',true,false):m.material_override=mat
 update_weapon()
func play(n:String):
 if dead or n==clip:return
 if stepping:
  queued_clip=n;stop_cover_move();return
 clip=n;playback.travel(n)
func _physics_process(dt):
 if not model:return
 if dead:
  var inv=skeleton.global_transform.affine_inverse()
  for row in bodies:
   var pose=row.body.global_transform*row.offset;pose.origin/=RAG_SCALE
   skeleton.set_bone_global_pose_override(row.id,inv*pose,1.0,true)
  return
 skeleton.clear_bones_global_pose_override()
 if not stepping and cover_target!=Vector3.INF:begin_cover_step()
 tree.advance(dt*(root_speed if clip in ["rifle_walk_rm","rifle_jog_rm","rifle_crouch_rm","crawl"] else 1.0))
 var motion=tree.get_root_motion_position()
 if clip in ['rifle_walk_rm','rifle_jog_rm','rifle_crouch_rm','crawl','roll_rm','dodge_left_rm','cover_shuffle_left','cover_shuffle_right']:
  if stepping:motion.x*=step_scale
  var displacement=global_basis*motion;displacement.y=0
  if not stepping and drive_goal!=Vector3.INF:
   var delta=drive_goal-global_position;delta.y=0
   displacement=delta.normalized()*minf(displacement.length(),delta.length())
  if surface_target!=Vector3.INF:
   var flat=Vector2(surface_target.x-global_position.x,surface_target.z-global_position.z).length()
   if flat>.00001:displacement.y=(surface_target.y-global_position.y)*minf(1,displacement.length()/flat)
  if navigation_guard.is_valid() and not navigation_guard.call(global_position+displacement):displacement=Vector3.ZERO;last_blocker="navigation"
  var hit=move_and_collide(displacement) if displacement.length_squared()>.00000000001 else null
  if hit:last_blocker=str(hit.get_collider().name)
  elif displacement.length()>.0001:last_blocker=""
  roots_travelled+=displacement.length()
  if hit and stepping:
   stop_after_step=true;cover_target=Vector3.INF
 apply_foot_contacts()
 if stepping:
  step_time+=dt
  if step_time>=float(gait.clips[clip].duration)-.00001:
   stepping=false
   if stop_after_step:cover_target=Vector3.INF
   clip=queued_clip if queued_clip!="" else "cover_idle";queued_clip=""
   playback.start(clip,true)
 update_weapon()
func update_weapon():
 var right=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone('RightHand'))
 var left=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone('LeftHand'))
 weapon.global_position=right.origin
 var forward=(left.origin-right.origin).normalized()
 if forward.length()<.1:forward=global_basis.z
 weapon.global_basis=Basis.looking_at(-forward,Vector3.UP)
 # Imported flat gun is in meters, +Y up; long axis determined at import audit.
 weapon.scale=Vector3.ONE*.075
 if weapon_mode=='rocket':weapon.global_position+=(right.basis.y)*.005
func ragdoll(origin:Vector3,power=.5):
 if dead:return
 dead=true;tree.active=false;collision_layer=0;collision_mask=0;weapon.visible=false
 # Solve miniature joints at human scale in an isolated physics world, then map skin poses back.
 var vp=SubViewport.new();vp.size=Vector2i(2,2);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(vp)
 rag_world=Node3D.new();vp.add_child(rag_world)
 var floor=StaticBody3D.new();rag_world.add_child(floor);floor.collision_layer=1
 floor.position=Vector3(global_position.x,.805,global_position.z)*RAG_SCALE
 var fc=CollisionShape3D.new();var fb=BoxShape3D.new();fb.size=Vector3(2,.025,2)*RAG_SCALE;fc.shape=fb;floor.add_child(fc)
 # Copy the tabletop, cover and tank collision proxies into the simulation space.
 for obstacle in get_tree().root.find_children("*","StaticBody3D",true,false):
  if obstacle.get_world_3d()!=get_world_3d():continue
  if obstacle is StaticBody3D and obstacle.collision_layer==1:
   for child in obstacle.get_children():
    if child is CollisionShape3D and child.shape is BoxShape3D:
     var proxy=StaticBody3D.new();rag_world.add_child(proxy);proxy.collision_layer=1;proxy.global_transform=child.global_transform;proxy.position*=RAG_SCALE
     var shape=CollisionShape3D.new();shape.shape=child.shape.duplicate();shape.shape.size*=RAG_SCALE;proxy.add_child(shape)
 var names=['Hips','Spine','Spine1','Spine2','Neck','Head','LeftArm','LeftForeArm','LeftHand','RightArm','RightForeArm','RightHand','LeftUpLeg','LeftLeg','LeftFoot','RightUpLeg','RightLeg','RightFoot']
 var by_name={}
 for n in names:
  var id=skeleton.find_bone(n);var g=skeleton.global_transform*skeleton.get_bone_global_pose(id)
  var end=g.origin+g.basis.y*.009
  for cid in skeleton.get_bone_children(id):
   if skeleton.get_bone_name(cid) in names:
    end=(skeleton.global_transform*skeleton.get_bone_global_pose(cid)).origin;break
  var length=maxf(.008,g.origin.distance_to(end));var body=RigidBody3D.new();rag_world.add_child(body)
  body.mass=4.0 if n=='Hips' else 1.0;body.gravity_scale=1.0;body.linear_damp=.7;body.angular_damp=2.5;body.collision_layer=4;body.collision_mask=1
  body.continuous_cd=true
  var direction=(end-g.origin).normalized();var q=Quaternion(Vector3.UP,direction)
  body.global_transform=Transform3D(Basis(q),g.origin.lerp(end,.5)*RAG_SCALE)
  var col=CollisionShape3D.new();var cap=CapsuleShape3D.new();cap.radius=.006 if n in ['Hips','Spine','Spine1','Spine2','Head'] else .0035;var height=maxf(length,cap.radius*2)*RAG_SCALE;cap.radius*=RAG_SCALE;cap.height=height;col.shape=cap;body.add_child(col)
  var sim_g=g;sim_g.origin*=RAG_SCALE
  var row={'id':id,'body':body,'offset':body.global_transform.affine_inverse()*sim_g,'start':g.origin*RAG_SCALE};bodies.append(row);by_name[n]=row
 for n in names:
  var row=by_name[n];var parent=skeleton.get_bone_parent(row.id)
  while parent>=0 and not by_name.has(skeleton.get_bone_name(parent)):parent=skeleton.get_bone_parent(parent)
  if parent<0:continue
  var joint=PinJoint3D.new();rag_world.add_child(joint);joint.global_position=row.start
  joint.node_a=joint.get_path_to(by_name[skeleton.get_bone_name(parent)].body);joint.node_b=joint.get_path_to(row.body)
  joint.set_param(PinJoint3D.PARAM_BIAS,.3);joint.set_param(PinJoint3D.PARAM_DAMPING,1.0)
 for row in bodies:
  var v=(global_position-origin);v.y=0;v=v.normalized()*power+Vector3.UP*power*.7
  row.body.apply_central_impulse(v*row.body.mass*RAG_SCALE*.5)

func advance_drive(target:Vector3, speed:float, dt:float, lateral:bool, gait_mode:String="run"):
 drive_goal=target
 if stepping:
  _physics_process(dt)
  return
 if lateral:
  cover_target=target
  play("cover_idle")
 else:
  cover_target=Vector3.INF
  var movement_clip={"run":"rifle_jog_rm","crouch_run":"rifle_crouch_rm","crawl":"crawl","walk":"rifle_walk_rm"}.get(gait_mode,"rifle_jog_rm")
  root_speed=clampf(speed/float(clip_speeds.get(movement_clip,walk_speed)),.05,5)
  play(movement_clip)
 _physics_process(dt)

func advance_idle(dt:float):
 drive_goal=Vector3.INF
 if not stepping:cover_target=Vector3.INF
 _physics_process(dt)

func grip_handle(side:String,world_point:Vector3):
 var upper=skeleton.find_bone(side+"Arm");var lower=skeleton.find_bone(side+"ForeArm");var hand=skeleton.find_bone(side+"Hand")
 if upper<0 or lower<0 or hand<0:return
 var a=skeleton.get_bone_global_pose(upper);var b=skeleton.get_bone_global_pose(lower);var h=skeleton.get_bone_global_pose(hand)
 var target=skeleton.global_transform.affine_inverse()*world_point
 var l1=a.origin.distance_to(b.origin);var l2=b.origin.distance_to(h.origin)
 var v=target-a.origin;var dist=clampf(v.length(),.00001,(l1+l2)*.995);var axis=v.normalized()
 var pole=Vector3.DOWN-axis*Vector3.DOWN.dot(axis)
 if pole.length_squared()<.000001:pole=Vector3.RIGHT
 var along=(l1*l1-l2*l2+dist*dist)/(2*dist)
 var elbow=a.origin+axis*along+pole.normalized()*sqrt(maxf(0,l1*l1-along*along))
 rotate_bone_to(upper,b.origin-a.origin,elbow-a.origin,a)
 var original=h.origin-b.origin;b.origin=elbow
 rotate_bone_to(lower,original,a.origin+axis*dist-elbow,b)
 h.origin=a.origin+axis*dist;skeleton.set_bone_global_pose_override(hand,h,1,true)
