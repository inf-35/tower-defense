shader_type canvas_item;

#include "res://Shaders/combat_light_mix.gdshaderinc"

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform vec2 frame_size = vec2(1.0);
uniform vec4 frame_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 frame_flip = vec2(0.0);
uniform int sample_count = 8;
uniform vec2 quad_origin = vec2(0.0);
uniform vec2 quad_size = vec2(1.0);
uniform vec2 day_sweep_offset = vec2(0.0);
uniform vec2 night_sweep_offset = vec2(0.0);
uniform vec2 secondary_night_sweep_offset = vec2(0.0);
uniform vec2 night_alpha_multipliers = vec2(1.0, 0.0);
uniform bool secondary_night_enabled = false;
uniform float night_mix = 0.0;

varying vec2 quad_uv;

void vertex() {
	quad_uv = VERTEX / frame_size;
}

float sample_sweep(vec2 point, vec2 sweep_offset, vec2 half_texel, sampler2D cover_texture) {
	vec2 minimum_bound = min(sweep_offset, vec2(0.0));
	vec2 maximum_bound = frame_size + max(sweep_offset, vec2(0.0));
	if (any(lessThan(point, minimum_bound)) || any(greaterThan(point, maximum_bound))) {
		return 0.0;
	}
	float coverage = 0.0;
	int samples = clamp(sample_count, 2, 32);
	for (int i = 0; i < samples; i++) {
		float progress = float(i) / float(samples - 1);
		vec2 frame_uv = (point - sweep_offset * progress) / frame_size;
		if (any(lessThan(frame_uv, vec2(0.0))) || any(greaterThan(frame_uv, vec2(1.0)))) {
			continue;
		}
		frame_uv = mix(frame_uv, vec2(1.0) - frame_uv, frame_flip);
		vec2 sample_uv = frame_region.xy + frame_uv * frame_region.zw;
		//clamp filtering to the current frame; samples outside the frame contribute nothing.
		sample_uv = clamp(sample_uv, frame_region.xy + half_texel, frame_region.xy + frame_region.zw - half_texel);
		coverage = max(coverage, texture(cover_texture, sample_uv).a);
		if (coverage >= 1.0) {
			break;
		}
	}
	return coverage;
}

void fragment() {
	vec2 point = quad_uv * quad_size + quad_origin;
	vec2 half_texel = TEXTURE_PIXEL_SIZE * 0.5;
	float day_coverage = 0.0;
	float night_coverage = 0.0;
	if (night_mix < 1.0) {
		day_coverage = sample_sweep(point, day_sweep_offset, half_texel, TEXTURE);
	}
	if (night_mix > 0.0) {
		float primary_alpha = sample_sweep(point, night_sweep_offset, half_texel, TEXTURE) * night_alpha_multipliers.x;
		float secondary_alpha = 0.0;
		if (secondary_night_enabled) {
			secondary_alpha = sample_sweep(point, secondary_night_sweep_offset, half_texel, TEXTURE) * night_alpha_multipliers.y;
		}
		night_coverage = 1.0 - (1.0 - primary_alpha) * (1.0 - secondary_alpha);
	}
	float coverage = mix(day_coverage, night_coverage, night_mix);
	COLOR = vec4(shadow_color.rgb, coverage * shadow_color.a);
}
