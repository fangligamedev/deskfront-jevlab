extends Node3D
## Streaming world authority. Model proposals choose validated data, never mutate an occupied segment.
const SETTINGS = preload("res://scripts/battlefield.gd")
var game
var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/eastfront.json"))
var chunks:Array=[]
var history:Array=[]
var request:Dictionary={}
var cleared:int=0
var active_sector:int=1
var sequence:int=0
var held:float=0
var follow:bool=true
var backend:String="local"
var seed:int=19
var logical:float=0
var stopped:bool=false
var total_built:int=0
var retired:int=0
var recruits:int=0
var peak_chunks:int=0
var label:Label3D
static func initial_level()->Dictionary:
 return {"id":"eastfront","name":"无尽东线 · 向东推进","bounds":[0,-.7,1.45,.7],"floor_color":"#b4b49a","spawns":[[.22,0],[.22,-.5],[1.15,0]],"objective":[1.1,0],"tank_spawn":[1.3,-.55],"objects":[],"at_guns":[]}
func setup(g):
 game=g;backend=str(get_tree().get_meta("eastfront_backend","local"));seed=int(get_tree().get_meta("eastfront_seed",19))
 game.paused=false;game.config.rules.match_seconds=1e12;game.config.rules.hold_seconds=rules.hold_seconds;game.flag_objective.required_seconds=rules.hold_seconds
 game.office_root.hide();game.worker.hide()
 for root in [game.office_root,game.worker]:
  for body in root.find_children("*","CollisionObject3D",true,false):body.collision_layer=0
 game.arena.map_root.hide()
 for body in game.arena.map_root.find_children("*","CollisionObject3D",true,false):body.collision_layer=0
 if game.reserve_tank:
  game.reserve_tank.hide()
  for body in game.reserve_tank.find_children("*","CollisionObject3D",true,false):body.collision_layer=0
 for u in game.units.duplicate():
  if u.faction!="green":game.units.erase(u);u.queue_free()
 game.control={"green":str(get_tree().get_meta("eastfront_control","game_ai")),"red":"game_ai","blue":"game_ai"}
 game.control_epochs={"green":0,"red":0,"blue":0}
 for i in range(game.units.size()):game.units[i].equip(["rifle","smg","rocket"][i])
 var c={"index":0,"phase":"cleared","node":tile(0),"covers":[],"units":[],"source":"initial_camp","elapsed":0.0,"template":"camp"};chunks.append(c)
 label=Label3D.new();add_child(label);label.font_size=42;label.pixel_size=.0025;label.modulate=Color(.97,.87,.57);label.no_depth_test=true
 game.camera_mode="battle";game.camera_size=2.2;game.camera_target=Vector3(.8,.84,0)
 emit("campaign_start",{"seed":seed,"backend":backend});need_next()
func emit(kind:String,data:Dictionary={}):
 var e={"tick":game.tick_id,"time":snappedf(logical,.1),"kind":kind,"data":data};history.append(e)
 if history.size()>80:history.pop_front()
 game.add_event("东线 · "+kind+" · "+JSON.stringify(data))
func tile(index:int)->Node3D:
 var root=Node3D.new();add_child(root)
 var center=Vector3((index+.5)*float(rules.width),game.field.height-.02,0)
 var body=StaticBody3D.new();root.add_child(body);body.position=center;body.collision_layer=1
 game.field.cube(body,Vector3.ZERO,Vector3(rules.width,.04,rules.half_depth*2),game.field.mat(Color("#b9b797") if index%2==0 else Color("#afaf91")))
 var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(rules.width,.04,rules.half_depth*2);cs.shape=shape;body.add_child(cs)
 for z in [-float(rules.half_depth),float(rules.half_depth)]:game.field.cube(root,Vector3(center.x,game.field.height+.006,z),Vector3(rules.width,.02,.018),game.field.mat(Color("#717a60")))
 var text=Label3D.new();root.add_child(text);text.text="EAST / %03d  →"%index;text.font_size=28;text.pixel_size=.0018;text.position=Vector3(center.x,game.field.height+.018,-.60);text.rotation_degrees.x=-90;text.modulate=Color("#454b3b")
 return root
func need_next():
 if not request.is_empty() or chunks.size()>=int(rules.max_chunks):return
 var next:int=int(chunks[-1].index)+1
 if next>cleared+2:return
 sequence+=1;request={"sequence":sequence,"index":next,"age":0.0,"candidates":rules.templates.map(func(t):return {"id":t.id,"name":t.name}),"seed":seed}
 emit("generation_requested",{"index":next,"sequence":sequence,"backend":backend})
