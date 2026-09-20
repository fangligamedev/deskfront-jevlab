extends Node
## Local single-unit possession. The RTS world remains the sole simulation authority.
var game
var unit
var active:bool=false
var perspective:String="third"
var yaw:float=0
var pitch:float=-.12
var aiming:bool=false
var trigger:bool=false
var crouched:bool=false
var in_cover:bool=false
var cover_arrived:bool=false
var throw_point:=Vector3.INF
var previous_camera:String="battle"
var previous_speed:float=1
var first_weapon:Node3D
var sight:Label
var objective_readout:Label
var readout:Label
var overlay:CanvasLayer
var message:String=""
var shots_fired:int=0
var sample_input:bool=true
var input_axis:=Vector2.ZERO
var sprinting:bool=false
var camera_initialized:bool=false
var held_keys:Dictionary={}

func setup(g):
 game=g
 get_window().focus_exited.connect(func():held_keys.clear();trigger=false;aiming=false)
 overlay=CanvasLayer.new();overlay.layer=8;add_child(overlay)
 var root=Control.new();overlay.add_child(root);root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var panel=ColorRect.new();panel.color=Color(.035,.05,.04,.88);root.add_child(panel);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);panel.offset_top=-106
 sight=g.label("＋",23);sight.add_theme_color_override("font_outline_color",Color(.05,.08,.06));sight.add_theme_constant_override("outline_size",4);root.add_child(sight);sight.set_anchors_and_offsets_preset(Control.PRESET_CENTER);sight.offset_left=-14;sight.offset_top=-16;sight.offset_right=14;sight.offset_bottom=16;sight.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 readout=g.label("",14);root.add_child(readout);readout.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);readout.offset_left=22;readout.offset_top=-96;readout.offset_right=-18
 objective_readout=g.label("",17);root.add_child(objective_readout);objective_readout.position=Vector2(20,16);objective_readout.add_theme_color_override("font_outline_color",Color(.04,.06,.05));objective_readout.add_theme_constant_override("outline_size",6)
 overlay.hide()

func eligible(u)->bool:
 return u!=null and u.hp>0 and not u.tank and u.deployment_phase=="active" and u.gun_id=="" and u.garrison_phase=="" and u.grenade_time<0 and not u.actor.stepping

func enter(id:String="",view:String="third")->bool:
 if active:leave()
 if game.paused or game.winner!="":message="请先继续战斗，再接管士兵";return false
 if game.demo and game.demo.phase!="battle":message="请先开始演示战斗";return false
 var options=game.units.filter(func(u):return eligible(u) and ((u.id==id) if id!="" else u.selected))
 if options.is_empty():message="先选中一名存活、未操炮或驻楼的步兵";return false
 held_keys.clear();unit=options[0];active=true;unit.direct_controlled=true
 game.tactics_ai.cancel_selected(unit.faction,[unit.id]);unit.route.clear();unit.target_id="";unit.focus_id="";unit.goal=unit.pos();unit.safety_until=0
 game.field.release(unit.id);unit.cover_id="";unit.cover_slot={};unit.cqb_stance="open"
 previous_camera=game.camera_mode;previous_speed=game.speed;game.speed=1
 if game.eastfront:game.eastfront.follow=false
 game.selected_faction=unit.faction
 for u in game.units:u.selected=u==unit
 yaw=unit.rotation.y;pitch=-.08;crouched=false;in_cover=false;aiming=false;trigger=false;throw_point=Vector3.INF
 perspective=view if view in ["first","third"] else "third"
 first_weapon=unit.actor.weapon.duplicate();game.camera.add_child(first_weapon);first_weapon.scale=Vector3.ONE*.11
 for mesh in first_weapon.find_children("*","MeshInstance3D",true,false):mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 game.selecting=false;game.panning=false;game.if_box_hide()
 camera_initialized=false;game.camera.projection=Camera3D.PROJECTION_PERSPECTIVE;game.camera.near=.003;game.camera.far=30
 game.ui.hide();overlay.show();message="单兵接管 · 队友继续自主行动"
 update_camera(0)
 return true

