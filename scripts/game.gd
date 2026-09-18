extends Node3D

const Field = preload("res://scripts/battlefield.gd")
const Unit = preload("res://scripts/unit.gd")
const Tactics = preload("res://scripts/tactics.gd")
const CombatFX = preload("res://scripts/combat_fx.gd")
const Bridge = preload("res://scripts/bridge.gd")
var config: Dictionary
var field
var units: Array=[]
var colors: Dictionary={}
var control: Dictionary={"green":"game_ai","blue":"game_ai","red":"game_ai"}
var scores: Dictionary={"green":0.0,"blue":0.0,"red":0.0}
var decisions: Dictionary={}
var events: Array=[]
var elapsed: float=0
var tick_id: int=0
var shots: int=0
var paused: bool=false
var speed: float=1
var winner: String=""
var tank_spawned: bool=false
var selected_faction: String="green"
var rng := RandomNumberGenerator.new()
var ai_clock: float=0
var hud_clock: float=0
var objective: Vector2
var camera: Camera3D
var camera_mode: String="office"
var camera_target := Vector3.ZERO
var camera_size: float=3.6
var worker: Node3D
var worker_anim: AnimationPlayer
var ui: CanvasLayer
var status_label: Label
var score_label: Label
var selection_label: Label
var hint_label: Label
var phase_label: Label
var bridge
var fx
var tactics_ai
var drag_start := Vector2.ZERO
var drag_current := Vector2.ZERO
var pan_cursor := Vector2.ZERO
var selecting: bool=false
var panning: bool=false
var edge_pan: bool=true
var pointer_inside: bool=false
var selection_box: Panel
var command_feedback: String=""
var feedback_until: float=0
var last_action: Dictionary={}
var run_id: String=""
var capture_path: String=""
var capture_frames: int=120
var capture_effects: bool=false
var rendered_frames: int=0

func _ready() -> void:
	config=JSON.parse_string(FileAccess.get_file_as_string("res://data/battle.json"))
	rng.seed=int(config.seed)
	run_id=str(Time.get_unix_time_from_system())+"-"+str(randi())
	for f in config.factions:colors[f.id]=Color(f.color)
	objective=Vector2(config.objective[0],config.objective[1])
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode=Environment.BG_COLOR;e.background_color=Color(.29,.35,.31)
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.75,.80,.72);e.ambient_light_energy=.35
	e.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	env.environment=e;add_child(env)
	var sun := DirectionalLight3D.new();add_child(sun);sun.rotation_degrees=Vector3(-55,-35,0);sun.light_color=Color(1,.92,.76);sun.light_energy=.48;sun.shadow_enabled=true
	sun.directional_shadow_max_distance=12;sun.shadow_bias=.03
	var fill := DirectionalLight3D.new();add_child(fill);fill.rotation_degrees=Vector3(-35,145,0);fill.light_color=Color(.65,.78,.85);fill.light_energy=.24
	var office=load("res://assets/models/office.glb").instantiate();add_child(office)
	worker=load("res://assets/models/worker.glb").instantiate();add_child(worker);worker.position=Vector3(-.67,-.02,.57);worker.scale=Vector3.ONE*.85
	var aps=worker.find_children("*","AnimationPlayer",true,false)
	if not aps.is_empty():
		worker_anim=aps[0]
		for a in worker_anim.get_animation_list():
			if "typing" in a:worker_anim.get_animation(a).loop_mode=Animation.LOOP_LINEAR;worker_anim.play(a);worker_anim.speed_scale=.6
	field=Field.new();add_child(field);field.setup(config)
	fx=CombatFX.new();add_child(fx);fx.setup(self)
	get_viewport().mouse_entered.connect(func():pointer_inside=true)
	get_viewport().mouse_exited.connect(func():pointer_inside=false;panning=false;selecting=false;if_box_hide())
	var target := MeshInstance3D.new();var disc := CylinderMesh.new();disc.top_radius=.044;disc.bottom_radius=.044;disc.height=.007;target.mesh=disc
	target.material_override=field.mat(Color(.65,.49,.21),.4);add_child(target);target.position=Vector3(objective.x,.825,objective.y)
	for f in config.factions:
		for i in range(3):spawn_unit(f.id+"-"+str(i+1),f.id,Vector2(f.spawn[0]+(i-1)*.064,f.spawn[1]))
	tactics_ai=Tactics.new();add_child(tactics_ai);tactics_ai.setup(self)
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=.02;camera.far=30;camera.current=true
	set_camera("office",true);make_hud()
	bridge=Bridge.new();add_child(bridge);bridge.setup(self)
	add_event("战场就绪 · 三个阵营 · 九名步兵")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
		if arg.begins_with("--frames="):capture_frames=int(arg.trim_prefix("--frames="))
		if arg=="--capture-effects":capture_effects=true
		if arg=="--battle":set_camera("battle",true)
		if arg=="--tank":spawn_tank()
		if arg=="--paused":paused=true

