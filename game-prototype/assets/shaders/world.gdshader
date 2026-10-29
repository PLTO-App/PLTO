// Town and props: the colour comes from the vertex colours painted in Blender (tools/blender/make_town.py), lit with the shared toon light.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/toon_light.gdshaderinc"

uniform float tint_amount = 0.0;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	ALBEDO = mix(COLOR.rgb, COLOR.rgb * tint, tint_amount);
	ROUGHNESS = 0.9;
}
