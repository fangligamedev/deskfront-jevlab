extends Node
## Input/camera adapter only. Orders still pass through the authoritative game.command.
var game
var anchor:=Vector3.ZERO
var yaw:float=atan2(2.6,3.5)
var pitch:float=deg_to_rad(38.75)
var rotating:bool=false
var pan_button:int=0
var groups:Dictionary={}
var last_order:Dictionary={}
var last_group:int=-1
var last_group_time:float=-10
var last_backspace:float=-10
var pan_speed:float=0.65
var web_blur_callback

func setup(g) -> void:
 game=g;anchor=game.camera_target
 preset(true)
 get_window().focus_exited.connect(cancel_interaction)
 if OS.has_feature("web"):
  web_blur_callback=JavaScriptBridge.create_callback(func(_args):cancel_interaction();release_navigation_keys())
  JavaScriptBridge.get_interface("window").deskfrontBlur=web_blur_callback
  JavaScriptBridge.eval("""
  (()=>{const c=document.getElementById('canvas');if(!c||c.dataset.rtsInput)return;c.dataset.rtsInput='true';c.tabIndex=0;c.style.touchAction='none';c.style.userSelect='none';
  c.addEventListener('pointerdown',()=>c.focus({preventScroll:true}),true);
  c.addEventListener('contextmenu',e=>e.preventDefault());
  c.addEventListener('wheel',e=>e.preventDefault(),{passive:false});
  c.addEventListener('keydown',e=>{if(['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Space','Tab','Home','Backspace','PageUp','PageDown'].includes(e.code)||(e.ctrlKey||e.metaKey)&&/^Digit[0-9]$/.test(e.code))e.preventDefault()});
  window.addEventListener('blur',()=>window.deskfrontBlur?.());
  document.addEventListener('visibilitychange',()=>{if(document.hidden)window.deskfrontBlur?.()});
  })();
  """)

func preset(instant:bool=false) -> void:
 yaw=0 if game.eastfront or game.camera_mode=="top" else atan2(2.6,3.5)
 pitch=deg_to_rad(89.9 if game.camera_mode=="top" else 38.75)
 if instant:anchor=game.camera_target;apply_camera(1.0)

func apply_camera(weight:float) -> void:
 anchor=anchor.lerp(game.camera_target,weight)
 game.camera.size=lerpf(game.camera.size,game.camera_size,weight)
 var offset:=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*5.6
 game.camera.position=anchor+offset
 game.camera.look_at(anchor,Vector3.UP)

func editable_focus() -> bool:
 var control=get_viewport().gui_get_focus_owner()
 return control is LineEdit or control is TextEdit

func over_button() -> bool:
 var control=get_viewport().gui_get_hovered_control()
 while control:
  if control is BaseButton or control is Range or control is LineEdit or control is TextEdit:return true
  control=control.get_parent() as Control
 return false

func tick(dt:float) -> void:
 if not game.camera:return
 for u in game.units:
  if is_instance_valid(u.ring):u.ring.visible=u.selected and u.hp>0
 if get_window().has_focus() and not editable_focus():
  var axis:=Vector2.ZERO
  if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):axis.x-=1
  if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):axis.x+=1
  if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):axis.y-=1
  if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):axis.y+=1
  if game.edge_pan and game.pointer_inside and not game.selecting and not game.panning and not rotating and not over_button():
   var p=get_viewport().get_mouse_position();var size=get_viewport().get_visible_rect().size
   var edge:float=18
   if p.x>=0 and p.y>=0 and p.x<=size.x and p.y<=size.y:
    if p.x<edge:axis.x-=1
    if p.x>size.x-edge:axis.x+=1
    if p.y<edge:axis.y-=1
    if p.y>size.y-edge:axis.y+=1
  if axis.length_squared()>0:
   var right:=Vector3(cos(yaw),0,-sin(yaw));var down:=Vector3(sin(yaw),0,cos(yaw))
   var fast:float=1.7 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
   game.pan_by((right*axis.normalized().x+down*axis.normalized().y)*minf(dt,.05)*game.camera_size*pan_speed*fast)
  var rotation_axis:float=float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
  if rotation_axis!=0:manual_camera();yaw+=rotation_axis*dt*1.25
 apply_camera(1.0-exp(-dt*12))

func manual_camera() -> void:
 if game.eastfront:game.eastfront.follow=false

func clamp_target() -> void:
 var b=game.config.bounds
 if game.eastfront:
  game.camera_target.x=clampf(game.camera_target.x,b[0]-.35,b[2]+.35)
  game.camera_target.z=clampf(game.camera_target.z,b[1]-.5,b[3]+.5)
 else:
  game.camera_target.x=clampf(game.camera_target.x,minf(-3.1,b[0]-.5),maxf(2.0,b[2]+.5))
  game.camera_target.z=clampf(game.camera_target.z,minf(-1.4,b[1]-.5),maxf(4.1,b[3]+.5))