func spawn_unit(unit_id: String, faction: String, p: Vector2, tank: bool=false):
	var u=Unit.new();add_child(u);u.setup(self,unit_id,faction,p,tank);units.append(u);return u

func faction_data(team: String) -> Dictionary:
	for f in config.factions:
		if f.id==team:return f
	return {}

func living(team: String="") -> Array:
	return units.filter(func(u):return u.hp>0 and (team=="" or u.faction==team))

func closest_enemy(u):
	var best=null;var distance: float=INF
	for other in living():
		if other.faction==u.faction:continue
		var d: float=u.pos().distance_to(other.pos())
		if d<distance:best=other;distance=d
	return best

func find_target(u, requested: String=""):
	var best=null;var distance: float=config.weapons[u.weapon].range
	var best_score: float=-INF
	for enemy in units:
		if enemy.faction==u.faction or enemy.hp<=0:continue
		var d: float=u.pos().distance_to(enemy.pos())
		if d<distance and field.line_of_sight(u.pos(),enemy.pos()):
			if enemy.id==requested:return enemy
			var score: float=-d+(1.5 if u.weapon=="rocket" and enemy.tank else 0.0)
			if u.tank and enemy.weapon=="rocket":score+=.6
			if u.weapon=="smg" and not enemy.tank:score+=.15*(1-enemy.suppression)
			if enemy.tank and u.weapon in ["rifle","smg"]:score-=1.0
			if score>best_score:best=enemy;best_score=score
	return best

func _physics_process(delta: float) -> void:
	tick_id+=1
	if paused or winner!="":return
	var dt: float=delta*speed
	elapsed+=dt
	if worker_anim:worker_anim.speed_scale=.6*speed
	fx.physics_tick(dt)
	tactics_ai.tick(dt)
	for u in units:u.tick(dt)
	var present: Array=[]
	for u in living():
		if u.pos().distance_to(objective)<config.rules.capture_radius and not present.has(u.faction):present.append(u.faction)
	if present.size()==1:scores[present[0]]+=dt
	if not tank_spawned and elapsed>config.rules.reinforce_after:
		var red_hp: float=0
		for u in units:
			if u.faction=="red":red_hp+=u.hp
		if red_hp/(config.soldier.hp*3)<config.rules.reinforce_hp_ratio:spawn_tank()
	for team in scores:
		if scores[team]>=config.rules.score_to_win:finish_match(team,"目标控制积分达成")
	var alive_teams: Array=[]
	for team in scores:
		if not living(team).is_empty():alive_teams.append(team)
	if alive_teams.size()==1 and elapsed>4:
		if alive_teams[0]!="red" and not tank_spawned:spawn_tank()
		else:finish_match(alive_teams[0],"其余阵营失去战斗力")
	if alive_teams.is_empty():finish_match("draw","全部阵营失去战斗力")
	if elapsed>=config.rules.match_seconds:
		var leading: String="draw";var value: float=-1;var ties: int=0
		for team in scores:
			if scores[team]>value:value=scores[team];leading=team;ties=1
			elif is_equal_approx(scores[team],value):ties+=1
		finish_match("draw" if ties>1 else leading,"时间结束")

