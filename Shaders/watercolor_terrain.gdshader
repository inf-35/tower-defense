shader_type canvas_item;
render_mode blend_mix;

// --- inputs ---
uniform sampler2D brush_mask_texture : filter_linear;

uniform sampler2D grid_data_texture : filter_linear;
uniform sampler2D distortion_texture : repeat_enable, filter_linear;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform sampler2D paper_texture : repeat_enable, filter_linear_mipmap;

// --- coordinate mapping ---
// these are set by the script to tell the shader where this rect is in the world
uniform vec2 region_pixel_offset; // the world position of the top-left of the rect
uniform vec2 region_pixel_size;   // the total size of the rect in pixels

// --- colors ---
uniform vec4 paint_color : source_color = vec4(0.2, 0.6, 0.8, 1.0);
uniform vec4 wash_color : source_color = vec4(0.5, 0.8, 0.9, 0.6);

// --- configuration ---
uniform float distortion_strength : hint_range(0.0, 10.0) = 5.0; // strength in pixels
uniform float distortion_scale : hint_range(0.001, 0.1) = 0.01; // scale relative to pixels
uniform float noise_strength = 1.0;
uniform float cut_threshold : hint_range(0.0, 0.5) = 0.05;
uniform float edge_softness : hint_range(0.0, 0.2) = 0.0;
uniform float center_falloff : hint_range(0.1, 5.0) = 1.0;
uniform float noise_falloff: hint_range(0.1, 5.0) = 1.0;
uniform float brush_strength: hint_range(0.0, 1.0) = 0.8;

void fragment() {
	// 1. coordinate setup
	// calculate the absolute world coordinate of the current pixel
	vec2 world_pos = region_pixel_offset + UV * region_pixel_size;

	// 2. domain warping (world space)
	// we sample noise using world coordinates so it tiles infinitely
	vec2 noise_uv = world_pos * distortion_scale;
	vec2 noise_val = texture(distortion_texture, noise_uv + vec2(0.005,0.005) * TIME).rg;

	// apply distortion to the UV we use to read the data texture.
	// we convert the pixel-based distortion back to UV space (0-1) for the texture lookup.
	vec2 distortion_px = (noise_val - 0.5) * distortion_strength;
	vec2 distorted_uv = UV + (distortion_px / region_pixel_size);

	// 3. sample distance field
	float dist_value = texture(grid_data_texture, distorted_uv).r;

	// 4. shape & alpha
	float alpha = smoothstep(cut_threshold, cut_threshold + edge_softness, dist_value);

	// 5. vibrancy
	float inner_strength = clamp((dist_value - cut_threshold) / (1.0 - cut_threshold), 0.0, 1.0);
	float vibrancy = pow(inner_strength, center_falloff);
	float watercolor_noise = pow(texture(noise_texture, noise_uv + vec2(0.005, 0.005) * TIME).r, noise_falloff);
	vibrancy = vibrancy * (1.0 - noise_strength) + watercolor_noise * vibrancy * noise_strength;

	// 6. texture & color
	// map paper texture to world space too
	vec4 paper = texture(paper_texture, world_pos * 0.02); // 0.02 = 1/50 scale

	vec4 final_color = mix(wash_color, paint_color, vibrancy);
	final_color = mix(final_color, final_color * paper, 0.1);

	float brush_alpha = pow(clamp(texture(brush_mask_texture, UV).a * 2.0, 0.5, 1.0), 2.0);
	//COLOR = vec4(final_color.rgb, alpha * final_color.a);
	COLOR = vec4(final_color.rgb, (brush_alpha * brush_strength + (1.0 - brush_strength)) * alpha * final_color.a);
}