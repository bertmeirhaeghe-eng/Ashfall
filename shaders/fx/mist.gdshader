shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap, specular_disabled, skip_vertex_transform;
// Low mist banks hovering over the battlefield: flat, soft-edged patches of
// swirling noise (one MultiMesh instance each) that drift with the wind and
// wrap around the map. Lit by the scene, so the sun, headlights, fires and
// lightning all light them up. Thins out where it touches the ground or a
// building, near the camera and at the map edges.

#include "res://shaders/fx/fx_common.gdshaderinc"

uniform vec3 mist_color : source_color = vec3(0.92, 0.93, 0.96);
uniform float density = 0.2;
uniform float glow = 0.12;          // faint self-light so the mist still reads at night
uniform vec2 wind = vec2(0.35, 0.12);
uniform vec2 map_size = vec2(80.0, 80.0);
uniform float margin = 12.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 wpos;
varying float seed;
varying float edge_fade;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seed = INSTANCE_CUSTOM.x * 91.7;
	// drift with the wind (each bank a little faster or slower) and wrap round the map
	vec2 span = map_size + vec2(margin * 2.0);
	vec2 p = origin.xz + wind * TIME * (0.7 + 0.6 * INSTANCE_CUSTOM.y) + vec2(margin);
	p = mod(p, span) - vec2(margin);
	vec3 o = vec3(p.x, origin.y + sin(TIME * 0.2 + seed) * 0.15, p.y);
	wpos = o + mat3(MODEL_MATRIX) * VERTEX;
	VERTEX = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	NORMAL = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	// fade out while crossing the map edge so the wrap is never seen
	vec2 inside = min(p, map_size - p);
	edge_fade = clamp(min(inside.x, inside.y) / margin + 0.35, 0.0, 1.0);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	vec2 q = wpos.xz * 0.11 + vec2(seed);
	// slow internal churn
	vec2 warp = vec2(fx_fbm(q + TIME * 0.03), fx_fbm(q.yx - TIME * 0.025)) - 0.5;
	float n = fx_fbm(q * 1.6 + warp * 1.8);
	float wisps = fx_noise(q * 5.0 + warp * 3.0);
	float shape = smoothstep(1.0, 0.25, r + (n - 0.5) * 0.9);
	float a = shape * smoothstep(0.3, 0.75, n + wisps * 0.25) * density * edge_fade;
	// soft where it meets the ground or a building
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -ndc.z / ndc.w;
	a *= clamp((scene_z + VERTEX.z) / 1.5, 0.0, 1.0);
	// never fog up the view right in front of the lens
	a *= smoothstep(4.0, 12.0, -VERTEX.z);
	ALBEDO = mist_color * (0.85 + 0.2 * wisps);
	EMISSION = mist_color * glow;
	ROUGHNESS = 1.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
