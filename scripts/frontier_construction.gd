extends Node3D
## Existing skinned plastic soldiers working as engineers. Visual work follows authoritative construction jobs.
var game
var chunk:Dictionary
var jobs:Array=[]
var workers:Array=[]
var policy:String="balanced"
var elapsed:float=0
var completed:bool=false
var work_seconds:float=6.0
func box(parent:Node3D,p:Vector3,size:Vector3,color:String)->Node3D:
 return game.field.cube(parent,p,size,game.field.mat(Color(color)))
func setup(g,ch:Dictionary):
 game=g;chunk=ch
 for c in ch.covers:
  for child in c.node.get_children():if child is Node3D:child.visible=false
  var site=Node3D.new();add_child(site);site.position=Vector3(c.position[0]+.085,game.field.height+.002,c.position[1])
  var bed=box(site,Vector3.ZERO,Vector3(.10,.002,c.size[1]+.08),"#544a38");bed.scale.z=.02
  var dirt=box(site,Vector3(-.06,.009,0),Vector3(.035,.018,c.size[1]+.1),"#88724d");dirt.scale.y=.05
  if c.kind not in ["sandbag","trench"]:
   site.position.x=c.position[0];bed.mesh.size=Vector3(c.size[0]+.02,.002,c.size[1]+.02);dirt.hide()
  jobs.append({"cover":c,"progress":0.0,"worker":-1,"bed":bed,"dirt":dirt})
 work_seconds=maxf(2.0,float(game.eastfront.rules.build_seconds)/ceilf(jobs.size()/2.0))
 for i in range(2):
  var w=Node3D.new();add_child(w)
  var actor=preload("res://scripts/toy_actor.gd").new();w.add_child(actor);actor.setup(game.colors.red,"rifle")
  actor.collision_layer=0;actor.collision_mask=0;actor.weapon.hide()
  var shovel=Node3D.new();w.add_child(shovel);shovel.position=Vector3(.015,.065,-.035)
  box(shovel,Vector3(0,-.025,0),Vector3(.004,.075,.004),"#b49a64")
  box(shovel,Vector3(0,-.064,0),Vector3(.025,.025,.005),"#525c56")
  var bag=box(w,Vector3(0,.072,-.03),Vector3(.05,.025,.028),"#b5a47b")
  workers.append({"node":w,"actor":actor,"shovel":shovel,"bag":bag,"job":-1,"state":"survey"})
 var stock=Node3D.new();add_child(stock);stock.position=Vector3((ch.index+1)*float(game.eastfront.rules.width)-.14,game.field.height,.48)
 for i in range(8):box(stock,Vector3((i%2)*.036,(i/4)*.02,(i%4)*.025),Vector3(.036,.019,.025),"#b5a47b")
func choose_job()->int:
 var ids:Array=[]
 for i in range(jobs.size()):if jobs[i].progress<1 and jobs[i].worker<0:ids.append(i)
 ids.sort_custom(func(a,b):return jobs[a].cover.position[1]<jobs[b].cover.position[1] if policy=="north_first" else jobs[a].cover.position[1]>jobs[b].cover.position[1] if policy=="south_first" else a<b)
 if policy=="dig_first" and jobs.any(func(j):return j.progress<.4):ids=ids.filter(func(i):return jobs[i].progress<.4)
 if policy=="dig_first":ids.sort_custom(func(a,b):return jobs[a].progress<jobs[b].progress)
 elif policy=="sandbag_first":ids.sort_custom(func(a,b):return jobs[a].progress>jobs[b].progress)
 return -1 if ids.is_empty() else int(ids[0])
func tick(dt:float):
 if completed:return
 elapsed+=dt
 for wi in range(workers.size()):
  var w:Dictionary=workers[wi]
  if w.job<0:
   var selected=choose_job()
   if selected<0:w.state="secure";w.node.visible=false;continue
   w.job=selected;jobs[selected].worker=wi
  var job:Dictionary=jobs[w.job];var before:float=job.progress;job.progress=minf(1,job.progress+dt/work_seconds)
  var p:float=job.progress;var c:Dictionary=job.cover
  var site=Vector3(c.position[0]+.095,game.field.height,c.position[1])
  var stock=Vector3((chunk.index+1)*float(game.eastfront.rules.width)-.14,game.field.height,.48)
  w.state="survey" if p<.12 else "dig" if p<.40 else "carry_sandbag" if p<.75 else "stack_sandbag"
  if c.kind not in ["sandbag","trench"] and p>=.40:w.state="carry_material" if p<.75 else "assemble_structure"
  w.node.visible=true;w.node.position=site
  if p>=.40 and p<.75:
   var travel:float=(p-.40)/.35
   w.node.position=site.lerp(stock,travel*2) if travel<.5 else stock.lerp(site,(travel-.5)*2)
   var target:Vector3=stock if travel<.5 else site
   var direction:Vector3=target-w.node.position
   if direction.length()>.001:w.node.rotation.y=atan2(-direction.x,-direction.z)
  else:w.node.rotation.y=-PI/2
  w.bag.visible=p>=.575 and p<1;w.shovel.visible=w.state=="dig"
  # Reuse the production skinned plastic soldier. Tools are gripped through its arm IK.
  var actor=w.actor
  actor.play("rifle_jog_rm" if w.state in ["carry_sandbag","carry_material"] else "cover_idle" if w.state in ["dig","stack_sandbag","assemble_structure"] else "rifle_idle")
  actor.drive_speed=.25 if w.state in ["carry_sandbag","carry_material"] else 0.0
  actor.contact_blend=1.0;actor._physics_process(dt);actor.weapon.hide()
  if w.state=="dig":
   w.shovel.rotation.x=sin(elapsed*8)*.45
   actor.grip_handle("Right",w.shovel.to_global(Vector3(0,.005,0)))
   actor.grip_handle("Left",w.shovel.to_global(Vector3(0,-.020,0)))
  elif w.bag.visible:
   actor.grip_handle("Right",w.bag.to_global(Vector3(.021,0,0)))
   actor.grip_handle("Left",w.bag.to_global(Vector3(-.021,0,0)))
  job.bed.scale.z=clampf((p-.12)/.28,.02,1);job.dirt.scale.y=clampf((p-.12)/.28,.05,1)
  var children=c.node.get_children()
  var visible_count:int=int(clampf((p-.75)/.25,0,1)*children.size())
  for i in range(children.size()):if children[i] is Node3D:children[i].visible=i<visible_count
  if policy=="dig_first" and before<.4 and p>=.4 and jobs.any(func(j):return j.progress<.4):
   job.progress=.4;w.job=-1;job.worker=-1
  elif p>=1:
   if c.kind not in ["sandbag","trench"]:job.bed.hide();job.dirt.hide()
   w.job=-1;job.worker=-1
 completed=jobs.all(func(j):return j.progress>=1)
func snapshot()->Dictionary:
 return {"jobs":jobs.map(func(j):return {"kind":j.cover.kind,"progress":j.progress}),"policy":policy,"elapsed":snappedf(elapsed,.1),"progress":jobs.reduce(func(sum,j):return sum+j.progress,0.0)/maxi(1,jobs.size()),"workers":workers.map(func(w):return {"model":"toy-soldier.glb","bones":w.actor.skeleton.get_bone_count(),"action":w.state,"job":w.job,"position":[w.node.position.x,w.node.position.z]})}
