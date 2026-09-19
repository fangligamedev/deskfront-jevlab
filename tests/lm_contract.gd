extends SceneTree
var checks=[]
func _initialize():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/v06"))
 call_deferred("run")
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func run():
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_physics_process(false);g.fx.set_muted(true)
 var u=g.units[0];var buddy=g.units[1]
 check(g.command({"action":"control","faction":"green","mode":"lm"}).accepted,"LM control mode is executable")
 var cmd={"action":"move","position":[.4,2.8],"source":"lm","faction":"green","unit_ids":[u.id],"run_id":g.run_id,"seen_tick":g.tick_id,"control_epoch":g.control_epochs.green,"intent":"advance","reason":"单兵独立移动"}
 buddy.order_mode="overwatch";buddy.focus_id="red-1";buddy.move_to(Vector2(.4,3.0));var goal=buddy.goal;var route=buddy.route.duplicate()
 check(g.command(cmd).accepted and g.control.green=="lm","LM order does not change team into player mode")
 check(buddy.order_mode=="overwatch" and buddy.focus_id=="red-1" and buddy.goal==goal and buddy.route==route,"single-unit order preserves teammate intent, focus and route")
 check(u.snapshot().lm_intent=="advance","unit publishes accepted LM intent")
 cmd.action="move";cmd.posture="prone"
 check(g.command(cmd).accepted and u.posture=="prone" and u.locomotion=="crawl","LM can combine prone posture and a movement intention")
 cmd.erase("posture");cmd.unit_ids=[u.id,buddy.id]
 check(g.command(cmd).message=="lm_single_unit_required","LM cannot order multiple units")
 cmd.unit_ids=["red-1"]
 check(g.command(cmd).message=="invalid_unit_authority","LM cannot control enemy units")
 cmd.unit_ids=[u.id];cmd.source="agent"
 check(g.command(cmd).message=="authority_denied","external Agent cannot issue orders into an LM-owned team")
 cmd.source="lm"
 g.command({"action":"control","faction":"green","mode":"player"})
 check(g.command(cmd).message=="authority_denied","player takeover rejects old LM order")
 g.command({"action":"control","faction":"green","mode":"lm"})
 check(g.command(cmd).message=="stale_control_epoch","switch away and back still rejects in-flight LM decision")
 cmd.control_epoch=g.control_epochs.green;cmd.seen_tick=-999
 check(g.command(cmd).message=="stale_observation","old LM observations are rejected")
 cmd.seen_tick=g.tick_id;cmd.run_id="old"
 check(g.command(cmd).message=="stale_run","old match results are rejected")
 cmd.run_id=g.run_id;u.safety_until=g.elapsed+3
 check(g.command(cmd).message=="survival_override","LM cannot override an emergency escape with advance")
 u.posture_order="stand";u.suppression=.9;u.posture_since=-10;u.update_posture(false)
 check(u.posture=="prone","LM standing preference cannot prevent emergency prone response")
 u.safety_until=0;u.suppression=0;u.posture_order="auto";cmd.action="attack";cmd.target_id="missing";cmd.posture="prone"
 check(not g.command(cmd).accepted and u.posture_order=="auto","invalid action cannot partially mutate posture")
 cmd.action="hold";cmd.erase("target_id");cmd.erase("posture");u.hp=0
 check(g.command(cmd).message=="invalid_unit_authority","dead units reject LM orders")
 u.hp=100;cmd.action="reset"
 check(g.command(cmd).message=="authority_denied","LM cannot reset or administer the match")
 # Low-health attack pursuit used to overwrite the very escape chosen by survival_tick.
 var enemy=g.units[6];enemy.position=u.position+Vector3(.2,0,0);enemy.actor.global_position=enemy.global_position
 u.hp=20;u.target_id=enemy.id;u.reaction_at=0;u.last_threat_at=g.elapsed;u.survival_tick()
 check(u.target_id=="" and u.safety_until>g.elapsed,"emergency survival clears explicit pursuit target")
 g.spawn_tank();var tank=g.units[-1];tank.deployment_phase="active";g.command({"action":"control","faction":"red","mode":"lm"});tank.hp=100;tank.reaction_at=0;tank.survival_tick()
 check(not tank.available_actions().has("flank") and not tank.available_actions().has("posture") and not tank.available_actions().has("grenade"),"tank exposes only its implemented LM tactical actions")
 check(tank.safety_until>g.elapsed,"LM-controlled tank retains emergency anti-armor escape guard")
 # Switching back restores native coordinator ownership.
 g.command({"action":"control","faction":"green","mode":"game_ai"});g.tactics_ai.tick(.4)
 check(g.control.green=="game_ai" and g.tactics_ai.squads.has("green"),"game AI resumes when control is handed back")
 # A tank on the protected side must not hide an exposed infantry flank.
 var flank_game=load("res://scenes/main.tscn").instantiate();root.add_child(flank_game);flank_game.set_physics_process(false);flank_game.fx.set_muted(true)
 var scout=flank_game.units[0];var flanker=flank_game.units[6]
 flank_game.spawn_tank();var armor=flank_game.units[-1];armor.deployment_phase="active"
 var sandbag=flank_game.field.covers.filter(func(c):return c.kind!="hard")[0]
 var station=flank_game.field.slots(sandbag).filter(func(s):return flank_game.field.walkable(s.position))[0]
 for other in flank_game.units:
  if other.faction!=scout.faction:other.position=Vector3(5,flank_game.field.height,5)
 scout.position=Vector3(station.position.x,flank_game.field.height,station.position.y);scout.occupy(station);scout.route.clear()
 var back:Vector2=station.position-station.normal*.3;var front:Vector2=station.position+station.normal*.7
 flanker.position=Vector3(back.x,flank_game.field.height,back.y);armor.position=Vector3(front.x,flank_game.field.height,front.y)
 check(scout.in_cover() and flank_game.field.protection(scout.pos(),flanker.pos())<.2 and flank_game.field.protection(scout.pos(),armor.pos())>.2,"crossfire fixture has protected armor and exposed infantry sides")
 scout.reaction_at=0;scout.survival_tick()
 check(not scout.in_cover() and scout.safety_until>flank_game.elapsed,"tank threat cannot suppress evacuation of a flanked cover position")
 flank_game.queue_free()
 var ok=checks.all(func(c):return c.passed)
 FileAccess.open("res://output/v06/lm-contract.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks},"  "))
 print("LM_CONTRACT ",ok," checks=",checks.size());g.queue_free();await process_frame;quit(0 if ok else 1)
