shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
// Lasers, lightning and the Halo Lance: camera-facing ribbons with a white-hot
// core, a coloured corona and crawling energy noise. UV.x runs across the
// ribbon, UV.y along it. `fade` (1 -> 0) and `flicker` drive the life.

#include "res://shaders/fx/fx_common.gdshaderinc"

instance uniform vec4 beam_color : source_color = vec4(0.5, 0.9, 1.0, 1.0);
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;
uniform float intensity = 5.0;
uniform float core_width = 0.18;
uniform float crawl = 1.0;
// true: a unit quad stretched along the node's Y axis (length) and turned to
// face the camera around it (X scale = width). false: a prebuilt ribbon mesh.
uniform bool axis_billboard = true;

void vertex() {
	if (axis_billboard) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		vec3 axis = MODEL_MATRIX[1].xyz;
		float len = length(axis);
		axis /= max(len, 0.0001);
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - origin);
		vec3 side = cross(axis, to_cam);
		side = length(side) < 0.001 ? vec3(1.0, 0.0, 0.0) : normalize(side);
		vec3 w = origin + side * VERTEX.x * length(MODEL_MATRIX[0].xyz) + axis * VERTEX.y * len;
		VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	} else {
		VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float x = clamp(abs(UV.x * 2.0 - 1.0), 0.0, 1.0);
	float n = fx_noise(vec2(UV.y * 22.0 - TIME * 30.0 * crawl + seed * 11.0, seed * 3.0));
	float core = smoothstep(core_width, 0.0, x);
	float glow = pow(1.0 - x, 2.5) * (0.55 + 0.45 * n);
	// the ends taper so the beam never ends in a hard edge
	float ends = smoothstep(0.0, 0.03, UV.y) * smoothstep(1.0, 0.97, UV.y);
	vec3 col = beam_color.rgb * glow + vec3(1.0) * core * 1.3;
	ALBEDO = col * intensity * fade * ends;
}
