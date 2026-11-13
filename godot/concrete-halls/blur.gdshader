shader_type canvas_item;
// Фон меню и паузы: лёгкое размытие, виньетка, слабый плёночный шум
// и затемнение справа — будто игровой автомат светит в темноту.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod : hint_range(0.0, 6.0) = 1.0;
uniform float spread = 2.0;
uniform float darken = 0.88;
uniform float vignette = 0.55;
uniform float grain = 0.045;
uniform float right_dark = 0.6;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * spread;
	vec3 c = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			c += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px, lod).rgb;
		}
	}
	c /= 9.0;
	c *= darken;
	// виньетка
	float r = length((SCREEN_UV - 0.5) * vec2(1.0, 0.85)) * 1.45;
	c *= 1.0 - vignette * smoothstep(0.35, 1.05, r);
	// затемнение у правого края
	c *= 1.0 - right_dark * smoothstep(0.78, 1.0, SCREEN_UV.x);
	// слабый шум, меняется каждый кадр
	float n = fract(sin(dot(FRAGCOORD.xy + vec2(TIME * 61.0, TIME * 37.0), vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) * grain;
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
