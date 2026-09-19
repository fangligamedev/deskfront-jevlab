extends SceneTree
var checks=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func run():
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g)
 g.set_physics_process(false);g.set_process_unhandled_input(false);g.fx.set_muted(true)
 check(g.control.values().all(func(v):return v=="lm"),"new main game defaults all factions to LLM")
 check(not g.snapshot().debug_visualize.enabled and g.snapshot().debug_visualize.units.is_empty(),"diagnostics off: no route payload")
 var u=g.units[0];var modes=g.control.duplicate();var epoch=g.control_epochs.duplicate()
 check(g.command({"action":"debug_visualize","value":true,"unit":u.id}).accepted,"debug toggle accepted")
 check(g.control==modes and g.control_epochs==epoch,"toggle cannot take unit authority or cancel LLM")
 var path=[Vector2(-.2,2.4),Vector2(-.1,2.5)];u.route=PackedVector2Array(path)
 var row=g.debug_view.rows()[0]
 check(row.waypoints.size()==2 and is_equal_approx(row.waypoints[0][0],path[0].x),"ordered future path reads actual unit route")
 u.garrison_path.assign([Vector3(.8,.96,1.2),Vector3(.9,1.06,1.3)])
 row=g.debug_view.rows()[0]
 check(is_equal_approx(row.next[1],.96) and row.waypoints.size()==2,"stair navigation preserves real three-dimensional height")
 u.garrison_path.clear();g.debug_view._process(.2);var previous=u.global_position
 u.position.x+=.01;g.debug_view._process(.2);row=g.debug_view.rows()[0]
 check(row.trail.size()==2 and is_equal_approx(row.trail[0][0],previous.x) and is_equal_approx(row.trail[1][0],u.position.x),"history samples actual positions")
 for i in range(130):u.position.x+=.01;g.debug_view._process(.2)
 check(g.debug_view.histories[u.id].size()==100,"history is bounded")
 var c={"action":"hold","source":"lm","faction":"green","unit_ids":[u.id],"run_id":g.run_id,"seen_tick":g.tick_id,"control_epoch":g.control_epochs.green,"reason":"守住观察位置","id":"test-debug-command"}
 check(g.command(c).accepted and g.debug_view.rows()[0].command.command_id==c.id,"accepted command links exact receipt ID and reason")
 c.seen_tick=-999;c.reason="过期理由"
 check(not g.command(c).accepted and g.debug_view.rows()[0].command.reason=="守住观察位置","rejected reasoning never masquerades as executing order")
 c.seen_tick=g.tick_id;c.decision_origin="local_fallback";g.command(c)
 check(g.debug_view.rows()[0].command.source=="local_fallback","local safety fallback is distinguished from model")
 check(not g.command({"action":"debug_visualize","value":true,"unit":"missing"}).accepted,"unknown debug unit rejected")
 check(not g.command({"action":"debug_visualize","value":"yes"}).accepted,"non-boolean toggle rejected")
 g.debug_view.configure(true,"not-yet-spawned-tank")
 check(g.debug_view.focus=="","reset clears a focus unit absent from the new scene")
 g.command({"action":"debug_visualize","value":false})
 check(not g.debug_view.visible and g.debug_view.histories.is_empty() and g.debug_view.snapshot().units.is_empty(),"off removes overlay, trace and route payload")
 var f=FileAccess.open("res://output/debug-visualize-contract.json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":checks.all(func(c):return c.passed),"checks":checks},"  "));f.close()
 g.queue_free();await process_frame
 quit(0 if checks.all(func(c):return c.passed) else 1)