func _process(delta: float) -> void:
	update_pan(delta)
	if camera:
		camera.size=lerpf(camera.size,camera_size,minf(1,delta*5))
		var target_pos: Vector3=camera_target+Vector3(0,3.8,.001) if camera_mode=="top" else camera_target+Vector3(2.6,3.5,3.5)
		camera.position=camera.position.lerp(target_pos,minf(1,delta*5));camera.look_at(camera_target,Vector3.FORWARD if camera_mode=="top" else Vector3.UP)
	hud_clock-=delta
	if hud_clock<=0 and status_label:hud_clock=.15;update_hud()
	if paused and worker_anim:worker_anim.speed_scale=0
	rendered_frames+=1
	if capture_path!="" and (rendered_frames==capture_frames or (capture_effects and rendered_frames>120 and fx.projectiles.size()>0 and fx.visuals.size()>8)):
		var destination: String=capture_path;capture_path=""
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(destination)
		var state_file=FileAccess.open(destination.trim_suffix(".png")+".json",FileAccess.WRITE)
		state_file.store_string(JSON.stringify(snapshot(),"  "))
		print("CAPTURE_SAVED ",destination)
		paused=true;fx.set_muted(true)
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()

func finish_match(team: String, why: String) -> void:
	if winner!="":return
	winner=team;add_event("战斗结束 · "+team+" · "+why)

func decide(team: String) -> void:
	tactics_ai.plan(team)

func issue_tactic(team: String, action: String, destination: Vector2, ids: Array) -> void:
	var squad: Array=living(team).filter(func(u):return ids.is_empty() or ids.has(u.id))
	var data: Dictionary=faction_data(team)
	if action in ["move","capture","retreat"] and squad.filter(func(u):return not u.tank).size()>1:
		var dest: Vector2=Vector2(data.spawn[0],data.spawn[1]) if action=="retreat" else destination
		tactics_ai.begin_move(team,dest,ids,action=="retreat")
		for u in squad:
			if u.tank:u.move_to(dest)
		return
	for index in range(squad.size()):
		var u=squad[index];var enemy=closest_enemy(u)
		u.target_id=""
		var threat: Vector2=enemy.pos() if enemy!=null else objective
		var offset := Vector2((index-(squad.size()-1)*.5)*.058,0)
		u.order_mode=action
		match action:
			"cover":
				if u.tank:
					tactics_ai.tank_next.erase(u.id);tactics_ai.plan_tank(u)
				elif not u.seek_cover(threat,u.pos()):u.route.clear();u.goal=u.pos()
			"retreat":u.move_to(Vector2(data.spawn[0],data.spawn[1])+offset)
			"hold":u.route.clear();u.goal=u.pos();u.state="aim"
			"flank":
				var flank: Dictionary=tactics_ai.flank_goal(u,enemy) if enemy!=null and not u.tank else {}
				if not flank.is_empty():u.move_to(flank.position);u.order_mode="cqb_flank"
				elif not u.tank:u.seek_cover(threat,u.pos())
			_:
				u.move_to(destination+offset)

func spawn_tank() -> bool:
	if tank_spawned:return false
	tank_spawned=true
	var t=spawn_unit("red-tank","red",Vector2(1.20,-.46),true)
	t.move_to(Vector2(1.05,-.29));add_event("红方失势 · 后方坦克增援抵达");return true

func add_event(message: String) -> void:
	events.push_front({"time":snappedf(elapsed,.1),"text":message})
	if events.size()>40:events.resize(40)

func set_camera(mode: String, instant: bool=false) -> void:
	camera_mode=mode
	if mode=="office":camera_target=Vector3(-.02,.60,.07);camera_size=4.05
	elif mode=="top":camera_target=Vector3(.61,.82,-.01);camera_size=1.80
	else:camera_target=Vector3(.60,.84,-.02);camera_size=1.87
	if instant and camera:
		camera.position=camera_target+(Vector3(0,3.8,.001) if mode=="top" else Vector3(2.6,3.5,3.5));camera.look_at(camera_target,Vector3.FORWARD if camera_mode=="top" else Vector3.UP);camera.size=camera_size

func selected_ids() -> Array:
	var ids: Array=[]
	for u in units:
		if u.selected and u.hp>0:ids.append(u.id)
	return ids

