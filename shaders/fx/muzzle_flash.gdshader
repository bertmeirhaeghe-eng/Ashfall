shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Muzzle flash petals. Two crossed quads along the barrel (UV.y = 0 at the
// muzzle, 1 at the tip) plus a front-facing star; each shot gets a new seed
// so no two flashes look alike. `fade` runs 1 -> 0 over the flash's life.

#include "res://shaders/fx/fx_common.gdshaderinc"

instance uniform float seed = 0.0;
instance uniform float fade = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float intensity = 6.0;
uniform bool star = false;

void vertex() {
	if (star) {
		// the front star always faces the camera
		float sc = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc, MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec3 col;
	float a;
	if (star) {
		vec2 c = UV * 2.0 - 1.0;
		float r = length(c);
		float ang = atan(c.y, c.x);
		float spikes = pow(abs(cos(ang * 3.0 + seed * 6.0)) + 1e-4, 6.0) * 0.6 + pow(abs(cos(ang * 5.0 + seed * 3.0)) + 1e-4, 12.0) * 0.4;
		float n = fx_noise(vec2(ang * 3.0, seed * 17.0));
		a = smoothstep(1.0, 0.0, r / (0.3 + spikes * (0.5 + 0.4 * n)));
		a += smoothstep(0.35, 0.0, r) * 1.5;
	} else {
		float x = UV.x * 2.0 - 1.0;
		float y = clamp(UV.y, 0.0, 1.0);
		// a tongue of flame that pinches toward the tip, with ragged edges
		float n = fx_fbm(vec2(y * 5.0 - seed * 13.0, x * 2.0 + seed * 7.0));
		float w = mix(0.75, 0.05, pow(y + 1e-4, 0.7)) * (0.7 + 0.6 * n);
		a = smoothstep(w, w * 0.25, abs(x)) * smoothstep(1.0, 0.55 + 0.3 * n, y);
		a *= 0.75 + 0.5 * n;
	}
	vec3 hot = vec3(1.0, 0.95, 0.8);
	col = mix(tint.rgb, hot, clamp(a * a, 0.0, 1.0));
	ALBEDO = col * a * intensity * fade * tint.a;
}
