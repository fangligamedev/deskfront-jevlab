extends Node
var game
var phase:String="building"
var steps_done:Array=[]
var entries:Array=[]
var targets:Dictionary={}
var routes:Dictionary={}
var pending:Array=[]
var clock:float=0
var running:bool=true
var driver:String="local_rehearsal"
func setup(g):
 game=g;game.paused=true;driver=str(get_tree().get_meta("demo_driver","local_rehearsal"))
 game.office_root.hide();game.worker.hide()
 for body in game.office_root.find_children("*","CollisionObject3D",true,false):body.collision_layer=0
 for body in game.worker.find_children("*","CollisionObject3D",true,false):body.collision_layer=0
 var scene=preload("res://scripts/demo_scene.gd").new();game.add_child(scene);scene.setup(game.config.bounds)
 game.camera_target=Vector3(game.objective.x,.85,game.objective.y);game.camera_size=3.8;game.camera_mode="battle"
 for row in game.arena.props:
  if str(row.spec.id).begins_with("studio-cover-"):row.node.hide();row.node.collision_layer=0;pending.append(row)
 for u in game.units:
  targets[u.id]=u.position
  u.deployment_phase="parked";u.state="idle";u.order_mode="reserve";u.route.clear()
  if u.faction=="blue":u.hide();continue
  var b=game.config.bounds;var x:float=b[0]-.21 if u.faction=="green" else b[2]+.21
  u.position=Vector3(x,game.field.height,game.objective.y+(int(u.id.get_slice("-",1))-2)*.14)
  if u.actor:
   u.actor.global_position=u.global_position
   u.actor.navigation_guard=func(p:Vector3):return p.x<b[0] or p.x>b[2] or game.field.walkable(Vector2(p.x,p.z))
 if game.building:game.building.show()
 for gun in game.at_guns:gun.show()
 if game.reserve_tank:
  game.reserve_tank.show();game.reserve_tank.position=Vector3(game.config.bounds[2]+.19,game.field.height,game.config.bounds[3]-.3)
  for body in game.reserve_tank.find_children("*","CollisionObject3D",true,false):body.collision_layer=0
 event("演示就绪：两位玩家、两侧待命兵力；已校验方案等待逐步搭建")
func event(message:String):
 entries.append({"at":snappedf(clock,.01),"tick":game.tick_id,"phase":phase,"message":message});game.add_event(message)
func options()->Array:
 var result:Array=[]
 if phase=="building":
  for row in pending:
   if not steps_done.has(row.spec.id):result.append({"id":row.spec.id,"action":"place_cover","object":row.spec})
 elif phase=="deploying":
  for u in game.units:
   if u.faction in ["green","red"] and u.deployment_phase=="parked":result.append({"id":"deploy:"+u.id,"action":"deploy_unit","unit":u.id,"faction":u.faction,"weapon":u.weapon})
 elif phase=="ready":result.append({"id":"start_battle","action":"start_battle"})
 return result
func execute(id:String)->String:
 if not running:return "demo_paused"
 if not options().any(func(o):return o.id==id):return "demo_step_unavailable"
 if phase=="building":
  for row in pending:
   if row.spec.id==id:row.node.show();row.node.collision_layer=1;steps_done.append(id);event("编辑器放置 "+row.spec.kind+" · "+id)
  if steps_done.size()==pending.size():phase="deploying";event("关卡搭建完成；开始从桌边派兵")
 elif phase=="deploying":
  var uid=id.trim_prefix("deploy:")
  for u in game.units:
   if u.id==uid:
    routes[uid]=u.navigation_path(Vector2(targets[uid].x,targets[uid].z))
    if routes[uid].is_empty():return "demo_deployment_path_unavailable"
    u.deployment_phase="entering";u.state="move";u.order_mode="deploying";event(uid+" 从桌边入场")
 elif phase=="ready":
  phase="battle";game.paused=false;event("双方兵力已就位；开始夺旗博弈")
 return "applied"
func tick(delta:float):
 if not running or phase=="finished":return
 clock+=delta
 if phase=="deploying":
  var active:int=0
  for u in game.units:
   if u.faction=="blue":continue
   if u.deployment_phase=="entering":
    var path:PackedVector2Array=routes[u.id]
    while not path.is_empty() and u.pos().distance_to(path[0])<.014:path.remove_at(0)
    routes[u.id]=path
    var target:Vector3=targets[u.id] if path.is_empty() else Vector3(path[0].x,game.field.height,path[0].y)
    var d:Vector3=target-u.position
    u.rotation.y=atan2(-d.x,-d.z);u.locomotion="run"
    if u.actor:
     u.actor.rotation.y=u.rotation.y+PI;u.actor.advance_drive(target,.18,delta,false,"run");u.global_position=u.actor.global_position
    else:u.position=u.position.move_toward(target,.18*delta)
    if path.is_empty() and u.pos().distance_to(Vector2(target.x,target.z))<.014:u.deployment_phase="active";u.state="idle";u.goal=u.pos();u.order_mode="hold";event(u.id+" 到达部署位")
   if u.deployment_phase=="active":active+=1
  if active==6:phase="ready";event("双方各三名士兵已入场，等待开战")
 if phase=="battle" and game.winner!="":phase="finished";event("夺旗结束 · "+game.winner+"；等待战后报告")
func snapshot()->Dictionary:
 return {"enabled":true,"phase":phase,"clock":snappedf(clock,.1),"running":running,"driver":driver,"participants":["green","red"],"human_count":2,"completed":steps_done,"steps":options(),"timeline":entries,"deployed":game.units.filter(func(u):return u.faction!="blue" and u.deployment_phase=="active").size()}
