extends SceneTree
var checks:Array=[]
var layout="staggered"
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func plan(template:String)->Dictionary:
 return {"template":template,"defenders":[{"weapon":"rifle","station":0},{"weapon":"rocket","station":2},{"weapon":"smg","station":1}],"defense":"entrench","construction":"dig_first","armor":{"green":{"enabled":true,"delay":2,"role":"support"},"red":{"enabled":true,"delay":3,"role":"support"}},"reason":"前沿分工据壕，双方装甲按计划入场"}
func _initialize():call_deferred("run")
func run():
 if not OS.get_cmdline_user_args().is_empty():layout=OS.get_cmdline_user_args()[0]
 set_meta("eastfront_enabled",true);set_meta("eastfront_backend","dual_brain_laya")
 var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);current_scene=g;g.set_physics_process(false)
 var f=g.eastfront
 f.tick(25)
 check(f.chunks.size()==1 and not f.request.is_empty(),"dual brain waits for actual slow plan beyond timeout")
 check(f.propose(f.sequence,layout,"deepseek_slow_plan",plan(layout))=="applied","executable plan accepted")
 var ch=f.chunks[-1]
 check(ch.construction.workers.all(func(w):return w.actor.skeleton.get_bone_count()>20 and w.actor.model!=null),"construction uses production plastic soldier skin and rig")
 for i in range(260):f.tick(.05)
 check(ch.phase=="combat","construction commits collision before activation")
 var red=g.living("red").filter(func(u):return not u.tank)
 check(red.size()==3 and red[1].weapon=="rocket","slow plan defender loadout honored")
 check(red.all(func(u):return u.cover_id!="" and not u.route.is_empty()) and red[0].cover_id!=red[1].cover_id,"defenders assigned separate reachable trench positions")
 check(f.armor.snapshot().size()==2,"both planned visible tanks created")
 var tanks=g.units.filter(func(u):return u.tank)
 check(tanks.all(func(u):return u.deployment_phase=="parked" and u.visible),"tanks visible before deployment, not combat ready")
 f.apply_directive(f.active_sector,"advance","dig_first","laya_fast","entrench","deploy_both")
 check(tanks.all(func(u):return u.deployment_phase=="parked"),"fast brain cannot bypass planned delay")
 f.logical+=4
 g.control.green="player"
 f.apply_directive(f.active_sector,"advance","balanced","laya_fast","entrench","deploy_both")
 check(tanks.filter(func(u):return u.faction=="green")[0].deployment_phase=="parked","player control prevents automated green deployment")
 g.control.green="lm"
 f.apply_directive(f.active_sector,"advance","balanced","laya_fast","entrench","deploy_both")
 check(tanks.all(func(u):return u.deployment_phase=="entering"),"fast directive releases both tanks")
 var origins=tanks.map(func(u):return u.pos())
 for u in tanks:u.tick(.1)
 check(tanks.all(func(u):return u.deployment_phase=="entering" and u.last_shot_at<0),"entering tanks cannot ghost fire")
 for i in range(tanks.size()):check(tanks[i].pos().distance_to(origins[i])<.02,"tank entry is incremental, never teleport")
 for i in range(300):
  for u in tanks:u.deployment_tick(.05)
 check(tanks.all(func(u):return u.deployment_phase=="active"),"both tanks reach battlefield through navigable entry")
 # Remove enemy fire to verify actual cover arrival independently of combat casualties.
 for u in g.living("green"):u.deployment_phase="parked"
 for i in range(360):
  g.elapsed+=.05
  f.plan_defenders()
  for u in red:u.tick(.05)
 check(red.all(func(u):return u.in_cover()),"all assigned defenders physically arrive inside protective cover")
 for u in g.units:
  if u.faction=="green" and not u.tank:u.hp=0
 f.tick(.05)
 check(f.reinforcement_due>0,"infantry wipe requests reinforcements even with surviving tank")
 print("FRONTIER_CAMPAIGN ",JSON.stringify(checks))
 var file=FileAccess.open("res://output/frontier-campaign-"+layout+".json",FileAccess.WRITE);file.store_string(JSON.stringify(checks,"  "))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
