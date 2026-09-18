extends Node3D

var config: Dictionary
var covers: Array = []
var obstacles: Array = []
var grid := AStarGrid2D.new()
var tank_grid := AStarGrid2D.new()
var base := Vector2.ZERO
var cell: float = 0.025
var height: float = 0.82
var revision: int = 0
var reservations: Dictionary = {}
var slot_cache: Dictionary={}
var path_queries: int=0
var destruction_count: int=0
var ray_queries: int=0
var reserved_positions: Dictionary={}
var unavailable_until: Dictionary={}
var simulation_time: float=0

func setup(data: Dictionary, arena=null) -> void:
	config = data
	height = data.table_height
	cell = data.cell_size
	base = Vector2(data.bounds[0], data.bounds[1])
	for source in data.covers:
		var c: Dictionary = source.duplicate(true)
		c["alive"] = true
		c["max_hp"] = c.hp
		c["damage_stage"] = "intact"
		c["node"] = null
		if arena:
			for row in arena.props:
				if row.spec.id==c.id:c["node"]=row.node
		else:c["node"] = make_cover(c)
		covers.append(c)
	obstacles = data.obstacles.duplicate(true)
	for o in obstacles:
		covers.append({"id":"hard_"+o.id,"position":o.position,"size":o.size,"normal":[1,0],"height":.18,"hp":-1,"kind":"hard","alive":true,"node":null})
	rebuild()

func mat(color: Color, roughness: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func cube(parent: Node3D, p: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = p
	return mesh

func make_cover(c: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = c.id
	add_child(node)
	node.position = Vector3(c.position[0], height, c.position[1])
	var size := Vector2(c.size[0], c.size[1])
	if c.kind == "sandbag":
		var count: int = 5
		var vertical: bool = size.y > size.x
		for row in range(2):
			for i in range(count):
				var bag: Node3D = load("res://assets/models/sandbag.glb").instantiate()
				node.add_child(bag)
				var offset: float = (i - 2) * .048 + (row * .008)
				bag.position = Vector3(0 if vertical else offset, .011 + row * .019, offset if vertical else 0)
				bag.rotation.y = (PI/2 if vertical else 0) + float((i+row)%3-1)*.045
		# deterministic grains, individually merged by Godot MultiMesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var grain := BoxMesh.new()
		grain.size = Vector3(.003,.0015,.003)
		mm.mesh = grain
		mm.instance_count = 75
		var rng := RandomNumberGenerator.new()
		rng.seed = c.id.hash()
		for i in range(75):
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-size.x*.8,size.x*.8),.001,rng.randf_range(-size.y*.8,size.y*.8))))
		var grains := MultiMeshInstance3D.new()
		grains.multimesh = mm
		grains.material_override = mat(Color(.46,.39,.26))
		node.add_child(grains)
	elif c.kind == "notebook":
		cube(node,Vector3(0,.016,0),Vector3(size.x,.025,size.y),mat(Color(.68,.67,.54)))
		cube(node,Vector3(0,.032,0),Vector3(size.x+.006,.006,size.y+.006),mat(Color(.12,.19,.17)))
	elif c.kind == "pencil":
		for i in range(3):
			var p := cube(node,Vector3((i-1)*.012,.014,0),Vector3(.012,.025,size.y),mat(Color(.64,.41,.15)))
			p.rotation.y = (i-1)*.09
	else:
		cube(node,Vector3(0,c.height/2,0),Vector3(size.x,c.height,size.y),mat(Color(.61,.40,.37)))
	return node

func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(roundi((p.x-base.x)/cell),roundi((p.y-base.y)/cell))

func to_world(p: Vector2i) -> Vector2:
	return base + Vector2(p)*cell

