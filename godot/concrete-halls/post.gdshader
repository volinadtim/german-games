shader_type canvas_item;
// Постобработка поверх 3D: средняя постеризация (с лёгким дизерингом, чтобы не было грубых ступенек)
// и размытие в движении для ударов: направленное (хук, апперкот) или «зум» к центру (прямой).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float levels = 16.0;
uniform vec2 blur_dir = vec2(0.0);
uniform float blur_amt = 0.0;
uniform float zoom_amt = 0.0;

void fragment() {
	vec3 c = vec3(0.0);
	if (blur_amt > 0.0001 || zoom_amt > 0.0001) {
		for (int i = 0; i < 10; i++) {
			float t = float(i) / 9.0 - 0.5;
			vec2 uv = SCREEN_UV + blur_dir * blur_amt * t + (SCREEN_UV - 0.5) * zoom_amt * t;
			c += texture(screen_tex, uv).rgb;
		}
		c /= 10.0;
	} else {
		c = texture(screen_tex, SCREEN_UV).rgb;
	}
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	// квантуем в «перцептивном» пространстве (sqrt), иначе тёмные тона проваливаются в ноль
	vec3 g = sqrt(max(c, vec3(0.0)));
	g = floor(g * levels + 0.5 + n * 0.3) / levels;
	c = g * g;
	COLOR = vec4(c, 1.0);
}
