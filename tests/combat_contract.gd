extends SceneTree
var checks=[]
func _initialize():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/v05"))
 call_deferred("run")
func check(ok:bool,name:String):
 checks.append({"test":name,"passed":ok})
 if not ok:push_error(name)
func run():
 var g=load("res://scenes/main.tscn").instantiate();g.use_legacy_fixture=true;root.add_child(g);g.set_physics_process(false);g.fx.set_muted(true)
 for c in g.field.covers:
  c.alive=false
  if is_instance_valid(c.node):c.node.visible=false
 g.field.obstacles.clear();g.field.rebuild()
 for u in g.units:u.hp=0;u.actor.collision_layer=0;u.visible=false
 var shooter=g.units[0];var target=g.units[6];shooter.hp=100;target.hp=100
 shooter.position=Vector3(.24,g.field.height,.1);target.position=Vector3(.55,g.field.height,.1)
 var wall={"id":"contract_wall","position":[.5,.1],"size":[.018,.3],"normal":[-1,0],"height":.20,"hp":1000.0,"max_hp":1000.0,"kind":"hard","alive":true,"node":null}
 g.field.covers.append(wall);g.field.rebuild()
 for weapon in ["rifle","smg","pistol","rocket","cannon","grenade"]:
  wall.alive=true;wall.hp=1000;target.hp=100;target.suppression=0
  var count=g.fx.collision_counts.cover
  g.fx.launch(shooter,target,weapon,true)
  for step in range(180):g.fx.physics_tick(1.0/60)
  check(g.fx.collision_counts.cover==count+1,weapon+" projectile hits the first wall surface")
  check(target.hp==100,weapon+" does not damage a target through intact tall cover")
 # Height-sensitive ray, not a blanket cover probability.
 wall.height=.055
 var a=Vector3(.24,g.field.height+.025,.1);var b=Vector3(.55,g.field.height+.025,.1)
 check(not g.field.trace_cover(a,b).is_empty(),"low cover blocks prone-height bullets")
 check(g.field.trace_cover(a+Vector3.UP*.08,b+Vector3.UP*.08).is_empty(),"a shot above low cover remains legal")
 wall.height=.2
 var p=Vector2(.42,.1);var safe=g.field.choose_cover(shooter.id,p,Vector2(.65,.1),p,{"max_travel":.4,"reserve":false})
 check(not safe.is_empty() and safe.position.x<.5,"cover query selects the threat-opposite side of a wall")
 if not safe.is_empty():
  check(g.field.shields(wall,safe.position,Vector2(.65,.1)),"selected station actually intersects its claimed shielding object")
  g.field.reserve_slot(shooter.id,safe)
 var revision=g.field.revision
 wall.hp=50;g.fx.launch(shooter,target,"cannon",true)
 for step in range(120):g.fx.physics_tick(1.0/60)
 check(not wall.alive and g.field.revision>revision,"real cannon impact destroys cover and rebuilds navigation")
 check(not g.field.reservations.values().has(shooter.id),"destroyed station reservations are removed")
 check(g.field.trace_cover(a,b).is_empty(),"destroyed cover no longer blocks rays")
 target.hp=100;g.fx.launch(shooter,target,"rifle",true)
 for step in range(60):g.fx.physics_tick(1.0/60)
 check(target.hp<100,"next bullet crosses the breached gap and hits the actual body")
 # Intervening unit receives the shot; the preselected distant target must not.
 var middle=g.units[3];middle.hp=100;middle.position=Vector3(.4,g.field.height,.1);target.hp=100
 g.fx.launch(shooter,target,"rifle",true)
 for step in range(60):g.fx.physics_tick(1.0/60)
 check(middle.hp<100 and target.hp==100,"nearest intervening hostile body intercepts the ray")
 middle.hp=0
 var friendly=g.units[1];friendly.hp=100;friendly.position=Vector3(.4,g.field.height,.1)
 g.fx.launch(shooter,target,"rifle",true)
 for step in range(60):g.fx.physics_tick(1.0/60)
 check(friendly.hp==100 and target.hp==100 and g.fx.collision_counts.friendly_block>0,"friendly body blocks fire without friendly damage")
 friendly.hp=0
 # Posture is physically lower and crawl has root displacement, not just a state label.
 shooter.actor.global_position=shooter.global_position;shooter.actor.navigation_guard=Callable();shooter.actor.collision_mask=0
 var heights={}
 for clip in ["rifle_idle","cover_idle","prone_idle"]:
  shooter.actor.clip=clip;shooter.actor.playback.start(clip,true);shooter.actor.tree.advance(.4)
  var sk=shooter.actor.skeleton;heights[clip]=(sk.global_transform*sk.get_bone_global_pose(sk.find_bone("Head"))).origin.y-shooter.actor.global_position.y
 check(heights.prone_idle<.045 and heights.prone_idle<heights.cover_idle*.65,"prone head really lies below crouched head")
 var original=shooter.actor.global_position;shooter.actor.rotation.y=0
 for i in range(90):shooter.actor.advance_drive(original+Vector3(0,0,.15),.038,1.0/60,false,"crawl")
 check(shooter.actor.global_position.distance_to(original)>.035 and shooter.actor.clip=="crawl","crawl moves with calibrated root motion")
 # Hiding behind LOW cover lowers the real pose, not only an invisible hit box.
 shooter.cover_id="test_low";shooter.cover_slot={"position":shooter.pos(),"hard":false};shooter.cqb_stance="hide";shooter.posture_order="auto";shooter.update_posture(false);shooter.animate("idle")
 check(shooter.posture=="prone" and shooter.actor.clip=="prone_idle","low-cover concealment uses real prone pose")
 shooter.cover_slot.hard=true;shooter.posture_since=-10;shooter.update_posture(false)
 check(shooter.posture=="crouch" and shooter.hit_box().size.y>.06,"hard-cover concealment retains a physically crouched body")
 shooter.cover_id="";shooter.cover_slot={};shooter.cqb_stance="open"
 # Agent commands reject invalid or incompatible action rather than silently claiming success.
 g.command({"action":"control","faction":"green","mode":"agent"})
 var command={"action":"posture","posture":"prone","source":"agent","faction":"green","unit_ids":[shooter.id],"run_id":g.run_id,"seen_tick":g.tick_id}
 var ack=g.command(command);check(ack.accepted and shooter.posture_order=="prone","authorized Agent can request prone posture")
 command.posture="flying";check(not g.command(command).accepted,"unsupported posture rejected")
 command.posture="stand";command.run_id="old";check(not g.command(command).accepted,"posture obeys observation freshness and ownership")
 # Tank pivots before driving sideways; the turret remains independent.
 for u in g.units:u.hp=0
 var armor=g.spawn_unit("contract-tank","green",Vector2(.7,.3),true)
 armor.move_to(Vector2(1.0,.3));var start=armor.pos()
 for i in range(4):armor.tick(.1);armor.presentation_tick(.1)
 check(armor.pos().distance_to(start)<.005 and absf(armor.rotation.y)>.1,"tank rotates hull before translating across its side")
 for i in range(60):armor.tick(1.0/60);armor.presentation_tick(1.0/60)
 check(armor.pos().distance_to(start)>.01,"aligned tank resumes forward locomotion")
 var ok=checks.all(func(c):return c.passed)
 FileAccess.open("res://output/v05/combat-contract.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"measured_head_heights":heights},"  "))
 print("COMBAT_CONTRACT ",ok," checks=",checks.size())
 g.queue_free();await process_frame;quit(0 if ok else 1)
