shader_type spatial;
// Бетон, трипланарно в мировых координатах.
//  polished = 0: стены — шероховатый «каменный» рельеф (зерно, поры), мягкие широкие пятна, плесень у пола/потолка,
//                пыль на верхних гранях, затемнение у стыков, случайные трещины.
//  polished = 1: пол/потолок — шлифованный бетон: ровный тон, лёгкий матовый блеск, случайные трещины, мягкая пыль.

uniform sampler2D noise_big : filter_nearest_mipmap, repeat_enable;
uniform sampler2D noise_fine : filter_nearest_mipmap, repeat_enable;
uniform sampler2D noise_cell : filter_nearest_mipmap, repeat_enable;   // ячеистый шум — зерно камня
uniform sampler2D noise_crack : filter_nearest_mipmap, repeat_enable;  // извилистый шум — трещины
uniform vec3 base_color : source_color = vec3(0.27, 0.265, 0.25);
uniform vec3 mold_color : source_color = vec3(0.17, 0.18, 0.15);
uniform vec3 dust_color : source_color = vec3(0.33, 0.31, 0.29);
uniform float ceiling_h = 3.2;
uniform float polished = 0.0;
uniform float bump = 0.25;
uniform float grain_bump = 0.4;

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

// Случайные трещины: тонкие «гребни» извилистого шума, только там, где их разрешает маска.
float cracks(vec3 p, vec3 n, float density) {
	vec3 warp = vec3(tri(noise_big, p, n, 0.11), 0.0, tri(noise_big, p + vec3(9.0), n, 0.11)) * 1.5;
	float c = tri(noise_crack, p + warp, n, 0.09);
	float d = abs(c - 0.5);
	float w = fwidth(c) * 1.2 + 0.003;
	float line = 1.0 - smoothstep(w * 0.4, w, d);
	float mask = smoothstep(1.0 - density, 1.0 - density + 0.15, tri(noise_big, p + vec3(53.0, 0.0, 11.0), n, 0.06));
	return line * mask;
}

void fragment() {
	float wall = 1.0 - abs(wnrm.y);
	float up = clamp(wnrm.y, 0.0, 1.0);
	float h = wpos.y;
	float big = tri(noise_big, wpos, wnrm, 0.025);
	float mid = tri(noise_big, wpos + vec3(17.0, 3.0, 29.0), wnrm, 0.07);
	float fine = tri(noise_fine, wpos, wnrm, 0.3);
	vec3 col;
	float rough;
	float ao = 1.0;
	float hgt;

	if (polished > 0.5) {
		col = base_color * (0.95 + 0.07 * (big - 0.5) + 0.05 * (mid - 0.5) + 0.03 * (fine - 0.5));
		float cr = 0.0;
		col *= 1.0 - 0.5 * cr;
		float dust = smoothstep(0.55, 0.85, tri(noise_big, wpos + vec3(31.0, 0.0, 7.0), wnrm, 0.08)) * up;
		col = mix(col, dust_color, dust * 0.1);
		rough = 0.5 + 0.12 * big + 0.3 * dust + 0.3 * cr;
		hgt = fine * 0.015 - cr * 0.3;
	} else {
		float cell = tri(noise_cell, wpos, wnrm, 0.45);
		float grain = tri(noise_fine, wpos * 1.4, wnrm, 0.6);
		col = base_color * (0.95 + 0.1 * (big - 0.5) + 0.05 * (mid - 0.5) + 0.06 * (cell - 0.5) + 0.04 * (grain - 0.5));
		float stain = smoothstep(0.35, 0.9, tri(noise_big, wpos * 0.5 + vec3(41.0), wnrm, 0.02));
		col *= 1.0 - 0.05 * stain;
		float streak = texture(noise_big, vec2((wpos.x + wpos.z) * 0.25, wpos.y * 0.02)).r;
		col *= 1.0 - 0.06 * smoothstep(0.5, 0.85, streak) * wall;
		float near_floor = 1.0 - smoothstep(0.0, 1.3, h);
		float near_ceil = smoothstep(ceiling_h - 0.8, ceiling_h, h);
		float mold_n = tri(noise_big, wpos + vec3(5.0, 0.0, 9.0), wnrm, 0.06);
		float mold = smoothstep(0.45, 0.95, mold_n + near_floor * 0.3 + near_ceil * 0.15);
		col = mix(col, mold_color, mold * 0.28);
		float dust = smoothstep(0.35, 0.75, tri(noise_big, wpos + vec3(31.0, 0.0, 7.0), wnrm, 0.12)) * up;
		col = mix(col, dust_color, dust * 0.2);
		float cr = 0.0;
		col *= 1.0 - 0.45 * cr;
		ao = 1.0 - 0.4 * (1.0 - smoothstep(0.0, 0.5, h)) * wall - 0.3 * smoothstep(ceiling_h - 0.45, ceiling_h, h) * wall;
		rough = 0.94 - mold * 0.12;
		// плавные волны + шероховатое зерно камня + углубления трещин
		hgt = (mid * 0.7 + big * 0.3) * (bump / grain_bump) + cell * 0.05 + grain * 0.03 - cr * 0.12;
	}

	ALBEDO = col;
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = rough;
	SPECULAR = 0.3;

	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(hgt);
	float dhy = dFdy(hgt);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grain_bump * grad);
}
