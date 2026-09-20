extends RefCounted
## Visible reserves, model-authorized release, swept navigation before combat activation.
var front
var reserves:Array=[]
func setup(f):front=f
func prepare(ch:Dictionary):
 var g=front.game
 if ch.get("battle_plan",{}).is_empty():return
 for team in ["green","red"]:
  var p=ch.battle_plan.armor[team]
  if not p.enabled:continue
  # At most one surviving tank per side. Reuse it across streamed checkpoints.
  var existing=g.units.filter(func(u):return u.tank and u.faction==team and u.hp>0)
  if not existing.is_empty():
   var u=existing[0];u.armor_role=p.role
   for row in reserves:
    if row.unit!=u.id:continue
    row.sector=ch.index;row.role=p.role;row.source=ch.source
    if u.deployment_phase=="parked":row.release_at=front.logical+float(p.delay)
   continue
  var x:float=maxf(g.config.bounds[0]+.20,ch.index*float(front.rules.width)-.45) if team=="green" else (ch.index+1)*float(front.rules.width)-.18
  var spawn:=Vector2(x,float(front.rules.half_depth)-.24);var goal:=Vector2(x+(.24 if team=="green" else -.24),float(front.rules.half_depth)-.24)
  var path:PackedVector2Array=g.field.path(spawn,goal,true)
  if path.is_empty():
   for lane in [-float(front.rules.half_depth)+.24,0.0,.60,-.60]:
    spawn.y=lane;goal.y=lane;path=g.field.path(spawn,goal,true)
    if not path.is_empty():break
  if path.is_empty():front.emit("armor_blocked",{"team":team,"sector":ch.index});continue
  spawn=path[0];goal=path[-1]
  var u=g.spawn_unit(team+"-tank-e"+str(ch.index),team,spawn,true)
  u.deployment_phase="parked";u.order_mode="reserve";u.armor_role=p.role;u.rotation.y=-PI/2 if team=="green" else PI/2
  reserves.append({"unit":u.id,"team":team,"sector":ch.index,"release_at":front.logical+float(p.delay),"goal":goal,"planned_delay":p.delay,"role":p.role,"source":ch.source})
  front.emit("armor_reserved",{"unit":u.id,"team":team,"sector":ch.index,"source":ch.source})
func release(selection:String,source:String):
 var g=front.game
 for row in reserves:
  if selection not in ["deploy_both","deploy_"+str(row.team)]:continue
  if row.team=="green" and g.control.green not in ["game_ai","lm"]:continue
  var found=g.units.filter(func(u):return u.id==row.unit and u.hp>0)
  if found.is_empty():continue
  var u=found[0]
  if u.deployment_phase!="parked" or front.logical<row.release_at or row.sector!=front.active_sector:continue
  var path:PackedVector2Array=g.field.path(u.pos(),row.goal,true)
  if path.is_empty():continue
  u.deployment_route=path;u.deployment_goal=path[-1];u.deployment_phase="entering";u.order_mode="deploy"
  front.emit("armor_released",{"unit":u.id,"source":source,"role":row.role})
func snapshot()->Array:
 var result:Array=[]
 for row in reserves:
  var found=front.game.units.filter(func(u):return u.id==row.unit)
  if found.is_empty():continue
  var u=found[0]
  result.append({"unit":u.id,"team":row.team,"sector":row.sector,"phase":u.deployment_phase if u.hp>0 else "destroyed","ready":u.hp>0 and u.deployment_phase=="parked" and row.sector==front.active_sector and front.logical>=row.release_at,"delay_remaining":maxf(0,row.release_at-front.logical),"role":row.role,"source":row.source})
 return result
func prune():
 reserves=reserves.filter(func(row):return front.game.units.any(func(u):return u.id==row.unit))

func enforce_schedule():
 # Fast decisions may release a ready reserve earlier; never lose a scheduled
 # deployment indefinitely because a model keeps selecting the other side.
 for row in reserves:
  if row.sector==front.active_sector and front.logical>=row.release_at+8:
   release("deploy_"+str(row.team),"slow_plan_schedule")
