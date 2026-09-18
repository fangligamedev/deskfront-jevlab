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
var actor
var actor_advanced: bool=false
var grenade_count: int=2
var grenade_time: float=-1
var grenade_target
var grenade_released: bool=false
var tank_skeleton: Skeleton3D
var weapon_attachment: BoneAttachment3D

func weapon_config() -> Dictionary:
	var cfg: Dictionary=game.config.weapons[weapon].duplicate()
	# Existing designer sliders act as shared multipliers; defaults preserve balance.
	cfg.damage*=game.config.soldier.damage/9.0
	cfg.cooldown*=game.config.soldier.cooldown/1.3
	cfg.accuracy=clampf(cfg.accuracy*game.config.soldier.accuracy/.72,0,1)
	return cfg

func install_weapon() -> void:
	pass # Weapon assets are attached to the imported hand anchors by toy_actor.gd.

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
	if not tank:
		actor=preload("res://scripts/toy_actor.gd").new();add_child(actor);actor.top_level=true
		actor.global_position=global_position;actor.rotation.y=rotation.y+PI
		actor.navigation_guard=func(p:Vector3):return game.field.walkable(Vector2(p.x,p.z))
		actor.setup(game.colors[faction],"rocket" if weapon=="rocket" else "rifle")
		model=actor.model;anim=actor.anim;tree=actor.tree;playback=actor.playback;bone_count=actor.skeleton.get_bone_count()
		for clip_name in anim.get_animation_list():animation_names[clip_name]=clip_name
	else:
		model=Node3D.new();add_child(model)
		var raw=load("res://assets/models/tank.glb").instantiate();model.add_child(raw)
		var box=AABB();var first=true
		for m in raw.find_children("*","MeshInstance3D",true,false):
			var b=raw.global_transform.affine_inverse()*m.global_transform*m.get_aabb()
			box=b if first else box.merge(b);first=false
		var factor=.30/maxf(box.size.x,maxf(box.size.y,box.size.z))
		raw.scale=Vector3.ONE*factor
		var offset=Vector3(-box.get_center().x,-box.position.y,-box.get_center().z)
		for c in raw.get_children():
			if c is Node3D:c.position+=offset
		raw.rotation.y=-PI/2 # T2 source forward -X becomes the game's -Z.
		var mat=game.field.mat(game.colors[faction],.32)
		for m in raw.find_children("*","MeshInstance3D",true,false):m.material_override=mat
		anim=raw.find_children("*","AnimationPlayer",true,false)[0]
		for n in anim.get_animation_list():anim.get_animation(n).loop_mode=Animation.LOOP_LINEAR
		anim.play("TankArmature|Tank_Forward");anim.speed_scale=0
		# This source's gun is a separate mesh; preserve its normalized transform under a game-space pivot.
		var gun=raw.find_child("Tank_Gun",true,false)
		turret=Node3D.new();turret.name="TurretPivot";model.add_child(turret)
		if gun:
			turret.global_position=gun.global_position
			gun.reparent(turret,true)
		var body=StaticBody3D.new();add_child(body);body.collision_layer=1;body.collision_mask=0
		var col=CollisionShape3D.new();body.add_child(col);var shape=BoxShape3D.new();shape.size=Vector3(.13,.065,.21);col.shape=shape;col.position.y=.04
		muzzle=Node3D.new();turret.add_child(muzzle);muzzle.position=Vector3(0,.02,-.15)
	var torus := TorusMesh.new();torus.inner_radius=.027 if not tank else .10;torus.outer_radius=.031 if not tank else .105
	ring=MeshInstance3D.new();ring.mesh=torus;add_child(ring);ring.position.y=.003;ring.scale.y=.10
	var rm := StandardMaterial3D.new();rm.albedo_color=Color(.93,.81,.47);rm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override=rm;ring.visible=false
	hp_fill=game.field.cube(self,Vector3(0,.145 if not tank else .18,0),Vector3(.05,.003,.005),game.field.mat(game.colors[faction].lightened(.25)))