func command(c: Dictionary) -> Dictionary:
	var action: String=str(c.get("action",""));var source: String=str(c.get("source","console"));var team: String=str(c.get("faction",selected_faction))
	var rejected: String="";var tactics: Array=["move","capture","flank","cover","hold","retreat","attack"]
	if not control.has(team):rejected="unknown_faction"
	elif source=="agent" and (not tactics.has(action) or control[team]!="agent"):rejected="authority_denied"
	elif source=="agent" and str(c.get("run_id",""))!=run_id:rejected="stale_run"
	elif source=="agent" and (not c.has("seen_tick") or abs(tick_id-int(c.seen_tick))>300):rejected="stale_observation"
	if rejected!="":return ack(c,false,rejected)
	var ids: Array=c.get("unit_ids",[])
	for unit_id in ids:
		var found: bool=false
		for u in units:
			if u.id==unit_id and u.faction==team and u.hp>0:found=true
		if not found:return ack(c,false,"invalid_unit_authority")
	var dest: Vector2=objective
	if c.has("position"):
		var p=c.position
		if not p is Array or p.size()!=2:return ack(c,false,"invalid_position")
		if not (p[0] is float or p[0] is int) or not (p[1] is float or p[1] is int):return ack(c,false,"invalid_position")
		dest=Vector2(float(p[0]),float(p[1]))
		if not is_finite(dest.x) or not is_finite(dest.y) or dest.x<config.bounds[0] or dest.x>config.bounds[2] or dest.y<config.bounds[1] or dest.y>config.bounds[3]:return ack(c,false,"position_out_of_bounds")
	if tactics.has(action):
		if winner!="":return ack(c,false,"match_finished")
		if action=="attack":
			var target=null
			for u in units:
				if u.id==str(c.get("target_id","")) and u.faction!=team and u.hp>0:target=u
			if target==null:return ack(c,false,"invalid_target")
			tactics_ai.cancel(team)
			if source!="agent":control[team]="player"
			for u in living(team):
				if ids.is_empty() or ids.has(u.id):
					u.target_id=target.id;u.order_mode="attack"
					if find_target(u,target.id)!=target:u.move_to(target.pos())
					else:u.route.clear();u.goal=u.pos()
			fx.ring(target.pos(),Color(1,.30,.16),.065)
			command_feedback="ATTACK / "+target.id
		else:
			tactics_ai.cancel(team)
			if source!="agent":control[team]="player"
			issue_tactic(team,action,dest,ids)
			for u in living(team):
				if ids.is_empty() or ids.has(u.id):fx.ring(u.goal,Color(.42,.94,.66),.04)
			command_feedback=action.to_upper()+" / "+str(ids.size() if not ids.is_empty() else living(team).size())+" UNITS"
		feedback_until=Time.get_ticks_msec()/1000.0+2.0
		fx.sound("order",Vector3(dest.x,field.height,dest.y),-3)
		decisions[team]={"action":action,"reason":"Agent 指令" if source=="agent" else "玩家/策划指令","source":source,"tick":tick_id,"candidates":[]}
	elif action=="control":
		var mode: String=str(c.get("mode",""))
		if not mode in ["game_ai","player","agent"]:return ack(c,false,"invalid_mode")
		tactics_ai.cancel(team)
		control[team]=mode;selected_faction=team
		for u in units:u.selected=u.faction==team and mode=="player"
		add_event(team+" 控制权 → "+mode)
	elif action=="pause":paused=bool(c.get("value",not paused))
	elif action=="speed":speed=clampf(float(c.get("value",1)),.25,3)
	elif action=="camera":
		var mode: String=str(c.get("mode","battle"))
		if not mode in ["office","battle","top"]:return ack(c,false,"invalid_camera")
		set_camera(mode)
	elif action=="reinforce":
		if not spawn_tank():return ack(c,false,"reinforcement_already_used")
	elif action=="config":
		var key: String=str(c.get("key",""));var value: float=float(c.get("value",0))
		var ranges: Dictionary={"damage":[1,30],"speed":[.04,.30],"accuracy":[.1,1],"cooldown":[.3,4]}
		if not ranges.has(key) or not is_finite(value):return ack(c,false,"invalid_parameter")
		config.soldier[key]=clampf(value,ranges[key][0],ranges[key][1]);add_event("参数更新 "+key+" = "+str(config.soldier[key]))
	elif action=="reset":
		var result=ack(c,true,"resetting");get_tree().call_deferred("reload_current_scene");return result
	else:return ack(c,false,"unknown_action")
	return ack(c,true,"applied")