func propose(seq:int,template_id:String,source:String)->String:
 if request.is_empty() or seq!=int(request.sequence):return "stale_frontier_request"
 var index:int=request.index
 var candidates=rules.templates.filter(func(t):return t.id==template_id)
 if candidates.is_empty():return "unknown_frontier_template"
 var t:Dictionary=candidates[0];var specs:Array=[]
 for i in range(t.covers.size()):
  var a=t.covers[i]
  if not a is Array or a.size()!=4 or not a.all(func(v):return (v is float or v is int) and is_finite(v)):return "invalid_component_bounds"
  if a[2]<=0 or a[3]<=0 or a[0]-a[2]/2<.12 or a[0]+a[2]/2>rules.width-.1:return "invalid_component_bounds"
  var x:float=index*float(rules.width)+float(a[0])
  if a[0]<.25 or a[0]>float(rules.width)-.2 or absf(a[1])+a[3]/2>rules.half_depth-.08:return "invalid_component_bounds"
  var c={"id":"east-%d-cover-%d"%[index,i],"position":[x,a[1]],"size":[a[2],a[3]],"height":.06,"hp":100.0,"max_hp":100.0,"kind":"sandbag","alive":true,"normal":([-1,0] if a[2]<=a[3] else [0,-1]),"node":null,"damage_stage":"intact"}
  if game.living().any(func(u):return u.pos().distance_to(Vector2(x,a[1]))<.30):return "occupied_frontier"
  specs.append(c)
 var probe=SETTINGS.new();probe.config=game.config.duplicate(true);probe.config.bounds=[game.config.bounds[0],-rules.half_depth,(index+1)*float(rules.width),rules.half_depth];probe.base=Vector2(probe.config.bounds[0],-rules.half_depth);probe.cell=game.field.cell;probe.covers=game.field.covers+specs;probe.rebuild()
 var end=Vector2((index+1)*float(rules.width)-.22,0);var valid:bool=probe.walkable(end) and not probe.path(Vector2(index*float(rules.width)+.1,0),end).is_empty()
 for u in game.living("green"):
  if probe.path(u.pos(),end).is_empty():valid=false
 for a in t.enemies:
  if a.size()!=3 or a[0]<.3 or a[0]>rules.width-.1 or absf(a[1])>.5 or a[2] not in ["rifle","smg","rocket","pistol"]:valid=false
  elif not probe.walkable(Vector2(index*float(rules.width)+a[0],a[1])):valid=false
 probe.free()
 if not valid:return "frontier_unreachable"
 var root=tile(index)
 for c in specs:
  c.node=game.field.make_cover(c);c.node.reparent(root);c.node.scale.y=.08
 var ch={"index":index,"phase":"building","node":root,"covers":specs,"units":[],"source":source,"elapsed":0.0,"template":template_id,"enemies":t.enemies}
 chunks.append(ch);peak_chunks=maxi(peak_chunks,chunks.size());request.clear();emit("construction_started",{"index":index,"source":source,"template":template_id});return "applied"
func commit(ch:Dictionary):
 # Physics and navigation are activated only when construction visibly completes.
 for c in ch.covers:
  c.node.scale.y=1;var body=StaticBody3D.new();c.node.add_child(body);body.collision_layer=1
  var cs=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(c.size[0],c.height,c.size[1]);cs.shape=box;cs.position.y=c.height/2;body.add_child(cs);game.field.covers.append(c)
 ch.phase="ready";total_built+=1
 game.config.bounds[2]=(ch.index+1)*float(rules.width);game.field.config=game.config;game.field.rebuild()
 for i in range(ch.enemies.size()):
  var a:Array=ch.enemies[i];var u=game.spawn_unit("red-e%d-%d"%[ch.index,i],"red",Vector2(ch.index*float(rules.width)+a[0],a[1]));u.equip(a[2]);u.hp=float(rules.defender_hp);u.deployment_phase="parked";u.order_mode="reserve";ch.units.append(u.id)
 emit("chunk_committed",{"index":ch.index,"source":ch.source,"navigation_revision":game.field.revision});activate()
func activate():
 for ch in chunks:
  if ch.index!=active_sector or ch.phase!="ready":continue
  ch.phase="combat";game.objective=Vector2((ch.index+1)*float(rules.width)-.22,0);game.config.objective=[game.objective.x,0]
  for f in game.config.factions:
   f.spawn=[maxf(game.config.bounds[0]+.18,ch.index*float(rules.width)-.28),0] if f.id=="green" else [game.objective.x,.25]
  for u in game.units:
   if ch.units.has(u.id):u.deployment_phase="active";u.order_mode="hold"
  game.flag_objective.holder="";game.flag_objective.held_seconds=0;game.flag_objective.capture_epoch+=1
  game.tactics_ai.squads.clear();game.tactics_ai.flag_hints.clear();game.tactics_ai.flag_distance.clear();game.tactics_ai.flag_progress.clear();held=0
  game.flag_banner.position.x=game.objective.x+.055;game.flag_pole.position.x=game.objective.x
  emit("sector_activated",{"index":ch.index,"objective":[game.objective.x,0]})
