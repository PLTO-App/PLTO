// Ink outline: the mesh drawn again slightly larger with its front faces culled (inverted hull).
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(0.16, 0.09, 0.07);
uniform float width = 0.012;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color;
}
