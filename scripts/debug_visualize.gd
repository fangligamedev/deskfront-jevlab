extends Control
## Read-only projection of live navigation; never creates movement orders.
var game
var enabled: bool=false
var focus: String=""
var histories: Dictionary={}
var accepted: Dictionary={}
var sample_clock: float=0
const LIMIT=100
const ACTIONS={"move":"移动","capture":"夺旗","cover":"进入掩体","flank":"侧翼推进","retreat":"撤退","hold":"防守","attack":"攻击","garrison":"进驻小楼","leave_building":"撤离小楼","man_at_gun":"操纵反坦克炮","grenade":"投掷手雷","posture":"调整姿态"}

func setup(owner_game) -> void:
	game=owner_game
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var layer=CanvasLayer.new();layer.layer=4
	get_parent().add_child(layer);reparent(layer)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var options: Dictionary=get_tree().get_meta("debug_visualize",{})
	configure(options.get("enabled",false),options.get("unit",""))

func configure(value: bool, unit_id: String) -> void:
	enabled=value;focus=unit_id if game.units.any(func(u):return u.id==unit_id) else "";visible=value
	histories.clear();sample_clock=0
	get_tree().set_meta("debug_visualize",{"enabled":enabled,"unit":focus})
	queue_redraw()

func record_command(c: Dictionary) -> void:
	if not ACTIONS.has(c.get("action","")):return
	for u in game.units:
		if u.faction==c.get("faction",game.selected_faction) and u.hp>0 and (c.get("unit_ids",[]).is_empty() or u.id in c.unit_ids):
			accepted[u.id]={"command_id":c.get("id","local"),"action":c.action,"reason":str(c.get("reason","玩家/策划指令")).left(160),"source":c.get("decision_origin",c.get("source","console")),"tick":game.tick_id}

func _process(delta: float) -> void:
	if not enabled or not is_instance_valid(game):return
	sample_clock+=delta
	if sample_clock>=.15:
		sample_clock=0
		for u in game.units:
			if u.hp<=0:continue
			var trail: Array=histories.get(u.id,[])
			if trail.is_empty() or Vector3(trail[-1]).distance_to(u.global_position)>.005:
				trail.append(u.global_position)
				if trail.size()>LIMIT:trail.pop_front()
			histories[u.id]=trail
	queue_redraw()

func path_for(u) -> Array:
	var points: Array=[]
	if u.hp<=0:return points
	if not u.garrison_path.is_empty():
		for p in u.garrison_path:points.append(p)
	else:
		for p in u.route:points.append(Vector3(p.x,game.field.ground_height(p),p.y))
	return points

func rows() -> Array:
	var result: Array=[]
	for u in game.units:
		if u.hp<=0 or (focus!="" and u.id!=focus):continue
		var points=path_for(u)
		var next: Vector3=points[0] if not points.is_empty() else u.global_position
		var issued: Dictionary=accepted.get(u.id,{})
		result.append({"unit_id":u.id,"control":game.control[u.faction],"command":issued,"state":u.state,"order":u.order_mode,"next":[next.x,next.y,next.z],"waypoints":points.map(func(p):return [p.x,p.y,p.z]),"trail":histories.get(u.id,[]).map(func(p):return [p.x,p.y,p.z]),"path_failure":u.path_failure,"safety":u.safety_reason if game.elapsed<u.safety_until else "","suppression":u.suppression,"target_id":u.target_id,"cover_id":u.cover_id,"navigation_revision":game.field.revision})
	return result

func snapshot() -> Dictionary:
	return {"enabled":enabled,"unit":focus,"units":rows() if enabled else [],"history_limit":LIMIT}

func pixel(p: Vector3) -> Vector2:
	return game.camera.unproject_position(p+Vector3(0,.012,0))

func arrow(a: Vector2,b: Vector2,color: Color) -> void:
	if a.distance_to(b)<15:return
	var v=(b-a).normalized();var n=Vector2(-v.y,v.x)
	draw_colored_polygon(PackedVector2Array([b,b-v*10+n*4,b-v*10-n*4]),color)

func _draw() -> void:
	if not enabled or not is_instance_valid(game) or not game.camera:return
	var font=ThemeDB.fallback_font
	for u in game.units:
		if u.hp<=0 or (focus!="" and u.id!=focus):continue
		var color: Color=game.colors[u.faction].lightened(.35)
		var trail: Array=histories.get(u.id,[])
		for i in range(1,trail.size()):draw_dashed_line(pixel(trail[i-1]),pixel(trail[i]),Color(1,.75,.3,.7),1.5,4)
		var previous=pixel(u.global_position)
		var points=path_for(u)
		var last_number:=Vector2.INF
		for i in points.size():
			var p=pixel(points[i])
			draw_line(previous,p,Color(.04,.08,.06,.9),3.5,true);draw_line(previous,p,color,1.8,true);arrow(previous,p,color)
			draw_circle(p,2.5,Color(.04,.08,.06,.95));draw_circle(p,1.5,color)
			if i==0 or p.distance_to(last_number)>32:
				draw_string_outline(font,p+Vector2(6,16),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,3,Color(.03,.05,.03))
				draw_string(font,p+Vector2(6,16),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,color);last_number=p
			previous=p
		var start=pixel(u.global_position)
		draw_arc(start,11,0,TAU,24,color,2,true)
		for target in game.units:
			if target.id==u.target_id and target.hp>0:draw_dashed_line(start,pixel(target.global_position),Color(1,.35,.28,.85),1.5,7)
		var title: String=u.id+" | "+("NEXT 1" if not points.is_empty() else "HOLD")
		var pos=start+Vector2(12,-22)
		var width=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		draw_style_box(label_box(),Rect2(pos-Vector2(5,16),Vector2(width+10,24)))
		draw_string(font,pos,title,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)

func label_box() -> StyleBoxFlat:
	var box=StyleBoxFlat.new();box.bg_color=Color(.03,.06,.04,.85);box.set_corner_radius_all(3);return box
