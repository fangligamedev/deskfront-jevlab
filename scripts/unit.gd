extends Node3D

var game
var id: String
var faction: String
var hp: float = 100
var max_hp: float = 100
var suppression: float = 0
var state: String = "idle"
var goal := Vector2.ZERO
var route := PackedVector2Array()
var route_revision: int = -1
var cover_id: String = ""
var target_id: String = ""
var cooldown: float = 0
var reload_timer: float = 0
var ammo: int = 6
var tank: bool = false
var anim: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var animation_names: Dictionary = {}
var model: Node3D
var ring: MeshInstance3D
var hp_fill: MeshInstance3D
var fire_until: float = 0
var last_clip: String = ""
var bone_count: int = 0
var selected: bool = false
var weapon: String="rifle"
var cover_since: float=0
var reaction_cooldown: float=0
var melee_until: float=0
var pursuit_clock: float=0
var tactical_role: String=""
var order_mode: String="hold"
var cover_slot: Dictionary={}
var cqb_stance: String="open"
var peek_until: float=0
var hide_until: float=0
var peeking: bool=false
var focus_id: String=""
var formation_speed: float=1
var aim_time: float=0
var turret: Node3D
var muzzle: Node3D
var reversing: bool=false
var weapon_attachment: BoneAttachment3D

func weapon_config() -> Dictionary:
	var cfg: Dictionary=game.config.weapons[weapon].duplicate()
	# Existing designer sliders act as shared multipliers; defaults preserve balance.
	cfg.damage*=game.config.soldier.damage/9.0
	cfg.cooldown*=game.config.soldier.cooldown/1.3
	cfg.accuracy=clampf(cfg.accuracy*game.config.soldier.accuracy/.72,0,1)
	return cfg

func install_weapon() -> void:
	if tank:return
	for n in model.find_children("*","MeshInstance3D",true,false):
		if "rifle" in n.name.to_lower():n.visible=false
	var skeleton: Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
	weapon_attachment=BoneAttachment3D.new();skeleton.add_child(weapon_attachment);weapon_attachment.bone_name="hand.R"
	var root := Node3D.new();weapon_attachment.add_child(root)
	root.transform=skeleton.get_bone_global_rest(skeleton.find_bone("hand.R")).affine_inverse()
	var m=game.field.mat(game.colors[faction].darkened(.22),.3)
	# Rest-space weapon geometry follows the existing right-hand skeleton in every clip.
	if weapon=="rocket":
		var tube := MeshInstance3D.new();var cylinder := CylinderMesh.new();cylinder.top_radius=.047;cylinder.bottom_radius=.047;cylinder.height=.51
		tube.mesh=cylinder;tube.material_override=m;root.add_child(tube);tube.position=Vector3(-.35,.64,-.025)
		game.field.cube(root,Vector3(-.35,.89,-.025),Vector3(.13,.065,.13),m)
	else:
		game.field.cube(root,Vector3(-.35,.74,-.025),Vector3(.065,.23 if weapon=="rifle" else .17,.075),m)
		game.field.cube(root,Vector3(-.35,.50 if weapon=="rifle" else .56,-.025),Vector3(.029,.27 if weapon=="rifle" else .13,.029),m)
		game.field.cube(root,Vector3(-.35,.71,-.10),Vector3(.047,.07,.14 if weapon=="smg" else .08),m)
		game.field.cube(root,Vector3(-.35,.34 if weapon=="rifle" else .45,-.025),Vector3(.018,.09,.014),game.field.mat(Color(.67,.70,.67)))

func pos() -> Vector2:
	return Vector2(position.x,position.z)

