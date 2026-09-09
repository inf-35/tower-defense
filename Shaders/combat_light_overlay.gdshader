shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D light_mask : repeat_disable, filter_linear;
uniform float max_light_energy : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float light_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec4 ambient_color : source_color = vec4(1.0);
uniform float surface_light_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float surface_tint_strength : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float lit_chroma_scale : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float additive_bloom_strength : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float dark_pixel_response : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float light_luminance_power : hint_range(0.1, 4.0, 0.05) = 0.65;
uniform bool world_style_enabled = false;
uniform float world_style_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform vec3 world_tone_input = vec3(0.58, 0.835, 0.902);
uniform vec3 world_tone_output = vec3(0.562, 0.817, 0.922);
uniform float neutral_chroma_scale : hint_range(0.0, 2.0, 0.01) = 0.86;
uniform float accent_chroma_scale : hint_range(0.0, 2.0, 0.01) = 1.06;
uniform float accent_chroma_start : hint_range(0.0, 1.0, 0.001) = 0.112;
uniform float accent_chroma_end : hint_range(0.0, 1.0, 0.001) = 0.137;

float remap_smooth(float value, float input_min, float input_max, float output_min, float output_max) {
	float progress = clamp((value - input_min) / max(input_max - input_min, 0.0001), 0.0, 1.0);
	progress = smoothstep(0.0, 1.0, progress);
	return mix(output_min, output_max, progress);
}

float apply_tone_curve(float luminance) {
	if (luminance < world_tone_input.x) {
		return remap_smooth(luminance, 0.0, world_tone_input.x, 0.0, world_tone_output.x);
	}
	if (luminance < world_tone_input.y) {
		return remap_smooth(luminance, world_tone_input.x, world_tone_input.y, world_tone_output.x, world_tone_output.y);
	}
	if (luminance < world_tone_input.z) {
		return remap_smooth(luminance, world_tone_input.y, world_tone_input.z, world_tone_output.y, world_tone_output.z);
	}
	return remap_smooth(luminance, world_tone_input.z, 1.0, world_tone_output.z, 1.0);
}

vec3 apply_world_style(vec3 input_color) {
	float source_luminance = dot(input_color, vec3(0.2126, 0.7152, 0.0722));
	float target_luminance = apply_tone_curve(source_luminance);
	float maximum_channel = max(input_color.r, max(input_color.g, input_color.b));
	float minimum_channel = min(input_color.r, min(input_color.g, input_color.b));
	float chroma = maximum_channel - minimum_channel;
	float accent_mix = smoothstep(accent_chroma_start, max(accent_chroma_end, accent_chroma_start + 0.001), chroma);
	float chroma_scale = mix(neutral_chroma_scale, accent_chroma_scale, accent_mix);
	vec3 chroma_offset = input_color - vec3(source_luminance);
	return clamp(vec3(target_luminance) + chroma_offset * chroma_scale, vec3(0.0), vec3(1.0));
}

vec3 scale_chroma(vec3 input_color, float chroma_scale) {
	float luminance = dot(input_color, vec3(0.2126, 0.7152, 0.0722));
	return clamp(vec3(luminance) + (input_color - vec3(luminance)) * chroma_scale, vec3(0.0), vec3(1.0));
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 safe_ambient = max(ambient_color.rgb, vec3(0.01));
	vec3 pre_light_color = screen_color.rgb / safe_ambient;
	if (world_style_enabled) {
		vec3 bounded_color = clamp(pre_light_color, vec3(0.0), vec3(1.0));
		vec3 style_delta = apply_world_style(bounded_color) - bounded_color;
		pre_light_color += style_delta * world_style_strength;
	}
	vec3 mask_color = texture(light_mask, UV).rgb * light_strength;
	float peak_energy = max(mask_color.r, max(mask_color.g, mask_color.b));
	if (peak_energy > max_light_energy) {
		mask_color *= max_light_energy / peak_energy;
		peak_energy = max_light_energy;
	}
	vec3 light_hue = mask_color / max(peak_energy, 0.0001);
	vec3 light_target = mix(vec3(1.0), light_hue, surface_tint_strength);
	float local_light_mix = clamp(peak_energy * surface_light_strength, 0.0, 1.0);
	pre_light_color = mix(pre_light_color, scale_chroma(pre_light_color, lit_chroma_scale), local_light_mix);
	float source_luminance = dot(pre_light_color, vec3(0.2126, 0.7152, 0.0722));
	float surface_response = mix(dark_pixel_response, 1.0, pow(source_luminance, light_luminance_power));
	float surface_recovery = clamp(peak_energy * surface_light_strength * surface_response, 0.0, 1.0);
	vec3 local_modulation = mix(ambient_color.rgb, light_target, surface_recovery);
	vec3 lit_surface = pre_light_color * local_modulation;
	float bloom_response = pow(source_luminance, max(light_luminance_power, 1.0));
	vec3 bloom = mask_color * additive_bloom_strength * bloom_response;
	COLOR = vec4(min(lit_surface + bloom, vec3(1.0)), screen_color.a);
}
