// Town and props: the colour comes from the vertex colours painted in Blender (tools/blender/make_town.py), lit with the shared toon light.
// A cheap fake ambient occlusion darkens walls near the ground and the undersides of roofs and canopies, so pieces sit on the street
// instead of floating on it.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/toon_light.gdshaderinc"

uniform float tint_amount = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float ao_height = 2.2;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.38;
uniform float under_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec3 ao_color : source_color = vec3(0.52, 0.44, 0.6);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = mix(COLOR.rgb, COLOR.rgb * tint, tint_amount);
	float side = 1.0 - smoothstep(0.3, 0.8, abs(wnrm.y));
	float near_ground = 1.0 - smoothstep(0.0, ao_height, wpos.y);
	float under = smoothstep(0.1, -0.7, wnrm.y);
	float ao = clamp(ao_strength * side * near_ground + under_strength * under, 0.0, 0.8);
	ALBEDO = c * mix(vec3(1.0), ao_color, ao);
	ROUGHNESS = 0.9;
}