func setup(owner_game, unit_id: String, team: String, p: Vector2, is_tank: bool=false) -> void:
	game=owner_game;id=unit_id;faction=team;tank=is_tank
	var cfg: Dictionary = game.config.tank if tank else game.config.soldier
	max_hp=cfg.hp;hp=max_hp
	weapon="cannon" if tank else game.config.loadout[(int(unit_id.get_slice("-",1))-1)%3]
	tactical_role={"rifle":"overwatch","smg":"assault","rocket":"anti_armor"}.get(weapon,"armor")
	ammo=int(game.config.weapons[weapon].magazine)
	position=Vector3(p.x,game.field.height,p.y);goal=p
	model=load("res://assets/models/tank.glb" if tank else "res://assets/models/infantry-"+faction+".glb").instantiate()
	add_child(model)
	if not tank:model.scale=Vector3.ONE*.069
	var material := StandardMaterial3D.new()
	material.albedo_color=game.colors[faction]
	material.roughness=.35
	for n in model.find_children("*","MeshInstance3D",true,false):n.material_override=material
	for sk in model.find_children("*","Skeleton3D",true,false):bone_count+=sk.get_bone_count()
	var players=model.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty():
		anim=players[0]
		var machine := AnimationNodeStateMachine.new()
		for full in anim.get_animation_list():
			if full=="RESET":continue
			var key: String=String(full).get_slice("/",String(full).get_slice_count("/")-1)
			animation_names[key]=full
			var a: Animation=anim.get_animation(full)
			a.loop_mode=Animation.LOOP_LINEAR if key in ["idle","run","aim","crouch","prone"] else Animation.LOOP_NONE
			var an := AnimationNodeAnimation.new();an.animation=full
			machine.add_node(key,an)
		for a in animation_names:
			for b in animation_names:
				if a==b:continue
				var transition := AnimationNodeStateMachineTransition.new();transition.xfade_time=.14
				machine.add_transition(a,b,transition)
		tree=AnimationTree.new();model.add_child(tree);tree.anim_player=tree.get_path_to(anim);tree.tree_root=machine;tree.active=true
		playback=tree.get("parameters/playback")
		if animation_names.has("idle"):playback.start("idle")
	install_weapon()
	if tank:
		turret=model.find_child("TurretPivot",true,false)
		muzzle=model.find_child("Muzzle",true,false)
	var torus := TorusMesh.new();torus.inner_radius=.027 if not tank else .10;torus.outer_radius=.031 if not tank else .105
	ring=MeshInstance3D.new();ring.mesh=torus;add_child(ring);ring.position.y=.003;ring.scale.y=.10
	var rm := StandardMaterial3D.new();rm.albedo_color=Color(.93,.81,.47);rm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override=rm;ring.visible=false
	hp_fill=game.field.cube(self,Vector3(0,.145 if not tank else .18,0),Vector3(.05,.003,.005),game.field.mat(game.colors[faction].lightened(.25)))

func animate(clip: String) -> void:
	if clip==last_clip:return
	last_clip=clip
	if playback and animation_names.has(clip):playback.travel(clip)

func in_cover() -> bool:
	return cover_id!="" and not cover_slot.is_empty() and pos().distance_to(cover_slot.position)<(.028 if cover_slot.hard else .055)

func armor_multiplier(from: Vector2) -> float:
	if not tank:return 1.0
	var forward := Vector2(-sin(rotation.y),-cos(rotation.y))
	var facing: float=forward.dot((from-pos()).normalized())
	return game.config.tactics.tank_front_armor if facing>.45 else (game.config.tactics.tank_rear_armor if facing<-.45 else game.config.tactics.tank_side_armor)

func muzzle_position(target: Vector3) -> Vector3:
	if tank and muzzle:return muzzle.global_position
	var start := Vector3(position.x,game.field.height+(.133 if tank else (.075 if in_cover() else .10)),position.z)
	return start+(target-start).normalized()*(.13 if tank else .023)

func move_to(p: Vector2, keep_cover: bool=false) -> void:
	if hp<=0:return
	if not keep_cover:game.field.release(id);cover_id="";cover_slot={};peeking=false;cqb_stance="open"
	var destination: Vector2=game.field.to_world(game.field.nearest(p,tank))
	if route_revision==game.field.revision and destination.distance_to(goal)<game.config.tactics.repath_delta and (not route.is_empty() or pos().distance_to(destination)<.025):return
	goal=destination
	route=game.field.path(pos(),goal,tank)
	route_revision=game.field.revision
	state="move"

func occupy(slot: Dictionary) -> void:
	if cover_slot.get("key","")!=slot.key:cover_since=game.elapsed
	game.field.reserve_slot(id,slot)
	cover_id=slot.cover_id;cover_slot=slot;peeking=false
	hide_until=game.elapsed+.25
	move_to(slot.position,true)

func seek_cover(threat: Vector2, near_goal: Vector2, options: Dictionary={}) -> bool:
	var slot: Dictionary=game.field.choose_cover(id,pos(),threat,near_goal,options)
	if slot.is_empty():return false
	occupy(slot);return true

