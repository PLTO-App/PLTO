// Window panes and lamps: a soft sky reflection with a diagonal glint by day, a warm glow from inside at night (glow is set by the time of day).
shader_type spatial;
render_mode cull_back, unshaded;

uniform float glow : hint_range(0.0, 2.0) = 0.0;
uniform vec3 day_sky : source_color = vec3(0.62, 0.8, 0.95);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 day = mix(COLOR.rgb * 0.8, day_sky, 0.36 + 0.36 * fres);
	float s = fract((wpos.x * 0.55 + wpos.y * 0.9) * 0.4);
	float streak = smoothstep(0.0, 0.05, s) * (1.0 - smoothstep(0.12, 0.2, s));
	day += vec3(0.22, 0.24, 0.26) * streak;
	vec3 night = COLOR.rgb * (0.9 + glow);
	ALBEDO = mix(day, night, clamp(glow, 0.0, 1.0));
}
