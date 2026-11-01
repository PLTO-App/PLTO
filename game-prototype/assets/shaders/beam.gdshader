// A soft patch of sunlight on the floor under a window: additive, with the window bars cast as darker stripes and a fade with distance.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 beam_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float strength : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	float fade = 1.0 - smoothstep(0.0, 1.0, UV.y);
	float edge = smoothstep(0.0, 0.07, UV.x) * smoothstep(1.0, 0.93, UV.x) * smoothstep(0.0, 0.05, UV.y);
	float bars = smoothstep(0.015, 0.045, abs(UV.x - 0.3333)) * smoothstep(0.015, 0.045, abs(UV.x - 0.6667));
	ALBEDO = beam_color * strength * fade * edge * (0.45 + 0.55 * bars);
}
