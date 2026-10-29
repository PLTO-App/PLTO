// Plain colour with the shared toon lighting (hair, accessories, simple props). A soft sheen band on hair.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/toon_light.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.4, 0.25, 0.15);
uniform float sheen = 0.0;

void fragment() {
	float band = sheen * smoothstep(0.55, 0.8, NORMAL.y) * (1.0 - smoothstep(0.8, 0.95, NORMAL.y));
	ALBEDO = albedo * (1.0 + band * 0.35);
	ROUGHNESS = 0.7;
}
