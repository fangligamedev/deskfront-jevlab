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

func pos() -> Vector2:
	return Vector2(position.x,position.z)

func setup(owner_game, unit_id: String, team: String, p: Vector2, is_tank: bool=false) -> void:
	game=owner_game;id=unit_id;faction=team;tank=is_tank
	var cfg: Dictionary = game.config.tank if tank else game.config.soldier
	max_hp=cfg.hp;hp=max_hp
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
	suppression=maxf(0,suppression-dt*game.config.soldier.suppression_decay)
	if cover_id!="":
		var valid: bool=false
		for c in game.field.covers:
			if c.id==cover_id and c.alive:valid=true
		if not valid:cover_id=""
	if route_revision!=game.field.revision and not route.is_empty():route=game.field.path(pos(),goal,tank);route_revision=game.field.revision
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
	if reload_timer>0:
		reload_timer-=dt;state="reload";animate("reload")
		if reload_timer<=0:ammo=int(game.config.soldier.magazine)
		return
	var enemy=game.find_target(self,target_id)
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
	var cfg: Dictionary=game.config.tank if tank else game.config.soldier
	cooldown=cfg.cooldown
	var cover: float=game.field.protection(enemy.pos(),pos())
	var chance: float=(.92 if tank else game.config.soldier.accuracy)*(1-suppression*.38)
	var damage: float=cfg.damage*(1-cover)
	var landed: bool=game.rng.randf()<chance
	enemy.hit(damage if landed else 0,.20 if tank else .11)
	game.shots+=1
	game.add_shot(pos(),enemy.pos(),faction,landed)
	state="fire";animate("fire");fire_until=game.elapsed+.32
	if tank:
		for c in game.field.covers:
			if c.alive and c.hp>0 and Vector2(c.position[0],c.position[1]).distance_to(enemy.pos())<.18:
				if game.field.damage_cover(c.id,45):game.add_event("坦克摧毁 "+c.id+"，通路已更新")
	else:
		ammo-=1
		if ammo<=0:reload_timer=game.config.soldier.reload

func snapshot() -> Dictionary:
	return {"id":id,"faction":faction,"kind":"tank" if tank else "infantry","position":[position.x,position.z],"hp":snappedf(hp,.1),"max_hp":max_hp,"state":state,"cover_id":cover_id,"suppression":snappedf(suppression,.01),"ammo":ammo,"selected":selected,"goal":[goal.x,goal.y],"animation":last_clip,"bone_count":bone_count}
