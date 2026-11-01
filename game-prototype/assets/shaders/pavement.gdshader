// Street surfaces drawn procedurally in world space: asphalt with grain, wear and cracks, paving stones with soft joints,
// grass with patches, mowing stripes and tiny flowers, and wooden plank floors. kind: 0 asphalt, 1 pavers, 2 grass, 3 planks.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/toon_light.gdshaderinc"

uniform int kind = 0;
uniform vec3 base : source_color = vec3(0.35, 0.36, 0.4);
uniform vec3 line : source_color = vec3(0.8, 0.78, 0.74);
uniform float tile = 1.2;
varying vec3 wpos;
varying vec3 lpos;
uniform vec2 room_half = vec2(6.3, 4.3);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}

void fragment() {
	vec3 c = base;
	vec2 p = wpos.xz;
	if (kind == 0) {
		// asphalt: fine grain, large soft blotches, a darker wheel track in each lane, a repair patch here and there
		float grain = hash(floor(p * 9.0));
		float blot = vnoise(p * 0.45);
		c *= 0.9 + 0.07 * grain + 0.14 * blot;
		float lane = abs(fract(wpos.z / 3.6 + 0.5) - 0.5);
		float track = smoothstep(0.17, 0.0, abs(lane - 0.2));
		c *= 1.0 - 0.1 * track;
		// patched repair rectangle here and there
		vec2 cell = floor(p / vec2(9.0, 3.4));
		float patch_on = step(0.78, hash(cell));
		vec2 pf = fract(p / vec2(9.0, 3.4));
		float in_patch = step(0.35, pf.x) * step(pf.x, 0.55) * step(0.3, pf.y) * step(pf.y, 0.5);
		c *= 1.0 - 0.1 * patch_on * in_patch;
	} else if (kind == 1) {
		vec2 q = p / tile;
		q.x += 0.5 * step(1.0, mod(floor(q.y), 2.0));
		vec2 f = fract(q);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float n = hash(floor(q));
		float warm = hash(floor(q) + 7.0);
		c *= 0.9 + 0.14 * n;
		c = mix(c, c * vec3(1.04, 1.0, 0.94), warm);
		// soft inner shading toward the joints, then the joint itself
		c *= 0.93 + 0.07 * smoothstep(0.02, 0.2, edge);
		c = mix(line, c, smoothstep(0.02, 0.055, edge));
	} else if (kind == 3) {
		// wooden planks along x: every row is shifted, each plank has its own tone, grain and a soft dark joint;
		// the floor darkens a little toward the walls (the front of the room is open)
		float plank_w = 0.55 * tile; float plank_l = 3.2 * tile;
		vec2 q = vec2(p.x / plank_l, p.y / plank_w);
		float row = floor(q.y);
		q.x += hash(vec2(row, 3.0)) * 5.0;
		float col = floor(q.x);
		vec2 f = fract(q);
		float tone = hash(vec2(col, row));
		c *= 0.84 + 0.3 * tone;
		float grain = vnoise(vec2(p.x * 1.6, p.y * 16.0 + tone * 30.0));
		c *= 0.92 + 0.14 * grain;
		float edge = min(min(f.x, 1.0 - f.x) * plank_l, min(f.y, 1.0 - f.y) * plank_w);
		c *= 0.94 + 0.06 * smoothstep(0.02, 0.12, edge);
		c = mix(line, c, smoothstep(0.012, 0.035, edge));
		float to_wall = min(room_half.x - abs(lpos.x), lpos.z + room_half.y);
		c *= mix(0.7, 1.0, smoothstep(0.0, 1.6, to_wall));
	} else {
		// grass: big colour patches, fine blades, diagonal mowing stripes, scattered flowers
		float patches = vnoise(p * 0.22);
		float blades = vnoise(p * 3.2);
		float stripes = smoothstep(0.42, 0.58, abs(fract((p.x + p.y * 0.35) * 0.16) - 0.5) * 2.0);
		c *= 0.8 + 0.28 * patches;
		c *= 0.93 + 0.12 * blades;
		c *= 0.95 + 0.08 * stripes;
		c = mix(c, c * vec3(1.08, 1.02, 0.7), smoothstep(0.62, 0.82, vnoise(p * 0.12 + 5.0)) * 0.6);
		vec2 fc = floor(p * 3.0);
		float fl = step(0.975, hash(fc));
		vec2 fcen = fract(p * 3.0) - 0.5;
		float dot_ = smoothstep(0.17, 0.1, length(fcen)) * fl;
		vec3 petal = mix(vec3(1.0, 0.97, 0.88), vec3(1.0, 0.82, 0.3), step(0.5, hash(fc + 3.0)));
		c = mix(c, petal, dot_);
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
