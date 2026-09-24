shader_type canvas_item;
// Darkened, slightly warm screen edges for a bleak cinematic mood.

uniform float strength = 0.55;
uniform vec3 tint : source_color = vec3(0.12, 0.06, 0.02);

void fragment() {
	vec2 d = UV - 0.5;
	d.x *= 1.35;
	float v = smoothstep(0.35, 0.85, length(d));
	COLOR = vec4(tint, v * strength);
}
