shader_type spatial;
// Старый бетон: мягкие широкие пятна, потёки, плесень у пола и в углах, пыль на горизонтальных поверхностях,
// затемнение у пола и потолка (как ambient occlusion на стыках). Проекция трипланарная в мировых координатах.

uniform sampler2D noise_big : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_fine : filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.27, 0.265, 0.25);
uniform vec3 mold_color : source_color = vec3(0.06, 0.075, 0.045);
uniform vec3 dust_color : source_color = vec3(0.36, 0.34, 0.31);
uniform float ceiling_h = 3.2;
uniform float bump = 0.015;

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

void fragment() {
	float up = clamp(wnrm.y, 0.0, 1.0);
	float wall = 1.0 - abs(wnrm.y);
	float h = wpos.y;

	float big = tri(noise_big, wpos, wnrm, 0.05);
	float mid = tri(noise_big, wpos + vec3(17.0, 3.0, 29.0), wnrm, 0.13);
	float fine = tri(noise_fine, wpos, wnrm, 0.5);

	// базовый тон — низкий контраст
	vec3 col = base_color * (0.9 + 0.22 * (big - 0.5) + 0.12 * (mid - 0.5) + 0.06 * (fine - 0.5));

	// широкие смазанные пятна
	float stain = smoothstep(0.5, 0.85, tri(noise_big, wpos * 0.6 + vec3(41.0), wnrm, 0.04));
	col *= 1.0 - 0.22 * stain;

	// потёки на стенах сверху вниз: растягиваем шум по вертикали
	float streak = texture(noise_big, vec2((wpos.x + wpos.z) * 0.35, wpos.y * 0.03)).r;
	col *= 1.0 - 0.12 * smoothstep(0.55, 0.8, streak) * wall;

	// плесень: у пола, у потолка и пятнами
	float near_floor = 1.0 - smoothstep(0.0, 1.1, h);
	float near_ceil = smoothstep(ceiling_h - 0.7, ceiling_h, h);
	float mold_n = tri(noise_big, wpos + vec3(5.0, 0.0, 9.0), wnrm, 0.18);
	float mold = smoothstep(0.55, 0.9, mold_n + near_floor * 0.25 * (wall + 0.3) + near_ceil * 0.15 + (fine - 0.5) * 0.25);
	col = mix(col, mold_color, mold * 0.7);

	// пыль на полу и верхних гранях
	float dust_n = tri(noise_big, wpos + vec3(31.0, 0.0, 7.0), wnrm, 0.12);
	float dust = smoothstep(0.35, 0.75, dust_n + (fine - 0.5) * 0.3) * up;
	col = mix(col, dust_color, dust * 0.45 * (1.0 - mold));

	// затемнение у стыков пол/потолок
	float ao = 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.5, h)) * wall - 0.35 * smoothstep(ceiling_h - 0.45, ceiling_h, h) * wall;

	ALBEDO = col;
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = mix(0.93, 0.98, dust) - mold * 0.25;
	SPECULAR = 0.3;

	// рельеф из мелкого шума (bump без тангенсов)
	float hgt = fine + mid * 0.5;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(hgt);
	float dhy = dFdy(hgt);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - bump * grad);
}
