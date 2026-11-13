shader_type spatial;
// Старый крашеный металл и потускневший хром (автомат KILLBOX и всё железное в бункере).
// Трипланарно в мировых координатах, как concrete.gdshader: цвет — крупные «пиксели» (шум без сглаживания),
// без мелкой ряби. Краска выцвела и облупилась пятнами до тёмного металла, в сколах и подтёках ржавчина,
// на верхних гранях пыль, внизу — грязь. chrome = 1: тусклый хром в пятнах и с царапинами.

uniform sampler2D n_px : filter_nearest_mipmap, repeat_enable;
uniform sampler2D n_lin : filter_linear_mipmap, repeat_enable;
uniform vec3 paint_color : source_color = vec3(0.34, 0.04, 0.05);
uniform vec3 under_color : source_color = vec3(0.13, 0.12, 0.11);
uniform vec3 rust_color : source_color = vec3(0.32, 0.15, 0.07);
uniform vec3 dust_color : source_color = vec3(0.34, 0.32, 0.29);
uniform float chrome = 0.0;
uniform float wear = 0.3;      // доля облупившейся краски
uniform float rust = 0.6;
uniform float dust = 0.6;
uniform float base_y = 0.0;    // уровень пола — у пола больше грязи и сколов

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy * s).r * w.x + texture(t, p.xz * s).r * w.y + texture(t, p.xy * s).r * w.z;
}

// отдельная функция для сглаженной текстуры (Godot не даёт звать одну функцию с разными фильтрами)
float tri_lin(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy * s).r * w.x + texture(t, p.xz * s).r * w.y + texture(t, p.xy * s).r * w.z;
}

void fragment() {
	float up = clamp(wnrm.y, 0.0, 1.0);
	float side = 1.0 - abs(wnrm.y);
	float h = wpos.y - base_y;
	float big = tri(n_px, wpos, wnrm, 0.5);
	float mid = tri(n_px, wpos + vec3(7.0, 3.0, 11.0), wnrm, 1.4);
	float fine = tri(n_px, wpos + vec3(3.0, 9.0, 1.0), wnrm, 3.5);
	vec3 col;
	float metal;
	float rough;
	float chip = 0.0;

	if (chrome > 0.5) {
		col = paint_color * (0.8 + 0.3 * (mid - 0.5));
		float spots = smoothstep(0.55, 0.72, tri(n_px, wpos + vec3(19.0), wnrm, 2.5));
		col = mix(col, col * 0.4 + rust_color * 0.3, spots * 0.75);
		// царапины — короткие светлые чёрточки (вытянутый шум)
		float sc = texture(n_px, vec2((wpos.x + wpos.z) * 0.6, wpos.y * 7.0)).r;
		float scr = smoothstep(0.8, 0.84, sc) * (1.0 - spots);
		col = mix(col, col * 1.4 + vec3(0.04), scr * 0.45);
		metal = 0.75 - spots * 0.45;
		rough = 0.5 + spots * 0.35 + 0.1 * fine;
	} else {
		// выцветшая, местами меловая краска
		col = paint_color * (0.86 + 0.2 * (big - 0.5) + 0.08 * (fine - 0.5));
		col = mix(col, col * 0.7 + vec3(0.05, 0.045, 0.04), 0.35 * smoothstep(0.4, 0.8, mid));
		// облупившиеся пятна: крупными «пикселями», у пола чаще
		float chip_n = tri(n_px, wpos + vec3(31.0, 0.0, 7.0), wnrm, 2.0) * 0.65 + fine * 0.35;
		float bias = (1.0 - smoothstep(0.0, 0.6, h)) * 0.18;
		chip = step(1.0 - wear - bias, chip_n);
		col = mix(col, under_color * (0.8 + 0.4 * fine), chip);
		// ржавчина в сколах и рыжие подтёки вниз от них
		float r_n = tri(n_px, wpos + vec3(5.0, 13.0, 2.0), wnrm, 3.0);
		float in_chip = chip * smoothstep(0.35, 0.65, r_n) * rust;
		float streak = texture(n_px, vec2((wpos.x + wpos.z) * 1.7, wpos.y * 0.12)).r;
		float st = smoothstep(0.62, 0.85, streak) * side * rust * smoothstep(0.3, 0.7, big);
		col = mix(col, rust_color * (0.75 + 0.5 * r_n), max(in_chip, st * 0.55));
		metal = chip * 0.45;
		rough = 0.62 + 0.25 * chip + 0.1 * fine;
	}

	// пыль на верхних гранях и грязь у пола
	float dn = tri(n_px, wpos + vec3(41.0, 0.0, 3.0), wnrm, 1.1);
	float d = up * smoothstep(0.25, 0.65, dn) * dust;
	col = mix(col, dust_color, d * 0.85);
	float grime = (1.0 - smoothstep(0.0, 0.5, h)) * dust * smoothstep(0.2, 0.6, dn + 0.15);
	col = mix(col, dust_color * 0.6, grime * 0.55);
	rough = mix(rough, 0.95, max(d, grime * 0.6));
	metal *= 1.0 - max(d, grime);

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.4;

	// лёгкий рельеф: краска толще металла под ней, волны вмятин
	float hgt = -chip * 0.02 + tri_lin(n_lin, wpos + vec3(23.0), wnrm, 0.8) * 0.015;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(hgt);
	float dhy = dFdy(hgt);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
