extends SceneTree
var checks:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func run():
 var g=load("res://scenes/main.tscn").instantiate();g.use_legacy_fixture=true;root.add_child(g)
 g.set_physics_process(false);g.set_process(false);g.set_process_unhandled_input(false);g.set_process_input(false);g.fx.set_muted(true);g.edge_pan=false
 g.set_camera("top",true)
 var r=g.rts;var u=g.units[0];var buddy=g.units[1];var enemy=g.units[6]
 # Separate projected hit regions; test real command dispatch with authoritative units.
 u.position=Vector3(.25,g.field.height,.1);buddy.position=Vector3(.6,g.field.height,.1);enemy.position=Vector3(.8,g.field.height,-.3)
 for other in g.units:
  if other not in [u,buddy,enemy]:other.position=Vector3(-.8,g.field.height,-.6)
 var point=r.hit_rect(u).get_center();r.select_at(point,false)
 check(g.selected_ids()==[u.id] and g.control.green=="player","left click selects one soldier and takes player control")
 r.select_at(r.hit_rect(buddy).get_center(),true);check(g.selected_ids().size()==2,"Shift-click adds a soldier")
 r.select_at(r.hit_rect(buddy).get_center(),true);check(g.selected_ids()==[u.id],"Shift-click removes an already selected soldier")
 var prior=g.last_action.duplicate(true);r.select_at(Vector2(20,300),false)
 check(g.selected_ids().is_empty() and g.last_action==prior,"empty left click deselects without issuing a move")
 g.drag_start=point+Vector2(5,5);g.drag_current=point-Vector2(5,5);r.finish_selection(false)
 check(g.selected_ids()==[u.id],"reverse-direction tight box selects an individual soldier")
 r.select_at(r.hit_rect(enemy).get_center(),false)
 check(g.selected_ids()==[u.id],"left click on enemy does not issue attack or steal its faction")
 r.order_at(r.hit_rect(enemy).get_center())
 check(g.last_action.accepted and g.last_action.action=="attack" and u.target_id==enemy.id,"right click on enemy body dispatches targeted attack")
 enemy.position.y+=.35
 check(r.pick(r.hit_rect(enemy).get_center(),true)==enemy,"elevated enemy uses actual projected height")
 r.group_key(4,true);r.select_units([]);r.group_key(4,false)
 check(g.selected_ids()==[u.id],"control group preserves assigned individual IDs")
 r.group_key(4,false)
 check(Vector2(g.camera_target.x,g.camera_target.z).distance_to(u.pos())<.001,"double group recall focuses selected unit")
 g.set_camera("top",true);var basis=g.camera.basis
 g.pan_by(Vector3(.2,0,.1));r.apply_camera(.2)
 check(g.camera.basis.is_equal_approx(basis),"panning keeps camera orientation stable")
 var cursor=Vector2(600,340);var before=g.screen_point(cursor);r.zoom(.7,cursor)
 check(before.distance_to(g.screen_point(cursor))<.0001,"zoom anchors the world point under cursor")
 var c=g.control.duplicate();var key=InputEventKey.new();key.pressed=true;key.physical_keycode=KEY_A
 check(r.input(key) and g.control==c,"A belongs to camera movement and does not return control to LLM")
 g.panning=true;g.selecting=true;r.rotating=true;g.selection_box.show();r.cancel_interaction()
 check(not g.panning and not g.selecting and not r.rotating and not g.selection_box.visible,"focus loss clears every drag state")
 r.select_units([]);prior=g.last_action.duplicate();r.order_at(point)
 check(g.last_action==prior,"right click without selected soldiers cannot command an entire faction")
 g.queue_free();await process_frame
 set_meta("eastfront_enabled",true);set_meta("eastfront_control","player");set_meta("eastfront_backend","local")
 var east=load("res://scenes/main.tscn").instantiate();root.add_child(east);east.set_physics_process(false);east.set_process(false);east.set_process_unhandled_input(false);east.set_process_input(false);east.fx.set_muted(true)
 check(east.selected_faction=="green" and not east.eastfront.follow,"RTS campaign starts as green in free camera mode")
 east.config.bounds=[100,-.7,110,.7];east.camera_target=Vector3(105,.84,0);east.pan_by(Vector3(2,0,.2))
 check(is_equal_approx(east.camera_target.x,107),"streamed campaign camera supports coordinates beyond original room bounds")
 east.pan_by(Vector3(100,0,100));check(east.camera_target.x<=110.351 and east.camera_target.z<=1.201,"streamed camera remains bounded to currently loaded terrain")
 east.queue_free();await process_frame
 var result={"passed":checks.all(func(c):return c.passed),"checks":checks}
 var f=FileAccess.open("res://output/rts-contract.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
 print("RTS_CONTRACT ",result.passed," ",checks.size());quit(0 if result.passed else 1)
