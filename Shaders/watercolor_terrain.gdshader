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

// Per-cell terrain body color. RGB is the pigment color for that terrain type.
// A is the body-strength/opacity for that terrain when fully painted.
uniform sampler2D terrain_color_texture : filter_nearest;

// Per-cell wash color. This is the pale, watery pigment used at terrain edges
// and in any place where pigment is intentionally diluted.
uniform sampler2D terrain_wash_texture : filter_nearest;

// Per-cell control data. Currently we only use R, where higher values mean that
// a terrain is allowed to "own" the final color instead of being averaged with
// neighbors. Water uses this to stay legible against land.
uniform sampler2D terrain_control_texture : filter_nearest;

// Watercolor noise sources.
// distortion_texture bends the outer blob and inter-terrain boundaries so the
// island does not read as a rigid tile map.
uniform sampler2D distortion_texture : repeat_enable, filter_linear;

// noise_texture adds pigment irregularity inside the blob, so the center is not
// a flat fill even when the distance field says it is fully interior.
uniform sampler2D noise_texture : repeat_enable, filter_linear;

// paper_texture is a subtle final tint so the paint sits on "paper" rather than
// reading as pure digital color.
uniform sampler2D paper_texture : repeat_enable, filter_linear_mipmap;

// --- coordinate mapping ---
// These are set by TerrainRenderer so world-space noise does not swim when the rect resizes.
uniform vec2 region_pixel_offset;
uniform vec2 region_pixel_size;

// Size, in cells, of the terrain color/wash/control textures. We reconstruct cell
// indices from UVs manually because those textures represent tile data, not a
// pre-filtered image.
uniform vec2 terrain_color_texture_size = vec2(1.0, 1.0);

// --- configuration ---
uniform float distortion_strength : hint_range(0.0, 10.0) = 5.0;
uniform float distortion_scale : hint_range(0.001, 0.1) = 0.01;
uniform float noise_strength = 0.2;
// cut_threshold is not a transparency cutoff. It is the interior distance, in
// recovered tile units, that we keep as pure wash before pigment starts to build.
uniform float cut_threshold : hint_range(0.0, 0.5) = 0.2;
// edge_softness is the width, again in tile-distance unots, of the wash->pigment ramp.
uniform float edge_softness : hint_range(0.0, 2.0) = 1.0;
// TerrainRenderer stores depth normalized by max_gradient_depth; this converts
// the sampled value back into "tiles from the edge" so artist-facing controls stay intuitive.
uniform float distance_field_step = 1.0;
uniform float center_falloff : hint_range(0.1, 5.0) = 2.0;
uniform float noise_falloff: hint_range(0.1, 5.0) = 1.0;
uniform float brush_strength: hint_range(0.0, 1.0) = 0.3;
uniform float terrain_color_strength: hint_range(0.0, 1.0) = 1.0;
// Controls how soft terrain-to-terrain handoff is. This only affects boundaries
// between valid terrain cells, not terrain-to-empty edges.
uniform float terrain_transition_softness : hint_range(0.0, 1.0) = 0.15;
// Separate from the outer blob distortion: this specifically wobbles the ownership
// domain used when neighboring terrain types blend into one another.
uniform float terrain_warp_strength : hint_range(0.0, 12.0) = 8.0;

vec4 sample_terrain_cell(vec2 cell) {
	// These terrain textures are cell maps, so we sample at the center of the
	// chosen cell and clamp to valid bounds rather than letting filtered UVs bleed.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_color_texture, cell_uv);
}

vec4 sample_wash_cell(vec2 cell) {
	// Same addressing logic as sample_terrain_cell(), but reading wash instead of body pigment.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_wash_texture, cell_uv);
}

float sample_control_cell(vec2 cell) {
	// Dominance data is another per-cell map, so it uses the same cell-center sampling.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_control_texture, cell_uv).r;
}

