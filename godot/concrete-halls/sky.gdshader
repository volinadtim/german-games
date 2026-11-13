shader_type sky;
// Мрачное красноватое небо: тёмный верх, мутно-красный горизонт, медленные «пиксельные» облака
// (шум без сглаживания, тона ступеньками).

uniform sampler2D clouds : filter_nearest, repeat_enable;
uniform vec3 top_color : source_color = vec3(0.07, 0.03, 0.03);
uniform vec3 horizon_color : source_color = vec3(0.36, 0.13, 0.09);
uniform vec3 ground_color : source_color = vec3(0.1, 0.05, 0.04);
uniform vec3 cloud_dark : source_color = vec3(0.05, 0.025, 0.025);
uniform vec3 cloud_lit : source_color = vec3(0.42, 0.17, 0.11);

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 c = mix(horizon_color, top_color, smoothstep(-0.02, 0.55, y));
	c = mix(c, ground_color, smoothstep(0.0, -0.15, y));
	if (y > -0.02) {
		vec2 uv = d.xz / (max(y, 0.0) + 0.12) * 0.05 + vec2(TIME * 0.0015, TIME * 0.0006);
		float n = texture(clouds, uv).r;
		float n2 = texture(clouds, uv * 2.3 + vec2(0.4, 0.7)).r;
		float m = clamp((n - 0.42) * 2.6 + (n2 - 0.5) * 0.6, 0.0, 1.0);
		m = floor(m * 4.0) / 4.0;                     // ступенчатые тона
		float lit = floor(clamp(1.0 - y * 2.0, 0.0, 1.0) * 3.0) / 3.0;   // ближе к горизонту облака подсвечены
		vec3 cc = mix(cloud_dark, cloud_lit, lit * 0.6 + 0.15 * n2);
		c = mix(c, cc, m * 0.85 * smoothstep(-0.02, 0.08, y));
	}
	COLOR = c;
}