func update_capture(dt:float):
 var ready:bool=chunks.any(func(c):return c.index==active_sector and c.phase=="combat")
 if not ready:return
 var green:bool=game.living("green").any(func(u):return u.pos().distance_to(game.objective)<.19)
 var red:bool=game.living("red").any(func(u):return u.pos().distance_to(game.objective)<.24)
 held=held+dt if green and not red else (held if green else 0.0)
 game.flag_objective.holder="green" if green else "";game.flag_objective.contested=green and red;game.flag_objective.held_seconds=held;game.scores.green=held
 if held<float(rules.hold_seconds):return
 cleared=active_sector;active_sector+=1;held=0
 for ch in chunks:
  if ch.index==cleared:ch.phase="cleared"
 for u in game.living("green"):
  u.hp=minf(u.max_hp,u.hp+float(rules.heal_per_sector));u.ammo=int(u.weapon_config().magazine);u.grenade_count=2
 # Casualties stay dead. A newly identified recruit walks in from the secured rear.
 if game.living("green").size()<3:
  var rear=Vector2(cleared*float(rules.width)+.18,0)
  if game.field.walkable(rear):
   recruits+=1
   var recruit=game.spawn_unit("green-recruit-%d"%recruits,"green",rear)
   recruit.equip("rocket" if not game.living("green").any(func(u):return u.weapon=="rocket") else "rifle")
   emit("rear_reinforcement",{"unit":recruit.id,"position":[rear.x,rear.y]})
 emit("sector_captured",{"index":cleared,"survivors":game.living("green").size(),"supply_hp":rules.heal_per_sector});activate();need_next()
func retire_old():
 while chunks.size()>2:
  var ch:Dictionary=chunks[0];var edge:float=(ch.index+1)*float(rules.width)
  if ch.index>=cleared-1 or game.units.any(func(u):return u.hp>0 and u.deployment_phase=="active" and u.faction=="green" and u.pos().x<edge+.12):break
  # Rear enemies outside the expedition window disengage; do not count them as kills.
  if game.living("red").any(func(u):return u.pos().x<edge and game.living("green").any(func(v):return v.pos().distance_to(u.pos())<float(u.weapon_config().range)+.12)):break
  var disengaged=game.living("red").filter(func(u):return u.pos().x<edge).map(func(u):return u.id)
  if not disengaged.is_empty():emit("rear_disengaged",{"units":disengaged})
  for u in game.units.duplicate():
   if u.pos().x<edge:game.field.release(u.id);game.units.erase(u);u.queue_free()
  for c in ch.covers:game.field.covers.erase(c)
  for node in game.field.get_children():
   if node is Node3D and node.position.x<edge:node.queue_free()
  for key in game.field.unavailable_until.keys():
   if float(game.field.unavailable_until[key])<=game.elapsed:game.field.unavailable_until.erase(key)
  ch.node.queue_free();chunks.pop_front();retired+=1;game.config.bounds[0]=edge;game.field.base=Vector2(edge,-rules.half_depth);game.field.slot_cache.clear();game.field.rebuild();emit("chunk_retired",{"index":ch.index})
func tick(dt:float):
 if stopped:return
 logical+=dt
 if game.living("green").is_empty():stopped=true;game.finish_match("red","东线小队全员失去战斗力；本次推进结束");return
 if follow:game.camera_target=Vector3(game.living("green").map(func(u):return u.pos().x).max()+.45,game.field.height,0)
 game.ears.position=Vector3(game.camera_target.x,1.2,game.camera_target.z)
 label.position=Vector3(game.camera_target.x,game.field.height+.3,-.6);label.text="EAST FRONT  →  SECTOR %03d / CLEARED %d"%[active_sector,cleared]
 for ch in chunks:
  if ch.phase=="building":
   ch.elapsed+=dt
   for c in ch.covers:c.node.scale.y=clampf(ch.elapsed/float(rules.build_seconds),.08,1)
   if ch.elapsed>=float(rules.build_seconds):commit(ch)
 update_capture(dt);retire_old()
 var front:float=game.living("green").map(func(u):return u.pos().x).max()
 if request.is_empty() and not chunks.any(func(c):return c.phase=="building") and front>=game.config.bounds[2]-float(rules.lookahead):need_next()
 if not request.is_empty():
  request.age+=dt/maxf(.1,game.speed)
  if (backend=="local" and request.age>=0) or request.age>=float(rules.model_deadline_seconds):
   var reason="local_seeded" if backend=="local" else "local_timeout_fallback"
   var offset=posmod(seed+int(request.index),rules.templates.size())
   for i in range(rules.templates.size()):
    var choice=rules.templates[(offset+i)%rules.templates.size()].id
    var result=propose(int(request.sequence),choice,reason)
    if result=="applied":break
    emit("generation_rejected",{"template":choice,"reason":result})
   if not request.is_empty():request.age=-1.0
func snapshot()->Dictionary:
 var r=request.duplicate(true)
 return {"enabled":true,"direction":"east","axis":"+x","seed":seed,"backend":backend,"cleared":cleared,"active_sector":active_sector,"hold_seconds":held,"follow":follow,"request":r,"recruits":recruits,"built":total_built,"retired":retired,"peak_chunks":peak_chunks,"max_chunks":rules.max_chunks,"chunks":chunks.map(func(c):return {"index":c.index,"phase":c.phase,"source":c.source,"template":c.template,"elapsed":c.elapsed}),"events":history,"stopped":stopped}
