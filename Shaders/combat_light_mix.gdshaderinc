//combat light rgb contains steady brightness; native energy controls only blend influence.
void light() {
	LIGHT = vec4(COLOR.rgb * LIGHT_COLOR.rgb, LIGHT_COLOR.a * clamp(LIGHT_ENERGY, 0.0, 1.0));
}
