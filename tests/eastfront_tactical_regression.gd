extends SceneTree
var checks:Array=[]
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 set_meta("eastfront_enabled",true);set_meta("eastfront_backend","model");seed(19)
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);current_scene=g;g.set_physics_process(false)
 var f=g.eastfront
 f.backend="dual_brain_laya";g.set_control_mode("green","lm")
 f.propose(f.sequence,OS.get_environment("TACTICAL_TEMPLATE") if OS.get_environment("TACTICAL_TEMPLATE")!="" else "staggered","probe")
 var cover_ids:Dictionary={};var phases:Dictionary={};var cover_frames:int=0;var run_frames:int=0;var samples:Array=[]
 for i in range(2400):
  g._physics_process(.05)
  for u in g.living("green"):
   if u.in_cover():cover_frames+=1;cover_ids[u.id]=true
   if u.locomotion in ["run","sprint","crouch_run"]:run_frames+=1
  if g.tactics_ai.squads.has("green"):phases[g.tactics_ai.squads.green.phase]=true
  if i%100==0:samples.append({"time":g.elapsed,"cleared":f.cleared,"units":g.living("green").map(func(u):return {"id":u.id,"pos":[u.pos().x,u.pos().y],"cover":u.cover_id,"order":u.order_mode,"stance":u.cqb_stance,"hp":u.hp}),"squads":g.tactics_ai.snapshot()})
  if f.cleared>=1:break
 check(cover_ids.size()>=2,"two members actually occupy protected stations")
 check(phases.has("take_cover") and phases.has("suppress"),"contact uses original cover and suppression coordinator")
 check(phases.has("bound"),"contact includes a bounded reposition or leapfrog phase")
 check(run_frames>30,"safe transfers use run locomotion")
 check(f.cleared>=1,"real AI captures first sector without forced kills")
 check(g.control.green=="lm","Laya retains expedition model authority")
 for backend in ["dual_brain","dual_brain_laya"]:
  f.backend=backend
  check(g.command({"action":"control","faction":"green","mode":"lm"}).accepted,"model squad control accepted: "+backend)
  check(g.tactics_ai.model_squad("green"),"model squad coordinator enabled: "+backend)
  var ids=g.living("green").map(func(u):return u.id)
  check(not g.command({"source":"lm","action":"capture","faction":"green","unit_ids":ids,"run_id":g.run_id,"seen_tick":g.tick_id,"control_epoch":g.control_epochs.green}).accepted,"duplicate per-unit orders blocked: "+backend)
 check(g.command({"action":"control","faction":"green","mode":"player"}).accepted and not g.tactics_ai.model_squad("green"),"player takeover releases model squad")
 var result={"checks":checks,"phases":phases.keys(),"cover_units":cover_ids.keys(),"cover_frames":cover_frames,"run_frames":run_frames,"shots":g.shots,"seconds":g.elapsed,"samples":samples}
 var out=OS.get_environment("TACTICAL_PROBE_OUTPUT")
 if out=="":out="res://output/tactical-debug/after.json"
 FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("TACTICAL_REGRESSION ",JSON.stringify({"checks":checks,"phases":phases.keys(),"cover_units":cover_ids.keys(),"shots":g.shots,"seconds":g.elapsed}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
