extends Node3D
var actors=[]
var frame=0
var maximum_span=0.0
var maximum_stretch=0.0
var maximum_speed=0.0
var bad=false
func _ready():
 for i in 9:
  var a=preload("res://scripts/toy_actor.gd").new();add_child(a);a.position=Vector3(i*.3,.8275,0);a.rotation.y=i*PI/4;a.setup(Color.GREEN)
  a.clip=["rifle_idle","cover_idle","prone_idle"][i%3];a.playback.start(a.clip,true);a.tree.advance(0);a.tree.advance(.3)
  a.ragdoll(a.position+Vector3(.1,0,.05),.15 if i<6 else .5);actors.append(a)
func _physics_process(dt):
 frame+=1
 for a in actors:
  a.advance_idle(dt)
  var hips=a.bodies[0].body.global_position/a.RAG_SCALE
  for row in a.bodies:
   var p=row.body.global_position/a.RAG_SCALE
   if not p.is_finite():bad=true
   maximum_span=maxf(maximum_span,p.distance_to(hips));maximum_speed=maxf(maximum_speed,row.body.linear_velocity.length()/a.RAG_SCALE)
  for side in ["Left","Right"]:
   for pair in [["UpLeg","Leg"],["Leg","Foot"],["Arm","ForeArm"],["ForeArm","Hand"]]:
    var b=a.skeleton.find_bone(side+pair[0]);var c=a.skeleton.find_bone(side+pair[1])
    var rest=a.skeleton.get_bone_global_rest(b).origin.distance_to(a.skeleton.get_bone_global_rest(c).origin)
    var actual=a.skeleton.get_bone_global_pose(b).origin.distance_to(a.skeleton.get_bone_global_pose(c).origin)
    maximum_stretch=maxf(maximum_stretch,absf(actual/rest-1))
 if frame>=360:
  var hinges=actors[0].rag_world.find_children("*","HingeJoint3D",true,false).size()
  var limits=actors[0].rag_world.find_children("*","Generic6DOFJoint3D",true,false).size()
  var ok=not bad and maximum_span<.20 and maximum_stretch<.01 and maximum_speed<2 and hinges==4 and limits==13 and actors.all(func(a):return a.rag_settled)
  var report={"passed":ok,"actors":9,"frames":frame,"max_span_m":maximum_span,"max_segment_stretch":maximum_stretch,"max_speed_m_s":maximum_speed,"hinges_per_actor":hinges,"limited_joints_per_actor":limits,"all_settled":actors.all(func(a):return a.rag_settled)}
  FileAccess.open("res://docs/evidence/anatomy/ragdoll-contracts.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("RAGDOLL_ANATOMY ",JSON.stringify(report));get_tree().quit(0 if ok else 1)
