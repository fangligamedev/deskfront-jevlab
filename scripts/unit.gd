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
	var torus := TorusMesh.new();torus.inner_radius=.027 if not tank else .10;torus.outer_radius=.031 if not tank else .105
	ring=MeshInstance3D.new();ring.mesh=torus;add_child(ring);ring.position.y=.003;ring.scale.y=.10
	var rm := StandardMaterial3D.new();rm.albedo_color=Color(.93,.81,.47);rm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override=rm;ring.visible=false
	hp_fill=game.field.cube(self,Vector3(0,.145 if not tank else .18,0),Vector3(.05,.003,.005),game.field.mat(game.colors[faction].lightened(.25)))

func animate(clip: String) -> void:
	if clip==last_clip:return
	last_clip=clip
	if playback and animation_names.has(clip):playback.travel(clip)

func move_to(p: Vector2, keep_cover: bool=false) -> void:
	if hp<=0:return
	if not keep_cover:game.field.release(id);cover_id=""
	goal=game.field.to_world(game.field.nearest(p,tank))
	route=game.field.path(pos(),goal,tank)
	route_revision=game.field.revision
	state="move"

func seek_cover(threat: Vector2, near_goal: Vector2) -> bool:
	var slot: Dictionary=game.field.choose_cover(id,pos(),threat,near_goal)
	if slot.is_empty():return false
	if cover_id!=slot.cover_id:cover_since=game.elapsed
	cover_id=slot.cover_id
	move_to(slot.position,true)
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
		if not valid:cover_id=""
	if route_revision!=game.field.revision and not route.is_empty():route=game.field.path(pos(),goal,tank);route_revision=game.field.revision
	var enemy=game.find_target(self,target_id)
	# Explicit attack closes only to weapon range, never walks onto the target.
	if target_id!="":
		if enemy!=null and enemy.id==target_id:route.clear();goal=pos()
		elif pursuit_clock<=0:
			for candidate in game.living():
				if candidate.id==target_id:move_to(candidate.pos())
			pursuit_clock=.7
	pursuit_clock-=dt
	if not tank and game.control[faction]=="game_ai" and enemy!=null and cover_id=="" and reaction_cooldown<=0:
		reaction_cooldown=3.0
		if not seek_cover(enemy.pos(),pos()):route.clear();goal=pos()
	var moving: bool=not route.is_empty()
	if moving:
		var target: Vector2=route[0]
		var occupied: bool=false
		for other in game.units:
			if other!=self and other.hp>0 and other.pos().distance_to(target)<.029:occupied=true
		# An occupied intermediate cell must not pin the follower against separation.
		if pos().distance_to(target)<(.031 if occupied and route.size()>1 else .012):route.remove_at(0)
		else:
			var speed: float=(game.config.tank.speed if tank else game.config.soldier.speed)*(1-suppression*.55)
			var step: Vector2=pos().move_toward(target,speed*dt)
			# local separation, avoiding exact overlap without shifting into obstacles
			for other in game.units:
				if other==self or other.hp<=0:continue
				var distance: float=step.distance_to(other.pos())
				if distance>.001 and distance<.028:
					var separated: Vector2=step+(step-other.pos()).normalized()*(.028-distance)*.35
					if game.field.walkable(separated):step=separated
			var direction: Vector2=target-pos()
			rotation.y=lerp_angle(rotation.y,atan2(-direction.x,-direction.y),minf(1,dt*12))
			position.x=step.x;position.z=step.y
			state="move";animate("run")
	var close_enemy=game.closest_enemy(self)
	if not tank and close_enemy!=null and not close_enemy.tank and pos().distance_to(close_enemy.pos())<=game.config.weapons.bayonet.range and cooldown<=0:
		cooldown=game.config.weapons.bayonet.cooldown;state="melee";melee_until=game.elapsed+.24
		rotation.y=atan2(-(close_enemy.pos()-pos()).x,-(close_enemy.pos()-pos()).y)
		animate("fire");game.fx.launch(self,close_enemy,"bayonet",true);return
	if reload_timer>0:
		reload_timer-=dt;state="reload";animate("reload")
		if reload_timer<=0:ammo=int(game.config.weapons[weapon].magazine)
		return
	enemy=game.find_target(self,target_id)
	if enemy!=null:
		var direction: Vector2=enemy.pos()-pos()
		if not moving:rotation.y=lerp_angle(rotation.y,atan2(-direction.x,-direction.y),minf(1,dt*10))
		if cooldown<=0 and (not moving or tank):
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
	return {"id":id,"faction":faction,"kind":"tank" if tank else "infantry","position":[position.x,position.z],"hp":snappedf(hp,.1),"max_hp":max_hp,"state":state,"cover_id":cover_id,"suppression":snappedf(suppression,.01),"ammo":ammo,"selected":selected,"goal":[goal.x,goal.y],"animation":last_clip,"bone_count":bone_count,"weapon":weapon,"weapon_name":game.config.weapons[weapon].name,"reload_remaining":snappedf(reload_timer,.1),"weapon_range":game.config.weapons[weapon].range,"melee_ready":not tank and cooldown<=0}
