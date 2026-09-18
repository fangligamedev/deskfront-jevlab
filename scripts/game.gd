extends Node3D

const Field = preload("res://scripts/battlefield.gd")
const Unit = preload("res://scripts/unit.gd")
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
var shot_marks: Array=[]
var last_action: Dictionary={}
var run_id: String=""
var capture_path: String=""
var capture_frames: int=120
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
	var target := MeshInstance3D.new();var disc := CylinderMesh.new();disc.top_radius=.044;disc.bottom_radius=.044;disc.height=.007;target.mesh=disc
	target.material_override=field.mat(Color(.65,.49,.21),.4);add_child(target);target.position=Vector3(objective.x,.825,objective.y)
	for f in config.factions:
		for i in range(3):spawn_unit(f.id+"-"+str(i+1),f.id,Vector2(f.spawn[0]+(i-1)*.064,f.spawn[1]))
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=.02;camera.far=30;camera.current=true
	set_camera("office",true);make_hud()
	bridge=Bridge.new();add_child(bridge);bridge.setup(self)
	add_event("战场就绪 · 三个阵营 · 九名步兵")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
		if arg.begins_with("--frames="):capture_frames=int(arg.trim_prefix("--frames="))
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

func find_target(u, requested: String=""):
	var best=null;var distance: float=config.tank.range if u.tank else config.soldier.range
	for enemy in units:
		if enemy.faction==u.faction or enemy.hp<=0:continue
		var d: float=u.pos().distance_to(enemy.pos())
		if d<distance and field.line_of_sight(u.pos(),enemy.pos()):
			best=enemy;distance=d
			if enemy.id==requested:return enemy
	return best

func _physics_process(delta: float) -> void:
	tick_id+=1
	if paused or winner!="":return
	var dt: float=delta*speed
	elapsed+=dt
	if worker_anim:worker_anim.speed_scale=.6*speed
	for u in units:u.tick(dt)
	ai_clock-=dt
	if ai_clock<=0:
		ai_clock=config.rules.ai_interval
		for f in config.factions:
			if control[f.id]=="game_ai":decide(f.id)
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
	if camera:
		camera.size=lerpf(camera.size,camera_size,minf(1,delta*5))
		var target_pos: Vector3=camera_target+Vector3(0,3.8,.001) if camera_mode=="top" else camera_target+Vector3(2.6,3.5,3.5)
		camera.position=camera.position.lerp(target_pos,minf(1,delta*5));camera.look_at(camera_target)
	hud_clock-=delta
	if hud_clock<=0 and status_label:hud_clock=.15;update_hud()
	for shot in shot_marks.duplicate():
		shot.ttl-=delta
		if shot.ttl<=0:shot.node.queue_free();shot_marks.erase(shot)
	if paused and worker_anim:worker_anim.speed_scale=0
	rendered_frames+=1
	if capture_path!="" and rendered_frames==capture_frames:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_path)
		var state_file=FileAccess.open(capture_path.trim_suffix(".png")+".json",FileAccess.WRITE)
		state_file.store_string(JSON.stringify(snapshot(),"  "))
		print("CAPTURE_SAVED ",capture_path);get_tree().quit()

func finish_match(team: String, why: String) -> void:
	if winner!="":return
	winner=team;add_event("战斗结束 · "+team+" · "+why)

func decide(team: String) -> void:
	var squad: Array=living(team)
	if squad.is_empty():return
	var health: float=0;var pressure: float=0
	for u in squad:health+=u.hp/u.max_hp;pressure+=u.suppression
	health/=squad.size();pressure/=squad.size()
	var tactics: Array=[{"action":"capture","score":.72+(1-health)*.1,"reason":"争夺中央黄铜标记"},{"action":"cover","score":.34+pressure*.8,"reason":"利用朝向掩体降低压制"},{"action":"flank","score":.36+float(int(elapsed/18)%2)*.44,"reason":"从侧面避开敌人正面防线"},{"action":"retreat","score":(1-health)*.80+pressure*.3,"reason":"保存低生命单位"}]
	if team=="red" and elapsed<24:tactics[1].score=.88
	tactics.sort_custom(func(a,b):return a.score>b.score)
	var chosen: String=tactics[0].action
	decisions[team]={"action":chosen,"reason":tactics[0].reason,"candidates":tactics,"tick":tick_id,"source":"utility_game_ai","confidence":clampf(tactics[0].score,0,1)}
	issue_tactic(team,chosen,objective,[])

func issue_tactic(team: String, action: String, destination: Vector2, ids: Array) -> void:
	var squad: Array=living(team).filter(func(u):return ids.is_empty() or ids.has(u.id))
	var data: Dictionary=faction_data(team)
	for index in range(squad.size()):
		var u=squad[index];var enemy=find_target(u)
		var threat: Vector2=enemy.pos() if enemy!=null else objective
		var offset := Vector2((index-(squad.size()-1)*.5)*.058,0)
		if u.tank and action!="hold" and control[team]=="game_ai":u.move_to(Vector2(1.08,-.25));continue
		match action:
			"cover":
				if not u.seek_cover(threat,u.pos()):u.move_to(destination+offset)
			"retreat":u.move_to(Vector2(data.spawn[0],data.spawn[1])+offset)
			"hold":u.route.clear();u.goal=u.pos();u.state="aim"
			"flank":
				var flank := destination+Vector2(.19 if team!="red" else -.19,.13 if team=="blue" else -.13)
				if u.pos().distance_to(flank)<.15:flank=destination
				u.move_to(flank+offset)
			_:
				if u.suppression>.65 and control[team]=="game_ai":u.seek_cover(threat,u.pos())
				else:u.move_to(destination+offset)

