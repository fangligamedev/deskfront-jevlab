extends RefCounted

static func isolate(g) -> void:
	g.set_physics_process(false);g.fx.set_muted(true)
	for team in g.control:g.control[team]="player";g.tactics_ai.cancel(team)
	for u in g.units:u.hp=0;u.route.clear();u.cover_id="";u.cover_slot={};u.focus_id="";u.target_id=""

static func run(g, check: Callable) -> void:
	var objective_mode=g.config.rules.get("mode","");g.config.rules.mode="legacy_cqb_contract"
	isolate(g)
	var field=g.field;var rifle=g.units[0];var target=g.units[6]
	# A thin blocker between former LOS samples must still occlude the segment.
	field.obstacles.append({"id":"thin_probe","position":[.501,.43],"size":[.001,.08]})
	check.call(not field.line_of_sight(Vector2(.4,.43),Vector2(.62,.43)),"analytic LOS detects sub-cell thin blockers")
	field.obstacles.pop_back()
	var softened: Vector2=field.soft_offset(Vector2(.72,-.46),Vector2(.97,-.46),.17)
	check.call(softened.distance_to(Vector2(.97,-.46))>.10 and field.walkable(softened),"formation offset will not detour around far side of sharpener")
	rifle.hp=100;rifle.position=Vector3(.44,field.height,.43)
	rifle.move_to(Vector2(.57,.43));var paths: int=field.path_queries
	for i in range(20):rifle.move_to(Vector2(.571,.431))
	check.call(field.path_queries==paths,"small repeated movement orders do not trigger A* storms")
	rifle.route.clear();rifle.position=Vector3(.66,field.height,-.28);target.hp=100;target.position=Vector3(.715,field.height,-.28)
	rifle.cooldown=0;rifle.reload_timer=1
	var before: int=int(g.fx.launched.get("bayonet",0));rifle.tick(.016)
	check.call(int(g.fx.launched.get("bayonet",0))==before,"bayonet cannot stab through pencil cover")
	# Hard-cover corner with a blocked resting ray and an open shoulder ray.
	var hard: Dictionary={}
	for c in field.covers:
		if c.id=="hard_sharpener":hard=c
	var slot: Dictionary={}
	target.position=Vector3(.99,field.height,-.40)
	for candidate in field.slots(hard):
		if not field.line_of_sight(candidate.position,target.pos()) and field.line_of_sight(candidate.peek,target.pos()) and field.walkable(candidate.position) and field.walkable(candidate.peek):slot=candidate;break
	check.call(not slot.is_empty(),"hard cover has a hidden rest station and reachable peek corner")
	if not slot.is_empty():
		rifle.position=Vector3(slot.position.x,field.height,slot.position.y);rifle.occupy(slot);rifle.route.clear();rifle.reload_timer=0;rifle.suppression=0;rifle.hide_until=0
		rifle.cover_behavior()
		check.call(rifle.peeking and rifle.goal.distance_to(slot.peek)<.025,"soldier moves to shoulder peek before shooting around hard cover")
		rifle.position=Vector3(slot.peek.x,field.height,slot.peek.y);rifle.route.clear();rifle.reload_timer=1
		rifle.cover_behavior()
		check.call(not rifle.peeking and rifle.cqb_stance=="hide" and rifle.goal.distance_to(slot.position)<.025,"reload retracts soldier behind hard cover")
		rifle.reload_timer=0;rifle.suppression=.95;rifle.position=Vector3(slot.position.x,field.height,slot.position.y);rifle.route.clear();rifle.hide_until=0;rifle.cover_behavior()
		check.call(not rifle.peeking,"pinned soldier remains hidden instead of exposing shoulder")
		rifle.suppression=0;rifle.reload_timer=0;rifle.cooldown=0;rifle.ammo=8;rifle.hide_until=g.elapsed+10
		var shots_before: int=g.shots
		for i in range(20):g.elapsed+=1.0/60;rifle.tick(1.0/60);rifle.presentation_tick(1.0/60)
		check.call(g.shots==shots_before,"hidden hard-cover soldier cannot shoot through obstacle")
		rifle.hide_until=0
		for i in range(300):g.elapsed+=1.0/60;rifle.tick(1.0/60);rifle.presentation_tick(1.0/60);g.fx.physics_tick(1.0/60)
		check.call(g.shots>shots_before,"soldier actually traverses to corner and fires during the peek window")
	var cover_slot: Dictionary=field.choose_cover(rifle.id,Vector2(.20,.32),Vector2(.2,-.4),Vector2(.2,.32),{"threats":[Vector2(.2,-.4),Vector2(1,-.2)]})
	check.call(not cover_slot.is_empty() and cover_slot.has("risk") and cover_slot.has("path_length") and cover_slot.has("fire_arc"),"cover selection evaluates multiple threats, firing arc and route cost")
	if not cover_slot.is_empty():
		rifle.occupy(cover_slot)
		field.damage_cover(cover_slot.cover_id,10000);rifle.tick(.016)
		check.call(rifle.cover_id=="" and not field.reservations.values().has(rifle.id),"destroyed cover invalidates soldier station and reservation")
	# Isolated open table for vehicle control, without unrelated scenery constraints.
	for c in field.covers:c.alive=false
	field.obstacles.clear();field.rebuild();isolate(g)
	check.call(field.walkable(Vector2(.69,-.28)) and field.walkable(Vector2(.69,-.28),true),"destroyed cover actually clears old infantry and tank navigation cells")
	var armor=g.spawn_unit("probe-tank","red",Vector2(.65,.20),true)
	var rocket=g.units[2];rocket.hp=100;rocket.position=Vector3(.65,field.height,-.05)
	check.call(armor.turret!=null and armor.muzzle!=null,"Blender tank exposes independent turret and muzzle nodes")
	check.call(armor.armor_multiplier(Vector2(.65,-.4))<armor.armor_multiplier(Vector2(.65,.5)),"tank front armor is stronger than rear armor")
	g.tactics_ai.plan_tank(armor)
	check.call(armor.order_mode=="reverse" and armor.goal.distance_to(rocket.pos())>armor.pos().distance_to(rocket.pos())+.15,"nearby anti-tank threat triggers standoff reverse destination")
	var original: Vector2=armor.pos()
	for i in range(90):armor.tick(1.0/60);g.elapsed+=1.0/60
	check.call(armor.pos().distance_to(original)>.03 and armor.reversing,"tank actually reverses along a reachable path")
	check.call(armor.turret!=null and absf(armor.turret.rotation.y)>.02,"turret aims independently while hull manoeuvres")
	# Stable roles and shared formation anchor after leader loss.
	isolate(g)
	for i in range(3):g.units[i].hp=100;g.units[i].position=Vector3(.1+i*.07,field.height,.4)
	g.tactics_ai.begin_move("green",Vector2(.7,.4),[])
	check.call(g.tactics_ai.formations.has("green"),"squad move creates one shared virtual formation anchor")
	var goals: Array=[]
	for i in range(3):goals.append(g.units[i].goal)
	check.call(goals[0].distance_to(goals[1])>.02 and goals[1].distance_to(goals[2])>.02,"destination formation does not stack members on one point")
	var start: Vector2=g.tactics_ai.formations.green.anchor
	for i in range(15):g.tactics_ai.update_formations()
	check.call(g.tactics_ai.formations.green.anchor.distance_to(start)<.26,"virtual leader leash prevents anchor running away from stationary squad")
	var revision: int=field.revision;field.rebuild();g.tactics_ai.update_formations()
	check.call(g.tactics_ai.formations.green.revision>revision,"formation reroutes after navigation revision")
	var roles: Array=[g.units[1].tactical_role,g.units[2].tactical_role]
	g.tactics_ai.formations.clear();g.tactics_ai.squads.clear();g.control.green="game_ai";g.tactics_ai.plan("green");g.units[0].hp=0;g.tactics_ai.plan("green")
	check.call(g.tactics_ai.squads.green.leader==g.units[1].id and roles==[g.units[1].tactical_role,g.units[2].tactical_role],"leader death updates leader without swapping surviving weapon roles")

	# Contact interrupts a real group march; subsequent updates must not overwrite cover orders.
	isolate(g)
	for i in range(3):g.units[i].hp=100;g.units[i].position=Vector3(.2+i*.06,field.height,.32);g.units[i].reload_timer=0;g.units[i].suppression=0
	g.control.green="game_ai";g.tactics_ai.plan("green")
	g.tactics_ai.begin_move("green",Vector2(.8,.32),[])
	g.tactics_ai.squads.green.phase="advance"
	target.hp=100;target.position=Vector3(.5,field.height,.15)
	g.tactics_ai.plan("green")
	check.call(not g.tactics_ai.formations.has("green") and g.units.slice(0,3).all(func(u):return u.route.is_empty()),"new contact stops virtual formation before taking combat positions")
	# Genuine sandbag stations, one per member, establish a controlled CQB flank opportunity.
	isolate(g);field.covers.clear();field.slot_cache.clear();field.reservations.clear()
	var friendly: Dictionary={"id":"friendly_probe","position":[.35,.23],"size":[.26,.04],"normal":[0,-1],"kind":"sandbag","height":.055,"alive":true,"hp":500,"node":null}
	var hostile: Dictionary={"id":"hostile_probe","position":[.55,0],"size":[.24,.04],"normal":[0,1],"kind":"sandbag","height":.055,"alive":true,"hp":500,"node":null}
	field.covers.append(friendly);field.covers.append(hostile);field.rebuild()
	var stations: Array=field.slots(friendly).filter(func(st):return st.normal.y<0)
	for i in range(3):
		var soldier=g.units[i];soldier.hp=100;soldier.reload_timer=0;soldier.suppression=0;soldier.cooldown=0;soldier.cqb_stance="crouch"
		soldier.position=Vector3(stations[i].position.x,field.height,stations[i].position.y);soldier.occupy(stations[i]);soldier.route.clear()
	target.hp=100;target.suppression=.8;target.position=Vector3(.55,field.height,-.055)
	g.control.green="game_ai";g.tactics_ai.plan("green")
	# Re-establish exact arrived stations after the normal initial cover allocation.
	for i in range(3):g.units[i].occupy(stations[i]);g.units[i].position=Vector3(stations[i].position.x,field.height,stations[i].position.y);g.units[i].route.clear()
	g.tactics_ai.squads.green.phase="suppress";g.tactics_ai.squads.green.since=g.elapsed-10
	var bound_distance: float=g.config.tactics.bound_distance;g.config.tactics.bound_distance=.015
	g.tactics_ai.plan("green")
	check.call(g.tactics_ai.squads.green.phase!="bound","having a firing arc without recent covering shots does not authorize a bound")
	for soldier in g.units.slice(0,3):soldier.last_shot_at=g.elapsed;soldier.last_shot_target=target.id;soldier.ammo=8;soldier.safety_until=0;soldier.posture="crouch"
	g.tactics_ai.plan("green")
	var movers: Array=g.units.slice(0,3).filter(func(u):return not u.route.is_empty())
	check.call(g.tactics_ai.squads.green.phase=="bound" and movers.size()==1 and movers[0].order_mode=="cqb_flank","suppressed enemy permits exactly one CQB flanker while two soldiers hold")
	if movers.size()==1:
		check.call(field.protection(target.pos(),movers[0].goal)<.25,"CQB flank destination defeats enemy cover direction")
		for soldier in g.units.slice(0,3):
			if soldier!=movers[0]:soldier.reload_timer=3
		g.tactics_ai.plan("green")
		check.call(g.tactics_ai.squads.green.phase=="suppress" and movers[0].order_mode=="take_cover","loss of covering fire cancels flank and seeks immediate shelter")
	g.config.tactics.bound_distance=bound_distance
	# Without a suppression window, the same team must not rush the exposed flank.
	for i in range(3):
		var soldier=g.units[i];soldier.reload_timer=0;soldier.occupy(stations[i]);soldier.position=Vector3(stations[i].position.x,field.height,stations[i].position.y);soldier.route.clear()
	target.suppression=0;target.hp=target.max_hp
	g.tactics_ai.squads.green.phase="suppress";g.tactics_ai.squads.green.since=g.elapsed-10
	g.config.tactics.bound_distance=.015;g.tactics_ai.plan("green")
	check.call(g.units.slice(0,3).all(func(u):return u.order_mode!="cqb_flank"),"healthy unsuppressed enemy does not invite an unsupported rush")
	g.config.tactics.bound_distance=bound_distance
	var rejected: Dictionary=g.command({"action":"attack","faction":"green","target_id":"missing-target"})
	check.call(not rejected.accepted and g.tactics_ai.squads.has("green") and g.control.green=="game_ai","rejected attack cannot cancel an active squad plan or steal control")
	g.set_camera("top",true)
	var camera_start: Vector3=g.camera_target
	var press := InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_MIDDLE;press.pressed=true;press.position=Vector2(640,360)
	g._unhandled_input(press)
	var release := InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_MIDDLE;release.pressed=false;release.position=Vector2(800,420)
	g._input(release)
	check.call(g.camera_target.distance_to(camera_start)>.10 and not g.panning,"mouse release preserves full camera drag even when motion events are coalesced")
	g.set_camera("top",true);camera_start=g.camera_target;g.pan_cursor=Vector2(640,360)
	for i in range(1,13):
		g.pan_to(Vector2(640+i*13,360+i*3));g._process(.15)
	check.call(g.camera_target.x<camera_start.x-.20 and g.camera.global_basis.x.dot(Vector3.RIGHT)>.99,"top camera preserves screen axes during interpolated multi-frame pan")

	g.config.rules.mode=objective_mode
