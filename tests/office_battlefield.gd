extends SceneTree
var checks:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks.append({"test":label,"passed":ok})
 if not ok:push_error(label)
func run():
 set_meta('deskfront_map',3)
 var g=load('res://scenes/main.tscn').instantiate();root.add_child(g);g.set_physics_process(false);g.fx.set_muted(true)
 for team in g.control:g.control[team]='player'
 await physics_frame
 check(g.map_data.id=='office-front','new default office map loads')
 check(is_equal_approx(g.map_data.design.table_width_after,2*g.map_data.design.table_width_before),'right desk is twice the original width')
 check(g.building==null and g.at_guns.is_empty(),'no miniature buildings or gun emplacements on office map')
 check(not g.arena.map_root.get_node('map_surface').get_child(0).visible and g.arena.map_root.find_children('rim*').is_empty(),'no visible sandbox base or rim')
 check(g.map_data.objects.all(func(o):return o.kind in ['books','binder','keyboard','filebox','printer','stapler','mug']),'all tactical obstacles are office equipment')
 var routes=[]
 for u in g.units:
  check(g.field.walkable(u.pos()),u.id+' spawns on unobstructed desk')
  var route=g.field.path(u.pos(),g.objective)
  check(route.size()>1 and route[-1].distance_to(g.objective)<.04,u.id+' can reach flag')
  routes.append({'id':u.id,'distance':g.field.route_length(route)})
 var approaches=0
 for i in 8:
  var p=g.objective+Vector2.from_angle(i*TAU/8)*.25
  if g.field.segment_walkable(p,g.objective):approaches+=1
 check(approaches>=4,'flag has at least four unobstructed approach directions')
 for row in g.arena.props:
  var spec=row.spec;var p=Vector2(spec.position[0],spec.position[1]);var cover=g.field.covers.filter(func(c):return c.id==spec.id)[0]
  check(not g.field.walkable(p),'navigation blocks '+spec.id)
  check(cover.node==row.node and cover.label==spec.asset,'visible model and AI cover share identity: '+spec.id)
  check(not g.field.cover_ray(cover,Vector3(p.x-1,g.field.height+spec.size[1]*.5,p.y),Vector3(p.x+1,g.field.height+spec.size[1]*.5,p.y)).is_empty(),'office prop blocks actual projectile ray: '+spec.id)
 var c=g.field.covers.filter(func(v):return v.id=='west-book-cover')[0]
 var slots=g.field.slots(c)
 check(not slots.is_empty(),'book stack exposes reservable cover slots')
 var slot=slots[0]
 check(g.field.protection(slot.position,slot.position+slot.normal*.5)>.3,'book cover reduces frontal exposure')
 var box=g.field.covers.filter(func(v):return v.id=='east-archive')[0];var box_pos=Vector2(box.position[0],box.position[1]);var revision=g.field.revision
 check(g.field.damage_cover(box.id,99999),'cardboard box is destructible')
 check(not box.node.visible and box.node.collision_layer==0 and g.field.walkable(box_pos) and g.field.revision>revision,'destroying cardboard updates visuals collision and navigation together')
 check(not g.field.damage_cover('east-printer',99999),'printer remains a hard office obstacle')
 g.spawn_tank();var tank=g.reserve_tank
 for i in 900:tank.tick(1.0/60)
 check(tank.deployment_phase=='active','tank enters expanded office desk')
 var tank_path=g.field.path(tank.pos(),g.objective,true)
 check(tank_path.size()>1 and tank_path[-1].distance_to(g.objective)<.04,'tank has a hull-width route to flag')
 var u=g.units[0]
 for v in g.units:
  if v!=u:v.hp=0
 u.posture_order='stand';u.move_to(g.objective)
 for i in 1800:
  g.elapsed+=1.0/60;u.tick(1.0/60);u.presentation_tick(1.0/60)
  if u.route.is_empty():break
 check(u.pos().distance_to(g.objective)<.04 and u.actor.roots_travelled>1,'real root-motion soldier traverses office props and reaches flag')
 var report={'passed':checks.all(func(c):return c.passed),'checks':checks,'routes':routes,'approaches':approaches,'bounds':g.config.bounds,'final_position':[u.pos().x,u.pos().y]}
 FileAccess.open('res://docs/evidence/office-battlefield/contracts.json',FileAccess.WRITE).store_string(JSON.stringify(report,'  '))
 print('OFFICE_BATTLEFIELD ',JSON.stringify(report));quit(0 if report.passed else 1)
