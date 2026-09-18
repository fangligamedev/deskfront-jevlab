extends SceneTree
## 10 distinct scenarios × 10 deterministic seeds, using the real game tick/animation/FX.
var cases=["meeting","suppressed","flanked","cover_destroyed","wounded","corner","armor_threat","grenade","crossfire","retreat"]
func _initialize():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/v05"))
 call_deferred("run")
func place(g,u,p):
 var q=g.field.to_world(g.field.nearest(p,u.tank));u.position=Vector3(q.x,g.field.height,q.y);u.route.clear();u.goal=q;u.cover_id="";u.cover_slot={}
 if u.actor:u.actor.global_position=u.global_position
func run():
 var count=100;var prefix="final";var first_index=0
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--start="):first_index=int(arg.split("=")[1])
  if arg.begins_with("--runs="):count=int(arg.split("=")[1])
  if arg.begins_with("--prefix="):prefix=arg.split("=")[1]
 var runs=[];var start=Time.get_ticks_msec()
 for index in range(first_index,first_index+count):
  var scenario=cases[index%cases.size()];var seed_value=19092026+index*7919;var map_index=index%3
  set_meta("deskfront_map",map_index)
  var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_physics_process(false);g.fx.set_muted(true);g.rng.seed=seed_value;g.fx.random.seed=seed_value+1
  g.config.rules.match_seconds=70;g.config.rules.score_to_win=999
  var subject=g.units[0];var enemy=g.units[6]
  var cover=g.field.covers.filter(func(c):return c.kind!="hard")[0]
  var slots=g.field.slots(cover);var slot=slots.filter(func(s):return g.field.walkable(s.position))[0]
  var forward:Vector2=slot.normal
  if scenario!="meeting":
   place(g,subject,slot.position);subject.occupy(slot);subject.route.clear()
   place(g,enemy,slot.position+forward*.43)
   for i in [1,2]:place(g,g.units[i],slot.position+Vector2(.07*i,0)-forward*.12)
  if scenario=="suppressed":subject.receive_pressure(.96,enemy.global_position)
  if scenario=="flanked":place(g,enemy,slot.position-forward*.35)
  if scenario=="wounded":subject.hp=24;subject.receive_pressure(.65,enemy.global_position)
  if scenario=="corner":
   var hard=g.field.covers.filter(func(c):return c.kind=="hard")
   if not hard.is_empty():
    for station in g.field.slots(hard[0]):
     if g.field.walkable(station.position) and g.field.walkable(station.peek):
      place(g,subject,station.position);subject.occupy(station);subject.route.clear();place(g,enemy,station.position+station.normal*.4);break
  if scenario=="armor_threat":
   g.spawn_tank();var tank=g.units[-1];var rocket=g.units[2]
   place(g,rocket,tank.pos()+Vector2(.2,.13));tank.hp=130
  if scenario=="grenade":
   place(g,enemy,slot.position+forward*.22);subject.grenade_count=2;subject.request_grenade(enemy)
  if scenario=="crossfire":place(g,g.units[3],slot.position-forward*.38)
  if scenario=="retreat":
   for u in g.living("green"):u.hp=26;u.receive_pressure(.65,enemy.global_position)
  var m={"alive_samples":0,"cover_samples":0,"prone_samples":0,"crawl_samples":0,"run_samples":0,"walk_samples":0,"survival_samples":0,"unsafe_cover_samples":0,"invalid_navigation":[],"animation_mismatch":[],"postures":{},"locomotion":{},"shots_at_15":0,"deaths_at_15":0}
  var samples=[];var injected=false;var unsafe_dwell={};var stuck_dwell={};var last_positions={}
  m["stuck_examples"]=[];m["unsafe_examples"]=[];m["unsafe_dwell_max"]=0.0;m["stuck_dwell_max"]=0.0
  for step in range(1800): # 60 s at fixed 30 Hz; swept projectiles avoid tunneling.
   if scenario=="cover_destroyed" and not injected and g.elapsed>=3:
    g.field.damage_cover(cover.id,10000);injected=true
   g._physics_process(1.0/30);g.fx._process(1.0/30)
   if step%15==0:
    for u in g.living():
     var navigable:bool=g.field.walkable(u.pos(),u.tank)
     if u.garrison_phase!="":navigable=u.position.y>=g.field.height-.01 and u.position.y<=g.building.floor_y+.015 and u.pos().x>.72 and u.pos().x<1.37 and u.pos().y>.8 and u.pos().y<1.87
     if not navigable and m.invalid_navigation.size()<20:m.invalid_navigation.append({"t":g.elapsed,"unit":u.id,"p":[u.pos().x,u.pos().y]})
     if u.tank:continue
     m.alive_samples+=1
     if u.in_cover():m.cover_samples+=1
     if u.posture=="prone":m.prone_samples+=1
     if u.locomotion=="crawl":m.crawl_samples+=1
     if u.locomotion=="run":m.run_samples+=1
     if u.locomotion=="walk":m.walk_samples+=1
     if g.elapsed<u.safety_until:m.survival_samples+=1
     m.postures[u.posture]=int(m.postures.get(u.posture,0))+1;m.locomotion[u.locomotion]=int(m.locomotion.get(u.locomotion,0))+1
     var threat=g.closest_enemy(u)
     if u.in_cover() and threat!=null and g.field.protection(u.pos(),threat.pos())<.2:
      m.unsafe_cover_samples+=1;unsafe_dwell[u.id]=float(unsafe_dwell.get(u.id,0))+.5
     else:unsafe_dwell[u.id]=0.0
     if unsafe_dwell[u.id]>1.5 and m.unsafe_examples.size()<5:m.unsafe_examples.append({"t":g.elapsed,"u":u.snapshot(),"enemy":threat.snapshot(),"slot":str(u.cover_slot)})
     m.unsafe_dwell_max=maxf(m.unsafe_dwell_max,unsafe_dwell[u.id])
     if not u.route.is_empty() and last_positions.has(u.id) and u.pos().distance_to(last_positions[u.id])<.001:stuck_dwell[u.id]=float(stuck_dwell.get(u.id,0))+.5
     else:stuck_dwell[u.id]=0.0
     if stuck_dwell[u.id]>3 and m.stuck_examples.size()<5:m.stuck_examples.append({"t":g.elapsed,"u":u.snapshot(),"route":str(u.route),"blocker":u.actor.last_blocker,"step_target":str(u.actor.cover_target)})
     last_positions[u.id]=u.pos();m.stuck_dwell_max=maxf(m.stuck_dwell_max,stuck_dwell[u.id])
     if u.posture=="prone" and u.actor.clip=="cover_idle" and not u.actor.stepping:m.animation_mismatch.append({"t":g.elapsed,"unit":u.id})
    if step==450:m.shots_at_15=g.shots;m.deaths_at_15=9-g.living().filter(func(u):return not u.tank).size()
   if step%150==0:samples.append({"time":g.elapsed,"shots":g.shots,"destroyed":g.field.destruction_count,"units":g.living().map(func(u):return {"id":u.id,"hp":snappedf(u.hp,1),"pos":[snappedf(u.pos().x,.01),snappedf(u.pos().y,.01)],"posture":u.posture,"gait":u.locomotion,"intent":u.order_mode,"cover":u.cover_id,"reason":u.safety_reason}),"tactics":g.tactics_ai.snapshot()})
   if step%30==0:await process_frame
   if g.winner!="":break
  var passed=m.invalid_navigation.is_empty() and m.animation_mismatch.is_empty() and m.walk_samples==0 and m.unsafe_dwell_max<=1.5 and m.stuck_dwell_max<=4.0
  runs.append({"index":index,"case":scenario,"seed":seed_value,"map":g.map_data.id,"passed":passed,"time":g.elapsed,"shots":g.shots,"destroyed":g.field.destruction_count,"collisions":g.fx.collision_counts.duplicate(),"alive":g.living().size(),"metrics":m,"samples":samples})
  print("REHEARSAL ",index+1,"/",count," ",scenario," map=",g.map_data.id," shots=",g.shots," destruction=",g.field.destruction_count," nav=",m.invalid_navigation.size()," anim=",m.animation_mismatch.size())
  g.queue_free();await process_frame;await process_frame
  var report={"passed":runs.all(func(r):return r.passed),"count":runs.size(),"required_final_count":100,"fixed_dt":1.0/30,"wall_seconds":(Time.get_ticks_msec()-start)/1000.0,"runs":runs}
  FileAccess.open("res://output/v05/"+prefix+"-rehearsal.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 quit(0 if runs.all(func(r):return r.passed) else 1)
