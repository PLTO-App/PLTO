class_name PrimGoods
extends RefCounted
# Packaged goods for the minimarket (milk, eggs, yoghurt, water, soda, snacks, pasta, fruit), built in code from a few boxes,
# cylinders and spheres in the town's flat colours (vertex colours, like the models made by the Blender tools). Original shapes,
# no files. A good faces the +z side (the front) and stands on y = 0, like the other food models.

const IDS := ["milkcart", "eggs", "yogurt", "water", "soda", "snack", "pasta", "fruit"]

static func has(model: String) -> bool:
	return model.begins_with("goods_") and model.substr(6) in IDS

# model: "goods_<id>"
static func make(model: String) -> Node3D:
	var root := Node3D.new()
	match model.substr(6):
		"milkcart":
			_box(root, Vector3(0.2, 0.3, 0.12), Color("f6f4ee"), Vector3(0, 0.15, 0))
			_box(root, Vector3(0.2, 0.12, 0.12), Color("3b82d6"), Vector3(0, 0.1, 0.001))
			_box(root, Vector3(0.2, 0.1, 0.06), Color("f6f4ee"), Vector3(0, 0.34, 0), 0.0, true)
			_cyl(root, 0.035, 0.035, 0.03, Color("3b82d6"), Vector3(0, 0.37, 0))
		"eggs":
			_box(root, Vector3(0.3, 0.06, 0.2), Color("d9c7a3"), Vector3(0, 0.03, 0))
			for i in 3:
				_sphere(root, 0.05, Color("f3e3c3"), Vector3(-0.1 + i * 0.1, 0.09, 0.04), Vector3(1, 1.25, 1))
				_sphere(root, 0.05, Color("f3e3c3"), Vector3(-0.1 + i * 0.1, 0.09, -0.04), Vector3(1, 1.25, 1))
			_box(root, Vector3(0.3, 0.012, 0.2), Color("c2b08c"), Vector3(0, 0.062, 0))
		"yogurt":
			_cyl(root, 0.05, 0.036, 0.1, Color("fbf7f0"), Vector3(0, 0.05, 0))
			_cyl(root, 0.052, 0.052, 0.03, Color("ef6f8a"), Vector3(0, 0.085, 0))
			_cyl(root, 0.05, 0.05, 0.008, Color("d9dde3"), Vector3(0, 0.104, 0))
		"water":
			_cyl(root, 0.045, 0.045, 0.22, Color("bfe3f7"), Vector3(0, 0.11, 0))
			_cyl(root, 0.025, 0.04, 0.05, Color("bfe3f7"), Vector3(0, 0.245, 0))
			_cyl(root, 0.02, 0.02, 0.03, Color("2f6fcf"), Vector3(0, 0.285, 0))
			_cyl(root, 0.047, 0.047, 0.07, Color("2f6fcf"), Vector3(0, 0.11, 0))
		"soda":
			_cyl(root, 0.04, 0.04, 0.13, Color("e94b4b"), Vector3(0, 0.065, 0))
			_cyl(root, 0.041, 0.041, 0.035, Color("f6f4ee"), Vector3(0, 0.07, 0))
			_cyl(root, 0.034, 0.04, 0.012, Color("c9ced6"), Vector3(0, 0.136, 0))
		"snack":
			_box(root, Vector3(0.17, 0.26, 0.05), Color("f5b83d"), Vector3(0, 0.13, 0))
			_box(root, Vector3(0.17, 0.05, 0.06), Color("e8891c"), Vector3(0, 0.255, 0))
			_box(root, Vector3(0.17, 0.04, 0.06), Color("e8891c"), Vector3(0, 0.02, 0))
			_sphere(root, 0.04, Color("fff1c4"), Vector3(0, 0.14, 0.03), Vector3(1.4, 1.0, 0.5))
		"pasta":
			_box(root, Vector3(0.18, 0.26, 0.05), Color("f2d9a0"), Vector3(0, 0.13, 0))
			_box(root, Vector3(0.18, 0.09, 0.052), Color("c0392b"), Vector3(0, 0.13, 0.001))
			_box(root, Vector3(0.12, 0.02, 0.054), Color("fff6ea"), Vector3(0, 0.13, 0.002))
		"fruit":
			_box(root, Vector3(0.5, 0.14, 0.32), Color("b98b63"), Vector3(0, 0.07, 0))
			_box(root, Vector3(0.52, 0.03, 0.34), Color("a97f57"), Vector3(0, 0.135, 0))
			var cols := [Color("e94b4b"), Color("f08a2a"), Color("7bc043"), Color("e94b4b"), Color("f5b83d"), Color("7bc043")]
			for i in 6:
				_sphere(root, 0.07, cols[i], Vector3(-0.17 + (i % 3) * 0.17, 0.2 + (0.0 if i < 3 else 0.0), (-0.07 if i < 3 else 0.08)), Vector3.ONE)
	_flat(root)
	return root

# ---------------------------------------------------------------- parts
static func _colored(prim: PrimitiveMesh, color: Color) -> ArrayMesh:
	var arrays := prim.get_mesh_arrays()
	var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var cols := PackedColorArray(); cols.resize(n); cols.fill(color)
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

static func _add(root: Node3D, prim: PrimitiveMesh, color: Color, pos: Vector3, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = _colored(prim, color); mi.position = pos; mi.scale = scale; root.add_child(mi)
	return mi

static func _box(root: Node3D, size: Vector3, color: Color, pos: Vector3, _unused := 0.0, gable := false) -> void:
	if gable:
		var pm := PrismMesh.new(); pm.size = size; _add(root, pm, color, pos)
	else:
		var bm := BoxMesh.new(); bm.size = size; _add(root, bm, color, pos)

static func _cyl(root: Node3D, top: float, bottom: float, h: float, color: Color, pos: Vector3) -> void:
	var cm := CylinderMesh.new(); cm.top_radius = top; cm.bottom_radius = bottom; cm.height = h; cm.radial_segments = 14; cm.rings = 1; _add(root, cm, color, pos)

static func _sphere(root: Node3D, r: float, color: Color, pos: Vector3, scale: Vector3) -> void:
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 12; sm.rings = 6; _add(root, sm, color, pos, scale)

# The town's materials (vertex colours with the shared toon light), no shadows.
static func _flat(root: Node3D) -> void:
	Town._apply(root, false)