func animate(clip: String) -> void:
	if clip==last_clip:return
	last_clip=clip
	if actor:
		var mapped={"idle":"rifle_idle","run":"rifle_walk_rm","aim":"rocket_aim" if weapon=="rocket" else "rifle_idle","crouch":"cover_idle","prone":"cover_idle","reload":"reload","fire":"rocket_aim" if weapon=="rocket" else ("pistol_fire" if weapon=="pistol" else "rifle_idle"),"death":"death"}.get(clip,clip)
		if cqb_stance=="peek" and clip in ["aim","fire","crouch"]:mapped="cover_peek_left"
		if actor.anim.has_animation(mapped):actor.play(mapped)

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
	if not moving and not (actor and actor.stepping):rotation.y=lerp_angle(rotation.y,desired,minf(1,dt*10))
	return true

func hit(amount: float, pressure: float) -> void:
	if hp<=0:return
	hp=maxf(0,hp-amount);suppression=minf(1,suppression+pressure)
	if hp<=0:
		state="dead";route.clear();game.field.release(id);animate("death");hp_fill.visible=false;ring.visible=false
		if actor:actor.ragdoll(global_position+Vector3(.07,0,0),.25)
		else:
			for body in find_children("*","StaticBody3D",true,false):body.collision_layer=0
		game.add_event(faction+" · "+id+" 失去战斗力")

func tick(dt: float) -> void:
	actor_advanced=false
	if hp<=0:return
	if actor and actor.global_position.distance_to(global_position)>.001 and not actor.stepping:actor.global_position=global_position
	if grenade_time>=0:
		grenade_time+=dt
		if grenade_time>=.62 and not grenade_released:
			grenade_released=true
			if is_instance_valid(grenade_target):game.fx.launch(self,grenade_target,"grenade",true);game.shots+=1
		if grenade_time>=1.267:grenade_time=-1;last_clip=""
		return
	ring.visible=selected
	hp_fill.scale.x=maxf(.01,hp/max_hp)
	cooldown=maxf(0,cooldown-dt)
	reaction_cooldown=maxf(0,reaction_cooldown-dt)
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
		if pos().distance_to(target)<(.031 if occupied and route.size()>1 else (.008 if tank else .002)):route.remove_at(0)
		else:
			var speed: float=(game.config.tank.speed if tank else game.config.soldier.speed)*(1-suppression*.55)*formation_speed
			var direction: Vector2=target-pos()
			var facing: float=atan2(-direction.x,-direction.y)
			reversing=tank and order_mode=="reverse"
			if reversing:facing=wrapf(facing+PI,-PI,PI)
			if tank:
				rotation.y=rotate_toward(rotation.y,facing,game.config.tactics.tank_turn_speed*dt)
				var step=pos().move_toward(target,speed*dt);position.x=step.x;position.z=step.y;position.y=game.field.ground_height(step)
			else:
				var lateral=false
				if not cover_slot.is_empty() and pos().distance_to(cover_slot.position)<.18:
					var normal:Vector2=cover_slot.normal
					lateral=absf(direction.normalized().dot(normal))<.20
					if lateral:facing=atan2(-normal.x,-normal.y)
				if not lateral and not actor.stepping:
					# Steer the root-motion direction; never translate a planted cover foot externally.
					for other in game.units:
						if other==self or other.hp<=0:continue
						var apart=pos()-other.pos();var space=.13 if other.tank else .030
						if apart.length()>.001 and apart.length()<space:
							var steered=target+apart.normalized()*(space-apart.length())*.8
							if game.field.walkable(steered):target=steered;direction=target-pos();facing=atan2(-direction.x,-direction.y)
				if not actor.stepping:
					rotation.y=facing;actor.rotation.y=facing+PI
					actor.position.y=game.field.ground_height(pos())
				actor.advance_drive(Vector3(target.x,actor.position.y,target.y),speed,dt,lateral)
				global_position=actor.global_position;actor_advanced=true
			state="move";last_clip="run"
	var close_enemy=game.closest_enemy(self)
	if not tank and close_enemy!=null and not close_enemy.tank and pos().distance_to(close_enemy.pos())<=game.config.weapons.bayonet.range and cooldown<=0 and not (actor and actor.stepping) and game.field.melee_clear(pos(),close_enemy.pos()):
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
		if cooldown<=0 and aligned and (tank or (not moving and not actor.stepping and aim_time>=.16 and cqb_stance!="hide" and suppression<.95)):
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
	return {"id":id,"faction":faction,"kind":"tank" if tank else "infantry","position":[position.x,position.z],"hp":snappedf(hp,.1),"max_hp":max_hp,"state":state,"cover_id":cover_id,"suppression":snappedf(suppression,.01),"ammo":ammo,"selected":selected,"goal":[goal.x,goal.y],"animation":last_clip,"bone_count":bone_count,"weapon":weapon,"weapon_name":game.config.weapons[weapon].name,"reload_remaining":snappedf(reload_timer,.1),"weapon_range":game.config.weapons[weapon].range,"melee_ready":not tank and cooldown<=0,"tactical_role":tactical_role,"order_mode":order_mode,"cqb_stance":cqb_stance,"in_cover":in_cover(),"cover_slot":cover_slot.get("key",""),"cover_risk":cover_slot.get("risk",0),"focus_id":focus_id,"reversing":reversing,"turret_yaw":turret.rotation.y if turret else 0.0,"formation_speed":formation_speed,"grenades":grenade_count,"asset_animation":actor.clip if actor else "tracks","root_distance":actor.roots_travelled if actor else 0,"cover_step":actor.stepping if actor else false,"contact_slip_max":actor.contact_slip_max if actor else 0}