func ack(c: Dictionary, ok: bool, message: String) -> Dictionary:
	last_action={"id":c.get("id","local"),"accepted":ok,"message":message,"tick":tick_id,"action":c.get("action","")};return last_action.duplicate()

func snapshot() -> Dictionary:
	var unit_states: Array=[]
	for u in units:
		var state: Dictionary=u.snapshot()
		var pixel: Vector2=camera.unproject_position(u.position+Vector3(0,.05,0))
		state["screen_position"]=[pixel.x,pixel.y];unit_states.append(state)
	return {"schema_version":1,"version":"0.3.0","viewport":[get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y],"run_id":run_id,"tick":tick_id,"time":snappedf(elapsed,.1),"paused":paused,"speed":speed,"winner":winner,"units":unit_states,"factions":config.factions,"control":control,"scores":scores,"objective":{"position":[objective.x,objective.y],"screen_position":[camera.unproject_position(Vector3(objective.x,field.height,objective.y)).x,camera.unproject_position(Vector3(objective.x,field.height,objective.y)).y],"radius":config.rules.capture_radius,"score_to_win":config.rules.score_to_win},"covers":field.snapshot(),"obstacles":config.obstacles,"bounds":config.bounds,"decisions":decisions,"events":events,"tank_spawned":tank_spawned,"shots":shots,"navigation_revision":field.revision,"reservations":field.reservations,"selected_faction":selected_faction,"camera":camera_mode,"camera_target":[camera_target.x,camera_target.z],"camera_size":camera_size,"edge_pan":edge_pan,"combat_fx":{"projectiles":fx.projectiles.size(),"visuals":fx.visuals.size(),"impacts":fx.impacts,"audio_events":fx.audio_events,"muted":fx.muted,"launched":fx.launched},"weapons":config.weapons,"tactical":tactics_ai.snapshot(),"command_feedback":command_feedback,"last_action":last_action,"parameters":config.soldier,"fps":Engine.get_frames_per_second(),"worker_animation_time":worker_anim.current_animation_position if worker_anim and worker_anim.is_playing() else 0.0}

func screen_point(p: Vector2) -> Vector2:
	var origin: Vector3=camera.project_ray_origin(p);var ray: Vector3=camera.project_ray_normal(p)
	if absf(ray.y)<.0001:return objective
	var world: Vector3=origin+ray*((field.height-origin.y)/ray.y);return Vector2(world.x,world.z)

func if_box_hide() -> void:
	if selection_box:selection_box.visible=false

func pan_by(amount: Vector3) -> void:
	camera_target.x=clampf(camera_target.x+amount.x,-1.4,1.7)
	camera_target.z=clampf(camera_target.z+amount.z,-.95,1.3)

func pan_to(cursor: Vector2) -> void:
	# Absolute cursor positions retain total drag when Web events are coalesced.
	var offset: Vector2=screen_point(pan_cursor)-screen_point(cursor)
	pan_cursor=cursor
	pan_by(Vector3(offset.x,0,offset.y))

func update_pan(dt: float) -> void:
	if not camera or not get_window().has_focus():return
	var axis := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT):axis.x-=1
	if Input.is_physical_key_pressed(KEY_RIGHT):axis.x+=1
	if Input.is_physical_key_pressed(KEY_UP):axis.y-=1
	if Input.is_physical_key_pressed(KEY_DOWN):axis.y+=1
	if edge_pan and pointer_inside and not selecting and not panning and get_viewport().gui_get_hovered_control()==null:
		var p: Vector2=get_viewport().get_mouse_position();var size: Vector2=get_viewport().get_visible_rect().size
		if p.x<12:axis.x-=1
		if p.x>size.x-12:axis.x+=1
		if p.y<12:axis.y-=1
		if p.y>size.y-12:axis.y+=1
	var right: Vector3=camera.global_basis.x;right.y=0;right=right.normalized()
	var down: Vector3=-camera.global_basis.y;down.y=0;down=down.normalized()
	pan_by((right*axis.x+down*axis.y)*dt*camera_size*.55)

