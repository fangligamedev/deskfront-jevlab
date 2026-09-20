extends SceneTree
var checks:Array=[]
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 set_meta("eastfront_enabled",true);set_meta("eastfront_backend","model")
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);current_scene=g;g.set_physics_process(false)
 var f=g.eastfront
 check(f.rules.templates.size()>=6,"six distinct tactical layouts")
 var original=g.units.map(func(u):return u.id)
 var start:float=g.units[0].pos().x
 for i in range(50):g._physics_process(.05)
 check(g.units.all(func(u):return not u.route.is_empty() or u.pos().x>start+.25),"safe approach moves all soldiers without one-at-a-time waits")
 check(f.propose(f.sequence,"trench_zigzag","test")=="applied","trench scenario validates")
 var ch:Dictionary=f.chunks[-1];var states:Array=[]
 ch.construction.policy="dig_first"
 for i in range(260):
  f.tick(.05)
  if i==60:check(ch.construction.jobs.all(func(j):return j.progress<=.401),"dig-first policy delays hauling until all trenches dug")
  for w in ch.construction.workers:if w.state not in states:states.append(w.state)
 check(states.has("dig") and states.has("carry_sandbag") and states.has("stack_sandbag"),"visible dig carry stack stages")
 check(ch.phase=="combat" and g.field.covers.size()==3,"construction completes before physics commit")
 check(is_equal_approx(g.objective.y,.20),"layout changes capture route")
 check(f.apply_directive(f.active_sector,"flank_north","north_first","test")=="applied","typed fast directive accepted")
 check(f.apply_directive(999,"advance","balanced","test")=="stale_frontier_directive","stale tactical policy rejected")
 for u in g.living("green"):u.hp=0
 f.tick(.05)
 check(g.winner=="" and f.reinforcement_due>0,"wipe schedules a wave instead of ending campaign")
 f.tick(5.1)
 check(g.living("green").size()==3 and g.living("green").all(func(u):return not original.has(u.id)),"new identities spawn from rear")
 check(g.living("green").all(func(u):return u.pos().x<g.objective.x-.5),"reinforcements enter from west")
 check(f.wave==2,"wave count advances")
 var patient=g.living("green")[0];patient.hp=20
 f.update_aid(.5)
 check(patient.hp>20 and patient.order_mode=="rear_aid","aid heals only after reaching safe rear")
 var enemy=g.living("red")[0];enemy.position=patient.position+Vector3(.1,0,0)
 var hp:float=patient.hp;f.update_aid(.5)
 check(is_equal_approx(patient.hp,hp),"enemy pressure prevents rear healing")
 f.need_next()
 check(f.propose(f.sequence,"trench_zigzag","test")=="repeated_frontier_template","adjacent layouts cannot repeat")
 print("DUAL_BRAIN_CONTRACT ",JSON.stringify(checks))
 var file=FileAccess.open("res://output/dual-brain/contract.json",FileAccess.WRITE);file.store_string(JSON.stringify(checks,"  "))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
