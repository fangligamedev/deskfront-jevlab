extends Node
var checks:Array=[]
func check(value:bool,label:String):
 checks.append({"test":label,"passed":value})
 if not value:push_error(label)
func _ready():
 get_tree().set_meta("eastfront_enabled",true)
 get_tree().set_meta("eastfront_backend","local")
 var game=load("res://scenes/main.tscn").instantiate();add_child(game);game.set_physics_process(false)
 await get_tree().process_frame
 var front=game.eastfront
 check(front!=null,"eastfront controller created")
 check(game.units.size()==3,"green expedition only at start")
 game._physics_process(.05)
 check(front.chunks.size()==2 and front.chunks[1].phase=="building","construction preview before collision commit")
 check(game.field.covers.is_empty(),"preview not prematurely solid")
 check(front.propose(0,"staggered","test")=="stale_frontier_request","old proposal rejected")
 for i in range(12000):
  game._physics_process(.05)
  if i%200==0:await get_tree().process_frame
  if i%600==0:print("EAST_PROGRESS ",JSON.stringify({"time":game.elapsed,"cleared":front.cleared,"units":game.units.map(func(u):return {"id":u.id,"hp":u.hp,"pos":[u.pos().x,u.pos().y],"order":u.order_mode}),"request":front.request,"last":front.history[-1]}))
  if game.winner!="" or front.cleared>=3:break
 check(front.total_built>=2,"built multiple sectors")
 check(game.shots>0,"real projectile combat")
 check(front.cleared>=3,"game AI wins three consecutive real sectors")
 check(front.peak_chunks<=int(front.rules.max_chunks),"live chunk window bounded")
 var result={"checks":checks,"frontier":front.snapshot(),"shots":game.shots,"seconds":game.elapsed,"winner":game.winner}
 var file=FileAccess.open("res://output/eastfront/simulation.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "))
 print("EASTFRONT_RESULT ",JSON.stringify(checks));get_tree().quit(1 if checks.any(func(c):return not c.passed) else 0)
