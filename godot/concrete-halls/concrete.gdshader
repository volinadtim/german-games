shader_type spatial;
// Бетон, трипланарно в мировых координатах.
//  polished = 0: стены — очень мягкие широкие пятна, лёгкие потёки, плесень у пола/потолка, пыль сверху,
//                затемнение у стыков с полом и потолком, едва заметная неровность.
//  polished = 1: пол/потолок — шлифованный бетон: ровный тон, слабый глянец, швы-распилы, редкая пыль.

uniform sampler2D noise_big : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_fine : filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.27, 0.265, 0.25);
uniform vec3 mold_color : source_color = vec3(0.17, 0.18, 0.15);
uniform vec3 dust_color : source_color = vec3(0.33, 0.31, 0.29);
uniform float ceiling_h = 3.2;
uniform float polished = 0.0;
uniform float joint_step = 3.0;
uniform float bump = 0.25;

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
	float wall = 1.0 - abs(wnrm.y);
	float up = clamp(wnrm.y, 0.0, 1.0);
	float h = wpos.y;
	float big = tri(noise_big, wpos, wnrm, 0.025);
	float mid = tri(noise_big, wpos + vec3(17.0, 3.0, 29.0), wnrm, 0.07);
	float fine = tri(noise_fine, wpos, wnrm, 0.5);
	vec3 col;
	float rough;
	float ao = 1.0;
	float hgt;

	if (polished > 0.5) {
		// шлифованный бетон
		col = base_color * (0.94 + 0.12 * (big - 0.5) + 0.05 * (mid - 0.5) + 0.02 * (fine - 0.5));
		// швы-распилы
		vec2 g = abs(fract(wpos.xz / joint_step + 0.5) - 0.5) * joint_step;
		float joint = 1.0 - smoothstep(0.004, 0.012, min(g.x, g.y));
		col *= 1.0 - 0.45 * joint;
		// редкая мягкая пыль только на полу
		float dust = smoothstep(0.55, 0.85, tri(noise_big, wpos + vec3(31.0, 0.0, 7.0), wnrm, 0.08)) * up;
		col = mix(col, dust_color, dust * 0.25);
		rough = 0.28 + 0.14 * big + 0.35 * dust + 0.3 * joint;
		hgt = 0.0;
	} else {
		col = base_color * (0.95 + 0.1 * (big - 0.5) + 0.05 * (mid - 0.5) + 0.03 * (fine - 0.5));
		// очень крупные мягкие пятна, почти в цвет стены
		float stain = smoothstep(0.35, 0.9, tri(noise_big, wpos * 0.5 + vec3(41.0), wnrm, 0.02));
		col *= 1.0 - 0.1 * stain;
		// лёгкие потёки сверху вниз
		float streak = texture(noise_big, vec2((wpos.x + wpos.z) * 0.25, wpos.y * 0.02)).r;
		col *= 1.0 - 0.06 * smoothstep(0.5, 0.85, streak) * wall;
		// плесень у пола и потолка — широкая и мягкая
		float near_floor = 1.0 - smoothstep(0.0, 1.3, h);
		float near_ceil = smoothstep(ceiling_h - 0.8, ceiling_h, h);
		float mold_n = tri(noise_big, wpos + vec3(5.0, 0.0, 9.0), wnrm, 0.06);
		float mold = smoothstep(0.45, 0.95, mold_n + near_floor * 0.3 + near_ceil * 0.15);
		col = mix(col, mold_color, mold * 0.45);
		// пыль на верхних гранях обломков
		float dust = smoothstep(0.35, 0.75, tri(noise_big, wpos + vec3(31.0, 0.0, 7.0), wnrm, 0.12)) * up;
		col = mix(col, dust_color, dust * 0.4);
		ao = 1.0 - 0.4 * (1.0 - smoothstep(0.0, 0.5, h)) * wall - 0.3 * smoothstep(ceiling_h - 0.45, ceiling_h, h) * wall;
		rough = 0.92 - mold * 0.15;
		// плавная неровность: только низкочастотный шум
		hgt = mid * 0.7 + big * 0.3;
	}

	ALBEDO = col;
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = rough;
	SPECULAR = 0.4;

	if (bump > 0.0 && polished < 0.5) {
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
}
