extends SceneTree
var checks:int=0
var failures:Array=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 var level=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/studio_level.json"))
 set_meta("studio_level",level);set_meta("demo_enabled",true);set_meta("demo_driver","local_rehearsal");set_meta("studio_controls",{"green":"game_ai","red":"game_ai","blue":"game_ai"})
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);current_scene=g;g.set_physics_process(false)
 check(g.demo!=null and g.demo.snapshot().human_count==2,"two standing people and director are present")
 check(g.living().is_empty() and g.units.size()==9,"all soldiers initially reserve, none participates")
 check(g.units.all(func(u):return u.available_actions().is_empty()),"reserve units cannot accept combat actions")
 g.command({"action":"pause"});var paused_clock=g.demo.clock;g.demo.tick(1)
 check(not g.demo.running and g.demo.clock==paused_clock,"setup pauses clock")
 g.command({"action":"pause"});check(g.demo.running,"setup pause button toggles resume")
 var count=g.demo.options().size();check(count>=4,"validated build operations exposed")
 check(not g.command({"action":"demo_step","step_id":"arbitrary-code"}).accepted,"unknown editor action rejected")
 check(not g.command({"action":"capture","faction":"green"}).accepted,"combat blocked during setup")
 for i in range(count):check(g.command({"action":"demo_step","step_id":g.demo.options()[0].id}).accepted,"actual cover placement "+str(i))
 check(g.demo.phase=="deploying","building completes before deployment")
 for o in g.demo.options():g.command({"action":"demo_step","step_id":o.id})
 check(g.units.filter(func(u):return u.deployment_phase=="entering").size()==6,"exactly six soldiers enter")
 for i in range(1500):g.demo.tick(1.0/60)
 check(g.demo.phase=="ready" and g.living().size()==6,"all units reach deployment locations")
 check(g.living("blue").is_empty() and g.shots==0,"blue remains reserve and no premature shots")
 check(g.command({"action":"demo_step","step_id":"start_battle"}).accepted and not g.paused,"director starts battle")
 for i in range(100):g._physics_process(1.0/60)
 check(g.elapsed>0 and g.demo.phase=="battle","real game simulation advances")
 g.finish_match("green","test conclusion");g.demo.tick(.1)
 check(g.demo.phase=="finished","winner transitions to report stage")
 print("DEMO_CONTRACT "+JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures}));quit(0 if failures.is_empty() else 1)