func rebuild() -> void:
	# update() does not clear solids when region/cell size are unchanged.
	grid.clear();tank_grid.clear()
	grid.region = Rect2i(0,0, int((config.bounds[2]-base.x)/cell)+1,int((config.bounds[3]-base.y)/cell)+1)
	grid.cell_size = Vector2.ONE * cell
	grid.offset = base
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	tank_grid.region=grid.region
	tank_grid.cell_size=grid.cell_size
	tank_grid.offset=base
	tank_grid.diagonal_mode=grid.diagonal_mode
	tank_grid.update()
	for c in covers + obstacles:
		if not c.get("alive",true) or not c.get("nav_block",true): continue
		var center := Vector2(c.position[0],c.position[1])
		var half := Vector2(c.size[0],c.size[1])/2 + Vector2.ONE*.018
		for x in range(grid.region.size.x):
			for y in range(grid.region.size.y):
				var pos := to_world(Vector2i(x,y))
				if absf(pos.x-center.x)<half.x and absf(pos.y-center.y)<half.y:
					grid.set_point_solid(Vector2i(x,y))
				if absf(pos.x-center.x)<half.x+.075 and absf(pos.y-center.y)<half.y+.075:
					tank_grid.set_point_solid(Vector2i(x,y))
	for x in range(grid.region.size.x):
		for y in range(grid.region.size.y):
			var p=to_world(Vector2i(x,y))
			for water in config.get("water",[]):
				if inside_object(p,water):
					var bridge=false
					for b in config.get("bridges",[]):
						if inside_object(p,b):bridge=true
					if not bridge:grid.set_point_solid(Vector2i(x,y));tank_grid.set_point_solid(Vector2i(x,y))
	revision += 1

func nearest(p: Vector2, tank: bool=false) -> Vector2i:
	var nav: AStarGrid2D=tank_grid if tank else grid
	var id := to_cell(p)
	id.x = clampi(id.x,0,grid.region.size.x-1)
	id.y = clampi(id.y,0,grid.region.size.y-1)
	if not nav.is_point_solid(id): return id
	for radius in range(1,16):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				var q := id+Vector2i(x,y)
				if nav.is_in_boundsv(q) and not nav.is_point_solid(q): return q
	return id

func path(from: Vector2, dest: Vector2, tank: bool=false) -> PackedVector2Array:
	path_queries+=1
	var nav: AStarGrid2D=tank_grid if tank else grid
	return nav.get_point_path(nearest(from,tank),nearest(dest,tank))

func walkable(p: Vector2, tank: bool=false) -> bool:
	var id := to_cell(p)
	var nav: AStarGrid2D=tank_grid if tank else grid
	return nav.is_in_boundsv(id) and not nav.is_point_solid(id)

func segment_walkable(a: Vector2,b: Vector2,tank: bool=false) -> bool:
	if not walkable(a,tank) or not walkable(b,tank):return false
	var nav: AStarGrid2D=tank_grid if tank else grid
	var first:=to_cell(a);var last:=to_cell(b)
	# Exact touched-cell test: regular point samples can miss a sub-millimetre
	# sliver at a cell corner, which the root's next physics step still hits.
	for x in range(mini(first.x,last.x)-1,maxi(first.x,last.x)+2):
		for y in range(mini(first.y,last.y)-1,maxi(first.y,last.y)+2):
			var id:=Vector2i(x,y)
			if not nav.is_in_boundsv(id) or not nav.is_point_solid(id):continue
			var center:=to_world(id)
			if not ray_box(Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),Vector3(center.x,0,center.y),Vector3(cell-.000001,1,cell-.000001)).is_empty():return false
	return true

func path_around_units(from: Vector2,dest: Vector2,occupants: Array) -> PackedVector2Array:
	var saved: Array=[];var start:=nearest(from)
	for occupant in occupants:
		var center:=to_cell(occupant.pos())
		var radius: float=float(occupant.get_meta("nav_radius",.14 if occupant.tank else .034))
		var cells: int=ceili(radius/cell)
		for x in range(center.x-cells,center.x+cells+1):
			for y in range(center.y-cells,center.y+cells+1):
				var id:=Vector2i(x,y)
				if id==start or not grid.is_in_boundsv(id) or grid.is_point_solid(id):continue
				if to_world(id).distance_to(occupant.pos())<radius:saved.append(id);grid.set_point_solid(id,true)
	path_queries+=1
	var result:=grid.get_point_path(start,nearest(dest))
	for id in saved:grid.set_point_solid(id,false)
	return result

func route_length(points: PackedVector2Array) -> float:
	var length: float=0
	for i in range(1,points.size()):length+=points[i-1].distance_to(points[i])
	return length

