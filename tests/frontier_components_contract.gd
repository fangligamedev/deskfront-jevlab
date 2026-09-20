extends SceneTree
var checks:Array=[]
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 set_meta("eastfront_enabled",true);set_meta("eastfront_backend","dual_brain_laya")
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);current_scene=g;g.set_physics_process(false)
 var f=g.eastfront
 var plan={"template":"staggered","defenders":[{"weapon":"rifle","station":0},{"weapon":"rocket","station":2},{"weapon":"smg","station":1}],"defense":"entrench","construction":"balanced","armor":{"green":{"enabled":true,"delay":0,"role":"push"},"red":{"enabled":true,"delay":0,"role":"support"}},"reason":"村落纵深防御","layout":{"theme":"village","objective_z":0,"components":[
 {"kind":"house","x":.42,"z":-.8,"width":.30,"depth":.36},
 {"kind":"trench","x":.65,"z":0,"width":.075,"depth":.34},
 {"kind":"bunker","x":.97,"z":.78,"width":.30,"depth":.32},
 {"kind":"fuel_depot","x":.85,"z":-.75,"width":.15,"depth":.20},
 {"kind":"mud","x":.40,"z":.65,"width":.25,"depth":.40},
 {"kind":"water","x":.78,"z":-1.18,"width":.40,"depth":.15}]}}
 check(is_equal_approx(g.config.bounds[3]-g.config.bounds[1],2.8),"initial navigation and tabletop width doubled")
 check(f.propose(f.sequence,"staggered","fixture",plan)=="applied","model-authored varied component layout accepted")
 if f.chunks.size()<2:quit(1);return
 var ch=f.chunks[1]
 check(ch.covers.size()==6 and ch.covers[0].kind=="house","layout overrides three-sandbag legacy template")
 f.tick(1)
 check(ch.construction.jobs.any(func(j):return j.progress>0 and j.progress<1),"mixed architecture builds progressively")
 for i in range(300):f.tick(.05)
 check(ch.phase=="combat","mixed layout completed and activated without resetting match")
 check(ch.covers.all(func(c):return c.node.get_children().all(func(n):return not n is Node3D or n.visible)),"all building pieces including windows and roof revealed")
 f.logical+=30;f.armor.enforce_schedule()
 check(g.units.filter(func(u):return u.tank).all(func(u):return u.deployment_phase=="entering"),"slow deployment schedule cannot be starved by fast brain choosing hold")
 var defenders=g.units.filter(func(u):return ch.units.has(u.id))
 check(defenders.all(func(u):return u.cover_id!=""),"defenders assigned distinct architectural protection")
 var field=g.field;var trench=ch.covers[1];var house=ch.covers[0];var mud=ch.covers[4];var water=ch.covers[5]
 var center=Vector2(trench.position[0],trench.position[1])
 check(field.walkable(center,true) and not field.walkable(center),"tanks can cross shallow revetment while infantry must route to cover")
 var building=Vector2(house.position[0],house.position[1])
 check(not field.walkable(building,true),"strong building footprint blocks tanks")
 check(not field.segment_walkable(building-Vector2(.3,0),building+Vector2(.3,0),true),"tank sweep cannot phase through house")
 check(not field.path(building-Vector2(.3,0),building+Vector2(.3,0),true).is_empty(),"tank route goes around strong building")
 check(is_equal_approx(field.terrain_speed(Vector2(mud.position[0],mud.position[1])),.55),"mud actually reduces locomotion speed")
 check(not field.walkable(Vector2(water.position[0],water.position[1]),true),"water blocks tank navigation")
 for u in g.units:u.deployment_phase="parked"
 var tank=g.units.filter(func(u):return u.tank and u.faction=="green")[0]
 tank.position=Vector3(center.x-.25,field.height,center.y);tank.deployment_phase="active"
 var revision=field.revision
 for i in range(50):tank.tank_translate(tank.pos()+Vector2(.01,0))
 check(tank.pos().x>center.x+.20 and not trench.alive,"physical tank advances through and crushes shallow trench")
 check(field.revision>revision and field.walkable(center),"crushing opens infantry path with destruction and navigation update")
 check(house.alive,"crushing leaves unrelated strong buildings intact")
 tank.position=Vector3(building.x-.32,field.height,building.y);tank.rotation.y=-PI/2;tank.turret.rotation.y=0;tank.route.clear();tank.cooldown=0;tank.set_meta("breach_cover",house.id)
 var hp_before:float=house.hp;var shots:int=g.shots
 tank.tick(.05)
 check(g.shots>shots and g.fx.projectiles.size()>0,"breaching fires a real cannon projectile")
 for i in range(30):g.fx.physics_tick(.02)
 check(house.hp<hp_before,"breach cannon ray hits and damages the building")
 var fuel=ch.covers[3];var n=field.destruction_count
 field.damage_cover(fuel.id,1000)
 check(field.pending_blasts.size()==1,"destroyed fuel depot queues one real secondary explosion")
 var impacts=g.fx.impacts;g.fx.physics_tick(.02)
 check(field.pending_blasts.is_empty() and g.fx.impacts>impacts,"fuel blast processed through combat damage and effects")
 for u in g.units:
  if u.faction=="red":u.hp=0
 tank.route.clear();g.tactics_ai.tank_next.clear();g.tactics_ai.plan_tank(tank)
 check(tank.order_mode=="escort_advance" and not tank.route.is_empty(),"tank follows objective after enemies disappear")
 check(f.snapshot().component_catalog.size()==11 and f.snapshot().dimensions.battlefield_width==2.8,"model observation advertises geometry and material affordances")
 var invalid=plan.duplicate(true);invalid.layout.components[0].kind="water"
 check(preload("res://scripts/frontier_plan.gd").validate(invalid,"staggered")=="unsafe_defender_station","engine independently rejects unsafe defender station")
 print("FRONTIER_COMPONENTS ",JSON.stringify(checks))
 var out=FileAccess.open("res://output/frontier-components.json",FileAccess.WRITE);out.store_string(JSON.stringify(checks,"  "))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
