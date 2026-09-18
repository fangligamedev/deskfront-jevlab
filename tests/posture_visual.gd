extends Node
func _ready():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/v05"))
 var g=load("res://scenes/main.tscn").instantiate();add_child(g);g.set_physics_process(false);g.fx.set_muted(true);g.ui.visible=false;g.paused=true
 var u=g.units[0]
 for other in g.units:
  other.visible=false;other.actor.visible=false;other.hp=0
 u.hp=100;u.visible=true;u.actor.visible=true;u.position=Vector3(.54,g.field.height,2.26);u.actor.global_position=u.global_position;u.rotation.y=0;u.actor.rotation.y=PI
 g.camera_mode="battle";g.camera_target=u.position+Vector3(0,.04,0);g.camera_size=.32;g.camera.size=.32
 for clip in ["rifle_jog_rm","cover_idle","prone_idle","prone_fire","crawl","prone_reload","bayonet"]:
  u.actor.clip=clip;u.actor.playback.start(clip,true);u.actor.drive_goal=Vector3.INF
  for i in range(16):u.actor.tree.advance(1.0/30)
  u.actor.update_weapon()
  for i in range(5):await get_tree().process_frame
  await RenderingServer.frame_post_draw
  g.get_viewport().get_texture().get_image().save_png("res://output/v05/pose-"+clip+".png")
  var head=u.actor.skeleton.global_transform*u.actor.skeleton.get_bone_global_pose(u.actor.skeleton.find_bone("Head"))
  print("POSE ",clip," head_y=",head.origin.y-u.actor.global_position.y)
 g.queue_free();await get_tree().process_frame;get_tree().quit()
