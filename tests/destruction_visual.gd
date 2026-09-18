extends Node
func capture(g,name):
 for i in range(4):await get_tree().process_frame
 await RenderingServer.frame_post_draw
 g.get_viewport().get_texture().get_image().save_png("res://output/v05/destruction-"+name+".png")
func _ready():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/v05"))
 get_tree().set_meta("deskfront_map",1)
 var g=load("res://scenes/main.tscn").instantiate();add_child(g);g.set_physics_process(false);g.fx.set_muted(true);g.ui.visible=false
 for u in g.units:u.hp=0;u.visible=false;u.actor.visible=false
 var c=g.field.covers.filter(func(v):return v.id=="rock-0")[0];var center=Vector3(c.position[0],g.field.height,c.position[1])
 var tank=g.spawn_unit("visual-tank","green",Vector2(center.x,center.z+.50),true)
 var target=g.units[6];target.hp=100;target.visible=true;target.actor.visible=true;target.position=center+Vector3(0,0,-.30);target.actor.global_position=target.global_position;target.actor.advance_idle(.2)
 g.camera_mode="battle";g.camera_target=center+Vector3(0,.04,.08);g.camera_size=1.05;g.camera.size=1.05
 await capture(g,"intact")
 for shot in range(3):
  g.fx.launch(tank,target,"cannon",true)
  for step in range(60):
   g.elapsed+=1.0/60;g.fx.physics_tick(1.0/60)
   await get_tree().process_frame
  await capture(g,"shot-"+str(shot+1))
  print("DESTRUCTION shot=",shot+1," hp=",c.hp," alive=",c.alive," layer=",c.node.collision_layer," revision=",g.field.revision)
 for i in range(210):g.fx._process(1.0/30);await get_tree().process_frame
 await capture(g,"cleared")
 g.queue_free();await get_tree().process_frame;get_tree().quit()
