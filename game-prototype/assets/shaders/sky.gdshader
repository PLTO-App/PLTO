// The sky of the street: a soft gradient, a warm glow around the sun, slow stylised clouds and a few stars at night.
// All colours come from Town.set_time (time of day). No textures, so it costs one cheap full-screen pass.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.3, 0.6, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.88, 0.97);
uniform vec3 ground_color : source_color = vec3(0.55, 0.7, 0.5);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.78, 0.84, 0.93);
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.5;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float drift = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.03 + 17.0; a *= 0.5; }
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.3, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.18, h));
	// glow around the sun
	float sd = 0.0;
	if (LIGHT0_ENABLED) sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
	col += sun_color * (pow(sd, 6.0) * 0.18 + pow(sd, 90.0) * 0.5);
	// clouds on a flat layer above the horizon
	if (h > 0.02) {
		vec2 uv = dir.xz / (h + 0.28) * 1.6 + vec2(drift, drift * 0.3);
		float n = fbm(uv * 1.3);
		float cover = smoothstep(1.0 - cloud_amount, 1.0 - cloud_amount + 0.26, n);
		float lit = smoothstep(0.35, 0.8, fbm(uv * 1.3 + vec2(0.07, 0.11)));
		vec3 cc = mix(cloud_shade, cloud_color, lit);
		cover *= smoothstep(0.0, 0.12, h);
		col = mix(col, cc, cover * 0.92);
	}
	// stars
	if (night > 0.01 && h > 0.0) {
		vec2 sp = dir.xz / (h + 0.3) * 90.0;
		vec2 sc = floor(sp);
		float star = step(0.992, hash(sc)) * smoothstep(0.38, 0.12, length(fract(sp) - 0.5)) * smoothstep(0.05, 0.3, h);
		col += vec3(1.0, 0.95, 0.85) * star * night * 0.9;
	}
	COLOR = col;
}
