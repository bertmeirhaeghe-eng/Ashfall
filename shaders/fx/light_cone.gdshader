shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Fake volumetric beam for headlights, flashlights and searchlights: a cone
// mesh (tip at the lamp, UV.y 0 -> 1 along the beam) that glows brightest near
// the lamp and along its axis, fades softly at the rim and where it meets the
// ground, with slow drifting dust. Scaled by the scene darkness.

#include "res://shaders/fx/fx_common.gdshaderinc"

instance uniform vec4 beam_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
instance uniform float strength = 1.0;
uniform float intensity = 0.24;
// How quickly the beam fades toward its sides. Higher = softer, narrower-looking core.
uniform float edge_power : hint_range(1.0, 8.0) = 3.5;
// Fraction of the beam length where the fade-out begins; light is exactly 0 at the far end.
uniform float fade_start : hint_range(0.0, 0.99) = 0.35;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float f = smoothstep(0.0, 0.85, clamp(facing, 0.0, 1.0));
	float rim = pow(f, edge_power);
	float along = clamp(UV.y, 0.0, 1.0);
	float end_fade = 1.0 - smoothstep(fade_start, 1.0, along);
	float falloff = pow(1.0 - along, 1.7) * end_fade * end_fade;
	float dust = 0.75 + 0.5 * fx_noise(wpos.xz * 1.3 + vec2(TIME * 0.21, TIME * 0.13)) * fx_noise(wpos.xy * 2.1 - TIME * 0.17);
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -ndc.z / ndc.w;
	float soft = clamp((scene_z + VERTEX.z) / 1.2, 0.0, 1.0);
	ALBEDO = beam_color.rgb * intensity * strength * rim * falloff * dust * soft;
}
