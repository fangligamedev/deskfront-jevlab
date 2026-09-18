extends SceneTree
var checks:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func run():
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_physics_process(false);g.fx.set_muted(true)
 for team in g.control:g.control[team]="player"
 await physics_frame
 check(g.building!=null and g.building.spec.center==[1.0,1.13],"Existing two-storey building is on the northeast of the table")
 check(g.at_guns.size()==3,"Each faction has an actual field gun")
 g.spawn_tank();var tank=g.units[-1];var u=g.units[0];var blue=g.units[3]
 check(not u.can_engage(tank),"Rifle cannot engage armor")
 check(g.command({"action":"attack","faction":"green","unit_ids":[u.id],"target_id":tank.id}).message=="anti_armor_required","Explicit light-weapon tank attack rejected")
 check(not g.command({"action":"garrison","faction":"green","unit_ids":[u.id]}).accepted,"Blue building rejects other factions")
 check(g.command({"action":"garrison","faction":"blue","unit_ids":[blue.id],"floor":2}).accepted,"Blue infantry receives upstairs path")
 var blue_start:Vector3=blue.position
 # Real physics frames, root animation and collisions; stop combat to isolate route geometry.
 for other in g.units:
  if other!=blue:
   other.cooldown=999
   if other.faction=="blue":other.position=Vector3(.4+other.get_index()*.03,g.field.height,2.5);other.actor.global_position=other.position
 for i in range(1800):
  g.elapsed+=1.0/60;blue.cooldown=999;blue.tick(1.0/60);blue.presentation_tick(1.0/60)
  if i%60==0:print("BUILDING ",i," ",blue.global_position," ",blue.garrison_phase," ",blue.actor.last_blocker)
  if blue.garrison_phase=="stationed":break
  await physics_frame
 check(blue.garrison_phase=="stationed" and blue.position.y>1.02,"Blue walks up the actual external staircase to second-floor window")
 check(blue.actor.roots_travelled>.3,"Garrison uses actual root motion")
 check(g.command({"action":"leave_building","faction":"blue","unit_ids":[blue.id]}).accepted,"Garrison can evacuate")
 for i in range(1800):
  g.elapsed+=1.0/60;blue.tick(1.0/60);blue.presentation_tick(1.0/60)
  if blue.garrison_phase=="":break
  await physics_frame
 check(blue.garrison_phase=="" and blue.position.y<.87,"Evacuation returns down the staircase without teleporting")
 var gun=g.at_guns[0]
 check(gun.claim(u),"Green rifleman can take over friendly AT gun")
 for i in range(2100):
  g.elapsed+=1.0/60;gun.tick(1.0/60);u.tick(1.0/60);u.presentation_tick(1.0/60)
  if i%120==0:print("GUN ",i," ",u.pos()," ",gun.phase," ",u.actor.last_blocker)
  if gun.phase=="ready":break
  await physics_frame
 check(gun.phase=="ready" and gun.distance_pushed>.08,"Crew physically pushes and deploys the AT gun")
 check(gun.shots==0,"Cannot fire while forming or towing")
 # Target fixture in the carriage firing arc, no scenario-state substitutions in live tests.
 tank.position=gun.position+Vector3(gun.forward().x*.7,0,gun.forward().y*.7);tank.position.y=g.field.height
 gun.cooldown=0;gun.tick(.02)
 check(gun.shots==1 and g.fx.launched.get("at_cannon",0)==1,"Deployed gun launches a real swept AT shell")
 u.suppression=.9;gun.tick(.02)
 check(u.gun_id=="" and gun.phase=="abandoned","Suppressed crew abandons gun before continued attack")
 for part in g.building.parts:
  if part.id=="upper_floor":g.field.damage_cover(part.cover.id,9999)
 g.building.tick(.02)
 check(g.building.collapsed and g.building.stair.collision_layer==0,"Destroyed floor closes upstairs route and removes stair collider")
 var report={"passed":checks.all(func(c):return c.passed),"checks":checks,"blue_final":blue.snapshot(),"gun":gun.snapshot()}
 var f=FileAccess.open("res://output/v06/equipment-contract.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
 g.queue_free();await process_frame;quit(0 if report.passed else 1)
