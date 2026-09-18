extends Node
func capture(g,path):
 await RenderingServer.frame_post_draw
 g.get_viewport().get_texture().get_image().save_png("res://output/integration/"+path+".png")
func _ready():
 var g=load("res://scenes/main.tscn").instantiate();add_child(g);g.set_physics_process(false);g.fx.set_muted(true);g.ui.visible=false
 g.paused=true
 for i in range(10):await get_tree().process_frame
 await capture(g,"office")
 var u=g.units[0];var enemy=g.units[6]
 for other in g.units:
  other.visible=false;other.actor.visible=false;other.hp=0
 u.visible=true;u.actor.visible=true;u.hp=100
 enemy.visible=true;enemy.actor.visible=true;enemy.hp=100
 u.position=Vector3(.52,g.field.height,2.015);u.actor.global_position=u.global_position;u.rotation.y=0;u.actor.rotation.y=PI
 enemy.position=Vector3(.72,g.field.height,1.73);enemy.actor.global_position=enemy.global_position;enemy.actor.rotation.y=0
 u.actor.play("cover_idle");enemy.actor.play("rocket_aim")
 g.camera_mode="battle";g.camera_target=Vector3(.56,.89,1.99);g.camera_size=.65;g.camera.size=.65
 g.paused=false
 for i in range(30):u.presentation_tick(1.0/60);enemy.presentation_tick(1.0/60);await get_tree().process_frame
 await capture(g,"soldier-cover")
 u.actor.cover_target=u.actor.global_position+Vector3(.033,0,0)
 for i in range(22):u.actor._physics_process(1.0/60);await get_tree().process_frame
 await capture(g,"soldier-step")
 for i in range(46):u.actor._physics_process(1.0/60);await get_tree().process_frame
 u.global_position=u.actor.global_position
 g.fx.launch(enemy,u,"rocket",true)
 for i in range(42):g.fx.physics_tick(1.0/60);await get_tree().process_frame
 u.hit(1000,1)
 for i in range(12):u.presentation_tick(1.0/60);await get_tree().physics_frame
 await capture(g,"explosion-ragdoll")
 g.fx.set_muted(true);g.queue_free();await get_tree().process_frame;await get_tree().process_frame;get_tree().quit()
