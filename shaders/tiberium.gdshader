shader_type spatial;
// Tiberium crystals: dark glassy roots, bright glowing tips, a fresnel rim
// and a slow pulse that differs per cluster.

uniform vec3 base_color : source_color = vec3(0.1, 0.55, 0.15);
uniform vec3 glow_color : source_color = vec3(0.3, 1.0, 0.35);
uniform float glow = 1.2;
uniform float crystal_height = 0.6;

varying float tip;
varying float phase;

void vertex() {
	tip = clamp(VERTEX.y / crystal_height, 0.0, 1.0);
	vec3 o = MODEL_MATRIX[3].xyz;
	phase = o.x * 1.37 + o.z * 0.71;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	float pulse = 0.78 + 0.22 * sin(TIME * 1.6 + phase);
	// facets catch light differently: fake inner refraction bands
	float band = 0.5 + 0.5 * sin(tip * 18.0 + phase * 3.0);
	ALBEDO = mix(base_color * 0.25, base_color, tip) * (0.85 + 0.15 * band);
	EMISSION = glow_color * glow * pulse * (0.12 + 0.75 * tip * tip + 1.1 * fres + 0.15 * band * tip);
	METALLIC = 0.35;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	RIM = 0.4;
	RIM_TINT = 0.8;
}
