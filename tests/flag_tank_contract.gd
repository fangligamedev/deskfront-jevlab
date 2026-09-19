extends SceneTree
var failures: Array=[]
var checks:int=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred('run')
func run():
 var flag=load('res://scripts/flag_objective.gd').new();flag.required_seconds=30
 check(flag.advance(['green'],12)=='','short hold cannot win')
 check(flag.advance(['green','red'],10)=='' and flag.held_seconds==12,'contested flag pauses clock')
 flag.advance([],1);check(flag.holder=='' and flag.held_seconds==0,'abandoned flag resets progress')
 flag.advance(['blue'],29);check(flag.advance(['red'],1)=='' and flag.held_seconds==1,'new holder restarts clock')
 check(flag.advance(['red'],29)=='red','30 continuous seconds wins');flag.free()
 var g=load('res://scenes/main.tscn').instantiate();root.add_child(g);g.set_physics_process(false);g.paused=true
 check(g.units.size()==9 and g.reserve_tank!=null,'tank visible in reserve without counting as active soldier')
 var t=g.reserve_tank;check(t.deployment_phase=='parked' and t.pos().y<g.config.bounds[1],'tank parks above battlefield')
 var start: Vector2=t.pos();var shots:int=g.shots;t.fire(g.units[0]);check(g.shots==shots,'parked tank cannot fire directly')
 check(g.spawn_tank() and not g.spawn_tank(),'single reinforcement')
 check(t.available_actions().is_empty() and not g.living().has(t),'entering tank has no combat authority')
 t.tick(1);check(t.pos().distance_to(start)>.03 and t.pos().distance_to(start)<.08,'tank enters gradually at configured speed')
 t.fire(g.units[0]);check(g.shots==shots,'entering tank cannot fire')
 for i in range(900):t.tick(1.0/60)
 check(t.deployment_phase=='active' and g.field.walkable(t.pos(),true),'tank arrives at walkable battlefield entry')
 check(g.living().has(t) and t.available_actions().has('attack'),'arrival enables tank combat')
 var body=t.model.find_child('Tank_body',true,false);var gun=t.model.find_child('Tank_Gun',true,false);var head=t.model.find_child('Tank_Turret',true,false)
 var box: AABB=t.global_transform.affine_inverse()*body.global_transform*body.get_aabb()
 var gunbox: AABB=t.global_transform.affine_inverse()*gun.global_transform*gun.get_aabb()
 var headbox: AABB=t.global_transform.affine_inverse()*head.global_transform*head.get_aabb()
 check(box.size.x>.1 and box.size.z>.15 and box.size.y<.12,'visible hull has horizontal toy-sized bounds')
 check(gunbox.size.z>.05 and headbox.size.x>.06,'gun and turret no longer microscopic')
 check(t.muzzle.global_position.distance_to(t.global_position)<.25 and t.muzzle.global_position.y>g.field.height,'muzzle belongs to visible tank')
 g.winner='';g.elapsed=5;g.paused=false
 for u in g.units:
  u.position.x=-2
  if u.faction!='green':u.hp=0
 g._physics_process(.1);check(g.winner=='','elimination alone is not flag victory')
 # Isolated flag navigation: healthy soldiers must navigate props and actually finish.
 for u in g.units:u.hp=0;u.route.clear()
 var scout=g.units[0];scout.hp=scout.max_hp;scout.suppression=0;scout.safety_until=0
 scout.position=Vector3(.446,g.field.height,2.36);scout.gun_id="";scout.garrison_phase=""
 g.control.green="game_ai";g.tactics_ai.flag_next.clear();g.tactics_ai.squads.clear()
 check(not g.tactics_ai.flag_options(scout).is_empty(),'healthy idle scout gets a navigable next flag step')
 scout.hp=scout.max_hp*.2
 check(g.tactics_ai.flag_options(scout).is_empty(),'critical scout is not forced into flag assault')
 scout.hp=scout.max_hp
 for i in range(5000):
  g._physics_process(1.0/60)
  if g.winner!="":break
 check(g.winner=='green','healthy isolated AI navigates into circle and holds to victory')
 check(scout.order_mode=='hold','flag defender holds position after arriving')
 print('FLAG_TANK_CONTRACT ',JSON.stringify({'passed':failures.is_empty(),'checks':checks,'failures':failures,'hull_size':str(box.size),'turret_size':str(headbox.size),'gun_size':str(gunbox.size)}))
 quit(0 if failures.is_empty() else 1)