func soft_offset(anchor: Vector2, ideal: Vector2, max_detour: float=.20) -> Vector2:
	# Local reachable offset search: avoid sending a follower around a long obstacle.
	var candidates: Array=[ideal,anchor.lerp(ideal,.66),anchor.lerp(ideal,.33),anchor]
	for candidate in candidates:
		var p: Vector2=to_world(nearest(candidate))
		var route := path(anchor,p)
		if not route.is_empty() and route_length(route)<=max_detour:return p
	return to_world(nearest(anchor))

func release(unit_id: String) -> void:
	reserved_positions.erase(unit_id)
	for slot in reservations.keys():
		if reservations[slot] == unit_id: reservations.erase(slot)

func slots(c: Dictionary) -> Array:
	if c.get("no_slots",false):return []
	if slot_cache.has(c.id):return slot_cache[c.id]
	if c.kind=="hard":
		var hard: Array=[]
		var center := Vector2(c.position[0],c.position[1])
		for normal in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			var tangent := Vector2(-normal.y,normal.x)
			var depth: float=c.size[0] if normal.x!=0 else c.size[1]
			var width: float=c.size[1] if normal.x!=0 else c.size[0]
			for side in [-1,1]:
				var rest: Vector2=center-normal*(depth*.5+.040)+tangent*(width*.5-.027)*side
				var peek: Vector2=center-normal*(depth*.5+.040)+tangent*(width*.5+.044)*side
				hard.append({"key":c.id+"_"+str(hard.size()),"position":rest,"peek":peek,"normal":normal,"cover_id":c.id,"hard":true})
		slot_cache[c.id]=hard;return hard
	var normal := Vector2(c.normal[0],c.normal[1])
	var tangent := Vector2(-normal.y,normal.x)
	var center := Vector2(c.position[0],c.position[1])
	var depth: float = c.size[0] if normal.x != 0 else c.size[1]
	var result: Array = []
	for side in [-1,1]:
		for i in range(3):
			result.append({"key":c.id+"_"+str(side)+"_"+str(i),"position":center+normal*(depth/2+.035)*side+tangent*(i-1)*.054,"normal":-normal*side,"cover_id":c.id,"peek":center+normal*(depth/2+.035)*side+tangent*(i-1)*.054,"hard":false})
	slot_cache[c.id]=result
	return result

func reserve_slot(id: String, slot: Dictionary) -> void:
	release(id);reservations[slot.key]=id;reserved_positions[id]=slot.position

func choose_cover(id: String, from: Vector2, threat: Vector2, goal: Vector2, options: Dictionary={}) -> Dictionary:
	var candidates: Array=[]
	var threats: Array=options.get("threats",[threat])
	var max_travel: float=options.get("max_travel",.70)
	for c in covers:
		if not c.alive:continue
		for s in slots(c):
			if reservations.has(s.key) and reservations[s.key]!=id:continue
			if float(unavailable_until.get(id+":"+s.key,0))>simulation_time:continue
			if not walkable(s.position):continue
			if reserved_positions.keys().any(func(owner):return owner!=id and reserved_positions[owner].distance_to(s.position)<.048):continue
			if not options.get("allow_same",true) and reservations.get(s.key,"")==id:continue
			var travel: float=from.distance_to(s.position)
			if travel>max_travel:continue
			var facing: float=s.normal.dot((threat-s.position).normalized())
			if facing<.40:continue
			# Hard filter before scoring: this exact object must separate body and threat.
			if not shields(c,s.position,threat):continue
			var snapped_position: Vector2=to_world(nearest(s.position))
			if not shields(c,snapped_position,threat):continue
			if [Vector2(.013,.013),Vector2(-.013,-.013),Vector2(.013,-.013),Vector2(-.013,.013)].any(func(offset):return not shields(c,snapped_position+offset,threat)):continue
			if s.position.distance_to(threat)<minf(.16,from.distance_to(threat)*.65):continue
			var risk: float=0;var arc: bool=false
			for enemy: Vector2 in threats:
				var shield: float=protection(s.position,enemy)
				var visible: bool=line_of_sight(s.position,enemy)
				risk+=(1-shield)*(1.0 if visible else .10)/maxf(.2,s.position.distance_to(enemy))
				if s.position.distance_to(enemy)<float(options.get("range",.9)) and line_of_sight(s.peek,enemy):arc=true
			risk/=maxi(1,threats.size())
			var cost: float=s.position.distance_to(goal)*1.35+travel*.65+risk*.13-facing*.08
			if not arc:cost+=.17
			if reservations.get(s.key,"")==id:cost-=.12
			if s.position.distance_to(threat)<.11:cost+=.5
			var candidate: Dictionary=s.duplicate();candidate["position"]=snapped_position;candidate["peek"]=to_world(nearest(s.peek));candidate["score"]=cost;candidate["risk"]=risk;candidate["fire_arc"]=arc;candidates.append(candidate)
	candidates.sort_custom(func(a,b):return a.score<b.score)
	# Bound expensive A* work to the best candidates, not every station every frame.
	var best: Dictionary={};var best_cost: float=INF
	for candidate in candidates.slice(0,8):
		var route := path(from,candidate.position)
		if route.is_empty():continue
		var length: float=route_length(route)
		if length>maxf(.15,from.distance_to(candidate.position)*float(options.get("detour",1.8))+.05):continue
		if length>max_travel*1.5:continue
		var exposure: float=route_exposure(route,threats)
		if options.get("survival",false) and candidate.position.distance_to(threat)+.03<from.distance_to(threat):continue
		var cost: float=candidate.score+length*.30+exposure*.40
		candidate["route_exposure"]=exposure
		if cost<best_cost:best_cost=cost;best=candidate;best["path_length"]=length
	if not best.is_empty() and options.get("reserve",true):reserve_slot(id,best)
	return best

