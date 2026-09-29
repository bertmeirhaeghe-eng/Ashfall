shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap, specular_disabled;
// Soft billowing smoke / dust. Lit by the scene lights (so muzzle flashes,
// fires and lightning light it up), with a fake round normal for volume,
// soft edges against the ground and a noisy dissolve as it thins out.

#include "res://shaders/fx/fx_common.gdshaderinc"

uniform float noise_scale = 2.4;
uniform float density = 1.0;
uniform float emission_from_color = 0.0;  // >0: hot smoke glowing at birth
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float soft_distance = 0.8;

instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying float age;
varying float seed;

void vertex() {
	FX_PARTICLE_BILLBOARD
	age = INSTANCE_CUSTOM.y;
	seed = float(INSTANCE_ID) * 3.17;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	vec2 drift = vec2(seed, seed * 1.7) + vec2(TIME * 0.05, -TIME * 0.12);
	float n = fx_fbm(c * noise_scale + drift);
	float n2 = fx_noise(c * noise_scale * 3.0 + drift * 2.0);
	float shape = 1.0 - smoothstep(0.25, 1.0, r + (n - 0.5) * 0.7);
	float thin = smoothstep(age * 0.9 - 0.1, age * 0.9 + 0.35, n * 0.8 + n2 * 0.2 + 0.1);
	float a = shape * thin * (COLOR.a * tint.a) * density;
	// round-ish normal so light wraps around the puff
	vec3 nrm = normalize(vec3(c * 0.8 + (vec2(n, n2) - 0.5) * 0.6, 1.0));
	NORMAL = nrm;
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -ndc.z / ndc.w;
	a *= clamp((scene_z + VERTEX.z) / soft_distance, 0.0, 1.0);
	ALBEDO = (COLOR.rgb * tint.rgb) * (0.75 + 0.35 * n);
	EMISSION = (COLOR.rgb * tint.rgb) * emission_from_color * pow(clamp(1.0 - age, 0.0, 1.0), 3.0) * vec3(1.6, 0.7, 0.25);
	ROUGHNESS = 1.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
