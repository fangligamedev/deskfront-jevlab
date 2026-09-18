extends SceneTree
## Three deterministic, full simulation matches. No replacement combat model.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var runs: Array=[];var passed: bool=true
	for seed_value in [18092026,42,773]:
		set_meta("deskfront_map",[18092026,42,773].find(seed_value))
		var g=load("res://scenes/main.tscn").instantiate();root.add_child(g)
		g.set_physics_process(false);g.fx.set_muted(true);g.rng.seed=seed_value
		var samples: Array=[];var invalid: Array=[];var cover_frames: int=0;var alive_frames: int=0
		var before: int=Time.get_ticks_usec()
		for step in range(5400):
			g._physics_process(1.0/60)
			if step%30==0:
				for u in g.living():
					if u.tank:continue
					alive_frames+=1
					if u.in_cover():cover_frames+=1
					if not g.field.walkable(u.pos()):invalid.append({"unit":u.id,"time":g.elapsed,"position":[u.pos().x,u.pos().y]})
				if step%120==0:samples.append({"time":g.elapsed,"units":g.living().map(func(u):return {"id":u.id,"hp":u.hp,"order":u.order_mode,"stance":u.cqb_stance,"cover":u.in_cover()}),"tactics":g.tactics_ai.snapshot()})
			if step%60==0:await process_frame
			if g.winner!="":break
		var ok: bool=g.shots>20 and g.units.any(func(u):return u.hp<u.max_hp) and cover_frames>20 and invalid.is_empty()
		passed=passed and ok
		runs.append({"map":g.map_data.id,"seed":seed_value,"passed":ok,"seconds":g.elapsed,"winner":g.winner,"shots":g.shots,"tank_spawned":g.tank_spawned,"cover_sample_ratio":float(cover_frames)/maxi(1,alive_frames),"invalid_navigation":invalid,"cpu_wall_seconds":(Time.get_ticks_usec()-before)/1000000.0,"final_tactics":g.tactics_ai.snapshot(),"samples":samples})
		g.queue_free();await process_frame
	var file=FileAccess.open("res://output/tactics-soak.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"runs":runs},"  "))
	print("TACTICS_SOAK ",passed," seeds=",runs.size())
	quit(0 if passed else 1)
