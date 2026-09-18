extends Node
## Controlled native CQB visual acceptance using the shipped scene and unit logic.
var g
var actor
var saved: Dictionary={}
var age: float=0

func _ready() -> void:
	g=load("res://scenes/main.tscn").instantiate();add_child(g)
	preload("res://tests/tactics_checks.gd").isolate(g)
	g.bridge.enabled=false
	for u in g.units:u.visible=false
	actor=g.units[0];actor.visible=true;actor.hp=100
	var enemy=g.units[6];enemy.visible=true;enemy.hp=100;enemy.position=Vector3(.99,g.field.height,-.4)
	var station: Dictionary={}
	for c in g.field.covers:
		if c.id!="hard_sharpener":continue
		for s in g.field.slots(c):
			if not g.field.line_of_sight(s.position,enemy.pos()) and g.field.line_of_sight(s.peek,enemy.pos()) and g.field.walkable(s.position) and g.field.walkable(s.peek):station=s;break
	assert(not station.is_empty())
	actor.position=Vector3(station.position.x,g.field.height,station.position.y);actor.occupy(station);actor.route.clear();actor.hide_until=1
	g.set_camera("battle",true);g.camera_target=Vector3(.84,.86,-.40);g.camera_size=.65
	g.camera.position=g.camera_target+Vector3(2.6,3.5,3.5);g.camera.look_at(g.camera_target);g.camera.size=g.camera_size
	g.ui.visible=false

func _physics_process(dt: float) -> void:
	if g==null:return
	age+=dt;g.elapsed=age
	g.fx.physics_tick(dt);actor.tick(dt)
	if age>.3 and not saved.has("hide"):capture("hide")
	if actor.state=="fire" and not saved.has("peek"):capture("peek")
	if saved.has("peek") and age>2.4 and not saved.has("reload"):actor.reload_timer=2
	if actor.reload_timer>0 and actor.pos().distance_to(actor.cover_slot.position)<.02 and not saved.has("reload"):capture("reload")
	if age>6:
		var f=FileAccess.open("res://output/tactics-visual.json",FileAccess.WRITE)
		f.store_string(JSON.stringify({"passed":saved.size()==3,"frames":saved,"shots":g.shots},"  "))
		get_tree().quit(0 if saved.size()==3 else 1)

func capture(label: String) -> void:
	saved[label]=actor.snapshot()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://output/cqb-"+label+".png")
