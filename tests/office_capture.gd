extends SceneTree
func _initialize():call_deferred('run')
func run():
 root.size=Vector2i(1280,900)
 set_meta('deskfront_map',3)
 var g=load('res://scenes/main.tscn').instantiate();root.add_child(g);g.paused=true;g.fx.set_muted(true)
 for mode in ['office','battle','top']:
  g.set_camera(mode,true)
  for i in 6:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png('res://docs/evidence/office-battlefield/'+mode+'.png')
 quit()
