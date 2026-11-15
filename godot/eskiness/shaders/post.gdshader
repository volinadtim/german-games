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
uniform vec2 blur_center = vec2(0.5, 0.7);   // где кулак на экране: размытие только вокруг него
uniform float blur_radius = 0.22;
// настройки изображения (меню «Настройки»)
uniform float toxic = 0.0;   // отравление наверху без противогаза: искажения и зелёный оттенок
uniform float brightness = 1.0;
uniform float gamma = 1.0;
uniform float contrast = 1.0;

vec3 sample_lens(vec2 uv) {
	uv += vec2(sin(uv.y * 23.0 + TIME * 2.1), cos(uv.x * 19.0 + TIME * 1.7)) * 0.007 * toxic;
	vec2 cc = uv - 0.5;
	float r2 = dot(cc, cc);
	// углы остаются на месте, середина чуть увеличена — как у широкоугольной линзы
	vec2 d = 0.5 + cc * (1.0 - distort + distort * r2 * 2.0);
	vec2 ca = cc * aberration * (r2 * 4.0 + toxic * 6.0);
	return vec3(
		texture(screen_tex, d + ca).r,
		texture(screen_tex, d).g,
		texture(screen_tex, d - ca).b);
}

void fragment() {
	vec3 c = vec3(0.0);
	float bm = 1.0 - smoothstep(blur_radius * 0.4, blur_radius, distance(SCREEN_UV, blur_center));
	if ((blur_amt > 0.0001 || zoom_amt > 0.0001) && bm > 0.001) {
		for (int i = 0; i < 10; i++) {
			float t = float(i) / 9.0 - 0.5;
			c += sample_lens(SCREEN_UV + (blur_dir * blur_amt * t + (SCREEN_UV - blur_center) * zoom_amt * t) * bm);
		}
		c /= 10.0;
	} else {
		c = sample_lens(SCREEN_UV);
	}
	c *= mix(vec3(1.0), vec3(0.8, 1.0, 0.62), toxic * 0.7);
	c *= 1.0 - toxic * 0.35 * smoothstep(0.2, 0.9, length(SCREEN_UV - 0.5) * 1.41);
	c = c * brightness;
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);
	c = pow(c, vec3(1.0 / gamma));
	float r = length(SCREEN_UV - 0.5) * 1.41;
	c *= 1.0 - vignette * smoothstep(0.35, 1.0, r);
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 g = sqrt(max(c, vec3(0.0)));
	g = floor(g * levels + 0.5 + n * 0.3) / levels;
	COLOR = vec4(g * g, 1.0);
}
