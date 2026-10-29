// Street surfaces drawn procedurally in world space: asphalt with a little grain, paving stones, grass. kind: 0 asphalt, 1 pavers, 2 grass.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/toon_light.gdshaderinc"

uniform int kind = 0;
uniform vec3 base : source_color = vec3(0.35, 0.36, 0.4);
uniform vec3 line : source_color = vec3(0.8, 0.78, 0.74);
uniform float tile = 1.2;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = base;
	vec2 p = wpos.xz;
	if (kind == 0) {
		float n = hash(floor(p * 6.0));
		c *= 0.94 + 0.08 * n;
	} else if (kind == 1) {
		vec2 q = p / tile;
		q.x += 0.5 * step(1.0, mod(floor(q.y), 2.0));
		vec2 f = fract(q);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float n = hash(floor(q));
		c *= 0.9 + 0.14 * n;
		c = mix(line, c, smoothstep(0.02, 0.06, edge));
	} else {
		float n = hash(floor(p * 3.0));
		c *= 0.9 + 0.15 * n;
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
