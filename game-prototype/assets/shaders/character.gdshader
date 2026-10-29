// The body of a modeled character: skin, clothes and face in one draw call (see tools/blender/make_characters.py).
// COLOR.r = region / 4 (0 arm, 1 torso and neck, 2 leg, 3 foot, 4 head). On the body UV = rest (x, height) and UV2 = (position
// along the limb 0..1, rest depth, negative is the front). On the head UV is the face projection. Clothing edges come from these
// continuous values, so they stay smooth.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/toon_light.gdshaderinc"

uniform vec3 skin_color : source_color = vec3(0.96, 0.78, 0.65);
uniform vec3 top_color : source_color = vec3(0.95, 0.93, 0.9);
uniform vec3 bottom_color : source_color = vec3(0.2, 0.25, 0.36);
uniform vec3 shoes_color : source_color = vec3(0.42, 0.25, 0.16);
uniform vec3 apron_color : source_color = vec3(0.94, 0.44, 0.54);
uniform float sleeve = 0.42;        // arm position where the sleeve ends (1 = long sleeves)
uniform float pants = 1.0;          // leg position where the trousers end (0.5 = shorts at the knee)
uniform float waist = 1.08;         // height of the waistline
uniform float collar = 1.66;        // height of the neckline
uniform float shoe_top = 0.15;
uniform float apron_on = 0.0;
uniform sampler2D face_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 face_cell = vec2(1.0, 0.0);

void fragment() {
	int region = int(round(COLOR.r * 4.0));
	vec3 c = skin_color;
	float h = UV.y;
	if (region == 4) {
		if (UV.x >= 0.0 && UV.x <= 1.0 && UV.y >= 0.0 && UV.y <= 1.0) {
			vec4 f = texture(face_tex, (face_cell + UV) / 3.0);
			c = mix(c, f.rgb, f.a);
		}
	} else {
		if (region == 0) c = UV2.x < sleeve ? top_color : skin_color;
		else if (region == 1) c = h < waist ? bottom_color : (h < collar ? top_color : skin_color);
		else if (region == 2) c = UV2.x < pants ? bottom_color : skin_color;
		if (region >= 2 && h < shoe_top) c = shoes_color;
		if (region == 3) c = shoes_color;
		// apron: a front panel from the chest to the upper thighs, a narrower bib above the waist
		if (apron_on > 0.5 && region >= 1 && region <= 2 && UV2.y < -0.04) {
			float w = h > 1.2 ? 0.12 : 0.2;
			if (abs(UV.x) < w && h > 0.66 && h < 1.5) c = apron_color;
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
