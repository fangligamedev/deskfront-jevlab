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
 check(f.propose(f.sequence,"staggered","fixture")=="applied","first sector construction starts")
 for i in range(250):f.tick(.05)
 check(f.active_sector==1 and f.chunks[1].phase=="combat","first sector still contested")
 check(not f.request.is_empty() and f.request.index==2,"requests eastern neighbor before expedition approaches edge")
 check(g.living("green").all(func(u):return u.pos().x<.5),"expedition remains far west during preconstruction request")
 var run_id=g.run_id;var objective=g.objective;var camera=g.camera_target
 var soldier=g.living("green")[0];soldier.move_to(Vector2(.9,0));var route=soldier.route.duplicate()
 var seq=f.sequence
 check(f.propose(seq,"crossfire","fixture")=="applied","next segment begins while current defenders alive")
 check(f.chunks[2].node.visible and f.chunks[2].construction.workers.size()==2,"visible right-side construction and workers")
 check(g.field.covers.size()==3,"unfinished next segment has no collision cover")
 f.tick(3)
 check(f.chunks[2].construction.snapshot().progress>0,"construction progresses concurrently")
 check(g.run_id==run_id and not g.paused and g.objective==objective,"construction does not reload pause or change combat goal")
 check(soldier.route==route and g.camera_target==camera,"construction preserves current route and camera")
 check(g.living("red").size()==2,"future defenders do not join current combat")
 for i in range(250):f.tick(.05)
 check(f.chunks[2].phase=="ready" and f.active_sector==1,"neighbor fully ready before current capture")
 check(g.units.filter(func(u):return f.chunks[2].units.has(u.id)).all(func(u):return u.deployment_phase=="parked"),"next defenders remain visible reserves")
 check(g.run_id==run_id and soldier.route==route and g.objective==objective,"neighbor commit leaves ongoing battle intact")
 f.need_next()
 check(f.request.is_empty() and f.chunks.size()==3,"one-sector preview prevents unbounded generation")
 for u in g.living("red"):u.hp=0
 for u in g.living("green"):u.position=Vector3(objective.x,g.field.height,objective.y)
 f.update_capture(5.1)
 check(f.active_sector==2 and f.chunks[2].phase=="combat","capture immediately activates prepared neighbor")
 check(g.run_id==run_id and not g.paused,"handoff has no reset or loading pause")
 check(not f.request.is_empty() and f.request.index==3,"handoff begins preparation of following neighbor")
 print("FRONTIER_CONTINUITY ",JSON.stringify(checks))
 var out=FileAccess.open("res://output/frontier-continuity.json",FileAccess.WRITE);out.store_string(JSON.stringify(checks,"  "))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