vec2 get_terrain_blend(vec2 cell_frac) {
	// For inter-terrain transitions we reconstruct a bilinear blend between the
	// four neighboring cells. terrain_transition_softness lets that blend happen
	// across a controllable band around the cell center instead of as a hard split.
	float half_width = terrain_transition_softness * 0.5;
	vec2 blend = step(vec2(0.5), cell_frac);

	if (terrain_transition_softness > 0.001) {
		blend = smoothstep(vec2(0.5 - half_width), vec2(0.5 + half_width), cell_frac);
	}
	return blend;
}

// Blends neighboring terrain colors, but ignores blank cells. The distance field
// owns terrain presence and the edge-depth used for wash blending.
vec4 sample_terrain_map(vec2 uv) {
	// Convert normalized UV into a cell-space position so we can manually blend the
	// four neighboring terrain cells.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 cell_pos = clamp(uv, vec2(0.0), vec2(1.0)) * map_size - vec2(0.5);
	vec2 base_cell = floor(cell_pos);
	vec2 blend = get_terrain_blend(fract(cell_pos));

	// Bilinear weights for the four surrounding cells.
	float w00 = (1.0 - blend.x) * (1.0 - blend.y);
	float w10 = blend.x * (1.0 - blend.y);
	float w01 = (1.0 - blend.x) * blend.y;
	float w11 = blend.x * blend.y;

	vec4 c00 = sample_terrain_cell(base_cell);
	vec4 c10 = sample_terrain_cell(base_cell + vec2(1.0, 0.0));
	vec4 c01 = sample_terrain_cell(base_cell + vec2(0.0, 1.0));
	vec4 c11 = sample_terrain_cell(base_cell + vec2(1.0, 1.0));

	// Cells with effectively zero alpha are treated as "no terrain data here".
	// We drop them from the average so the shader does not hallucinate color from
	// blank neighbors; terrain-to-empty behavior is handled by the distance field instead.
	float v00 = w00 * step(0.001, c00.a);
	float v10 = w10 * step(0.001, c10.a);
	float v01 = w01 * step(0.001, c01.a);
	float v11 = w11 * step(0.001, c11.a);
	float valid_weight = v00 + v10 + v01 + v11;
	if (valid_weight <= 0.001) {
		return vec4(0.0);
	}
	vec4 terrain = (c00 * v00 + c10 * v10 + c01 * v01 + c11 * v11) / valid_weight;
	return terrain;
}

// Wash uses the same valid-cell weighting as body color, so terrain edges fade
// through the local terrain's own pale pigment instead of a global scene tint.
vec4 sample_wash_map(vec2 uv) {
	// This intentionally mirrors sample_terrain_map(). The important design point
	// is that body color and wash color are blended over the same terrain ownership
	// basis, so the edge wash stays consistent with the terrain type actually present there.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 cell_pos = clamp(uv, vec2(0.0), vec2(1.0)) * map_size - vec2(0.5);
	vec2 base_cell = floor(cell_pos);
	vec2 blend = get_terrain_blend(fract(cell_pos));
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
	return (wash00 * v00 + wash10 * v10 + wash01 * v01 + wash11 * v11) / valid_weight;
}