func ground_order(p: Vector2) -> void:
	if selected_ids().is_empty():return
	var target=null
	for enemy in living():
		if enemy.faction!=selected_faction and enemy.pos().distance_to(p)<.06:target=enemy
	var result: Dictionary
	if target:result=command({"action":"attack","faction":selected_faction,"target_id":target.id,"unit_ids":selected_ids(),"source":"player"})
	else:result=command({"action":"move","faction":selected_faction,"position":[p.x,p.y],"unit_ids":selected_ids(),"source":"player"})
	if not result.accepted:
		fx.ring(p,Color(.95,.24,.18),.05);command_feedback="OUTSIDE BATTLEFIELD";feedback_until=Time.get_ticks_msec()/1000.0+2

func select_at(screen: Vector2, additive: bool) -> void:
	var nearest_unit=null;var distance: float=30
	for u in living():
		var pixel: Vector2=camera.unproject_position(u.position+Vector3(0,.06,0))
		var d: float=pixel.distance_to(screen)
		if d<distance:nearest_unit=u;distance=d
	if nearest_unit:
		if nearest_unit.faction!=selected_faction and not selected_ids().is_empty():ground_order(nearest_unit.pos());return
		selected_faction=nearest_unit.faction;control[selected_faction]="player"
		for u in units:u.selected=u==nearest_unit or (additive and u.selected and u.faction==selected_faction)
	elif not additive:ground_order(screen_point(screen))

func finish_selection(additive: bool) -> void:
	if drag_start.distance_to(drag_current)<8:select_at(drag_current,additive);return
	var rect := Rect2(drag_start,drag_current-drag_start).abs()
	var found: Array=[]
	for u in living(selected_faction):
		if rect.has_point(camera.unproject_position(u.position+Vector3(0,.05,0))):found.append(u)
	if found.is_empty():return
	control[selected_faction]="player"
	for u in units:u.selected=found.has(u) or (additive and u.selected and u.faction==selected_faction)

func _input(event: InputEvent) -> void:
	# Release anywhere, including on a HUD panel, so dragging cannot get stuck.
	if event is InputEventMouseButton and not event.pressed:
		if panning and event.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_LEFT]:pan_to(event.position);panning=false
		elif event.button_index==MOUSE_BUTTON_LEFT and selecting:
			drag_current=event.position;selecting=false;if_box_hide();finish_selection(event.shift_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_inside=true
		if panning:
			pan_to(event.position)
		elif selecting:
			drag_current=event.position
			var rect := Rect2(drag_start,drag_current-drag_start).abs()
			selection_box.position=rect.position;selection_box.size=rect.size;selection_box.visible=rect.size.length()>8
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:camera_size=clampf(camera_size*.90,.70,4.5)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera_size=clampf(camera_size*1.1,.70,4.5)
		elif event.button_index==MOUSE_BUTTON_MIDDLE or (event.button_index==MOUSE_BUTTON_LEFT and event.alt_pressed):panning=true;pan_cursor=event.position
		elif event.button_index==MOUSE_BUTTON_LEFT:selecting=true;drag_start=event.position;drag_current=event.position
		elif event.button_index==MOUSE_BUTTON_RIGHT:ground_order(screen_point(event.position))
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1,KEY_2,KEY_3:
				selected_faction=["green","blue","red"][event.physical_keycode-KEY_1];command({"action":"control","faction":selected_faction,"mode":"player"})
			KEY_SPACE:paused=not paused
			KEY_C:command({"action":"cover","unit_ids":selected_ids()})
			KEY_H:command({"action":"hold","unit_ids":selected_ids()})
			KEY_R:command({"action":"retreat","unit_ids":selected_ids()})
			KEY_A:command({"action":"control","mode":"game_ai"})
			KEY_T:spawn_tank()
			KEY_M:fx.set_muted(not fx.muted)
			KEY_E:edge_pan=not edge_pan
			KEY_V:set_camera("battle" if camera_mode=="office" else ("top" if camera_mode=="battle" else "office"))
			KEY_HOME:set_camera(camera_mode)
			KEY_ENTER:
				if winner!="":get_tree().reload_current_scene()
			KEY_F1:ui.visible=not ui.visible

func label(value: String, size: int, color: Color=Color(.86,.88,.80)) -> Label:
	var l := Label.new();l.text=value;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color);l.mouse_filter=Control.MOUSE_FILTER_IGNORE;return l

