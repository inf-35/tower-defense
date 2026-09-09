shader_type canvas_item;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
instance uniform vec2 frame_size = vec2(1.0);
instance uniform vec2 sweep_offset = vec2(0.0);
instance uniform vec4 frame_region = vec4(0.0, 0.0, 1.0, 1.0);
instance uniform vec2 frame_flip = vec2(0.0);
instance uniform int sample_count = 8;

varying vec2 quad_uv;

void vertex() {
	quad_uv = VERTEX / frame_size;
}

void fragment() {
	vec2 point = quad_uv * (frame_size + abs(sweep_offset)) + min(sweep_offset, vec2(0.0));
	vec2 half_texel = TEXTURE_PIXEL_SIZE * 0.5;
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
		coverage = max(coverage, texture(TEXTURE, sample_uv).a);
		if (coverage >= 1.0) {
			break;
		}
	}
	COLOR = vec4(shadow_color.rgb, coverage * shadow_color.a);
}