// Dominant terrains, currently water, can claim color ownership instead of being
// averaged with neighboring land. This keeps lake color legible without square overlays.
vec4 sample_dominant_terrain_map(vec2 uv) {
	// We use the same four-cell sampling domain as the normal terrain blend, but
	// instead of averaging colors we pick the strongest candidate after weighting
	// by both bilinear influence and per-cell dominance strength.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 cell_pos = clamp(uv, vec2(0.0), vec2(1.0)) * map_size - vec2(0.5);
	vec2 base_cell = floor(cell_pos);
	vec2 blend = get_terrain_blend(fract(cell_pos));

	float w00 = (1.0 - blend.x) * (1.0 - blend.y);
	float w10 = blend.x * (1.0 - blend.y);
	float w01 = (1.0 - blend.x) * blend.y;
	float w11 = blend.x * blend.y;
	vec4 c00 = sample_terrain_cell(base_cell);
	vec4 c10 = sample_terrain_cell(base_cell + vec2(1.0, 0.0));
	vec4 c01 = sample_terrain_cell(base_cell + vec2(0.0, 1.0));
	vec4 c11 = sample_terrain_cell(base_cell + vec2(1.0, 1.0));

	// These scores decide which terrain gets to "win" ownership at this pixel.
	// Water uses this so it removes green underpaint instead of simply layering blue on top.
	float s00 = w00 * sample_control_cell(base_cell);
	float s10 = w10 * sample_control_cell(base_cell + vec2(1.0, 0.0));
	float s01 = w01 * sample_control_cell(base_cell + vec2(0.0, 1.0));
	float s11 = w11 * sample_control_cell(base_cell + vec2(1.0, 1.0));

	vec3 color = c00.rgb;
	float strength = s00;
	if (s10 > strength) {
		color = c10.rgb;
		strength = s10;
	}
	if (s01 > strength) {
		color = c01.rgb;
		strength = s01;
	}
	if (s11 > strength) {
		color = c11.rgb;
		strength = s11;
	}
	return vec4(color, clamp(strength, 0.0, 1.0));
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
	float edge_distance = dist_value / max(distance_field_step, 0.001);
	float shape_mask = step(0.001, dist_value);

	// Convert "distance from edge" into a wash->pigment ramp.
	// 0..cut_threshold tiles from the edge: pure wash.
	// then over edge_softness tiles: gradually gain body pigment.
	float wash_to_pigment = shape_mask;
	if (edge_softness > 0.001) {
		wash_to_pigment = smoothstep(cut_threshold, cut_threshold + edge_softness, edge_distance);
	}

	// The center should generally be more pigmented than the edge, but we also
	// perturb that by watercolor noise so the fill is mottled and organic.
	float vibrancy = pow(wash_to_pigment, center_falloff);
	float watercolor_noise = pow(texture(noise_texture, noise_uv + vec2(0.002, 0.002) * TIME).r, noise_falloff);
	vibrancy = vibrancy * (1.0 - noise_strength) + watercolor_noise * vibrancy * noise_strength;

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

	// First build the normal multi-terrain body color, then let a dominant terrain
	// optionally override that ownership. This keeps ordinary terrain transitions soft
	// while still letting water read as "water" instead of green-with-blue-on-top.
	float dominance_strength = dominant_sample.a * terrain_color_strength;
	vec3 body_color = mix(wash_sample.rgb, terrain_sample.rgb, terrain_color_strength);
	body_color = mix(body_color, dominant_sample.rgb, dominance_strength);

	// Brush alpha represents paint coverage: fuller stroke areas receive pigment,
	// while dry gaps stay closer to the same wash layer used at terrain edges.
	float paint_coverage = pow(clamp(texture(brush_mask_texture, UV).a * 2.0, 0.5, 1.0), 2.0);
	float dry_brush = clamp((1.0 - paint_coverage) * brush_strength * 3.0, 0.0, 1.0);
	float pigment_weight = vibrancy * (1.0 - dry_brush);

	// Fade from blended per-terrain wash into full per-terrain pigment. The
	// distance field only decides the silhouette; wash/pigment blending owns fade.
	vec4 final_color = vec4(
		mix(wash_sample.rgb, body_color, pigment_weight),
		mix(wash_sample.a, terrain_sample.a, pigment_weight)
	);

	// Paper tint is deliberately subtle. It is there to integrate the paint into
	// the background, not to recolor the terrain in a dramatic way.
	final_color.rgb = mix(final_color.rgb, final_color.rgb * paper.rgb, 0.5);

	// Final alpha rule:
	// - shape_mask removes only true empty space outside the blob
	// - final_color.a comes from wash/body alpha blending inside the blob
	// This is the key separation that avoids "double fading" edges to transparency.
	COLOR = vec4(final_color.rgb, shape_mask * final_color.a);
}