func capture_mouse():
 if active and not game.paused and game.winner=="":Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func leave():
 if not active:return
 held_keys.clear();var old=unit;active=false;trigger=false;aiming=false;in_cover=false;throw_point=Vector3.INF
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 if is_instance_valid(old):
  old.direct_controlled=false;old.actor.model.show();old.actor.weapon.show();old.actor.animation_rate=1;old.actor.aim_pitch=0
  old.route.clear();old.goal=old.pos();old.posture_order="auto";old.cqb_stance="open";old.cover_id="";old.cover_slot={};old.order_mode="hold"
  game.field.release(old.id)
 if is_instance_valid(first_weapon):first_weapon.queue_free()
 first_weapon=null
 unit=null;overlay.hide();game.ui.show();game.speed=previous_speed
 game.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;game.camera.near=.02;game.set_camera(previous_camera,true)
 if game.ears:game.ears.position=Vector3(game.objective.x,1.2,game.objective.y)

func _exit_tree():
 if active:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func look_direction()->Vector3:
 return Basis.from_euler(Vector3(pitch,yaw,0))*Vector3.FORWARD

func aim_point()->Vector3:
 var start=game.camera.global_position;var direction=look_direction();var end=start+direction*8.0
 var hit=game.fx.trace(start,end,unit.id)
 if not hit.is_empty():end=hit.point
 if direction.y<-.0001:
  var t=(game.field.ground_height(unit.pos())-start.y)/direction.y
  if t>0 and t<start.distance_to(end):end=start+direction*t
 return end

func handle_input(event:InputEvent)->bool:
 if not active:return false
 if event is InputEventKey:
  if event.pressed:held_keys[event.physical_keycode]=true
  else:held_keys.erase(event.physical_keycode)
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_TAB,KEY_F6:leave();return true
   KEY_ESCAPE:
    held_keys.clear();trigger=false;aiming=false;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;return true
   KEY_V:perspective="first" if perspective=="third" else "third";camera_initialized=false
   KEY_C:crouched=not crouched
   KEY_E:toggle_cover()
   KEY_R:reload()
   KEY_G:throw_grenade()
   KEY_SPACE:game.paused=not game.paused;trigger=false;aiming=false
   KEY_M:game.fx.set_muted(not game.fx.muted)
 if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
  yaw=wrapf(yaw-event.relative.x*.0025,-PI,PI);pitch=clampf(pitch-event.relative.y*.0025,-1.15,.85)
 if event is InputEventMouseButton:
  if event.button_index==MOUSE_BUTTON_LEFT:
   if event.pressed and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:capture_mouse()
   else:trigger=event.pressed
  elif event.button_index==MOUSE_BUTTON_RIGHT:aiming=event.pressed
 return true

func toggle_cover():
 if game.paused or game.winner!="" or unit.grenade_time>=0:return
 if in_cover:
  in_cover=false;cover_arrived=false;unit.cover_id="";unit.cover_slot={};unit.cqb_stance="open";game.field.release(unit.id);message="离开掩体";return
 var nearest={};var distance=.20
 for c in game.field.covers:
  if not c.alive:continue
  for slot in game.field.slots(c):
   var d:float=unit.pos().distance_to(slot.position)
   if d<distance and game.field.walkable(slot.position) and game.field.segment_walkable(unit.pos(),slot.position) and game.field.reservations.get(slot.key,unit.id)==unit.id:
    nearest=slot.duplicate();distance=d
 if nearest.is_empty():message="靠近书堆、文件夹或纸盒后按 E";return
 game.field.reserve_slot(unit.id,nearest);unit.cover_slot=nearest;unit.cover_id=nearest.cover_id;in_cover=true;cover_arrived=false;crouched=true;message="掩体内：按住右键探身，松开缩回；E 离开"

func reload():
 if not active or game.paused or game.winner!="" or unit.reload_timer>0 or unit.grenade_time>=0:return
 if unit.ammo>=int(unit.weapon_config().magazine):return
 unit.reload_timer=float(unit.weapon_config().reload);game.fx.sound("reload",unit.position,-7)

func throw_grenade()->bool:
 if not active or game.paused or game.winner!="" or unit.grenade_count<=0 or unit.reload_timer>0 or unit.grenade_time>=0 or unit.actor.stepping or (in_cover and not aiming):return false
 var p=aim_point();var start=unit.aim_point();var delta=p-start
 if delta.length()>float(game.config.weapons.grenade.range):p=start+delta.normalized()*float(game.config.weapons.grenade.range)
 p.y=maxf(game.field.height+.004,p.y)
 throw_point=p;unit.grenade_point=p;unit.grenade_target=null;unit.grenade_count-=1;unit.grenade_time=0;unit.grenade_released=false;unit.state="grenade";unit.posture="stand";unit.actor.play("grenade_throw");return true

