shader_type canvas_item;
render_mode blend_mix;

// --- runtime textures ---
// This is a viewport full of stamped brush sprites. We do not use it to define
// the terrain silhouette; instead it modulates pigment density inside the blob
// so the paint feels dry and irregular instead of perfectly uniform.
uniform sampler2D brush_mask_texture : filter_linear;

// Single-channel distance field built by TerrainRenderer. Black means "outside
// the painted terrain". Positive values mean "inside", with larger values deeper
// into the terrain mass.
uniform sampler2D grid_data_texture : filter_linear;

// Premultiplied terrain body color. RGB is color * alpha, A is body strength.
uniform sampler2D terrain_color_texture : filter_linear;

// Premultiplied wash color. This is the pale, watery pigment used at terrain edges.
uniform sampler2D terrain_wash_texture : filter_linear;

// Per-cell control data. Currently we only use R, where higher values mean that
// a terrain is allowed to "own" the final color instead of being averaged with
// neighbors. Water uses this to stay legible against land.
uniform sampler2D terrain_control_texture : filter_linear;

// Premultiplied dominant terrain color. A is the dominance strength after
// environment/terrain data has already been packed on the CPU.
uniform sampler2D terrain_dominance_texture : filter_linear;

// Watercolor noise sources.
// distortion_texture bends the outer blob and inter-terrain boundaries so the
// island does not read as a rigid tile map.
uniform sampler2D distortion_texture : repeat_enable, filter_linear;

// noise_texture is retained for pencil contour breakup.
uniform sampler2D noise_texture : repeat_enable, filter_linear;

// paper_texture is a subtle final tint so the paint sits on "paper" rather than
// reading as pure digital color.
uniform sampler2D paper_texture : repeat_enable, filter_linear_mipmap;

// --- coordinate mapping ---
// These are set by TerrainRenderer so world-space noise does not swim when the rect resizes.
uniform vec2 region_pixel_offset;
uniform vec2 region_pixel_size;
uniform vec2 terrain_color_texture_size = vec2(1.0, 1.0);

// --- configuration ---
uniform float distortion_strength : hint_range(0.0, 10.0) = 5.0;
uniform float distortion_scale : hint_range(0.001, 0.1) = 0.01;
// cut_threshold is not a transparency cutoff. It is the interior distance, in
// recovered tile units, that we keep as pure wash before pigment starts to build.
uniform float cut_threshold : hint_range(0.0, 0.5) = 0.2;
// edge_softness is the width, again in tile-distance unots, of the wash->pigment ramp.
uniform float edge_softness : hint_range(0.0, 2.0) = 1.0;
// TerrainRenderer stores depth normalized by max_gradient_depth; this converts
// the sampled value back into "tiles from the edge" so artist-facing controls stay intuitive.
uniform float distance_field_step = 1.0;
uniform float center_falloff : hint_range(0.1, 5.0) = 2.0;
uniform float brush_strength: hint_range(0.0, 1.0) = 0.3;
uniform float min_paint_coverage: hint_range(0.0, 1.0) = 0.5;
uniform float terrain_color_strength: hint_range(0.0, 1.0) = 1.0;
// Separate from the outer blob distortion: this specifically wobbles the ownership
// domain used when neighboring terrain types blend into one another.
uniform float terrain_warp_strength : hint_range(0.0, 12.0) = 8.0;
uniform vec4 coastline_color : source_color = vec4(0.3, 0.28, 0.22, 1.0);
uniform float coastline_strength : hint_range(0.0, 1.0) = 0.0;
uniform float coastline_width : hint_range(0.01, 1.0) = 0.2;
uniform float waterline_strength : hint_range(0.0, 1.0) = 0.0;
uniform float waterline_width : hint_range(0.005, 0.25) = 0.03;
uniform float waterline_level : hint_range(0.0, 0.5) = 0.2;

vec4 unpack_premultiplied(vec4 sample_color) {
	if (sample_color.a <= 0.001) {
		return vec4(0.0);
	}
	return vec4(sample_color.rgb / sample_color.a, sample_color.a);
}

