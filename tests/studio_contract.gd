extends SceneTree
var checks:int=0
var failures:Array=[]
func check(value:bool,label:String):
 checks+=1
 if not value:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 var level=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/studio_level.json"))
 var valid=preload("res://scripts/scenario_validator.gd").validate(level)
 check(valid.passed and valid.spawn_routes.size()==9 and valid.open_approaches>=2,"authored level has real navigable routes and open flag approaches")
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);current_scene=g;g.paused=true
 var original_run=g.run_id;var bad=level.duplicate(true)
 for o in bad.objects:
  if str(o.id).begins_with("studio-cover"):o.position=bad.objective.duplicate();break
 var denied=g.command({"action":"scenario","level":bad})
 check(not denied.accepted and g.run_id==original_run,"blocked authored flag rejected without changing current battle")
 var extra=level.duplicate(true);extra.objects[-1]["elevation"]=200
 check(not preload("res://scripts/scenario_validator.gd").validate(extra).passed,"unrecognized prop fields rejected by engine")
 var accepted=g.command({"action":"scenario","level":level,"modes":{"green":"player","blue":"lm","red":"game_ai"}})
 check(accepted.accepted,"validated scenario command accepted")
 await process_frame;await process_frame
 g=current_scene;g.set_physics_process(false)
 check(g.run_id!=original_run and g.map_data.scenario_id=="contract","new game loaded actual authored scenario")
 check(g.paused and g.control.green=="player" and g.control.blue=="lm" and g.control.red=="game_ai","play setup loads paused with chosen player and AI authority")
 check(g.units.size()==9 and g.reserve_tank.deployment_phase=="parked","authored game retains nine soldiers and parked reinforcement")
 check(g.snapshot().scenario.name==level.name and g.flag_objective.required_seconds==level.hold_seconds,"scenario identity and rules observable to agents")
 var weapons:Array=g.living("green").map(func(u):return u.weapon)
 check(weapons==level.loadouts.green,"authored loadout applied to actual soldiers")
 var before_reset=g.run_id;g.command({"action":"reset"})
 await process_frame;await process_frame
 g=current_scene;g.set_physics_process(false)
 check(g.run_id!=before_reset and g.map_data.scenario_id=="contract","restart preserves authored level with a fresh run id")
 g.command({"action":"map","index":1})
 await process_frame;await process_frame
 g=current_scene;g.set_physics_process(false)
 check(g.map_data.id=="river" and not g.map_data.has("scenario_id"),"built-in map selector leaves authored scenario cleanly")
 print("STUDIO_CONTRACT "+JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
