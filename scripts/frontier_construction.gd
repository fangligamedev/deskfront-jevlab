extends Node3D
## Original articulated toy engineers. Visual work follows authoritative construction jobs.
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
  var site=Node3D.new();add_child(site);site.position=Vector3(c.position[0]-.085,game.field.height+.002,c.position[1])
  var bed=box(site,Vector3.ZERO,Vector3(.10,.002,c.size[1]+.08),"#544a38");bed.scale.z=.02
  var dirt=box(site,Vector3(-.06,.009,0),Vector3(.035,.018,c.size[1]+.1),"#88724d");dirt.scale.y=.05
  jobs.append({"cover":c,"progress":0.0,"worker":-1,"bed":bed,"dirt":dirt})
 work_seconds=maxf(2.0,float(game.eastfront.rules.build_seconds)/ceilf(jobs.size()/2.0))
 for i in range(2):
  var w=Node3D.new();add_child(w)
  var torso=Node3D.new();w.add_child(torso);torso.position.y=.063
  box(torso,Vector3.ZERO,Vector3(.035,.043,.025),"#975b43")
  box(torso,Vector3(0,.036,0),Vector3(.036,.022,.031),"#b97c55")
  box(torso,Vector3(0,.049,0),Vector3(.045,.012,.037),"#684b37")
  var limbs:Array=[]
  for side in [-1,1]:
   var arm=Node3D.new();torso.add_child(arm);arm.position=Vector3(side*.024,.012,0)
   box(arm,Vector3(0,-.02,0),Vector3(.014,.045,.014),"#975b43");limbs.append(arm)
  var shovel=Node3D.new();limbs[1].add_child(shovel);shovel.position=Vector3(0,-.034,0)
  box(shovel,Vector3(0,-.025,0),Vector3(.006,.06,.006),"#b49a64")
  box(shovel,Vector3(0,-.064,0),Vector3(.025,.025,.005),"#525c56")
  var bag=box(w,Vector3(0,.072,-.025),Vector3(.05,.025,.028),"#b5a47b")
  var legs:Array=[]
  for side in [-1,1]:
   var leg=Node3D.new();w.add_child(leg);leg.position=Vector3(side*.011,.044,0)
   box(leg,Vector3(0,-.019,0),Vector3(.016,.041,.017),"#6a5b41");legs.append(leg)
  workers.append({"node":w,"torso":torso,"arms":limbs,"legs":legs,"shovel":shovel,"bag":bag,"job":-1,"state":"survey"})
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
  var site=Vector3(c.position[0]-.095,game.field.height,c.position[1])
  var stock=Vector3((chunk.index+1)*float(game.eastfront.rules.width)-.14,game.field.height,.48)
  w.state="survey" if p<.12 else "dig" if p<.40 else "carry_sandbag" if p<.75 else "stack_sandbag"
  w.node.visible=true;w.node.position=site
  if p>=.40 and p<.75:
   var travel:float=(p-.40)/.35
   w.node.position=site.lerp(stock,travel*2) if travel<.5 else stock.lerp(site,(travel-.5)*2)
   var target:Vector3=stock if travel<.5 else site
   var direction:Vector3=target-w.node.position
   if direction.length()>.001:w.node.rotation.y=atan2(-direction.x,-direction.z)
  else:w.node.rotation.y=-PI/2
  w.bag.visible=p>=.575 and p<1;w.shovel.visible=w.state=="dig"
  var gait:float=sin(elapsed*15+wi)*.55 if w.state=="carry_sandbag" else 0.0
  w.legs[0].rotation.x=gait;w.legs[1].rotation.x=-gait
  w.torso.rotation.x=.30+sin(elapsed*8)*.2 if w.state=="dig" else .32 if w.state=="stack_sandbag" else 0.0
  for arm in w.arms:arm.rotation.x=-.8+sin(elapsed*8)*.5 if w.state=="dig" else -1.1 if w.bag.visible else 0.0
  job.bed.scale.z=clampf((p-.12)/.28,.02,1);job.dirt.scale.y=clampf((p-.12)/.28,.05,1)
  var visible_count:int=int(clampf((p-.75)/.25,0,1)*11)
  var children=c.node.get_children()
  for i in range(children.size()):if children[i] is Node3D:children[i].visible=i<visible_count
  if policy=="dig_first" and before<.4 and p>=.4 and jobs.any(func(j):return j.progress<.4):
   job.progress=.4;w.job=-1;job.worker=-1
  elif p>=1:w.job=-1;job.worker=-1
 completed=jobs.all(func(j):return j.progress>=1)
func snapshot()->Dictionary:
 return {"policy":policy,"elapsed":snappedf(elapsed,.1),"progress":jobs.reduce(func(sum,j):return sum+j.progress,0.0)/maxi(1,jobs.size()),"workers":workers.map(func(w):return {"action":w.state,"job":w.job,"position":[w.node.position.x,w.node.position.z]})}