vec4 sample_terrain_cell(vec2 cell) {
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_color_texture, cell_uv);
}

vec4 sample_wash_cell(vec2 cell) {
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_wash_texture, cell_uv);
}

vec4 sample_terrain_map(vec2 uv) {
	return unpack_premultiplied(texture(terrain_color_texture, uv));
}

vec4 sample_wash_map(vec2 uv) {
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 cell_pos = clamp(uv, vec2(0.0), vec2(1.0)) * map_size - vec2(0.5);
	vec2 base_cell = floor(cell_pos);
	vec2 blend = fract(cell_pos);
	float w00 = (1.0 - blend.x) * (1.0 - blend.y);
	float w10 = blend.x * (1.0 - blend.y);
	float w01 = (1.0 - blend.x) * blend.y;
	float w11 = blend.x * blend.y;

	vec4 c00 = sample_terrain_cell(base_cell);
	vec4 c10 = sample_terrain_cell(base_cell + vec2(1.0, 0.0));
	vec4 c01 = sample_terrain_cell(base_cell + vec2(0.0, 1.0));
	vec4 c11 = sample_terrain_cell(base_cell + vec2(1.0, 1.0));
	float v00 = w00 * step(0.001, c00.a);
	float v10 = w10 * step(0.001, c10.a);
	float v01 = w01 * step(0.001, c01.a);
	float v11 = w11 * step(0.001, c11.a);
	float valid_weight = v00 + v10 + v01 + v11;
	if (valid_weight <= 0.001) {
		return vec4(0.0);
	}

	vec4 wash00 = sample_wash_cell(base_cell);
	vec4 wash10 = sample_wash_cell(base_cell + vec2(1.0, 0.0));
	vec4 wash01 = sample_wash_cell(base_cell + vec2(0.0, 1.0));
	vec4 wash11 = sample_wash_cell(base_cell + vec2(1.0, 1.0));
	vec4 wash_sample = (wash00 * v00 + wash10 * v10 + wash01 * v01 + wash11 * v11) / valid_weight;
	return unpack_premultiplied(wash_sample);
}

vec4 sample_dominant_terrain_map(vec2 uv) {
	return unpack_premultiplied(texture(terrain_dominance_texture, uv));
}

