shader_type spatial;
// Трава поляны: в том же стиле, что бетон (concrete.gdshader) — цвет из шума без сглаживания (крупные «пиксели»),
// пятна ступенчатые; рельеф — из сглаженного шума. Тусклая жёлто-зелёная, местами проплешины земли.

uniform sampler2D noise_big : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_big_px : filter_nearest_mipmap, repeat_enable;
uniform sampler2D noise_fine_px : filter_nearest_mipmap, repeat_enable;
uniform sampler2D noise_cell_px : filter_nearest_mipmap, repeat_enable;
uniform vec3 green : source_color = vec3(0.13, 0.15, 0.06);
uniform vec3 yellow : source_color = vec3(0.23, 0.21, 0.08);
uniform vec3 dry : source_color = vec3(0.26, 0.22, 0.12);
uniform vec3 dirt : source_color = vec3(0.12, 0.1, 0.075);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float big = texture(noise_big_px, p * 0.02).r;
	float mid = texture(noise_big_px, p * 0.055 + vec2(0.37, 0.11)).r;
	float cell = texture(noise_cell_px, p * 0.07).r;
	float fine = texture(noise_fine_px, p * 0.08 + vec2(0.5, 0.2)).r;
	// ступенчатый переход зелёный → жёлтый (4 тона), как пиксель-арт
	float t = clamp((big - 0.5) * 1.8 + (mid - 0.5) * 0.9 + 0.5, 0.0, 1.0);
	t = floor(t * 3.99) / 3.0;
	vec3 col = mix(green, yellow, t);
	// сухие светлые клочки
	float dr = step(0.68, texture(noise_big_px, p * 0.09 + vec2(0.71, 0.23)).r);
	col = mix(col, dry, dr * 0.5);
	col *= 0.93 + 0.1 * (cell - 0.5) + 0.06 * (fine - 0.5);
	// проплешины земли, на склонах — больше
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float bare = texture(noise_big_px, p * 0.04 + vec2(0.13, 0.61)).r + slope * 1.2;
	col = mix(col, dirt * (0.9 + 0.2 * (fine - 0.5)), step(0.7, bare) * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;

	// мягкий рельеф кочек из сглаженного шума
	float hgt = texture(noise_big, p * 0.055 + vec2(0.37, 0.11)).r * 0.6 + texture(noise_big, p * 0.15).r * 0.25;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(hgt);
	float dhy = dFdy(hgt);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - 0.35 * grad);
}