func cover_behavior() -> void:
	if tank or cover_slot.is_empty() or cover_id=="":cqb_stance="open";return
	var hidden: bool=reload_timer>0 or suppression>=game.config.tactics.pinned_threshold
	if not cover_slot.hard:
		cqb_stance="hide" if hidden and in_cover() else "crouch"
		return
	var anchor: Vector2=cover_slot.position
	var peek: Vector2=cover_slot.peek
	if peeking:
		cqb_stance="peek"
		# Exposure dwell begins at the shoulder, not while travelling to it.
		if peek_until<0 and route.is_empty():peek_until=game.elapsed+game.config.tactics.peek_seconds
		if hidden or (peek_until>=0 and game.elapsed>peek_until):
			peeking=false;hide_until=game.elapsed+game.config.tactics.hide_seconds;cqb_stance="hide";move_to(anchor,true)
	elif pos().distance_to(anchor)<.04:
		cqb_stance="hide"
		var enemy=game.closest_enemy(self)
		if not hidden and game.elapsed>=hide_until and enemy!=null and peek.distance_to(enemy.pos())<game.config.weapons[weapon].range and game.field.walkable(peek) and game.field.line_of_sight(peek,enemy.pos()):
			peeking=true;peek_until=-1;cqb_stance="peek";move_to(peek,true)

func turn_weapon(enemy, moving: bool, dt: float) -> bool:
	if enemy==null:return false
	var direction: Vector2=enemy.pos()-pos()
	var desired: float=atan2(-direction.x,-direction.y)
	if tank:
		if turret:
			turret.rotation.y=rotate_toward(turret.rotation.y,wrapf(desired-rotation.y,-PI,PI),game.config.tactics.turret_turn_speed*dt)
			if not moving:rotation.y=rotate_toward(rotation.y,desired,game.config.tactics.tank_turn_speed*dt)
			return absf(angle_difference(rotation.y+turret.rotation.y,desired))<.16
		rotation.y=rotate_toward(rotation.y,desired,game.config.tactics.tank_turn_speed*dt)
		return absf(angle_difference(rotation.y,desired))<.16
	if not moving:rotation.y=lerp_angle(rotation.y,desired,minf(1,dt*10))
	return true

func hit(amount: float, pressure: float) -> void:
	if hp<=0:return
	hp=maxf(0,hp-amount);suppression=minf(1,suppression+pressure)
	if hp<=0:
		state="dead";route.clear();game.field.release(id);animate("death");hp_fill.visible=false;ring.visible=false
		game.add_event(faction+" · "+id+" 失去战斗力")

