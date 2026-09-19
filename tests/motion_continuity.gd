extends SceneTree
var checks: Array=[]
var measurements: Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):checks.append({"test":label,"passed":ok})
func run():
 var g=load('res://scenes/main.tscn').instantiate();root.add_child(g)
 g.set_physics_process(false);g.set_process(false);g.fx.set_muted(true)
 var profiles={}
 for mode in ['game_ai','lm']:
  for team in g.control:g.control[team]=mode
  var samples=[]
  var queries_before=g.field.path_queries
  for i in 8:
   g.tactics_ai.flag_hints.clear()
   var start=Time.get_ticks_usec();g.snapshot();samples.append((Time.get_ticks_usec()-start)/1000.0)
  profiles[mode+'_cold_snapshot_ms']=samples
  check(g.field.path_queries==queries_before,mode+' snapshots never trigger synchronous route searches')
 var cold=g.tactics_ai.flag_hints.size()
 g.tactics_ai.refresh_flag_hint(.1)
 check(g.tactics_ai.flag_hints.size()==cold+1,'one advisory route refreshed per time slice')
 for i in 20:g.tactics_ai.refresh_flag_hint(.1)
 check(g.tactics_ai.flag_hints.size()==9,'all nine live soldiers receive advisory routes')
 g.field.revision+=1
 check(g.tactics_ai.flag_hint(g.units[0]).pending,'changed navigation never exposes stale advice')
 var unit=g.units[0]
 for other in g.units:
  if other!=unit:other.hp=0
 var origin=Vector2.INF
 for x in range(4,50):
  for z in range(4,50):
   var p=g.field.to_world(Vector2i(x,z))
   if g.field.segment_walkable(p,p+Vector2(.55,0)):
    origin=p;break
  if origin!=Vector2.INF:break
 check(origin!=Vector2.INF,'find a real obstacle-free navigation corridor')
 for mode in ['game_ai','lm']:
  g.control[unit.faction]=mode
  unit.position=Vector3(origin.x,g.field.ground_height(origin),origin.y);unit.actor.global_position=unit.global_position
  unit.actor.advance_idle(1.0/60);unit.posture_order='stand';unit.target_id='';unit.cover_id='';unit.cover_slot={};unit.suppression=0;unit.safety_until=0
  unit.goal=origin+Vector2(.5,0);unit.route=PackedVector2Array()
  for i in 13:unit.route.append(origin+Vector2(i*.04,0))
  unit.route.append(unit.goal);unit.route_revision=g.field.revision
  var interrupted=[];var frames=[];var costs=[];var arrived=false
  for i in 360:
   g.elapsed+=1.0/60
   var count=unit.route.size();var before=unit.pos();var time=Time.get_ticks_usec()
   unit.tick(1.0/60);unit.presentation_tick(1.0/60)
   costs.append((Time.get_ticks_usec()-time)/1000.0)
   var active=not unit.route.is_empty()
   if i>15 and active and before.distance_to(unit.pos())<.000001:interrupted.append(i)
   if count!=unit.route.size() or (i>15 and active and before.distance_to(unit.pos())<.000001):frames.append({'frame':i,'nodes_before':count,'nodes_after':unit.route.size(),'speed':unit.actor.drive_speed,'actual':unit.actor.actual_speed,'clip':unit.actor.clip,'node':unit.actor.playback.get_current_node(),'fade':unit.actor.playback.get_fading_from_node(),'phase':unit.actor.playback.get_current_play_position(),'travel':unit.actor.playback.get_travel_path()})
   if not active:arrived=true;break
  check(arrived,mode+' reaches destination')
  check(interrupted.is_empty(),mode+' does not stop on intermediate route nodes')
  measurements.append({'mode':mode,'interrupted_frames':interrupted,'node_transitions':frames,'tick_ms':costs,'arrived':arrived})
 # A rapid stop/restart must finish its transition on the simulation clock.
 var a=unit.actor
 for i in 60:a.advance_drive(a.position+Vector3(1,0,0),.18,1.0/60,false,'run')
 a.advance_idle(1.0/60)
 for i in 24:a.advance_drive(a.position+Vector3(1,0,0),.03,1.0/60,false,'crouch_run')
 check(a.playback.get_current_node()=='rifle_crouch_rm' and a.playback.get_fading_from_node()=='','slow crouch transition finishes within 0.4 simulation seconds')
 var report={'passed':checks.all(func(c):return c.passed),'checks':checks,'profiles':profiles,'measurements':measurements}
 var label=OS.get_environment('MOTION_REPORT');if label=='':label='after'
 FileAccess.open('res://docs/evidence/motion-continuity/'+label+'.json',FileAccess.WRITE).store_string(JSON.stringify(report,'  '))
 print('MOTION_CONTINUITY ',JSON.stringify({'passed':report.passed,'checks':checks,'profiles':profiles,'interruptions':measurements.map(func(m):return m.interrupted_frames.size())}))
 quit(0 if report.passed else 1)
