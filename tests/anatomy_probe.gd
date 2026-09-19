extends Node
var rows=[]
var failures=[]
func inspect(a,tag:String,phase:float):
 a.skeleton.force_update_all_bone_transforms()
 var max_error=0.0
 var max_knee=0.0
 var max_elbow=0.0
 for side in ["Left","Right"]:
  for chain in [["UpLeg","Leg","Foot"],["Arm","ForeArm","Hand"]]:
   var points=[]
   for name in chain:points.append(a.skeleton.get_bone_global_pose(a.skeleton.find_bone(side+name)).origin)
   for i in 2:
    var id=a.skeleton.find_bone(side+chain[i]);var cid=a.skeleton.find_bone(side+chain[i+1])
    var rest=a.skeleton.get_bone_global_rest(id).origin.distance_to(a.skeleton.get_bone_global_rest(cid).origin)
    var actual=points[i].distance_to(points[i+1]);max_error=maxf(max_error,absf(actual/rest-1))
   var angle=rad_to_deg((points[1]-points[0]).angle_to(points[2]-points[1]))
   if chain[0]=="UpLeg":max_knee=maxf(max_knee,angle)
   else:max_elbow=maxf(max_elbow,angle)
 var row={"clip":tag,"phase":phase,"bone_length_error":max_error,"knee_flex_deg":max_knee,"elbow_flex_deg":max_elbow}
 rows.append(row)
 if max_error>.01 or not is_finite(max_error):failures.append(row)
 if max_knee>158 or max_elbow>165:failures.append(row)
func _ready():
 var a=preload("res://scripts/toy_actor.gd").new();add_child(a);a.setup(Color.GREEN)
 for clip in a.anim.get_animation_list():
  if clip=="RESET":continue
  for i in 41:
   a.skeleton.clear_bones_global_pose_override();a.clip=clip;a.playback.start(clip,true);a.tree.advance(0);a.tree.advance(a.anim.get_animation(clip).length*i/40.0)
   inspect(a,clip,i/40.0)
 for mode in ["walk","run","crouch_run"]:
  a.foot_locks.clear();a.foot_previous.clear();a.contact_slip_max=0
  var start=a.global_position
  for i in 240:
   a.advance_drive(start+Vector3(0,0,1),.07,1.0/60,false,mode);inspect(a,"runtime_"+mode,i/240.0)
 a.clip="cover_idle";a.playback.start(a.clip,true);a.tree.advance(0);a.tree.advance(.2);a.cover_target=Vector3.INF;a.drive_goal=Vector3.INF
 for direction in [1,-1]:
  var target=a.global_position+Vector3(direction*.099,0,0)
  for i in 220:
   a.advance_drive(target,.04,1.0/60,true);inspect(a,"runtime_cover_"+str(direction),i/220.0)
 # An unreachable ankle is rejected, with no stretching as an alternative.
 var target=a.foot_world("Left");target.origin+=Vector3(0,1,0)
 if a.plant_leg("Left",target):failures.append({"unreachable_target":"accepted"})
 var report={"passed":failures.is_empty(),"samples":rows.size(),"failures":failures,"rows":rows,"unreachable_contacts_released":a.unreachable_contacts}
 FileAccess.open("res://docs/evidence/anatomy/contracts.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("ANATOMY_CONTRACTS ",report.passed," samples=",rows.size()," failures=",failures.size())
 get_tree().quit(0 if failures.is_empty() else 1)
