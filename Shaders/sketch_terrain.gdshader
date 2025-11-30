shader_type canvas_item;
render_mode blend_mix;

// --- inputs ---
uniform sampler2D grid_data_texture : filter_linear; 
uniform sampler2D noise_texture : repeat_enable, filter_linear;

// --- configuration ---
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.8);
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);

uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.02;

// determines where the edge is drawn relative to the grid cells
uniform float cut_threshold : hint_range(0.0, 1.0) = 0.1;
uniform float outline_thickness : hint_range(0.0, 0.2) = 0.001;

void fragment() {
	// 1. domain warping (wobbly lines)
	vec2 noise_uv = UV * noise_scale;
	vec2 noise_val = texture(noise_texture, noise_uv).rg;
	vec2 distorted_uv = UV + (noise_val - 0.5) * distortion_strength;
	
	// 2. sample distance field
	float dist = texture(grid_data_texture, distorted_uv).r;
	
	// 3. calculate outline
	// edge starts at threshold, ends at threshold + thickness
	float alpha_start = smoothstep(cut_threshold - 0.01, cut_threshold, dist);
	float alpha_end = smoothstep(cut_threshold + outline_thickness, cut_threshold + outline_thickness + 0.01, dist);
	
	// the outline is the difference (the "band" between start and end)
	float outline_mask = alpha_start - alpha_end;
	
	// 4. calculate fill (interior)
	float fill_mask = alpha_end;
	
	// 5. mix
	vec4 final_color = mix(vec4(0.0), fill_color, fill_mask);
	final_color = mix(final_color, outline_color, outline_mask);
	
	COLOR = final_color;
}