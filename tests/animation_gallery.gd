extends Node3D
var players: Array=[]
var frame: int=0
func _ready() -> void:
	var world := WorldEnvironment.new();var env := Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.16,.20,.17);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.8,.85,.75);env.ambient_light_energy=.6;world.environment=env;add_child(world)
	var light := DirectionalLight3D.new();add_child(light);light.rotation_degrees=Vector3(-55,-25,0);light.light_energy=.6;light.shadow_enabled=true
	var camera := Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=9;camera.position=Vector3(2,6,9);camera.look_at(Vector3(0,.6,1.2));camera.current=true
	var floor := MeshInstance3D.new();var box := BoxMesh.new();box.size=Vector3(12,.1,8);floor.mesh=box;add_child(floor);floor.position=Vector3(0,-.075,1)
	var mat := StandardMaterial3D.new();mat.albedo_color=Color(.26,.30,.24);floor.material_override=mat
	var clips=["idle","run","aim","fire","crouch","prone","reload","death"]
	for i in range(clips.size()):
		var model=load("res://assets/models/infantry-green.glb").instantiate();add_child(model);model.position=Vector3(-3+(i%4)*2,0,(i/4)*2.6)
		model.rotation.y=PI
		var player: AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0];player.play(clips[i]);player.pause();players.append({"player":player,"clip":clips[i]})
		var title := Label3D.new();title.text=clips[i].to_upper();title.font_size=48;title.pixel_size=.007;title.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(title);title.position=model.position+Vector3(0,1.95,0)
func _process(_dt: float) -> void:
	frame+=1
	if frame in [10,30,50]:
		var ratio: float=0 if frame==10 else (.5 if frame==30 else .97)
		for item in players:item.player.seek(item.player.get_animation(item.clip).length*ratio,true)
	if frame in [15,35,55]:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/animations-"+str(frame)+".png")
	if frame==60:get_tree().quit()
