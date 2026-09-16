shader_type canvas_item;

uniform vec4 overlay_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float overlay_intensity = 0.0;
uniform vec4 correction_tint : source_color = vec4(1.0);
uniform float correction_tint_strength = 0.0;
uniform float brightness_lift = 0.0;
uniform float chroma_scale = 1.0;

vec3 scale_chroma(vec3 input_color, float scale) {
	float luminance = dot(input_color, vec3(0.2126, 0.7152, 0.0722));
	return clamp(vec3(luminance) + (input_color - vec3(luminance)) * max(scale, 0.0), vec3(0.0), vec3(1.0));
}

void fragment() {
	//color already contains the sampled sprite after node modulate/self_modulate.
	//that means shader overlays naturally stack on top of the shared root-modulate tint pipeline.
	vec4 base_color = COLOR;
	vec3 corrected_color = scale_chroma(base_color.rgb, chroma_scale);
	corrected_color = clamp(corrected_color * max(1.0 + brightness_lift, 0.0), vec3(0.0), vec3(1.0));
	corrected_color = mix(corrected_color, clamp(corrected_color * correction_tint.rgb, vec3(0.0), vec3(1.0)), clamp(correction_tint_strength, 0.0, 1.0));
	float overlay_strength = clamp(overlay_intensity, 0.0, 1.0);
	vec3 pushed_color = mix(corrected_color, clamp(overlay_color.rgb, 0.0, 1.0), overlay_strength);
	COLOR = vec4(pushed_color, base_color.a);
}
