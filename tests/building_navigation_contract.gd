extends SceneTree
var g
var checks:Array=[]
func _initialize():call_deferred('run')
func check(ok:bool,label:String):
 checks.append({'test':label,'passed':ok})
 if not ok:push_error(label)
func tick(u):
 g.elapsed+=1.0/60;u.cooldown=999;g.building.tick(1.0/60);u.tick(1.0/60);u.presentation_tick(1.0/60)
 await physics_frame
func fixture():
 if is_instance_valid(g):g.queue_free();await process_frame;await process_frame
 g=load('res://scenes/main.tscn').instantiate();root.add_child(g);g.set_physics_process(false);g.set_process_unhandled_input(false);g.fx.set_muted(true)
 for team in g.control:g.control[team]='player'
 for u in g.units:
  u.cooldown=999
  if u.faction=='blue' and u.id!='blue-1':u.position=Vector3(.4+u.get_index()*.03,g.field.height,2.5);u.actor.global_position=u.position
 await physics_frame
func settle(u,phase:String,limit=2200):
 for i in limit:
  await tick(u)
  if u.garrison_phase==phase:return true
 return false
func run():
 await fixture()
 var worker_names=g.worker.find_children('*','MeshInstance3D',true,false).map(func(m):return m.name)
 check(worker_names.any(func(n):return 'Suit' in n) and not worker_names.any(func(n):return 'Casual' in n),'Approved Business Man is instantiated in the main game')
 check(g.units.all(func(u):return u.animation_names.size()>=28),'Existing soldier upgrade retains at least 28 animation clips')
 check(g.building.parts.any(func(p):return p.id=='landing_threshold'),'Stair threshold remains physical and destructible')
 for member in 3:
  await fixture();var unit=g.units[3]
  # Test each ground-floor station with the actual main-game soldier.
  unit.id='blue-'+str(member+1)
  check(g.building.enter(unit,1) and await settle(unit,'stationed'),'Ground-floor window '+str(member))
 for at in [90,320,570]:
  await fixture();var u=g.units[3]
  check(g.building.enter(u,2),'Upper-floor order at '+str(at))
  for i in at:await tick(u)
  g.building.leave(u)
  check(await settle(u,''),'Mid-ascent evacuation completes at '+str(at))
  check(g.building.enter(u,2) and await settle(u,'stationed'),'Re-entry reaches the window at '+str(at))
 await fixture();var u=g.units[3]
 g.building.enter(u,2)
 u.position=Vector3(1.10,.857,1.74);u.actor.global_position=u.position
 u.garrison_path.assign([Vector3(1.285,.857,1.13)])
 check(await settle(u,'stationed') and u.path_repairs>0,'Wall-cut path repairs into a valid root-motion route')
 check(u.actor.roots_travelled>.3,'Building navigation retains authoritative root motion')
 var report={'passed':checks.all(func(c):return c.passed),'checks':checks}
 var f=FileAccess.open('res://output/asset-application/building.json',FileAccess.WRITE);f.store_string(JSON.stringify(report,'  '));f.close()
 g.queue_free();await process_frame;await process_frame;quit(0 if report.passed else 1)
