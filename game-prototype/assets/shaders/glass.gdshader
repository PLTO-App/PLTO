// Window panes and lamps: a soft sky reflection by day, a warm glow from inside at night (glow is set by the time of day).
shader_type spatial;
render_mode cull_back, unshaded;

uniform float glow : hint_range(0.0, 2.0) = 0.0;
uniform vec3 day_sky : source_color = vec3(0.62, 0.8, 0.95);

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 day = mix(COLOR.rgb * 0.55, day_sky, 0.55 + 0.35 * fres);
	vec3 night = COLOR.rgb * (0.9 + glow);
	ALBEDO = mix(day, night, clamp(glow, 0.0, 1.0));
}
