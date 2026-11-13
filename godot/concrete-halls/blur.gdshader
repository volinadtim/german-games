shader_type canvas_item;
// Размытие фона меню + затемнение и виньетка.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod : hint_range(0.0, 6.0) = 2.5;
uniform float spread = 5.0;
uniform float darken = 0.7;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * spread;
	vec3 c = vec3(0.0);
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			c += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px, lod).rgb;
		}
	}
	c /= 25.0;
	float v = smoothstep(1.0, 0.25, length(SCREEN_UV - 0.5) * 1.5);
	COLOR = vec4(c * darken * mix(0.45, 1.0, v), 1.0);
}