func spawn_tank() -> bool:
	if tank_spawned:return false
	tank_spawned=true
	var t=spawn_unit("red-tank","red",Vector2(1.20,-.46),true)
	t.move_to(Vector2(1.05,-.29));add_event("红方失势 · 后方坦克增援抵达");return true

func add_event(message: String) -> void:
	events.push_front({"time":snappedf(elapsed,.1),"text":message})
	if events.size()>40:events.resize(40)

func add_shot(_from: Vector2,to: Vector2,team: String,landed: bool) -> void:
	if not landed:return
	var marker := MeshInstance3D.new();var sphere := SphereMesh.new();sphere.radius=.004;sphere.height=.008;marker.mesh=sphere
	marker.material_override=field.mat(colors[team].lightened(.45));add_child(marker);marker.position=Vector3(to.x,.88,to.y)
	shot_marks.append({"node":marker,"ttl":.08})

func set_camera(mode: String, instant: bool=false) -> void:
	camera_mode=mode
	if mode=="office":camera_target=Vector3(-.02,.60,.07);camera_size=4.05
	elif mode=="top":camera_target=Vector3(.61,.82,-.01);camera_size=1.80
	else:camera_target=Vector3(.60,.84,-.02);camera_size=1.87
	if instant and camera:
		camera.position=camera_target+(Vector3(0,3.8,.001) if mode=="top" else Vector3(2.6,3.5,3.5));camera.look_at(camera_target);camera.size=camera_size

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
			if source!="agent":control[team]="player"
			for u in living(team):
				if ids.is_empty() or ids.has(u.id):u.target_id=target.id;u.move_to(target.pos())
		else:
			if source!="agent":control[team]="player"
			issue_tactic(team,action,dest,ids)
		decisions[team]={"action":action,"reason":"Agent 指令" if source=="agent" else "玩家/策划指令","source":source,"tick":tick_id,"candidates":[]}
	elif action=="control":
		var mode: String=str(c.get("mode",""))
		if not mode in ["game_ai","player","agent"]:return ack(c,false,"invalid_mode")
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
	for u in units:unit_states.append(u.snapshot())
	return {"schema_version":1,"run_id":run_id,"tick":tick_id,"time":snappedf(elapsed,.1),"paused":paused,"speed":speed,"winner":winner,"units":unit_states,"factions":config.factions,"control":control,"scores":scores,"objective":{"position":[objective.x,objective.y],"radius":config.rules.capture_radius,"score_to_win":config.rules.score_to_win},"covers":field.snapshot(),"obstacles":config.obstacles,"bounds":config.bounds,"decisions":decisions,"events":events,"tank_spawned":tank_spawned,"shots":shots,"navigation_revision":field.revision,"reservations":field.reservations,"selected_faction":selected_faction,"camera":camera_mode,"last_action":last_action,"parameters":config.soldier,"fps":Engine.get_frames_per_second(),"worker_animation_time":worker_anim.current_animation_position if worker_anim and worker_anim.is_playing() else 0.0}

func screen_point(p: Vector2) -> Vector2:
	var origin: Vector3=camera.project_ray_origin(p);var ray: Vector3=camera.project_ray_normal(p)
	if absf(ray.y)<.0001:return objective
	var world: Vector3=origin+ray*((field.height-origin.y)/ray.y);return Vector2(world.x,world.z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:camera_size=clampf(camera_size*.90,1.0,4.5)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera_size=clampf(camera_size*1.1,1.0,4.5)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			var p: Vector2=screen_point(event.position);var nearest_unit=null;var distance: float=.09
			for u in living():
				var d: float=u.pos().distance_to(p)
				if d<distance:nearest_unit=u;distance=d
			if nearest_unit:
				selected_faction=nearest_unit.faction;control[selected_faction]="player"
				for u in units:u.selected=u==nearest_unit or (event.shift_pressed and u.selected and u.faction==selected_faction)
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			var p: Vector2=screen_point(event.position)
			var target=null
			for enemy in living():
				if enemy.faction!=selected_faction and enemy.pos().distance_to(p)<.06:target=enemy
			if target:command({"action":"attack","faction":selected_faction,"target_id":target.id,"unit_ids":selected_ids(),"source":"player"})
			else:command({"action":"move","faction":selected_faction,"position":[p.x,p.y],"unit_ids":selected_ids(),"source":"player"})
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
			KEY_V:set_camera("battle" if camera_mode=="office" else ("top" if camera_mode=="battle" else "office"))
			KEY_ENTER:
				if winner!="":get_tree().reload_current_scene()
			KEY_F1:ui.visible=not ui.visible

func label(value: String, size: int, color: Color=Color(.86,.88,.80)) -> Label:
	var l := Label.new();l.text=value;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color);l.mouse_filter=Control.MOUSE_FILTER_IGNORE;return l

func make_hud() -> void:
	ui=CanvasLayer.new();add_child(ui)
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
	status_label.text="%02d:%02d   •   %s   •   %.1fx" % [int(elapsed)/60,int(elapsed)%60,"PAUSED" if paused else "LIVE",speed]
	selection_label.text="%s / %s / %d SELECTED   ·   HOLD THE BRASS MARKER TO SCORE" % [selected_faction.to_upper(),str(control[selected_faction]).to_upper(),selected_ids().size()]
	phase_label.text="RED REINFORCEMENTS ON DESK   •   DESTRUCTIBLE COVER" if tank_spawned else "TACTICAL DIORAMA   •   3 FACTIONS / 9 INFANTRY"
	hint_label.text="Click select · Shift add · Right-click move · Wheel zoom · Space pause · T tank · F1 clean view"
	if winner!="":selection_label.text=("DRAW" if winner=="draw" else winner.to_upper()+" WINS")+" / PRESS ENTER TO RESTART"
