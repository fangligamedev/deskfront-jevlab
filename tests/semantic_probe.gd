extends Node
var failures: Array=[]
var checks: Array=[]
func check(value: bool, text: String) -> void:
	checks.append({"test":text,"passed":value})
	if not value:failures.append(text);push_error(text)
func _ready() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.set_physics_process(false)
	await get_tree().process_frame
	check(game.units.size()==9,"exactly nine infantry in three factions")
	for u in game.units:
		check(u.bone_count==17,"17 imported bones: "+u.id)
		check(u.animation_names.size()==8,"8 imported animation clips: "+u.id)
		check(u.playback!=null,"AnimationTree configured: "+u.id)
	check(game.worker_anim!=null and game.worker_anim.is_playing(),"worker typing clip active")
	var start_time=game.worker_anim.current_animation_position
	for i in range(15):await get_tree().process_frame
	check(game.worker_anim.current_animation_position>start_time,"typing animation advances in real engine frames")
	var field=game.field
	var slot=field.slots(field.covers[0])[0]
	var n: Vector2=slot.normal
	check(field.protection(slot.position,slot.position+n*.3)>.5,"cover protects against frontal attack")
	check(field.protection(slot.position,slot.position-n*.3)==0,"flanked cover loses protection")
	var u=game.units[0]
	var a=field.choose_cover("probe1",u.pos(),Vector2(.3,-.3),u.pos())
	var b=field.choose_cover("probe2",u.pos(),Vector2(.3,-.3),u.pos())
	check(not a.is_empty() and not b.is_empty() and a.key!=b.key,"cover reservation is exclusive")
	field.release("probe1");field.release("probe2")
	check(not field.line_of_sight(Vector2(.84,-.59),Vector2(.84,-.30)),"sharpener blocks line of sight")
	var r=game.command({"action":"control","faction":"green","mode":"player"})
	check(r.accepted,"player takeover accepted")
	var original=u.pos()
	r=game.command({"action":"move","faction":"green","position":[.50,.40],"unit_ids":[u.id]})
	check(r.accepted,"player move accepted")
	for i in range(180):game._physics_process(1.0/60)
	check(u.pos().distance_to(original)>.12,"player-selected infantry actually moves")
	check(game.control.green=="player" and game.decisions.green.source=="console","AI does not override player faction")
	check(field.walkable(u.pos()),"movement respects blocked navigation cells")
	r=game.command({"action":"move","faction":"green","position":[50,50]})
	check(not r.accepted,"out of bounds command rejected")
	r=game.command({"action":"move","source":"agent","faction":"red","position":[.4,.4],"run_id":game.run_id,"seen_tick":game.tick_id})
	check(not r.accepted and r.message=="authority_denied","Agent cannot control unassigned faction")
	game.command({"action":"control","faction":"blue","mode":"agent"})
	r=game.command({"action":"capture","source":"agent","faction":"blue","run_id":"old","seen_tick":game.tick_id})
	check(not r.accepted and r.message=="stale_run","stale run rejected")
	r=game.command({"action":"capture","source":"agent","faction":"blue","run_id":game.run_id,"seen_tick":-10000})
	check(not r.accepted and r.message=="stale_observation","stale observation rejected")
	r=game.command({"action":"capture","source":"agent","faction":"blue","run_id":game.run_id,"seen_tick":game.tick_id})
	check(r.accepted and game.control.blue=="agent","fresh authorized Agent action accepted")
	r=game.command({"action":"hold","source":"agent","faction":"blue","unit_ids":["red-1"],"run_id":game.run_id,"seen_tick":game.tick_id})
	check(not r.accepted,"cross-faction unit command rejected")
	game.command({"action":"control","faction":"green","mode":"game_ai"})
	game.command({"action":"control","faction":"blue","mode":"game_ai"})
	for i in range(1800):
		game._physics_process(1.0/60)
		if i%60==0:await get_tree().process_frame
	check(game.shots>8,"AI combat fires real shots")
	check(game.units.any(func(v):return v.hp<v.max_hp),"combat deals damage")
	check(not game.decisions.is_empty(),"utility decisions are visible")
	if not game.tank_spawned:
		for red in game.living("red"):red.hp=minf(red.hp,20)
		game.elapsed=maxf(game.elapsed,30)
		game._physics_process(.1)
	check(game.tank_spawned,"losing red faction triggers reinforcement")
	check(not game.spawn_tank(),"tank reinforcement cannot be duplicated")
	check(game.units.filter(func(v):return v.tank).size()==1,"exactly one tank")
	var rev=field.revision
	var destroyed=field.damage_cover("pencil_barrier",1000)
	check(destroyed and field.revision>rev,"destroyed obstacle rebuilds navigation")
	check(not field.covers[4].alive,"destroyed cover loses protection")
	var t=game.elapsed;game.command({"action":"pause","value":true});game._physics_process(1)
	check(game.elapsed==t,"pause freezes battle simulation")
	game.paused=false;game.winner="";game.scores.green=game.config.rules.score_to_win;game._physics_process(.1)
	check(game.winner=="green","capture score produces victory")
	var file=FileAccess.open("res://output/semantic.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"final":game.snapshot()},"  "))
	if failures.is_empty():print("FORGE_SEMANTIC_PASS deskfront checks=",checks.size())
	else:print("SEMANTIC_FAILURES ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
