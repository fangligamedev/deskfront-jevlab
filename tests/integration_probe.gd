extends Node
var checks=[]
func check(ok:bool,name:String):
 checks.append({"test":name,"passed":ok})
 if not ok:push_error(name)
func _ready():
 for index in range(3):
  get_tree().set_meta("deskfront_map",index)
  var g=load("res://scenes/main.tscn").instantiate();add_child(g);g.set_physics_process(false);g.fx.set_muted(true)
  await get_tree().physics_frame
  check(g.units.size()==9 and g.units.all(func(u):return u.bone_count==50),"map %d: nine upgraded soldiers"%index)
  check(g.worker.find_children("*","Skeleton3D",true,false)[0].get_bone_count()==62,"map %d: new typing human"%index)
  check(g.units.all(func(u):return u.actor.weapon.scale.is_equal_approx(Vector3.ONE*.075)),"map %d: weapon scale valid before first tick"%index)
  for team in g.control:g.control[team]="player";g.tactics_ai.cancel(team)
  for u in g.units:
   check(g.field.walkable(u.pos()),"%d/%s spawn walkable"%[index,u.id])
   var path=g.field.path(u.pos(),g.objective)
   check(path.size()>1 and path[-1].distance_to(g.objective)<.05,"%d/%s objective reachable"%[index,u.id])
  g.spawn_tank();var t=g.units[-1]
  check(t.muzzle!=null and t.turret!=null,"map %d: T2 turret/muzzle adapted"%index)
  check((t.muzzle.global_position-t.global_position).normalized().dot(-t.global_basis.z)>.5,"map %d: T2 muzzle matches -Z forward"%index)
  check(g.field.walkable(t.pos(),true),"map %d: rear tank spawn fits navigation"%index)
  if index==1:
   check(not g.field.walkable(Vector2(.54,2.09)),"river is blocked")
   check(g.field.walkable(Vector2(.04,2.09)) and g.field.walkable(Vector2(1.01,2.09)),"both bridges are walkable")
   check(g.field.ground_height(Vector2(.04,2.09))>.85,"bridge has matching foot elevation")
  if index==0:
   var u=g.units[0];var enemy=g.units[6]
   # Isolated clear central lane; all physical cover remains present.
   for other in g.units:other.hp=0;other.route.clear()
   u.hp=100;enemy.hp=100;u.position=Vector3(.54,g.field.height,2.35);enemy.position=Vector3(.54,g.field.height,2.05)
   u.actor.global_position=u.global_position;enemy.actor.global_position=enemy.global_position
   u.cooldown=100
   u.move_to(Vector2(.54,2.23));var original=u.pos()
   for i in range(120):u.tick(1.0/60);u.presentation_tick(1.0/60);g.elapsed+=1.0/60
   check(u.pos().distance_to(original)>.07 and u.actor.roots_travelled>.07,"authoritative movement comes from root motion")
   # Exercise the integrated controller's finite side step and support contact.
   u.route.clear();u.actor.playback.start("cover_idle",true);u.actor.clip="cover_idle";u.actor.tree.advance(0)
   u.actor.rotation.y=0;u.rotation.y=PI;u.actor.foot_locks.clear();u.actor.foot_previous.clear()
   var start=u.actor.global_position;u.actor.cover_target=start+Vector3(.033,0,0)
   for i in range(66):u.actor.advance_idle(1.0/60) if i>0 else u.actor.advance_drive(start+Vector3(.033,0,0),.1,1.0/60,true)
   u.global_position=u.actor.global_position
   check(absf(u.position.x-start.x-.033)<.001,"integrated finite cover step travels 33 mm")
   check(u.actor.contact_slip_max<.0005,"integrated cover contact slip below 0.5 mm")
   check(not u.actor.stepping,"cover step completes before stance change")
   u.actor.foot_locks.clear();u.equip("pistol")
   check(u.actor.weapon_mode=="pistol" and u.ammo==12,"pistol model and gameplay loadout available")
   u.equip("rocket");check(u.actor.weapon_mode=="rocket","rocket mesh follows hand controller")
   u.equip("rifle");u.cooldown=0;u.grenade_count=2
   check(u.request_grenade(enemy),"grenade throw accepted in range")
   for i in range(36):u.tick(1.0/60);u.presentation_tick(1.0/60)
   check(g.fx.launched.get("grenade",0)==0,"grenade waits for release frame")
   for i in range(4):u.tick(1.0/60);u.presentation_tick(1.0/60)
   check(g.fx.launched.get("grenade",0)==1 and u.grenade_count==1,"grenade releases once and consumes inventory")
   g.fx.physics_tick(2)
   check(enemy.hp<100,"grenade impact uses authoritative damage")
   check(g.fx.visuals.any(func(v):return v.has("smoke")),"new flipbook smoke/explosion materials rendered")
   enemy.hit(1000,1);check(enemy.actor.dead and enemy.actor.bodies.size()==18,"death switches imported skin to 18-body ragdoll")
   g.paused=true;var old=u.actor.global_position;g._physics_process(.5)
   check(old.is_equal_approx(u.actor.global_position),"pause freezes authoritative root motion")
   var crate=g.field.covers.filter(func(c):return c.id=="crate-0")[0]
   g.field.damage_cover(crate.id,999)
   check(not crate.alive and crate.node.collision_layer==0,"destruction updates navigation and physical cover together")
  g.queue_free();await get_tree().process_frame;await get_tree().process_frame
 var ok=checks.all(func(c):return c.passed)
 var f=FileAccess.open("res://output/integration/qa.json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":ok,"checks":checks},"  "))
 print("ASSET_INTEGRATION ",ok," checks=",checks.size());get_tree().quit(0 if ok else 1)
