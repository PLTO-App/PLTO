class_name BlobShadow
extends MeshInstance3D
# A soft dark disc under a character. The sun's shadow is hard and thin, so this grounds characters cheaply (one quad).

static var _mat: StandardMaterial3D

static func make(size: float) -> BlobShadow:
	var b := BlobShadow.new()
	var q := QuadMesh.new(); q.size = Vector2(size * 2.0, size * 2.0); b.mesh = q
	if _mat == null:
		_mat = StandardMaterial3D.new(); _mat.albedo_texture = load("res://assets/ui/blob_shadow.png")
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; _mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED; _mat.no_depth_test = false
	b.material_override = _mat; b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.rotation.x = -PI / 2.0; b.position.y = 0.06
	return b