func protection(p: Vector2, attacker: Vector2) -> float:
	for c in covers:
		if not c.alive: continue
		for s in slots(c):
			if p.distance_to(s.position)<.06 and s.normal.dot((attacker-p).normalized())>.35 and shields(c,p,attacker): return .90 if c.kind=="hard" else .62
	return 0.0

func segment_hits(a: Vector2,b: Vector2,center: Vector2,half: Vector2) -> bool:
	var low: float=0;var high: float=1
	var delta := b-a
	for axis in range(2):
		if absf(delta[axis])<.00001:
			if a[axis]<center[axis]-half[axis] or a[axis]>center[axis]+half[axis]:return false
		else:
			var t1: float=(center[axis]-half[axis]-a[axis])/delta[axis]
			var t2: float=(center[axis]+half[axis]-a[axis])/delta[axis]
			low=maxf(low,minf(t1,t2));high=minf(high,maxf(t1,t2))
			if low>high:return false
	return high>.002 and low<.998

# Slab segment/OBB query. Uses the same dimensions and transform as map colliders,
# independent of PhysicsServer sync, including in fast-forward headless rehearsal.
func ray_box(a: Vector3,b: Vector3,center: Vector3,size: Vector3,yaw: float=0) -> Dictionary:
	var basis := Basis(Vector3.UP,yaw)
	var local_a := basis.inverse()*(a-center)
	var delta := basis.inverse()*(b-a)
	var half := size*.5
	var near: float=0;var far: float=1;var normal := Vector3.ZERO
	for axis in range(3):
		if absf(delta[axis])<.000001:
			if absf(local_a[axis])>half[axis]:return {}
		else:
			var lo: float=(-half[axis]-local_a[axis])/delta[axis]
			var hi: float=(half[axis]-local_a[axis])/delta[axis]
			var enter: float=minf(lo,hi)
			if enter>near:
				near=enter;normal=Vector3.ZERO;normal[axis]=-signf(delta[axis])
			far=minf(far,maxf(lo,hi))
			if near>far:return {}
	if far<.00001 or near>1:return {}
	return {"fraction":near,"point":a.lerp(b,near),"normal":basis*normal}

func cover_ray(c: Dictionary,a: Vector3,b: Vector3) -> Dictionary:
	var sz: Array=c.get("ray_size",[c.size[0],c.height,c.size[1]])
	var center := Vector3(c.position[0],float(c.get("bottom",height))+c.height*.5,c.position[1])
	return ray_box(a,b,center,Vector3(sz[0],sz[1],sz[2]),float(c.get("yaw",0)))

