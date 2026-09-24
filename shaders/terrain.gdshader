shader_type spatial;
// Tiberian Sun-style wasteland ground: ochre dirt, dark olive scrub patches,
// dusty flats, cracked grain and layered rock on steep slopes and cliffs.
// COLOR.r = cliff (0 walkable ground .. 1 raised rock), COLOR.g = baked occlusion.

uniform sampler2D cell_map : source_color, filter_linear;  // per-cell stains (rgb) with strength (a)
uniform vec2 map_size = vec2(80.0, 80.0);
uniform sampler2D patch_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D crack_noise : filter_linear_mipmap, repeat_enable;

uniform vec3 dirt_a : source_color = vec3(0.4, 0.29, 0.16);
uniform vec3 dirt_b : source_color = vec3(0.3, 0.22, 0.13);
uniform vec3 dust : source_color = vec3(0.5, 0.4, 0.26);
uniform vec3 scrub : source_color = vec3(0.16, 0.17, 0.11);
uniform vec3 rock_light : source_color = vec3(0.3, 0.28, 0.25);
uniform vec3 rock_dark : source_color = vec3(0.05, 0.045, 0.04);

varying vec3 wpos;
varying vec3 wnorm;
varying vec2 vdata;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdata = COLOR.rg;
}

void fragment() {
	vec2 p = wpos.xz;
	float big = texture(patch_noise, p * 0.021).r;
	float mid = texture(patch_noise, p * 0.071 + vec2(0.37, 0.61)).r;
	float small = texture(patch_noise, p * 0.23 + vec2(0.11, 0.83)).r;
	float grain = texture(grain_noise, p * 0.45).r;
	float grain2 = texture(grain_noise, p * 1.7 + vec2(0.5)).r;
	float crack = texture(crack_noise, p * 0.55).r;

	// ground: ochre dirt with darker bands, dark scrub patches and pale dust flats
	vec3 col = mix(dirt_a, dirt_b, smoothstep(0.35, 0.7, mid));
	float scrub_w = smoothstep(0.54, 0.66, big + (small - 0.5) * 0.35);
	col = mix(col, scrub * (0.8 + 0.4 * small), scrub_w * 0.9);
	float dust_w = smoothstep(0.66, 0.82, 1.0 - big + (mid - 0.5) * 0.3);
	col = mix(col, dust, dust_w * 0.55);
	col *= 0.72 + 0.4 * grain;                 // clods and pebbles
	col *= mix(0.86, 1.08, grain2);             // fine grit
	// dry cracks, mostly on the pale dust flats, broken up by the grain
	float crack_w = (0.15 + 0.6 * dust_w) * smoothstep(0.35, 0.65, small + grain * 0.4);
	col *= 1.0 - crack_w * (1.0 - smoothstep(0.0, 0.05, crack));

	// rock: vertical weathering streaks and ledges, dark in the crevices
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	// run the streaks straight down each cliff face
	vec3 fn = normalize(cross(dFdy(wpos), dFdx(wpos)));  // per-facet normal: steady streak direction
	vec2 t = normalize(vec2(-fn.z, fn.x) + vec2(0.0001, 0.0));
	float along = dot(p, t);
	float streak = texture(grain_noise, vec2(along * 0.28, wpos.y * 0.04)).r;
	float streak2 = texture(grain_noise, vec2(along * 0.7 + 0.3, wpos.y * 0.09)).r;
	float ledge = texture(grain_noise, vec2(along * 0.3, wpos.y * 3.0)).r;
	vec3 rock = mix(rock_dark, rock_light, smoothstep(0.25, 0.75, streak * 0.55 + streak2 * 0.45 + ledge * 0.2 - 0.1));
	rock *= 0.75 + 0.4 * grain2;
	// flat tops of plateaus: rubble-strewn dirt, a bit darker than the lowlands
	rock = mix(rock, col * 0.6, smoothstep(0.35, 0.12, slope) * 0.6);
	float rock_w = clamp(smoothstep(0.28, 0.55, slope) + vdata.r * smoothstep(0.05, 0.25, slope + grain * 0.2), 0.0, 1.0);
	col = mix(col, rock, rock_w);

	// per-cell stains (tiberium-poisoned soil)
	vec4 cm = texture(cell_map, p / map_size);
	col = mix(col, cm.rgb * (0.75 + 0.5 * grain), cm.a * (1.0 - rock_w));

	col *= mix(0.45, 1.0, vdata.g);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
