shader_type canvas_item;
// Постобработка поверх 3D:
//  - лёгкий эффект линзы: бочкообразное искажение, хроматическая аберрация к краям, виньетка;
//  - средняя постеризация (в «перцептивном» пространстве, с мягким дизерингом);
//  - размытие в движении для ударов: направленное (хук, апперкот) или «зум» к центру (прямой).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float levels = 16.0;
uniform float distort = 0.07;
uniform float aberration = 0.003;
uniform float vignette = 0.45;
uniform vec2 blur_dir = vec2(0.0);
uniform float blur_amt = 0.0;
uniform float zoom_amt = 0.0;

vec3 sample_lens(vec2 uv) {
	vec2 cc = uv - 0.5;
	float r2 = dot(cc, cc);
	// углы остаются на месте, середина чуть увеличена — как у широкоугольной линзы
	vec2 d = 0.5 + cc * (1.0 - distort + distort * r2 * 2.0);
	vec2 ca = cc * aberration * (r2 * 4.0);
	return vec3(
		texture(screen_tex, d + ca).r,
		texture(screen_tex, d).g,
		texture(screen_tex, d - ca).b);
}

void fragment() {
	vec3 c = vec3(0.0);
	if (blur_amt > 0.0001 || zoom_amt > 0.0001) {
		for (int i = 0; i < 10; i++) {
			float t = float(i) / 9.0 - 0.5;
			c += sample_lens(SCREEN_UV + blur_dir * blur_amt * t + (SCREEN_UV - 0.5) * zoom_amt * t);
		}
		c /= 10.0;
	} else {
		c = sample_lens(SCREEN_UV);
	}
	float r = length(SCREEN_UV - 0.5) * 1.41;
	c *= 1.0 - vignette * smoothstep(0.35, 1.0, r);
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 g = sqrt(max(c, vec3(0.0)));
	g = floor(g * levels + 0.5 + n * 0.3) / levels;
	COLOR = vec4(g * g, 1.0);
}