func make_hud() -> void:
	ui=CanvasLayer.new();add_child(ui)
	selection_box=Panel.new();ui.add_child(selection_box);selection_box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var box_style := StyleBoxFlat.new();box_style.bg_color=Color(.4,.8,.6,.12);box_style.border_color=Color(.6,1,.75,.9);box_style.set_border_width_all(1)
	selection_box.add_theme_stylebox_override("panel",box_style);selection_box.visible=false
	var root := Control.new();ui.add_child(root);root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var top := PanelContainer.new();root.add_child(top);top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);top.offset_bottom=88
	var style := StyleBoxFlat.new();style.bg_color=Color(.055,.075,.065,.92);style.content_margin_left=24;style.content_margin_right=24;style.content_margin_top=12;style.content_margin_bottom=10;top.add_theme_stylebox_override("panel",style)
	var row := HBoxContainer.new();top.add_child(row)
	var left := VBoxContainer.new();row.add_child(left);left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	left.add_child(label("DESKFRONT  /  THE QUIET OFFICE",21))
	phase_label=label("TACTICAL DIORAMA     •     3 FACTIONS / 9 INFANTRY",11,Color(.62,.69,.56));left.add_child(phase_label)
	var right := VBoxContainer.new();row.add_child(right)
	score_label=label("",16);right.add_child(score_label);status_label=label("",12);right.add_child(status_label)
	var bottom := PanelContainer.new();root.add_child(bottom);bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);bottom.offset_top=-99;bottom.add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new();bottom.add_child(column)
	selection_label=label("",14,Color(.84,.74,.49));column.add_child(selection_label)
	var buttons := HBoxContainer.new();buttons.add_theme_constant_override("separation",8);column.add_child(buttons)
	for item in [["01 GREEN","green"],["02 BLUE","blue"],["03 RED","red"],["COVER [C]","cover"],["RETREAT [R]","retreat"],["AUTO [A]","auto"],["VIEW [V]","view"]]:
		var button := Button.new();button.text=item[0];button.add_theme_font_size_override("font_size",12);buttons.add_child(button)
		var key: String=item[1]
		button.pressed.connect(func():
			if key in ["green","blue","red"]:command({"action":"control","faction":key,"mode":"player"})
			elif key=="auto":command({"action":"control","mode":"game_ai"})
			elif key=="view":set_camera("battle" if camera_mode=="office" else ("top" if camera_mode=="battle" else "office"))
			else:command({"action":key,"unit_ids":selected_ids()})
		)
	hint_label=label("",11);column.add_child(hint_label)

func update_hud() -> void:
	score_label.text="GREEN %02d   /   BLUE %02d   /   RED %02d" % [scores.green,scores.blue,scores.red]
	status_label.text="%02d:%02d   •   %s   •   %.1fx" % [int(elapsed)/60,int(elapsed)%60,"PAUSED" if paused else "LIVE",speed]+("   MUTED [M]" if fx.muted else "   SOUND [M]")
	selection_label.text="%s / %s / %d SELECTED   ·   HOLD THE BRASS MARKER TO SCORE" % [selected_faction.to_upper(),str(control[selected_faction]).to_upper(),selected_ids().size()]
	phase_label.text="RED REINFORCEMENTS ON DESK   •   DESTRUCTIBLE COVER" if tank_spawned else "TACTICAL DIORAMA   •   3 FACTIONS / 9 INFANTRY"
	hint_label.text="Drag select · RMB order · MMB/Alt-drag pan · Arrows pan · Wheel zoom · Home recenter · M sound · E edge pan"
	if Time.get_ticks_msec()/1000.0<feedback_until:selection_label.text=command_feedback
	else:
		var equipped: Array=[]
		for u in units:
			if u.selected and u.hp>0:equipped.append(u.weapon.to_upper()+" "+str(u.ammo))
		if not equipped.is_empty():selection_label.text=" / ".join(equipped)+("   [MUTED]" if fx.muted else "   [SOUND ON]")
	if winner!="":selection_label.text=("DRAW" if winner=="draw" else winner.to_upper()+" WINS")+" / PRESS ENTER TO RESTART"
