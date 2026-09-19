extends Node3D
var checks=[]
var rows=[]
func check(value:bool,message:String):
 checks.append({"test":message,"passed":value})
 if not value:push_error(message)
func _ready():
 for spec in [["run",.18],["sprint",.30],["sprint",.15]]:
  var a=preload("res://scripts/toy_actor.gd").new();add_child(a);a.setup(Color.GREEN)
  var speeds=[];var rates=[];var previous={};var slip=0.0;var ankle_vertical=0.0;var contacts=0
  for i in 240:
   a.advance_drive(Vector3(0,0,2),spec[1],1.0/60,false,spec[0])
   if i>=60:speeds.append(a.actual_speed);rates.append(a.root_speed)
   for side in ["Left","Right"]:
    if a.foot_locks.has(side) and previous.has(side):
     var delta=a.foot_world(side).origin-previous[side]
     ankle_vertical=maxf(ankle_vertical,absf(delta.y))
     var moved=Vector2(delta.x,delta.z).length()
     if moved>.0005:print("SLIP ",spec," frame ",i," phase ",a.playback.get_current_play_position()," side ",side," delta ",moved," unreachable ",a.unreachable_contacts)
     slip=maxf(slip,moved);contacts+=1
    if a.foot_locks.has(side):previous[side]=a.foot_world(side).origin
    else:previous.erase(side)
  var average=0.0
  for x in speeds:average+=x/speeds.size()
  var driving_clip=a.clip
  var stopped=a.global_position
  for i in 60:a.advance_idle(1.0/60)
  check(absf(average-spec[1])<.005,spec[0]+" actual speed follows requested "+str(spec[1]))
  check(contacts>20 and slip<.0005,spec[0]+" planted feet horizontal drift stays within 0.5 mm")
  check(a.global_position.distance_to(stopped)<.000001,spec[0]+" stop produces zero residual translation")
  rows.append({"mode":spec[0],"requested":spec[1],"steady_speed":average,"rate":rates[-1],"driving_clip":driving_clip,"native_stride_speed":a.clip_speeds.get(driving_clip),"slip_m":slip,"ankle_vertical_adjustment_m":ankle_vertical,"contact_samples":contacts,"releases":a.contact_releases})
  a.free()
 var a=preload("res://scripts/toy_actor.gd").new();add_child(a);a.setup(Color.GREEN)
 var ramp=[]
 for i in 30:a.advance_drive(Vector3(0,0,2),.30,1.0/60,false,"sprint");ramp.append(a.drive_speed)
 check(ramp[0]<.02 and ramp[24]>.28,"charge accelerates to target over about 0.42 seconds")
 var wall=StaticBody3D.new();add_child(wall);wall.collision_layer=1;wall.position=Vector3(0,.06,a.position.z+.04)
 var shape=CollisionShape3D.new();wall.add_child(shape);var box=BoxShape3D.new();box.size=Vector3(.2,.2,.02);shape.shape=box
 await get_tree().physics_frame
 for i in 60:
  await get_tree().physics_frame
  a.advance_drive(a.global_position+Vector3(0,0,.2),.30,1.0/60,false,"sprint")
 check(a.blocked_motion>0 and a.actual_speed==0 and a.clip=="rifle_idle","blocked charge stops animation instead of running in place")
 var arrival=preload("res://scripts/toy_actor.gd").new();add_child(arrival);arrival.setup(Color.BLUE);arrival.position.x=.5
 var destination=Vector3(.5,0,.08)
 for i in 120:arrival.advance_drive(destination,.30,1.0/60,false,"sprint")
 check(arrival.global_position.distance_to(destination)<.0005 and arrival.actual_speed==0 and arrival.clip=="rifle_idle","arrival brakes without overshoot and returns to idle")
 arrival.free()
 var report={"passed":checks.all(func(c):return c.passed),"checks":checks,"measurements":rows,"acceleration_ramp":ramp,"blocked_count":a.blocked_motion,"blocked_speed":a.actual_speed,"blocked_clip":a.clip}
 FileAccess.open("res://docs/evidence/charge/contracts.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("CHARGE_CONTRACTS ",report.passed);get_tree().quit(0 if report.passed else 1)
