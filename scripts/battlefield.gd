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

func setup(data: Dictionary) -> void:
	config = data
	height = data.table_height
	cell = data.cell_size
	base = Vector2(data.bounds[0], data.bounds[1])
	for source in data.covers:
		var c: Dictionary = source.duplicate(true)
		c["alive"] = true
		c["node"] = make_cover(c)
		covers.append(c)
	obstacles = data.obstacles.duplicate(true)
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
		if not c.get("alive",true): continue
		var center := Vector2(c.position[0],c.position[1])
		var half := Vector2(c.size[0],c.size[1])/2 + Vector2.ONE*.014
		for x in range(grid.region.size.x):
			for y in range(grid.region.size.y):
				var pos := to_world(Vector2i(x,y))
				if absf(pos.x-center.x)<half.x and absf(pos.y-center.y)<half.y:
					grid.set_point_solid(Vector2i(x,y))
				if absf(pos.x-center.x)<half.x+.075 and absf(pos.y-center.y)<half.y+.075:
					tank_grid.set_point_solid(Vector2i(x,y))
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
	var nav: AStarGrid2D=tank_grid if tank else grid
	return nav.get_point_path(nearest(from,tank),nearest(dest,tank))

func walkable(p: Vector2) -> bool:
	var id := to_cell(p)
	return grid.is_in_boundsv(id) and not grid.is_point_solid(id)

func release(unit_id: String) -> void:
	for slot in reservations.keys():
		if reservations[slot] == unit_id: reservations.erase(slot)

func slots(c: Dictionary) -> Array:
	var normal := Vector2(c.normal[0],c.normal[1])
	var tangent := Vector2(-normal.y,normal.x)
	var center := Vector2(c.position[0],c.position[1])
	var depth: float = c.size[0] if normal.x != 0 else c.size[1]
	var result: Array = []
	for side in [-1,1]:
		for i in range(3):
			result.append({"key":c.id+"_"+str(side)+"_"+str(i),"position":center+normal*(depth/2+.035)*side+tangent*(i-1)*.054,"normal":-normal*side,"cover_id":c.id})
	return result

func choose_cover(id: String, from: Vector2, threat: Vector2, goal: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var score: float = INF
	for c in covers:
		if not c.alive: continue
		for s in slots(c):
			if reservations.has(s.key) and reservations[s.key]!=id: continue
			if not walkable(s.position): continue
			var facing: float = s.normal.dot((threat-s.position).normalized())
			if facing < .15: continue
			var cost: float = s.position.distance_to(goal)*1.2 + from.distance_to(s.position)*.45 - facing*.08
			if cost >= score: continue
			var route := path(from,s.position)
			if route.is_empty(): continue
			score=cost; best=s
	if not best.is_empty():
		release(id); reservations[best.key]=id
	return best

func protection(p: Vector2, attacker: Vector2) -> float:
	for c in covers:
		if not c.alive: continue
		for s in slots(c):
			if p.distance_to(s.position)<.047 and s.normal.dot((attacker-p).normalized())>.35: return .62
	return 0.0

func line_of_sight(a: Vector2,b: Vector2) -> bool:
	for o in obstacles:
		var center := Vector2(o.position[0],o.position[1])
		var half := Vector2(o.size[0],o.size[1])*.5
		var rect := Rect2(center-half,half*2)
		for i in range(1,20):
			if rect.has_point(a.lerp(b,float(i)/20)):return false
	return true

func damage_cover(id: String, amount: float) -> bool:
	for c in covers:
		if c.id!=id or not c.alive or c.hp<0:continue
		c.hp -= amount
		if c.hp<=0:
			c.alive=false
			c.node.scale.y=.18
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