func fire_at(point:Vector3)->bool:
 if not active or game.paused or game.winner!="" or unit.hp<=0 or unit.cooldown>0 or unit.reload_timer>0 or unit.grenade_time>=0 or unit.actor.stepping:return false
 if in_cover and (not cover_arrived or not aiming):message="先按住右键探身再射击";return false
 if sprinting:return false
 # Movement clips face travel; don't twist the torso 180 degrees while strafing.
 if unit.actor.actual_speed>.02 and absf(angle_difference(unit.rotation.y,yaw))>.6:return false
 if unit.ammo<=0:reload();return false
 var cfg:Dictionary=unit.weapon_config();var start=unit.muzzle_position(point);var delta=point-start
 if delta.length()<.001:return false
 var end=start+delta.normalized()*minf(delta.length(),float(cfg.range))
 game.fx.launch_point(unit,end,unit.weapon,cfg);game.shots+=1;shots_fired+=1;unit.ammo-=1;unit.cooldown=float(cfg.cooldown);unit.actor.recoil=1
 unit.last_shot_at=game.elapsed;unit.last_shot_target="";unit.fire_until=game.elapsed+.22;unit.state="fire"
 if unit.actor.actual_speed<.02:unit.animate("fire")
 return true

func physics_tick(dt:float):
 if not active:return
 if unit.hp<=0 or game.winner!="":leave();return
 unit.actor_advanced=false
 unit.actor.aim_pitch=pitch if unit.actor.actual_speed<.02 else 0.0
 unit.cooldown=maxf(0,unit.cooldown-dt);unit.suppression=maxf(0,unit.suppression-dt*game.config.soldier.suppression_decay)
 unit.hp_fill.scale.x=maxf(.01,unit.hp/unit.max_hp);unit.ring.visible=false
 if unit.reload_timer>0:
  unit.reload_timer=maxf(0,unit.reload_timer-dt)
  if unit.reload_timer==0:unit.ammo=int(unit.weapon_config().magazine)
 if unit.grenade_time>=0:
  unit.grenade_time+=dt
  if unit.grenade_time>=.62 and not unit.grenade_released:
   unit.grenade_released=true
   if throw_point!=Vector3.INF:game.fx.launch_point(unit,throw_point,"grenade",game.config.weapons.grenade);game.shots+=1
  if unit.grenade_time>=1.267:unit.grenade_time=-1;unit.grenade_point=Vector3.INF;throw_point=Vector3.INF
  return
 if sample_input:
  input_axis=Vector2(float(held_keys.has(KEY_D))-float(held_keys.has(KEY_A)),float(held_keys.has(KEY_W))-float(held_keys.has(KEY_S))) if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and game.get_window().has_focus() else Vector2.ZERO
  sprinting=held_keys.has(KEY_SHIFT) and not aiming and not crouched and not in_cover
 if in_cover and not game.field.covers.any(func(c):return c.id==unit.cover_id and c.alive):in_cover=false;unit.cover_id="";unit.cover_slot={};message="掩体被击毁"
 if in_cover and input_axis.length()>.1:toggle_cover()
 unit.posture="crouch" if crouched or in_cover else "stand";unit.cqb_stance="open"
 var direction=Basis(Vector3.UP,yaw)*Vector3(input_axis.x,0,-input_axis.y).limit_length(1)
 # Deliberate aimed stance. Moving releases precise ADS instead of sliding feet.
 var moving=direction.length()>.01
 var target=Vector3.INF;var lateral=false
 if in_cover:
  var slot:Dictionary=unit.cover_slot
  var point:Vector2=slot.peek if aiming and slot.hard else slot.position
  target=Vector3(point.x,unit.position.y,point.y)
  var distance=Vector2(target.x-unit.position.x,target.z-unit.position.z).length()
  if not cover_arrived and distance<.003:cover_arrived=true
  moving=distance>.002
  lateral=cover_arrived and slot.hard
  unit.cqb_stance="peek" if aiming and cover_arrived else "hide"
  unit.posture="stand" if aiming and not slot.hard else "crouch"
 elif moving:target=unit.position+direction*.30
 if moving:
  if not lateral:unit.rotation.y=atan2(- (target.x-unit.position.x),- (target.z-unit.position.z))
  else:unit.rotation.y=atan2(-unit.cover_slot.normal.x,-unit.cover_slot.normal.y)
  if not unit.actor.stepping:unit.actor.rotation.y=unit.rotation.y+PI
  var gait="crouch_run" if unit.posture=="crouch" else ("sprint" if sprinting else "run")
  var velocity:float=game.config.tactics.crouch_speed if gait=="crouch_run" else (game.config.tactics.sprint_speed if sprinting else game.config.tactics.run_speed)
  unit.actor.drive_limit=unit.position.distance_to(target) if in_cover else INF
  unit.actor.advance_drive(target,velocity,dt,lateral,gait);unit.global_position=unit.actor.global_position;unit.actor_advanced=true;unit.state="move";unit.locomotion="cover_step" if lateral else gait
 else:
  unit.rotation.y=yaw;unit.locomotion="idle";unit.state="cover" if in_cover else "aim"
  unit.animate("reload" if unit.reload_timer>0 else ("fire" if game.elapsed<unit.fire_until else "aim"))
 unit.goal=unit.pos();unit.route.clear()
 if trigger and (not sample_input or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED):fire_at(aim_point())

