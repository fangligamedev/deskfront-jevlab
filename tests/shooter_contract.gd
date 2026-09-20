extends SceneTree
var checks:Array=[]
func _initialize():call_deferred('run')
func check(ok:bool,label:String):
 checks.append({'test':label,'passed':ok})
 if not ok:push_error(label)
func warp(u,p:Vector2):
 u.position=Vector3(p.x,u.game.field.ground_height(p),p.y);u.actor.global_position=u.global_position;u.actor.advance_idle(1.0/60)
func step(g,n:int):
 for i in n:
  g.elapsed+=1.0/60;g.shooter.physics_tick(1.0/60)
  if g.shooter.active:g.shooter.unit.presentation_tick(1.0/60)
  g.fx.physics_tick(1.0/60)
func run():
 var g=load('res://scenes/main.tscn').instantiate();root.add_child(g);g.set_physics_process(false);g.set_process(false);g.fx.set_muted(true)
 for team in g.control:g.control[team]='lm'
 var u=g.units[0];var enemy=g.units[6]
 for v in g.units:v.selected=v==u
 var s=g.shooter;s.sample_input=false
 check(s.enter(u.id),'selected infantry can be possessed')
 check(u.direct_controlled and g.control.green=='lm','possession leaves team AI mode unchanged')
 check(u.available_actions().is_empty(),'possessed unit advertises no model actions')
 var cmd={'action':'move','position':[1.49,2.15],'source':'lm','faction':'green','unit_ids':[u.id],'run_id':g.run_id,'seen_tick':g.tick_id,'control_epoch':g.control_epochs.green}
 check(g.command(cmd).message=='unit_directly_controlled','in-flight model order cannot overwrite local player')
 cmd.unit_ids=[g.units[1].id];check(g.command(cmd).accepted,'teammate still accepts its model order')
 check(not g.command({'action':'possess','source':'agent','faction':'green','run_id':g.run_id,'seen_tick':g.tick_id}).accepted,'agent cannot seize the player camera')
 for v in g.units:
  if v!=u and v!=enemy:v.hp=0
 warp(u,Vector2(1.92,3.37));warp(enemy,Vector2(2.8,2.4))
 var original=u.pos();s.yaw=0;s.input_axis=Vector2(0,1);s.sprinting=true
 step(g,60)
 check(u.pos().distance_to(original)>.18 and u.actor.roots_travelled>.18,'direct input drives real root motion with sprint acceleration')
 s.input_axis=Vector2.ZERO;s.sprinting=false;step(g,5)
 var stopped=u.pos();step(g,30);check(u.pos().distance_to(stopped)<.00001,'releasing input stops movement without residual slide')
 warp(u,Vector2(1.92,3.37));warp(enemy,Vector2(1.92,3.07));enemy.posture='stand';u.cooldown=0
 var ammo=u.ammo;var hp=enemy.hp
 check(s.fire_at(enemy.aim_point()),'manual free aim fires a real projectile')
 check(u.ammo==ammo-1 and not s.fire_at(enemy.aim_point()),'ammo and cooldown apply to player fire')
 step(g,30);check(enemy.hp<hp,'swept projectile inflicts real target damage')
 var before=u.ammo;s.reload();check(u.reload_timer>0 and not s.fire_at(enemy.aim_point()),'reload blocks fire')
 step(g,240);check(u.ammo==int(u.weapon_config().magazine) and u.ammo>before,'reload completes through simulation time')
 warp(u,Vector2(2.63,1.00));warp(enemy,Vector2(2.63,1.94));u.cooldown=0;hp=enemy.hp
 s.fire_at(enemy.aim_point());step(g,120);check(enemy.hp==hp,'printer blocks player rounds; aiming does not shoot through cover')
 var cover=g.field.covers.filter(func(c):return c.id=='west-book-cover')[0];var slot=g.field.slots(cover)[0]
 warp(u,slot.position-slot.normal*.06);s.toggle_cover();check(s.in_cover and u.cover_id!='','E equivalent reserves nearby physical cover')
 step(g,160);check(s.cover_arrived and u.posture=='crouch','soldier physically approaches cover and crouches')
 u.cooldown=0;check(not s.fire_at(enemy.aim_point()),'hidden soldier cannot fire through cover')
 s.aiming=true;step(g,10);check(u.posture=='stand' and u.cqb_stance=='peek','aiming exposes soldier above low cover')
 var grenades=u.grenade_count;s.update_camera(0)
 check(s.throw_grenade(),'player can throw toward crosshair without locking an enemy')
 step(g,100);check(u.grenade_count==grenades-1 and int(g.fx.launched.get('grenade',0))>0,'grenade inventory and delayed animation release are authoritative')
 s.perspective='first';s.update_camera(0);check(not u.actor.model.visible and g.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,'first person hides own body and uses perspective camera')
 s.in_cover=false;s.aiming=false
 var hard_cover=g.field.covers.filter(func(c):return c.kind=="hard" and c.id.contains("printer"))[0]
 var hard_slot=g.field.slots(hard_cover)[0];warp(u,hard_slot.position-hard_slot.normal*.05);s.toggle_cover();step(g,160)
 check(s.in_cover and s.cover_arrived and u.cover_slot.hard,'hard cover approached without teleporting')
 var resting=u.pos();s.aiming=true;step(g,360)
 check(u.pos().distance_to(resting)>.015 and u.pos().distance_to(u.cover_slot.peek)<.008,'right aim physically steps out around hard cover corner')
 s.aiming=false;step(g,360)
 check(u.pos().distance_to(resting)<.008,'releasing aim returns behind hard cover')
 u.grenade_count=1;u.grenade_time=-1;s.in_cover=false;s.aiming=false;u.reload_timer=0
 check(s.throw_grenade(),'can begin a second throw before returning to RTS')
 var launched=int(g.fx.launched.get('grenade',0));s.leave()
 for i in 85:u.tick(1.0/60);u.presentation_tick(1.0/60)
 check(int(g.fx.launched.get('grenade',0))==launched+1,'in-flight grenade animation completes exactly once after RTS handoff')
 check(not u.direct_controlled and u.actor.model.visible and g.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and g.ui.visible,'return to RTS restores camera body HUD and authority')
 check(not s.enter(g.reserve_tank.id),'tank cannot enter infantry shooter mode')
 g.paused=true;check(not s.enter(u.id),'paused battle does not silently resume');g.paused=false
 check(s.enter(u.id),'can re-enter after returning to RTS');u.hit(10000,1,u.position,.1);s.physics_tick(.016)
 check(not s.active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,'death returns to RTS and releases pointer')
 var result={'passed':checks.all(func(c):return c.passed),'checks':checks}
 FileAccess.open('res://docs/evidence/shooter/contracts.json',FileAccess.WRITE).store_string(JSON.stringify(result,'  '));print('SHOOTER_CONTRACT ',JSON.stringify(result));quit(0 if result.passed else 1)
