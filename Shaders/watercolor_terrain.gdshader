shader_type canvas_item;
render_mode blend_mix;

// --- inputs ---
uniform sampler2D brush_mask_texture : filter_linear;

uniform sampler2D grid_data_texture : filter_linear;
uniform sampler2D terrain_color_texture : filter_nearest;
uniform sampler2D distortion_texture : repeat_enable, filter_linear;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform sampler2D paper_texture : repeat_enable, filter_linear_mipmap;

// --- coordinate mapping ---
// these are set by the script to tell the shader where this rect is in the world
uniform vec2 region_pixel_offset; // the world position of the top-left of the rect
uniform vec2 region_pixel_size;   // the total size of the rect in pixels
uniform vec2 terrain_color_texture_size = vec2(1.0, 1.0);

// --- colors ---
uniform vec4 paint_color : source_color = vec4(0.2, 0.6, 0.8, 1.0);
uniform vec4 wash_color : source_color = vec4(0.5, 0.8, 0.9, 0.6);

// --- configuration ---
uniform float distortion_strength : hint_range(0.0, 10.0) = 5.0; // strength in pixels
uniform float distortion_scale : hint_range(0.001, 0.1) = 0.01; // scale relative to pixels
uniform float noise_strength = 1.0;
uniform float cut_threshold : hint_range(0.0, 0.5) = 0.1;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.05; //for terrain-blank transitions only
uniform float distance_field_step = 1.0;
uniform float center_falloff : hint_range(0.1, 5.0) = 1.0;
uniform float noise_falloff: hint_range(0.1, 5.0) = 1.0;
uniform float brush_strength: hint_range(0.0, 1.0) = 0.8;
uniform float terrain_color_strength: hint_range(0.0, 1.0) = 1.0;
uniform float terrain_transition_softness : hint_range(0.0, 1.0) = 0.15;
uniform float terrain_warp_strength : hint_range(0.0, 12.0) = 8.0;

vec4 sample_terrain_cell(vec2 cell) {
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_color_texture, cell_uv);
}

vec4 sample_terrain_map(vec2 uv) {
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 cell_pos = clamp(uv, vec2(0.0), vec2(1.0)) * map_size - vec2(0.5);
	vec2 base_cell = floor(cell_pos);
	vec2 cell_frac = fract(cell_pos);
	float half_width = terrain_transition_softness * 0.5;
	vec2 blend = step(vec2(0.5), cell_frac);

	if (terrain_transition_softness > 0.001) {
		blend = smoothstep(vec2(0.5 - half_width), vec2(0.5 + half_width), cell_frac);
	}

	vec4 c00 = sample_terrain_cell(base_cell);
	vec4 c10 = sample_terrain_cell(base_cell + vec2(1.0, 0.0));
	vec4 c01 = sample_terrain_cell(base_cell + vec2(0.0, 1.0));
	vec4 c11 = sample_terrain_cell(base_cell + vec2(1.0, 1.0));
	return mix(mix(c00, c10, blend.x), mix(c01, c11, blend.x), blend.y);
}

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
	float edge_value = dist_value / max(distance_field_step, 0.001);
	float alpha = step(cut_threshold, edge_value);
	if (edge_softness > 0.001) {
		alpha = smoothstep(cut_threshold, cut_threshold + edge_softness, edge_value);
	}

	// 5. vibrancy
	float inner_strength = clamp((dist_value - cut_threshold) / (1.0 - cut_threshold), 0.0, 1.0);
	float vibrancy = pow(inner_strength, center_falloff);
	float watercolor_noise = pow(texture(noise_texture, noise_uv + vec2(0.005, 0.005) * TIME).r, noise_falloff);
	vibrancy = vibrancy * (1.0 - noise_strength) + watercolor_noise * vibrancy * noise_strength;

	// 6. texture & color
	// map paper texture to world space too
	vec4 paper = texture(paper_texture, world_pos * 0.02); // 0.02 = 1/50 scale
	vec2 terrain_uv = clamp(UV + ((noise_val - 0.5) * terrain_warp_strength / region_pixel_size), vec2(0.0), vec2(1.0));
	vec4 terrain_sample = sample_terrain_map(terrain_uv);
	vec4 fallback_terrain_sample = sample_terrain_map(UV);
	terrain_sample = mix(fallback_terrain_sample, terrain_sample, step(0.001, terrain_sample.a));
	vec3 terrain_color = mix(paint_color.rgb, terrain_sample.rgb, terrain_sample.a * terrain_color_strength);
	vec4 terrain_paint = vec4(terrain_color, paint_color.a);
	vec4 terrain_wash = vec4(mix(wash_color.rgb, terrain_color, 0.35 * terrain_sample.a * terrain_color_strength), wash_color.a);

	vec4 final_color = mix(terrain_wash, terrain_paint, vibrancy);
	final_color = mix(final_color, final_color * paper, 0.1);

	float brush_alpha = pow(clamp(texture(brush_mask_texture, UV).a * 2.0, 0.5, 1.0), 2.0);
	//COLOR = vec4(final_color.rgb, alpha * final_color.a);
	COLOR = vec4(final_color.rgb, (brush_alpha * brush_strength + (1.0 - brush_strength)) * alpha * final_color.a);
}
