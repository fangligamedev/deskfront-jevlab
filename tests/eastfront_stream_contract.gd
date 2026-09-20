extends SceneTree
var failures:Array=[]
var checks:int=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 set_meta("eastfront_enabled",true);set_meta("eastfront_backend","model")
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);current_scene=g;g.set_physics_process(false)
 var f=g.eastfront
 check(not g.command({"action":"scenario","level":{}}).accepted and get_meta("eastfront_enabled"),"invalid scenario leaves campaign intact")
 check(not g.command({"action":"map","index":99}).accepted and get_meta("eastfront_enabled"),"invalid map leaves campaign intact")
 check(g.snapshot().objective.flag.mode=="eastfront_sector","public flag mode identifies sector capture")
 g.pan_by(Vector3(.1,0,0));check(not f.follow,"manual RTS pan releases camera follow")
 check(f.propose(1,"not-a-template","test")=="unknown_frontier_template","unknown template refused")
 var saved_size=f.rules.templates[0].covers[0][2];f.rules.templates[0].covers[0][2]=-1
 check(f.propose(1,"staggered","test")=="invalid_component_bounds","invalid component dimensions refused")
 f.rules.templates[0].covers[0][2]=saved_size
 var saved=g.units[0].position;g.units[0].position.x=float(f.rules.width)+float(f.rules.templates[0].covers[0][0]);g.units[0].position.z=float(f.rules.templates[0].covers[0][1])
 check(f.propose(1,"staggered","test")=="occupied_frontier","never construct over an occupied position")
 g.units[0].position=saved
 f.tick(float(f.rules.model_deadline_seconds)+.1)
 check(f.chunks[-1].source=="local_timeout_fallback","model timeout explicitly produces local fallback")
 check(f.propose(1,"crossfire","late_model")=="stale_frontier_request","late model cannot overwrite committed proposal")
 f.backend="local"
 var maximum_units=0;var maximum_covers=0
 for sector in range(1,101):
  f.need_next();f.tick(.1);f.tick(6.1);f.tick(6.1)
  check(f.active_sector==sector and f.total_built>=sector,"sector available "+str(sector))
  # This is a streaming stress contract, NOT a claimed autonomous combat win.
  for u in g.units:
   if u.faction=="red" and u.deployment_phase=="active":u.hp=0
  var i=0
  for u in g.living("green"):
   u.position=Vector3(g.objective.x-.04+i*.03,g.field.height,g.objective.y);u.goal=u.pos();u.route.clear();i+=1
  f.update_capture(5.1);f.retire_old()
  await process_frame
  maximum_units=maxi(maximum_units,g.units.size());maximum_covers=maxi(maximum_covers,g.field.covers.size())
  check(f.chunks.size()<=int(f.rules.max_chunks),"bounded window "+str(sector))
  check(g.field.walkable(g.living("green")[0].pos()),"navigation remains aligned "+str(sector))
 check(f.cleared==100 and f.retired>=98,"100 sectors generated and old sectors retired")
 check(maximum_units<=11 and maximum_covers<=12,"unit and collision lists bounded")
 check(f.history.size()<=80,"in-memory timeline bounded")
 var result={"checks":checks,"passed":failures.is_empty(),"failures":failures,"cleared":f.cleared,"retired":f.retired,"maximum_units":maximum_units,"maximum_covers":maximum_covers,"kind":"streaming_contract_not_autonomous_combat"}
 var file=FileAccess.open("res://output/eastfront/stream-contract.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "))
 print("EASTFRONT_STREAM "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
