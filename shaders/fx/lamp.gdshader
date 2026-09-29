shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled;
// Glowing lamp lens / warning light. `mode`: 0 steady, 1 blink, 2 strobe,
// 3 flicker (fire / failing power). The glow feeds the scene's bloom.

instance uniform vec4 lamp_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
instance uniform float energy = 3.0;
instance uniform float phase = 0.0;
instance uniform int mode = 0;

float flick(float t) {
	return 0.75 + 0.25 * sin(t * 23.0) * sin(t * 7.3 + 1.3);
}

void fragment() {
	float k = 1.0;
	float t = TIME + phase;
	if (mode == 1) {
		k = step(0.5, fract(t * 0.9)) * 0.9 + 0.1;
	} else if (mode == 2) {
		k = step(0.92, fract(t * 1.1)) + 0.05;
	} else if (mode == 3) {
		k = flick(t);
	}
	ALBEDO = lamp_color.rgb * energy * k;
}