func zoom(factor:float,cursor:Vector2) -> void:
 manual_camera()
 var before:Vector2=game.screen_point(cursor)
 game.camera_size=clampf(game.camera_size*factor,.45,3.6 if game.eastfront else 12.0)
 # Keep the surface under the mouse still while zooming; no horizontal drift.
 anchor=game.camera_target;apply_camera(1.0)
 var after:Vector2=game.screen_point(cursor)
 game.pan_by(Vector3(before.x-after.x,0,before.y-after.y));anchor=game.camera_target;apply_camera(1.0)

func hit_rect(u) -> Rect2:
 var foot:Vector2=game.camera.unproject_position(u.global_position+Vector3(0,.008,0))
 var head:Vector2=game.camera.unproject_position(u.global_position+Vector3(0,.08 if u.tank else (.035 if u.posture=="prone" else .11),0))
 var radius:float=clampf(foot.distance_to(head)*(.85 if u.tank else .35)+4,6,22 if u.tank else 14)
 return Rect2(foot,head-foot).abs().grow(radius)

func pick(screen:Vector2,enemies_only:bool=false):
 var best=null;var distance:float=INF
 for u in game.living():
  if game.camera.is_position_behind(u.global_position):continue
  if enemies_only and u.faction==game.selected_faction:continue
  if not hit_rect(u).has_point(screen):continue
  var d:float=hit_rect(u).get_center().distance_to(screen)
  if d<distance:best=u;distance=d
 return best

func feedback(message:String) -> void:
 game.command_feedback=message;game.feedback_until=Time.get_ticks_msec()/1000.0+2.5

func friendly(u) -> bool:
 return u.faction=="green" if game.eastfront else (u.faction==game.selected_faction or game.selected_ids().is_empty())

func select_units(found:Array,additive:bool=false,toggle:bool=false) -> void:
 if not found.is_empty():
  game.selected_faction=found[0].faction
  game.set_control_mode(game.selected_faction,"player")
 for u in game.units:
  if not additive:u.selected=found.has(u)
  elif u.faction!=game.selected_faction:u.selected=false
  elif found.has(u):u.selected=not u.selected if toggle else true
 feedback("SELECTED %d / %s"%[game.selected_ids().size(),game.selected_faction.to_upper()])

func select_at(screen:Vector2,additive:bool,double_click:bool=false) -> void:
 var u=pick(screen)
 if u and friendly(u):
  var found:Array=[u]
  if double_click:
   var viewport=get_viewport().get_visible_rect()
   found=game.living(u.faction).filter(func(other):return other.weapon==u.weapon and viewport.has_point(game.camera.unproject_position(other.global_position)))
  select_units(found,additive,additive and not double_click)
 elif u:feedback("ENEMY %s / RIGHT CLICK TO ATTACK"%u.id)
 elif not additive:select_units([])

func finish_selection(additive:bool) -> void:
 if game.drag_start.distance_to(game.drag_current)<7:select_at(game.drag_current,additive);return
 var rect=Rect2(game.drag_start,game.drag_current-game.drag_start).abs()
 var found:Array=[]
 for u in game.living(game.selected_faction):
  if rect.has_point(hit_rect(u).get_center()) or rect.has_point(game.camera.unproject_position(u.global_position)):found.append(u)
 if found.is_empty() and game.selected_ids().is_empty() and not game.eastfront:
  for u in game.living():
   if rect.has_point(hit_rect(u).get_center()) and (found.is_empty() or u.faction==found[0].faction):found.append(u)
 select_units(found,additive)

func order_at(screen:Vector2) -> void:
 if game.selected_ids().is_empty():feedback("SELECT A UNIT FIRST / LMB OR DRAG BOX");return
 var enemy=pick(screen,true)
 if enemy:game.ground_order(enemy.pos(),enemy)
 else:game.ground_order(game.screen_point(screen))

func focus_selection() -> void:
 var selected=game.living().filter(func(u):return u.selected)
 if selected.is_empty():return
 manual_camera();var center:=Vector3.ZERO
 for u in selected:center+=u.global_position
 game.camera_target=center/selected.size();clamp_target()

func group_key(index:int,assign:bool,additive:bool=false) -> void:
 if assign:
  groups[index]=game.selected_ids();feedback("GROUP %d / %d UNITS"%[index,groups[index].size()]);return
 var ids:Array=groups.get(index,[])
 # Unassigned 1/2/3 remain faction shortcuts in the sandbox; eastfront owns green only.
 if ids.is_empty() and index in [1,2,3]:
  var team:String=["green","blue","red"][index-1]
  if not game.eastfront or team=="green":ids=game.living(team).map(func(u):return u.id)
 var members=game.living().filter(func(u):return ids.has(u.id) and (not game.eastfront or u.faction=="green"))
 if members.is_empty():feedback("GROUP %d IS EMPTY"%index);return
 select_units(members,additive)
 var now:float=Time.get_ticks_msec()/1000.0
 if index==last_group and now-last_group_time<.4:focus_selection()
 last_group=index;last_group_time=now

