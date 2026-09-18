extends SceneTree
func _initialize():call_deferred("run")
func run():
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_physics_process(false);g.fx.set_muted(true)
 for team in g.control:g.control[team]="player"
 g.control.blue="game_ai"
 for u in g.units:u.cooldown=999
 await physics_frame
 for i in 2400:
  g.elapsed+=1.0/60;g.building.tick(1.0/60);g.tactics_ai.tick(1.0/60)
  for u in g.living("blue"):u.cooldown=999;u.tick(1.0/60);u.presentation_tick(1.0/60)
  if i%120==0:print(i," ",g.living("blue").map(func(u):return [u.id,u.position,u.garrison_phase,u.actor.last_blocker]))
  if g.living("blue").all(func(u):return u.garrison_phase=="stationed"):break
  await physics_frame
 var passed=g.living("blue").all(func(u):return u.garrison_phase=="stationed" and u.position.y>1.02)
 for u in g.living("blue"):g.building.leave(u)
 g.control.blue="player"
 for i in 3600:
  g.elapsed+=1.0/60;g.building.tick(1.0/60)
  for u in g.living("blue"):u.cooldown=999;u.tick(1.0/60);u.presentation_tick(1.0/60)
  if g.living("blue").all(func(u):return u.garrison_phase==""):break
  await physics_frame
 passed=passed and g.living("blue").all(func(u):return u.garrison_phase=="" and u.position.y<.87)
 var f=FileAccess.open("res://output/v06/equipment-squad.json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"building":g.building.snapshot(),"units":g.living("blue").map(func(u):return u.snapshot())},"  "));f.close()
 g.queue_free();await process_frame;quit(0 if passed else 1)
