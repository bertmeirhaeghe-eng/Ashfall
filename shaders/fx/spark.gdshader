shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
// Velocity-stretched streaks: sparks, hot debris, tracers of shrapnel, rain.
// The particle's Y axis is aligned to its velocity (particle_flag_align_y),
// and the quad turns around that axis to face the camera.

uniform float intensity = 4.0;
uniform float width = 0.03;
uniform float stretch = 1.0;       // extra length along the velocity
uniform bool additive_fade = true; // fade out with the colour ramp alpha

instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying float age;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float alen = length(axis);
	// dead particles have a zero transform: collapse them instead of dividing by zero
	float alive = step(0.00001, alen);
	float len = alen * stretch;
	axis = alive > 0.5 ? axis / alen : vec3(0.0, 1.0, 0.0);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 side = cross(axis, to_cam);
	if (length(side) < 0.001) {
		side = vec3(1.0, 0.0, 0.0);
	}
	side = normalize(side);
	vec3 w = origin + (side * VERTEX.x * width * 2.0 * length(MODEL_MATRIX[0].xyz) + axis * VERTEX.y * len) * alive;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(to_cam, 0.0)).xyz;
	age = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float across = 1.0 - smoothstep(0.0, 1.0, abs(c.x));
	float along = 1.0 - smoothstep(0.2, 1.0, abs(c.y));
	float a = across * across * along * (COLOR.a * tint.a);
	ALBEDO = (COLOR.rgb * tint.rgb) * intensity * a;
}