func update_camera(dt:float):
 if not active:return
 if unit.hp<=0 or game.winner!="":leave();return
 if not game.get_window().has_focus():trigger=false;aiming=false
 var eye=unit.global_position+Vector3.UP*(.070 if unit.posture=="crouch" else .112)
 var direction=look_direction();var desired=eye
 if perspective=="third":
  var right=Basis(Vector3.UP,yaw)*Vector3.RIGHT
  desired=eye-direction*(.20 if aiming else .34)+right*.045+Vector3.UP*.025
  var query=PhysicsRayQueryParameters3D.create(eye,desired,1);query.exclude=[unit.actor.get_rid()]
  var hit=game.get_world_3d().direct_space_state.intersect_ray(query)
  if not hit.is_empty():desired=hit.position+hit.normal*.015
  desired.y=maxf(desired.y,game.field.ground_height(unit.pos())+.025)
 game.camera.global_position=desired if not camera_initialized or perspective=="first" else game.camera.global_position.lerp(desired,1-exp(-dt*22))
 # Never allow interpolation to trail through a wall after the collision clamp.
 if perspective=="third":
  var hit=game.field.trace_cover(eye,game.camera.global_position)
  if not hit.is_empty():game.camera.global_position=hit.point+(eye-hit.point).normalized()*.012
 game.camera.look_at(game.camera.global_position+direction,Vector3.UP);game.camera.fov=55 if aiming else 76;camera_initialized=true
 unit.actor.model.visible=perspective!="first"
 unit.actor.weapon.visible=perspective!="first" and unit.grenade_time<0
 if is_instance_valid(first_weapon):
  first_weapon.visible=perspective=="first" and unit.grenade_time<0
  # Presentation only; authoritative muzzle/cover traces remain on the soldier.
  var bob=sin(unit.actor.roots_travelled*90)*minf(unit.actor.actual_speed,.2)*.006
  first_weapon.rotation=Vector3(-.06,PI if unit.actor.attachments[unit.weapon].forward_sign>0 else 0.0,-.22 if unit.reload_timer>0 else 0.0)
  first_weapon.position=Vector3(.010 if aiming else .022,-.013 if aiming else -.024+bob,-.040+unit.actor.recoil*.003)

 if game.ears:game.ears.global_position=eye
 objective_readout.text=""
 if game.flag_objective and game.flag_objective.holder!="":
  objective_readout.text=("立即夺回旗帜！ " if game.flag_objective.emergency_for(unit.faction) else "守住旗帜 ")+game.flag_objective.holder.to_upper()+"  "+str(ceili(game.flag_objective.remaining()))+" 秒"+(" · 争夺中" if game.flag_objective.contested else "")
 sight.modulate=Color(.92,.80,.48) if in_cover and not aiming else Color(.91,.96,.87)
 readout.text=("第一人称" if perspective=="first" else "第三人称")+"  ·  "+unit.id+"  HP "+str(int(unit.hp))+"  "+unit.weapon.to_upper()+" "+str(unit.ammo)+"/"+str(int(unit.weapon_config().magazine))+"  手雷 "+str(unit.grenade_count)+( "  换弹中" if unit.reload_timer>0 else "")+"\nWASD 移动 · Shift 冲锋 · 鼠标瞄准 / 左键射击 · 右键瞄准/探身 · C 蹲姿 · E 掩体 · R 换弹 · G 手雷\nV 切换人称 · Tab 返回 RTS · Esc 释放鼠标 · 点击画面锁定鼠标\n"+message

func snapshot()->Dictionary:
 return {"active":active,"unit_id":unit.id if active else "","perspective":perspective,"in_cover":in_cover,"aiming":aiming,"mouse_captured":Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"input_axis":[input_axis.x,input_axis.y],"held_keys":held_keys.keys(),"shots_fired":shots_fired,"message":message}