func trace_cover(a: Vector3,b: Vector3,ignore: String="") -> Dictionary:
	ray_queries+=1
	var best: Dictionary={}
	for c in covers:
		if not c.alive or c.id==ignore:continue
		var hit := cover_ray(c,a,b)
		if not hit.is_empty() and (best.is_empty() or hit.fraction<best.fraction):
			best=hit;best["cover_id"]=c.id;best["kind"]="cover"
	for o in obstacles:
		if covers.any(func(c):return c.id=="hard_"+o.id):continue
		var hit:=ray_box(a,b,Vector3(o.position[0],height+.09,o.position[1]),Vector3(o.size[0],.18,o.size[1]))
		if not hit.is_empty() and (best.is_empty() or hit.fraction<best.fraction):best=hit;best["kind"]="cover";best["cover_id"]=o.id
	return best

func shields(c: Dictionary,p: Vector2,threat: Vector2) -> bool:
	var y: float=float(c.get("bottom",height))+minf(c.height*.5,.025)
	return not cover_ray(c,Vector3(p.x,y,p.y),Vector3(threat.x,y,threat.y)).is_empty()

func line_of_sight(a: Vector2,b: Vector2) -> bool:
	return trace_cover(Vector3(a.x,height+.095,a.y),Vector3(b.x,height+.095,b.y)).is_empty()

func route_exposure(points: PackedVector2Array, threats: Array) -> float:
	var exposed: float=0
	for i in range(1,points.size(),3):
		var p: Vector2=points[i]
		for threat: Vector2 in threats:
			if p.distance_to(threat)<.9 and line_of_sight(p,threat):
				exposed+=points[maxi(0,i-3)].distance_to(p)*(1-protection(p,threat));break
	return exposed

func melee_clear(a: Vector2,b: Vector2) -> bool:
	return trace_cover(Vector3(a.x,height+.018,a.y),Vector3(b.x,height+.018,b.y)).is_empty()

func damage_cover(id: String, amount: float) -> bool:
	for c in covers:
		if c.id!=id or not c.alive or c.hp<0:continue
		c.hp=maxf(0,c.hp-amount)
		c.damage_stage="damaged" if c.hp>c.get("max_hp",100)*.4 else "critical"
		if is_instance_valid(c.node):
			# Material change communicates accumulated damage without falsifying geometry.
			for mesh in c.node.find_children("*","MeshInstance3D",true,false):
				if mesh.material_override is StandardMaterial3D:
					if not mesh.has_meta("base_color"):mesh.set_meta("base_color",mesh.material_override.albedo_color);mesh.material_override=mesh.material_override.duplicate()
					mesh.material_override.albedo_color=mesh.get_meta("base_color").darkened(.18 if c.damage_stage=="damaged" else .38)
		if c.hp<=0:
			c.alive=false;c.damage_stage="destroyed";destruction_count+=1
			if is_instance_valid(c.node):
				c.node.visible=false
				if c.node is CollisionObject3D:c.node.collision_layer=0
				for child in c.node.find_children("*","CollisionObject3D",true,false):child.collision_layer=0
			var debris := Node3D.new();add_child(debris)
			debris.position=Vector3(c.position[0],height,c.position[1])
			var rng := RandomNumberGenerator.new();rng.seed=c.id.hash()
			for i in range(9):
				var piece=cube(debris,Vector3(rng.randf_range(-c.size[0]*.65,c.size[0]*.65),.005,rng.randf_range(-c.size[1]*.65,c.size[1]*.65)),Vector3(.014,.009,.019),mat(Color(.34,.30,.23)))
				piece.rotation=Vector3(rng.randf_range(-.3,.3),rng.randf_range(0,TAU),0)
			for key in reservations.keys():
				if key.begins_with(id+"_"):reservations.erase(key)
			rebuild()
			return true
	return false

func snapshot() -> Array:
	var result: Array=[]
	for c in covers:
		var v: Dictionary=c.duplicate()
		v.erase("node")
		result.append(v)
	return result

func inside_object(p: Vector2,o: Dictionary) -> bool:
	return absf(p.x-o.position[0])<o.size[0]*.5 and absf(p.y-o.position[1])<o.size[2]*.5

func ground_height(p: Vector2) -> float:
	for b in config.get("bridges",[]):
		if inside_object(p,b):return .838+b.size[1]
	return height
