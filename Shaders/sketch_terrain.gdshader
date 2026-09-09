shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D grid_data_texture : filter_linear;
uniform sampler2D distortion_texture : repeat_enable, filter_linear;
uniform sampler2D noise_texture : repeat_enable, filter_linear;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.8);
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);
uniform vec2 region_pixel_offset = vec2(0.0);
uniform vec2 region_pixel_size = vec2(1.0);
uniform float distortion_strength : hint_range(0.0, 10.0) = 5.0;
uniform float distortion_scale : hint_range(0.001, 0.1) = 0.01;
uniform float distance_field_step : hint_range(0.001, 1.0) = 1.0;
uniform float outline_width : hint_range(0.005, 1.0) = 0.018;

void fragment() {
	vec2 world_pos = region_pixel_offset + UV * region_pixel_size;
	vec2 noise_uv = world_pos * distortion_scale;
	vec2 noise_val = texture(distortion_texture, noise_uv + vec2(0.002) * TIME).rg;
	vec2 distortion_px = (noise_val - 0.5) * distortion_strength;
	vec2 distorted_uv = UV + (distortion_px / max(region_pixel_size, vec2(1.0)));
	float dist_value = texture(grid_data_texture, distorted_uv).r;
	float edge_distance = dist_value / max(distance_field_step, 0.001);
	float shape_mask = step(0.001, dist_value);

	// match the terrain coastline's narrow contour and uneven pencil pressure
	float pencil_grain = mix(0.58, 1.0, texture(noise_texture, world_pos * 0.11 + vec2(0.61, 0.23)).r);
	float outline_feather = max(fwidth(edge_distance) * 1.35, 0.008);
	float outline_distance = abs(edge_distance - 0.5);
	float outline_mask = 1.0 - smoothstep(outline_width, outline_width + outline_feather, outline_distance);
	float fill_mask = smoothstep(0.5 + outline_width, 0.5 + outline_width + outline_feather, edge_distance) * shape_mask;
	float outline_alpha = outline_color.a * outline_mask * pencil_grain * shape_mask;

	vec4 final_color = vec4(fill_color.rgb, fill_color.a * fill_mask);
	final_color.rgb = mix(final_color.rgb, outline_color.rgb, outline_mask);
	final_color.a = max(final_color.a, outline_alpha);
	COLOR = final_color;
}