func presentation_tick(dt:float) -> void:
	if tank:
		if anim:anim.speed_scale=(.5 if state=="move" and hp>0 else 0.0)*game.speed
		return
	if not actor_advanced:
		if not actor.stepping and not actor.dead:actor.rotation.y=rotation.y+PI
		actor.advance_idle(dt)
		global_position=actor.global_position
	actor_advanced=false

func request_grenade(enemy) -> bool:
	if tank or hp<=0 or grenade_count<=0 or grenade_time>=0 or enemy==null:return false
	if pos().distance_to(enemy.pos())>game.config.weapons.grenade.range or actor.stepping:return false
	grenade_count-=1;grenade_time=0;grenade_released=false;grenade_target=enemy
	route.clear();goal=pos();state="grenade"
	var delta=enemy.pos()-pos();rotation.y=atan2(-delta.x,-delta.y)
	actor.play("grenade_throw");cooldown=1.3
	return true

func equip(value:String) -> void:
	if tank or value not in ["rifle","smg","rocket","pistol"]:return
	weapon=value;ammo=int(game.config.weapons[value].magazine);reload_timer=0
	tactical_role={"rifle":"overwatch","smg":"assault","rocket":"anti_armor","pistol":"assault"}[value]
	actor.weapon.queue_free();actor.weapon_mode="rifle" if value=="smg" else value
	actor.weapon=load("res://assets/models/"+actor.weapon_mode+".glb").instantiate();actor.add_child(actor.weapon)
	for part in actor.weapon.find_children("*","MeshInstance3D",true,false):part.material_override=game.field.mat(game.colors[faction],.32)
	actor.update_weapon()
	last_clip=""

func presentation_pause(value:bool) -> void:
	if tank:
		if anim:anim.speed_scale=0 if value else ((.5 if state=="move" and hp>0 else 0.0)*game.speed)
	elif actor.dead:
		for row in actor.bodies:row.body.freeze=value
