shader_type canvas_item;
render_mode unshaded;

//a crisp selection border following the icon's opaque silhouette, including internal gaps.
uniform bool outline_enabled = false;
uniform vec4 outline_color : source_color = vec4(0.96, 0.68, 0.16, 1.0);
//source-texture pixels; the border scales with the artwork during hover expansion.
uniform float outline_width : hint_range(0.0, 8.0, 0.25) = 5.0;
//ignores faint brush residue when deciding which pixels contribute to the silhouette.
uniform float alpha_threshold : hint_range(0.0, 0.95, 0.01) = 0.1;
//the bound texturerect supplies its size; this shader expects keep-aspect-centered stretching.
uniform vec2 draw_size = vec2(260.0);

varying vec4 item_modulate;

float sample_alpha(sampler2D source_texture, vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	return texture(source_texture, uv).a;
}

void vertex() {
	item_modulate = COLOR;
	if (outline_enabled && outline_width > 0.0) {
		float texture_scale = min(draw_size.x * TEXTURE_PIXEL_SIZE.x, draw_size.y * TEXTURE_PIXEL_SIZE.y);
		VERTEX += (UV * 2.0 - 1.0) * outline_width * texture_scale;
	}
}

void fragment() {
	if (outline_enabled && outline_width > 0.0) {
		//remap the expanded quad back to the original image without stretching its artwork.
		vec2 margin = TEXTURE_PIXEL_SIZE * outline_width;
		vec2 uv = UV * (vec2(1.0) + margin * 2.0) - margin;
		vec4 base = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
		base *= step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
		float expanded_alpha = sample_alpha(TEXTURE, uv + vec2(margin.x, 0.0));
		expanded_alpha = max(expanded_alpha, sample_alpha(TEXTURE, uv - vec2(margin.x, 0.0)));
		expanded_alpha = max(expanded_alpha, sample_alpha(TEXTURE, uv + vec2(0.0, margin.y)));
		expanded_alpha = max(expanded_alpha, sample_alpha(TEXTURE, uv - vec2(0.0, margin.y)));
		vec2 diagonal = margin * 0.70710678;
		expanded_alpha = max(expanded_alpha, sample_alpha(TEXTURE, uv + diagonal));
		expanded_alpha = max(expanded_alpha, sample_alpha(TEXTURE, uv - diagonal));
		expanded_alpha = max(expanded_alpha, sample_alpha(TEXTURE, uv + vec2(diagonal.x, -diagonal.y)));
		expanded_alpha = max(expanded_alpha, sample_alpha(TEXTURE, uv + vec2(-diagonal.x, diagonal.y)));
		float silhouette = smoothstep(alpha_threshold, alpha_threshold + 0.05, expanded_alpha);
		float border_alpha = silhouette * outline_color.a * (1.0 - base.a);
		float alpha = base.a + border_alpha;
		vec3 color = (base.rgb * base.a + outline_color.rgb * border_alpha) / max(alpha, 0.0001);
		COLOR = vec4(color, alpha) * item_modulate;
	}
}
