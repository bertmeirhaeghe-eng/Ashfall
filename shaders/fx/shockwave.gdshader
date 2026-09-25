shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Expanding ground shockwave / dust ring on a flat quad. `progress` 0 -> 1.

#include "res://shaders/fx/fx_common.gdshaderinc"

instance uniform float progress = 0.0;
instance uniform vec4 ring_color : source_color = vec4(1.0, 0.7, 0.4, 1.0);
uniform float thickness = 0.12;
uniform float intensity = 2.0;

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float ang = atan(c.y, c.x);
	float n = fx_noise(vec2(ang * 6.0, progress * 4.0));
	float radius = progress * (0.9 + 0.1 * n);
	float band = smoothstep(thickness, 0.0, abs(r - radius)) * (0.6 + 0.4 * n);
	float inner = smoothstep(radius, 0.0, r) * 0.15 * (1.0 - progress);
	float a = (band + inner) * (1.0 - progress) * (1.0 - progress);
	ALBEDO = ring_color.rgb * a * intensity * ring_color.a;
}
