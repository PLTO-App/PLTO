// Shared soft toon lighting: a two-step ramp with a soft edge, a warm lift in the shadow and a thin rim of light.
// The engine multiplies DIFFUSE_LIGHT by ALBEDO after the light pass.
uniform float toon_soft : hint_range(0.0, 0.5) = 0.08;
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.42;
uniform vec3 shadow_tint : source_color = vec3(0.78, 0.66, 0.74);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.22;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, toon_soft, ndl) * ATTENUATION;
	vec3 shade = mix(shadow_tint * shadow_lift, vec3(1.0), lit);
	DIFFUSE_LIGHT += shade * LIGHT_COLOR / PI;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * smoothstep(-0.2, 0.4, ndl);
	SPECULAR_LIGHT += rim * rim_amount * LIGHT_COLOR * ATTENUATION / PI;
}
