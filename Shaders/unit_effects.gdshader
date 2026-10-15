shader_type canvas_item;

uniform vec4 overlay_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float overlay_intensity = 0.0;
uniform vec4 correction_tint : source_color = vec4(1.0);
uniform float correction_tint_strength = 0.0;
uniform float brightness_lift = 0.0;
uniform float chroma_scale = 1.0;
uniform float light_chroma_scale : hint_range(1.0, 3.0, 0.01) = 2.5;
uniform float dark_pixel_light_floor : hint_range(0.0, 1.0, 0.01) = 0.08;

vec3 scale_chroma(vec3 input_color, float scale) {
	float luminance = dot(input_color, vec3(0.2126, 0.7152, 0.0722));
	return clamp(vec3(luminance) + (input_color - vec3(luminance)) * max(scale, 0.0), vec3(0.0), vec3(1.0));
}

void fragment() {
	//color already contains the sampled sprite after node modulate/self_modulate.
	//that means shader overlays naturally stack on top of the shared root-modulate tint pipeline.
	vec4 base_color = COLOR;
	float overlay_strength = clamp(overlay_intensity, 0.0, 1.0);
	bool has_correction = correction_tint_strength > 0.0 || abs(brightness_lift) > 0.0001 || abs(chroma_scale - 1.0) > 0.0001;
	if (has_correction || overlay_strength > 0.0) {
		vec3 corrected_color = scale_chroma(base_color.rgb, chroma_scale);
		corrected_color = clamp(corrected_color * max(1.0 + brightness_lift, 0.0), vec3(0.0), vec3(1.0));
		corrected_color = mix(corrected_color, clamp(corrected_color * correction_tint.rgb, vec3(0.0), vec3(1.0)), clamp(correction_tint_strength, 0.0, 1.0));
		vec3 pushed_color = mix(corrected_color, clamp(overlay_color.rgb, 0.0, 1.0), overlay_strength);
		COLOR = vec4(pushed_color, base_color.a);
	}
}

void light() {
	float source_luminance = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float light_peak = max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b));
	float light_intensity = clamp(light_peak * LIGHT_ENERGY, 0.0, 1.0);
	float local_chroma_scale = mix(1.0, light_chroma_scale, light_intensity);
	vec3 lit_surface = clamp(vec3(source_luminance) + (COLOR.rgb - vec3(source_luminance)) * local_chroma_scale, vec3(0.0), vec3(1.0));
	float surface_response = mix(dark_pixel_light_floor, 1.0, source_luminance);
	LIGHT = vec4(lit_surface * LIGHT_COLOR.rgb * LIGHT_ENERGY * surface_response, LIGHT_COLOR.a);
}
