shader_type spatial;
render_mode unshaded, cull_disabled;
// Мошка у лампы: крошечный пиксельный силуэт, всегда лицом к камере, крылышки «машут» (сжатие по ширине).

uniform sampler2D tex : filter_nearest;
uniform vec4 tint : source_color = vec4(0.8, 0.76, 0.66, 1.0);

void vertex() {
	float flap = 0.3 + 0.7 * abs(sin(TIME * 41.0 + float(INSTANCE_ID) * 1.73));
	VERTEX.x *= flap;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * tint.rgb * COLOR.rgb;
	ALPHA = t.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