func release_navigation_keys() -> void:
 for code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_Q,KEY_E,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_SHIFT,KEY_ALT,KEY_CTRL]:
  if Input.is_physical_key_pressed(code):
   var event=InputEventKey.new();event.physical_keycode=code;event.pressed=false;Input.parse_input_event(event)

func cancel_interaction() -> void:
 game.selecting=false;game.panning=false;rotating=false;pan_button=0;game.pointer_inside=false;game.if_box_hide()

func capture(event:InputEvent) -> bool:
 if event is InputEventMouseMotion and (game.panning or game.selecting or rotating):
  game.pointer_inside=true
  if rotating:
   manual_camera();yaw-=event.relative.x*.006;pitch=clampf(pitch+event.relative.y*.004,deg_to_rad(25),deg_to_rad(89.9));game.pan_cursor=event.position
  elif game.panning:game.pan_to(event.position)
  else:
   game.drag_current=event.position;var rect=Rect2(game.drag_start,game.drag_current-game.drag_start).abs()
   game.selection_box.position=rect.position;game.selection_box.size=rect.size;game.selection_box.visible=rect.size.length()>7
  return true
 if event is InputEventMouseButton and not event.pressed:
  if event.button_index==pan_button and (game.panning or rotating):
   if game.panning:game.pan_to(event.position)
   game.panning=false;rotating=false;pan_button=0;return true
  if event.button_index==MOUSE_BUTTON_LEFT and game.selecting:
   game.drag_current=event.position;game.selecting=false;game.if_box_hide();finish_selection(event.shift_pressed);return true
 return false

func input(event:InputEvent) -> bool:
 if event is InputEventMouseMotion:game.pointer_inside=true
 if event is InputEventMouseButton and event.pressed:
  game.pointer_inside=true
  match event.button_index:
   MOUSE_BUTTON_WHEEL_UP:zoom(.88,event.position)
   MOUSE_BUTTON_WHEEL_DOWN:zoom(1.0/.88,event.position)
   MOUSE_BUTTON_MIDDLE:
    game.panning=not event.alt_pressed;rotating=event.alt_pressed;pan_button=event.button_index;game.pan_cursor=event.position;manual_camera()
   MOUSE_BUTTON_LEFT:
    if event.alt_pressed:rotating=true;pan_button=event.button_index;game.pan_cursor=event.position;manual_camera()
    elif event.double_click and not event.shift_pressed:select_at(event.position,event.shift_pressed,true)
    else:game.selecting=true;game.drag_start=event.position;game.drag_current=event.position
   MOUSE_BUTTON_RIGHT:order_at(event.position)
   _:return false
  return true
 if event is InputEventKey and event.pressed and not event.echo and not editable_focus():
  var key:int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
  if key>=KEY_0 and key<=KEY_9:group_key(key-KEY_0,event.ctrl_pressed or event.meta_pressed,event.shift_pressed);return true
  match key:
   KEY_W,KEY_A,KEY_S,KEY_D,KEY_Q,KEY_E,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT:return true
   KEY_F:focus_selection()
   KEY_ESCAPE:select_units([]);cancel_interaction()
   KEY_PAGEUP:zoom(.88,get_viewport().get_visible_rect().size*.5)
   KEY_PAGEDOWN:zoom(1.0/.88,get_viewport().get_visible_rect().size*.5)
   KEY_BACKSPACE:
    var now:float=Time.get_ticks_msec()/1000.0
    if now-last_backspace<.4:game.set_camera(game.camera_mode)
    else:preset()
    last_backspace=now
   KEY_B:game.edge_pan=not game.edge_pan;feedback("EDGE PAN ON" if game.edge_pan else "EDGE PAN OFF")
   KEY_HOME:
    manual_camera()
    if game.eastfront:
     var data=game.faction_data("green");game.camera_target=Vector3(data.spawn[0],game.field.height,data.spawn[1]);clamp_target()
    else:game.set_camera(game.camera_mode)
   _:return false
  return true
 return false

func snapshot() -> Dictionary:
 return {"last_order":last_order,"yaw":yaw,"pitch":pitch,"anchor":[anchor.x,anchor.y,anchor.z],"selected_ids":game.selected_ids(),"groups":groups,"dragging":game.selecting,"panning":game.panning,"rotating":rotating,"selection_rect":[game.drag_start.x,game.drag_start.y,game.drag_current.x,game.drag_current.y],"focused":get_window().has_focus()}
