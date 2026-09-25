shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Fireballs, flame jets and embers: a billowing noise ball that burns from a
// white-hot core to deep orange, then breaks up and dissolves as it ages.
// COLOR comes from the particle colour ramp; INSTANCE_CUSTOM.y is the age (0..1).

#include "res://shaders/fx/fx_common.gdshaderinc"

uniform float intensity = 4.0;
uniform float noise_scale = 3.2;
uniform float softness = 0.35;
uniform vec3 hot_color : source_color = vec3(1.0, 0.95, 0.75);
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float soft_distance = 0.6;

instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying float age;
varying float seed;

void vertex() {
	FX_PARTICLE_BILLBOARD
	age = INSTANCE_CUSTOM.y;
	seed = float(INSTANCE_ID) * 7.31;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	vec2 flow = vec2(seed, seed * 0.37) + vec2(0.0, -TIME * 1.3 - age * 2.0);
	float n = fx_fbm(c * noise_scale + flow);
	float n2 = fx_fbm(c * noise_scale * 2.1 - flow * 0.7 + 3.1);
	// the ball erodes from the edge inward as it cools
	float edge = 1.0 - smoothstep(0.35 - softness * 0.3, 1.0, r + (n - 0.5) * 0.9);
	float burn = smoothstep(age * 0.95, age * 0.95 + softness, n * 0.75 + n2 * 0.4 + (1.0 - r) * 0.35);
	float a = edge * burn;
	float core = smoothstep(0.55, 0.0, r + n * 0.3 + age * 0.8);
	vec3 col = mix((COLOR.rgb * tint.rgb), hot_color, core);
	// soft particles: fade where the billboard cuts the ground or a building
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -ndc.z / ndc.w;
	float soft = clamp((scene_z + VERTEX.z) / soft_distance, 0.0, 1.0);
	ALBEDO = col * intensity * a * (COLOR.a * tint.a) * soft;
}
