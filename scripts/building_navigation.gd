extends RefCounted
# Explicit connected walkable corridors. Every edge and start attachment is swept
# with the soldier capsule; floors are connected only through the supported ramp.
var graph=AStar3D.new()
var body:CharacterBody3D
var building:Node3D
var ground_slots:Array[Vector3]=[]
var upper_slots:Array[Vector3]=[]
var clearance:CapsuleShape3D
var actor_shape:Shape3D
func setup(owner_building,actor):
 building=owner_building;body=actor
 actor_shape=body.find_children("*","CollisionShape3D",false,false)[0].shape
 clearance=CapsuleShape3D.new();clearance.radius=.018;clearance.height=.119
 rebuild()
func rebuild():
 graph.clear();ground_slots.clear();upper_slots.clear()
 var s=building.spec
 var x=float(s.center[0]);var z=float(s.center[1]);var front=z+float(s.size[1])/2
 var sx=float(s.stair_x);var toe=float(s.stair_front);var back=float(s.stair_back)
 var gy=.857;var low=.844;var high=building.floor_y+.006
 var approach=Vector3(x+.08,gy,maxf(front+.24,toe+.09))
 var foot=Vector3(sx,low,approach.z)
 corridor(Vector3(x-.11,gy,approach.z),approach)
 corridor(Vector3(x+.08,gy,approach.z+.13),approach)
 corridor(approach,foot)
 corridor(approach,Vector3(x+.08,gy,front-.08))
 corridor(foot,Vector3(sx,low,toe))
 corridor(Vector3(sx,low,toe),Vector3(sx,high,back))
 corridor(Vector3(sx,high,back),Vector3(sx,high,back-.05))
 corridor(Vector3(sx,high,back-.05),Vector3(x+.12,high,back-.05))
 var hub=Vector3(x+.02,high,z)
 corridor(Vector3(x+.12,high,back-.05),hub)
 for i in 3:
  var ground=Vector3(x-.13,gy,z-.17+i*.17)
  var upper=Vector3(x-.15,high,z-.17+i*.17)
  ground_slots.append(ground);upper_slots.append(upper)
  corridor(Vector3(x+.08,gy,front-.08),ground)
  corridor(hub,upper)
func point(p:Vector3)->int:
 for id in graph.get_point_ids():
  if graph.get_point_position(id).distance_to(p)<.0001:return id
 var id=graph.get_available_point_id();graph.add_point(id,p);return id
func corridor(a:Vector3,b:Vector3):
 var count=maxi(1,ceili(a.distance_to(b)/.035));var previous=point(a)
 for i in range(1,count+1):
  var p=a.lerp(b,float(i)/count);var id=point(p)
  if clear_segment(graph.get_point_position(previous),p):graph.connect_points(previous,id)
  previous=id
func clear_segment(a:Vector3,b:Vector3,departing=false)->bool:
 var space=body.get_world_3d().direct_space_state
 var q=PhysicsShapeQueryParameters3D.new();q.shape=actor_shape if departing else clearance
 q.transform=Transform3D(Basis.IDENTITY,a+Vector3.UP*.065)
 q.collision_mask=1;q.margin=.0001 if departing else .0003;q.exclude=[body.get_rid()]
 if not space.intersect_shape(q,1).is_empty():
  # Tiny-scale contacts can report a shallow overlap after move_and_collide.
  # Allow separation along the contact normal, never deeper movement through it.
  if not departing:return false
  var contact=space.get_rest_info(q)
  if contact.is_empty() or (b-a).dot(contact.normal)<=.0001:return false
 q.motion=b-a
 if space.cast_motion(q)[0]<.999:return false
 # Prevent a shortcut across unsupported air or between storeys.
 var n=maxi(1,ceili(a.distance_to(b)/.005))
 for i in range(n+1):
  var p=a.lerp(b,float(i)/n)
  var ray=PhysicsRayQueryParameters3D.create(p+Vector3.UP*.012,p-Vector3.UP*.040,1)
  var hit=space.intersect_ray(ray)
  if hit.is_empty() or hit.normal.y<.7 or p.y-hit.position.y<-.005:return false
 return true
func route(start:Vector3,floor_number:int,member:int)->Array:
 if building.collapsed:return []
 rebuild()
 var goal=ground_slots[member] if floor_number==1 else upper_slots[member]
 return route_to(start,goal)
func route_to(start:Vector3,goal:Vector3)->Array:
 if building.collapsed:return []
 rebuild()
 var target=graph.get_closest_point(goal)
 var candidates=Array(graph.get_point_ids())
 candidates.sort_custom(func(a,b):return graph.get_point_position(a).distance_squared_to(start)<graph.get_point_position(b).distance_squared_to(start))
 var best:Array=[];var best_cost=INF;var visible=0
 for id in candidates:
  var p=graph.get_point_position(id)
  if not clear_segment(start,p,true):continue
  var path=graph.get_point_path(id,target)
  if path.is_empty():continue
  var cost=start.distance_to(path[0])
  for i in range(1,path.size()):cost+=path[i-1].distance_to(path[i])
  if cost<best_cost:best_cost=cost;best=Array(path)
  visible+=1
  if visible>=8:break
 # Remove only physically verified shortcuts, keeping the ramp/platform turns.
 var result:Array=[];var from=start
 while not best.is_empty():
  var next=0
  for i in range(best.size()-1,-1,-1):
   if clear_segment(from,best[i],result.is_empty()):next=i;break
  from=best[next];result.append(from);best=best.slice(next+1)
 if not result.is_empty() and result[-1].distance_to(goal)>.001 and clear_segment(result[-1],goal):result.append(goal)
 return result