void fragment() {
	// Reconstruct stable world-space coordinates. Using world space for noise is
	// what prevents the texture pattern from "swimming" when the terrain rect resizes.
	vec2 world_pos = region_pixel_offset + UV * region_pixel_size;

	// Distort the distance-field lookup to get the outer watercolor silhouette.
	vec2 noise_uv = world_pos * distortion_scale;
	vec2 noise_val = texture(distortion_texture, noise_uv + vec2(0.002,0.002) * TIME).rg;
	vec2 distortion_px = (noise_val - 0.5) * distortion_strength;
	vec2 distorted_uv = UV + (distortion_px / region_pixel_size);

	// The distance field controls presence and wash depth. Nonzero field values
	// should become wash, not transparent; only true empty space is cut out.
	float dist_value = texture(grid_data_texture, distorted_uv).r;
	if (dist_value <= 0.001) {
		discard;
	}
	float edge_distance = dist_value / max(distance_field_step, 0.001);
	float wash_distance = max(edge_distance - 0.25, 0.0);
	float brush_alpha = texture(brush_mask_texture, UV).a;

	// Convert "distance from edge" into a wash->pigment ramp.
	// 0..cut_threshold tiles from the edge: pure wash.
	// then over edge_softness tiles: gradually gain body pigment.
	float wash_to_pigment = 1.0;
	if (edge_softness > 0.001) {
		wash_to_pigment = smoothstep(cut_threshold, cut_threshold + edge_softness * 1.12, wash_distance);
	}
	wash_to_pigment *= mix(0.82, 1.0, brush_alpha);

	// The center should generally be more pigmented than the edge.
	float vibrancy = pow(wash_to_pigment, center_falloff);

	// Warp only inter-terrain ownership/color, using the same distorted domain for
	// normal blending and dominant terrain selection.
	vec4 paper = texture(paper_texture, world_pos * 0.02);
	vec2 terrain_uv = clamp(UV + ((noise_val - 0.5) * terrain_warp_strength / region_pixel_size), vec2(0.0), vec2(1.0));
	vec4 terrain_sample = sample_terrain_map(terrain_uv);
	vec4 wash_sample = sample_wash_map(terrain_uv);
	vec4 dominant_sample = sample_dominant_terrain_map(terrain_uv);
	float terrain_sample_valid = step(0.001, max(terrain_sample.a, wash_sample.a));

	// If inter-terrain warping steps outside painted cells near the silhouette,
	// fall back to the distance-field domain so the edge still resolves to wash.
	vec2 field_uv = clamp(distorted_uv, vec2(0.0), vec2(1.0));
	terrain_sample = mix(sample_terrain_map(field_uv), terrain_sample, terrain_sample_valid);
	wash_sample = mix(sample_wash_map(field_uv), wash_sample, terrain_sample_valid);
	dominant_sample = mix(sample_dominant_terrain_map(field_uv), dominant_sample, terrain_sample_valid);
	float water_control = texture(terrain_control_texture, terrain_uv).r;

	// First build the normal multi-terrain body color, then let a dominant terrain
	// optionally override that ownership. This keeps ordinary terrain transitions soft
	// while still letting water read as "water" instead of green-with-blue-on-top.
	float dominance_strength = dominant_sample.a * terrain_color_strength;
	vec3 body_color = mix(wash_sample.rgb, terrain_sample.rgb, terrain_color_strength);
	body_color = mix(body_color, dominant_sample.rgb, dominance_strength);

	// Brush alpha represents paint coverage: fuller stroke areas receive pigment,
	// while dry gaps stay closer to the same wash layer used at terrain edges.
	float paint_coverage = pow(clamp(brush_alpha * 2.0, min_paint_coverage, 1.0), 2.0);
	float dry_brush = clamp((1.0 - paint_coverage) * brush_strength * 3.0, 0.0, 1.0);
	float pigment_weight = vibrancy * (1.0 - dry_brush);

	// Fade from blended per-terrain wash into full per-terrain pigment. The
	// distance field only decides the silhouette; wash/pigment blending owns fade.
	vec4 final_color = vec4(
		mix(wash_sample.rgb, body_color, pigment_weight),
		mix(wash_sample.a, max(terrain_sample.a, wash_sample.a), pigment_weight)
	);

	// Paper tint is deliberately subtle. It is there to integrate the paint into
	// the background, not to recolor the terrain in a dramatic way.
	final_color.rgb = mix(final_color.rgb, final_color.rgb * paper.rgb, 0.5);

	// thin, irregular contours replace the previous full-tile dark edge wash.
	float pencil_grain = mix(0.58, 1.0, texture(noise_texture, world_pos * 0.11 + vec2(0.61, 0.23)).r);
	float pencil_breakup = smoothstep(0.38, 0.82, texture(noise_texture, world_pos * 0.19 + vec2(0.14, 0.73)).r);
	float coastline_feather = max(fwidth(edge_distance) * 1.35, 0.008);
	float coastline_distance = abs(edge_distance - 0.5);
	float coastline_mask = 1.0 - smoothstep(coastline_width, coastline_width + coastline_feather, coastline_distance);
	float coastline_mix = coastline_mask * coastline_color.a * coastline_strength * pencil_grain * pencil_breakup;
	float waterline_feather = max(fwidth(water_control) * 1.2, 0.004);
	float waterline_distance = abs(water_control - waterline_level);
	float waterline_mask = 1.0 - smoothstep(waterline_width, waterline_width + waterline_feather, waterline_distance);
	float waterline_mix = waterline_mask * coastline_color.a * waterline_strength * pencil_grain;
	final_color.rgb = mix(final_color.rgb, coastline_color.rgb, max(coastline_mix, waterline_mix));

	// Final alpha rule:
	// - empty space outside the blob has already been discarded
	// - final_color.a comes from wash/body alpha blending inside the blob
	COLOR = vec4(final_color.rgb, final_color.a);
}
