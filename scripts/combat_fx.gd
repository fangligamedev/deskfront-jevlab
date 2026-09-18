extends Node3D
## Bounded visual/audio layer. Projectiles resolve damage only on arrival.
var game
var projectiles: Array=[]
var visuals: Array=[]
var voices: Array=[]
var sounds: Dictionary={}
var muted: bool=false
var audio_enabled: bool=DisplayServer.get_name()!="headless"
var audio_events: int=0
var impacts: int=0
var launched: Dictionary={}
var random := RandomNumberGenerator.new()

func setup(g) -> void:
	game=g;random.seed=2918
	for key in ["rifle","smg","rocket","cannon","explosion","impact","bayonet","order","reload","pistol","grenade","rocket_blast","tank_impact","grenade_blast"]:
		sounds[key]=load("res://assets/audio/"+{"rocket":"rocket_launch","cannon":"tank_cannon","grenade":"reload"}.get(key,key)+".wav")

func material(color: Color, glow: bool=true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new();m.albedo_color=color
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.no_depth_test=false
	return m

func ball(p: Vector3, radius: float, color: Color, ttl: float, velocity: Vector3=Vector3.ZERO) -> void:
	if visuals.size()>=100:return
	var n := MeshInstance3D.new();var mesh := SphereMesh.new()
	mesh.radius=radius;mesh.height=radius*2;mesh.radial_segments=8;mesh.rings=4;n.mesh=mesh
	n.material_override=material(color);add_child(n);n.position=p
	visuals.append({"node":n,"ttl":ttl,"life":ttl,"velocity":velocity,"grow":1.4})

func beam(a: Vector3, b: Vector3, width: float, color: Color, ttl: float) -> void:
	if a.distance_to(b)<.0001 or visuals.size()>=100:return
	var n := MeshInstance3D.new();var mesh := BoxMesh.new();mesh.size=Vector3(width,width,a.distance_to(b));n.mesh=mesh
	n.material_override=material(color);add_child(n);n.position=(a+b)*.5;n.look_at(b)
	visuals.append({"node":n,"ttl":ttl,"life":ttl,"velocity":Vector3.ZERO,"grow":0.0})

func ring(p: Vector2, color: Color, radius: float=.04, ttl: float=.75) -> void:
	if visuals.size()>=100:return
	var n := MeshInstance3D.new();var mesh := TorusMesh.new();mesh.inner_radius=radius*.86;mesh.outer_radius=radius
	mesh.rings=20;mesh.ring_segments=6;n.mesh=mesh;n.material_override=material(color)
	add_child(n);n.position=Vector3(p.x,game.field.height+.006,p.y);n.scale.y=.12
	visuals.append({"node":n,"ttl":ttl,"life":ttl,"velocity":Vector3.ZERO,"grow":.7})

func sound(key: String, p: Vector3, quiet: float=0) -> void:
	if muted or not audio_enabled or not sounds.has(key):return
	voices=voices.filter(func(v):return is_instance_valid(v))
	if voices.size()>=20:return
	var player := AudioStreamPlayer3D.new();add_child(player);player.position=p
	player.stream=sounds[key];player.unit_size=6;player.max_distance=25
	player.volume_db=(-15 if key=="smg" else -9)+quiet;player.pitch_scale=random.randf_range(.94,1.06)
	player.finished.connect(player.queue_free);voices.append(player);player.play();audio_events+=1

func set_muted(value: bool) -> void:
	muted=value
	if muted:
		for v in voices:
			if is_instance_valid(v):v.stop();v.stream=null;v.queue_free()
		voices.clear()

func launch(shooter, target, weapon: String, landed: bool) -> void:
	var cfg: Dictionary=game.config.weapons[weapon]
	launched[weapon]=int(launched.get(weapon,0))+1
	var end: Vector3=Vector3(target.position.x,game.field.height+(.09 if target.tank else .055),target.position.z)
	var from: Vector3=shooter.muzzle_position(end)
	var dir: Vector3=(end-from).normalized()
	sound(weapon,from)
	if weapon=="bayonet":
		beam(from,end,.007,Color(.84,.91,.95),.14)
		target.hit(float(cfg.damage),float(cfg.pressure));impacts+=1
		return
	if not landed:end+=Vector3(random.randf_range(.04,.09),-.02,random.randf_range(-.08,.08))
	var explosive: bool=weapon in ["rocket","cannon","grenade"]
	puff(from,.048 if explosive else .027,.20,false)
	beam(from,from+dir*.045,.009 if explosive else .006,Color(1,.91,.53),.10)
	var n := MeshInstance3D.new();var mesh := SphereMesh.new();mesh.radius=.009 if explosive else .0035;mesh.height=mesh.radius*2;mesh.radial_segments=8;mesh.rings=4;n.mesh=mesh
	n.material_override=material(Color(1,.54,.13) if explosive else Color(1,.91,.48));add_child(n);n.position=from
	if weapon=="grenade":
		var shell=load("res://assets/models/grenade.glb").instantiate();n.add_child(shell);shell.scale=Vector3.ONE*.075;n.mesh=null
		for part in shell.find_children("*","MeshInstance3D",true,false):part.material_override=game.field.mat(game.colors[shooter.faction],.32)
	projectiles.append({"node":n,"from":from,"to":end,"age":0.0,"duration":maxf(.09,from.distance_to(end)/float(cfg.projectile_speed)),"cfg":cfg.duplicate(),"weapon":weapon,"team":shooter.faction,"target":target,"landed":landed,"trail":0.0})

func physics_tick(dt: float) -> void:
	for p in projectiles.duplicate():
		p.age+=dt
		var previous: Vector3=p.node.position
		p.node.position=p.from.lerp(p.to,clampf(p.age/p.duration,0,1))
		if p.weapon=="grenade":p.node.position.y+=sin(clampf(p.age/p.duration,0,1)*PI)*.20
		p.trail-=dt
		if p.trail<=0:
			p.trail=.045
			beam(previous,p.node.position,.006 if p.weapon in ["rocket","cannon"] else .003,Color(1,.80,.36),.22)
			if p.weapon in ["rocket","cannon"]:puff(previous,.035,.7,true)
		if p.age>=p.duration:
			impact(p);p.node.queue_free();projectiles.erase(p)

func impact(p: Dictionary) -> void:
	impacts+=1
	var at: Vector2=Vector2(p.to.x,p.to.z)
	var explosive: bool=p.weapon in ["rocket","cannon","grenade"]
	if explosive:
		sound({"rocket":"rocket_blast","cannon":"tank_impact","grenade":"grenade_blast"}[p.weapon],p.to)
		var size=float(p.cfg.splash)*1.8
		puff(p.to+Vector3.UP*.025,size,1.0,false)
		for i in range(5):puff(p.to+Vector3(random.randf_range(-.025,.025),.03,random.randf_range(-.025,.025)),size,2.0+i*.35,true)
		for i in range(7):ball(p.to,.004,Color(.4,.34,.22),.65,Vector3(random.randf_range(-.15,.15),.15,random.randf_range(-.15,.15)))
		for enemy in game.living():
			if enemy.faction==p.team:continue
			var distance: float=enemy.pos().distance_to(at)
			if distance>float(p.cfg.splash):continue
			var direct: bool=enemy==p.target and p.landed and distance<.065
			var damage: float=float(p.cfg.damage)*(1.0 if direct else .65*(1-distance/float(p.cfg.splash)))
			if enemy.tank:damage*=float(p.cfg.armor_multiplier)*enemy.armor_multiplier(Vector2(p.from.x,p.from.z))
			else:damage*=1-game.field.protection(enemy.pos(),Vector2(p.from.x,p.from.z))
			enemy.hit(damage,float(p.cfg.pressure)*(1-game.field.protection(enemy.pos(),Vector2(p.from.x,p.from.z))*.6))
		for c in game.field.covers:
			if c.alive and Vector2(c.position[0],c.position[1]).distance_to(at)<float(p.cfg.splash)+.09:
				if game.field.damage_cover(c.id,24 if p.weapon=="rocket" else 35):game.add_event("爆炸摧毁 "+c.id+"，通路已更新")
	else:
		sound("impact",p.to,-11)
		for i in range(3):ball(p.to,.004,Color(1,.88,.46),.17,Vector3(random.randf_range(-.1,.1),.06,random.randf_range(-.1,.1)))
		var target=p.target
		if is_instance_valid(target) and target.hp>0 and target.pos().distance_to(at)<.08:
			var cover: float=game.field.protection(target.pos(),Vector2(p.from.x,p.from.z))
			var damage: float=float(p.cfg.damage)*(1-cover)*(float(p.cfg.armor_multiplier)*target.armor_multiplier(Vector2(p.from.x,p.from.z)) if target.tank else 1.0)
			target.hit(damage if p.landed else 0,float(p.cfg.pressure)*(1-cover*.6))

func _process(dt: float) -> void:
	if game==null:return
	if game.paused or game.winner!="":return
	for effect in visuals.duplicate():
		effect.ttl-=dt*game.speed
		if effect.ttl<=0:effect.node.queue_free();visuals.erase(effect);continue
		effect.node.position+=effect.velocity*dt
		effect.node.scale*=1+effect.grow*dt
		if effect.has("smoke"):
			var t=1-effect.ttl/effect.life
			effect.node.material_override.set_shader_parameter("progress",lerpf(.38,.99,t) if effect.smoke else t)
		else:effect.node.material_override.albedo_color.a=minf(1,effect.ttl/effect.life*1.6)

func _exit_tree() -> void:
	set_muted(true)
	sounds.clear()

func puff(p:Vector3,size:float,life:float,smoke:bool) -> void:
	if visuals.size()>=100:return
	var n=MeshInstance3D.new();var q=QuadMesh.new();q.size=Vector2.ONE*size;n.mesh=q
	n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m=ShaderMaterial.new();m.shader=load("res://assets/vfx/soft_flipbook.gdshader")
	m.set_shader_parameter("atlas",load("res://assets/vfx/fx.png"));m.set_shader_parameter("flow",load("res://assets/vfx/flow.png"))
	m.set_shader_parameter("smoke_only",smoke);m.set_shader_parameter("opacity",.4 if smoke else .88)
	n.material_override=m;add_child(n);n.position=p
	visuals.append({"node":n,"ttl":life,"life":life,"velocity":Vector3(.008,.035 if smoke else .006,.005),"grow":.15,"smoke":smoke})