func tick(dt: float) -> void:
	if hp<=0:return
	ring.visible=selected
	hp_fill.scale.x=maxf(.01,hp/max_hp)
	cooldown=maxf(0,cooldown-dt)
	reaction_cooldown=maxf(0,reaction_cooldown-dt)
	if melee_until>game.elapsed:
		model.position.z=-sin((melee_until-game.elapsed)/.24*PI)*.018
	else:model.position.z=0
	suppression=maxf(0,suppression-dt*game.config.soldier.suppression_decay)
	if cover_id!="":
		var valid: bool=false
		for c in game.field.covers:
			if c.id==cover_id and c.alive:valid=true
		if not valid:game.field.release(id);cover_id="";cover_slot={};peeking=false;cqb_stance="open"
	if route_revision!=game.field.revision and not route.is_empty():route=game.field.path(pos(),goal,tank);route_revision=game.field.revision
	cover_behavior()
	var enemy=game.find_target(self,target_id if target_id!="" else focus_id)
	# Explicit attack closes only to weapon range, never walks onto the target.
	if target_id!="":
		if enemy!=null and enemy.id==target_id:route.clear();goal=pos()
		elif pursuit_clock<=0:
			for candidate in game.living():
				if candidate.id==target_id:move_to(candidate.pos())
			pursuit_clock=.7
	pursuit_clock-=dt
	var moving: bool=not route.is_empty()
	if not moving:reversing=false
	aim_time=0 if moving else aim_time+dt
	if moving:
		var target: Vector2=route[0]
		var occupied: bool=false
		for other in game.units:
			if other!=self and other.hp>0 and other.pos().distance_to(target)<.029:occupied=true
		# An occupied intermediate cell must not pin the follower against separation.
		if pos().distance_to(target)<(.031 if occupied and route.size()>1 else .012):route.remove_at(0)
		else:
			var speed: float=(game.config.tank.speed if tank else game.config.soldier.speed)*(1-suppression*.55)*formation_speed
			var step: Vector2=pos().move_toward(target,speed*dt)
			# local separation, avoiding exact overlap without shifting into obstacles
			for other in game.units:
				if other==self or other.hp<=0:continue
				var distance: float=step.distance_to(other.pos())
				var spacing: float=.11 if tank or other.tank else .028
				if distance>.001 and distance<spacing:
					var separated: Vector2=step+(step-other.pos()).normalized()*(spacing-distance)*.35
					if game.field.walkable(separated,tank):step=separated
			var direction: Vector2=target-pos()
			var facing: float=atan2(-direction.x,-direction.y)
			reversing=tank and order_mode=="reverse"
			if reversing:facing=wrapf(facing+PI,-PI,PI)
			rotation.y=rotate_toward(rotation.y,facing,game.config.tactics.tank_turn_speed*dt) if tank else lerp_angle(rotation.y,facing,minf(1,dt*12))
			position.x=step.x;position.z=step.y
			state="move";animate("run")
	var close_enemy=game.closest_enemy(self)
	if not tank and close_enemy!=null and not close_enemy.tank and pos().distance_to(close_enemy.pos())<=game.config.weapons.bayonet.range and cooldown<=0 and game.field.melee_clear(pos(),close_enemy.pos()):
		cooldown=game.config.weapons.bayonet.cooldown;state="melee";melee_until=game.elapsed+.24
		rotation.y=atan2(-(close_enemy.pos()-pos()).x,-(close_enemy.pos()-pos()).y)
		animate("fire");game.fx.launch(self,close_enemy,"bayonet",true);return
	if reload_timer>0:
		reload_timer-=dt;state="reload";animate("reload")
		if reload_timer<=0:ammo=int(game.config.weapons[weapon].magazine)
		return
	enemy=game.find_target(self,target_id if target_id!="" else focus_id)
	var aligned: bool=turn_weapon(enemy,moving,dt)
	if enemy!=null:
		if cooldown<=0 and aligned and (tank or (not moving and aim_time>=.16 and cqb_stance!="hide" and suppression<.95)):
			fire(enemy)
			return
	if not moving:
		state="suppressed" if suppression>.7 else ("cover" if cover_id!="" else "aim")
		if game.elapsed<fire_until:animate("fire")
		else:animate("prone" if suppression>.7 else ("crouch" if cover_id!="" else ("aim" if enemy!=null else "idle")))

func fire(enemy) -> void:
	var cfg: Dictionary=weapon_config()
	cooldown=cfg.cooldown
	var chance: float=cfg.accuracy*(1-suppression*.32)
	var landed: bool=game.rng.randf()<chance
	game.shots+=1
	game.fx.launch(self,enemy,weapon,landed)
	# The projectile retains this shot's current designer-adjusted values.
	if not game.fx.projectiles.is_empty():game.fx.projectiles[-1].cfg=cfg
	state="fire";animate("fire");fire_until=game.elapsed+.22
	if not tank:
		ammo-=1
		if ammo<=0:
			reload_timer=cfg.reload;game.fx.sound("reload",position,-7)

func snapshot() -> Dictionary:
	return {"id":id,"faction":faction,"kind":"tank" if tank else "infantry","position":[position.x,position.z],"hp":snappedf(hp,.1),"max_hp":max_hp,"state":state,"cover_id":cover_id,"suppression":snappedf(suppression,.01),"ammo":ammo,"selected":selected,"goal":[goal.x,goal.y],"animation":last_clip,"bone_count":bone_count,"weapon":weapon,"weapon_name":game.config.weapons[weapon].name,"reload_remaining":snappedf(reload_timer,.1),"weapon_range":game.config.weapons[weapon].range,"melee_ready":not tank and cooldown<=0,"tactical_role":tactical_role,"order_mode":order_mode,"cqb_stance":cqb_stance,"in_cover":in_cover(),"cover_slot":cover_slot.get("key",""),"cover_risk":cover_slot.get("risk",0),"focus_id":focus_id,"reversing":reversing,"turret_yaw":turret.rotation.y if turret else 0.0,"formation_speed":formation_speed}
