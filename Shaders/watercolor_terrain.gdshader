shader_type canvas_item;
render_mode blend_mix;

#include "res://Shaders/combat_light_mix.gdshaderinc"

// stamped brush coverage inside the terrain silhouette. dense white areas hold
// solid pigment; sparse marks expose pale wash and create a dry, handmade texture.
uniform sampler2D brush_mask_texture : filter_linear;

// distance from empty space into the terrain mass. it owns the outer silhouette
// and makes edges watery while deeper cells gather richer body pigment.
uniform sampler2D grid_data_texture : filter_linear;

// per-cell body pigment and authored opacity. these are the recognizable interior
// terrain colors: stronger alpha feels dense and painted rather than lightly washed.
uniform sampler2D terrain_color_texture : filter_nearest;

// per-cell diluted pigment used at edges and dry gaps. pale, low-alpha values
// make terrain dissolve softly into the paper instead of ending as a solid shape.
uniform sampler2D terrain_wash_texture : filter_nearest;

// per-cell dominance in r. strong values let a terrain own nearby color instead
// of averaging evenly, keeping water and other decisive regions visually distinct.
uniform sampler2D terrain_control_texture : filter_linear;

// low-frequency displacement for the island edge and terrain ownership. broad
// variation makes boundaries wander like wet paint instead of following a grid.
uniform sampler2D distortion_texture : repeat_enable, filter_linear;

// grain applied to pencil contours. uneven values make outlines vary in weight
// and feel drawn on textured paper rather than rendered as perfect vector lines.
uniform sampler2D paper_noise_texture : repeat_enable, filter_linear;

// seamless fine-grain noise shared with the subdued paper-grain background layer.
// it excludes the broad photographed creases used by the separate crumple layer.
uniform sampler2D paper_grain_texture : repeat_enable, filter_linear;

// world-space addressing matched to the visible paper-grain rectangle so local
// posterisation responds to the same fixed fibres rather than camera-relative noise.
uniform vec2 paper_grain_world_origin = vec2(0.0);
uniform vec2 paper_grain_world_uv_scale = vec2(0.02);

// these mirror the environment's existing fine-grain controls. strength controls
// how far dark and light fibres push pigment density above or below its smooth value.
uniform float paper_grain_strength : hint_range(0.0, 3.0, 0.001) = 0.8;
uniform float paper_grain_scale : hint_range(0.01, 1.0, 0.01) = 0.06;

// blend between continuous and stepped pigment density. terrain hues remain intact;
// only the wash-to-body-pigment amount is quantised into visible watercolor pools.
uniform float posterization_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform int posterization_levels : hint_range(2, 32, 1) = 4;

// world-space origin of the terrain rectangle. this anchors grain and distortion
// so their marks stay fixed to the map when the generated texture bounds move.
uniform vec2 region_pixel_offset;

// pixel dimensions of the terrain rectangle. this converts pixel-scale wobble
// into stable uv offsets and prevents distortion from stretching as the island grows.
uniform vec2 region_pixel_size;

// dimensions of the cell-data textures. manual cell lookup uses this to preserve
// authored tile ownership while still drawing soft transitions between neighbors.
uniform vec2 terrain_color_texture_size = vec2(1.0, 1.0);

// maximum displacement of the outer silhouette in pixels. higher values produce
// a looser, more irregular watercolor edge; lower values keep the island controlled.
uniform float distortion_strength : hint_range(0.0, 10.0) = 5.0;

// world-space frequency of distortion noise. lower values create broad bends;
// higher values create busier, more rapidly wavering edges.
uniform float distortion_scale : hint_range(0.001, 0.1) = 0.01;

// interior distance retained as pure wash before body pigment begins. higher
// values widen the pale watery margin around the island.
uniform float cut_threshold : hint_range(0.0, 0.5) = 0.2;

// width of the wash-to-pigment ramp in recovered tile units. higher values feel
// diffuse and cloudlike; lower values make a firmer transition into solid color.
uniform float edge_softness : hint_range(0.0, 2.0) = 2.0;

// converts the normalized distance texture back into tile-distance units. it keeps
// edge controls visually consistent when terrainrenderer's gradient depth changes.
uniform float distance_field_step = 1.0;

// exponent shaping pigment buildup toward the center. higher values keep terrain
// pale for longer, then gather color sharply in deeper interior areas.
uniform float center_falloff : hint_range(0.1, 5.0) = 3.0;

// strength of dry-brush gaps from the stamp mask. higher values reveal more wash
// through the body pigment and make the surface feel rougher and less flooded.
uniform float brush_strength: hint_range(0.0, 1.0) = 0.3;

// minimum effective coverage in sparse mask areas. higher values close brush holes
// and make terrain feel fuller, smoother, and more continuously painted.
uniform float min_paint_coverage: hint_range(0.0, 1.0) = 0.5;

// influence of terrain body color over its local wash. higher values strengthen
// terrain identity and chroma; lower values keep the map subdued and watery.
uniform float terrain_color_strength: hint_range(0.0, 1.0) = 1.0;

// width of color handoff between valid terrain families. higher values blend over
// a broad band; lower values keep borders crisp and more visibly cell-authored.
uniform float terrain_transition_softness : hint_range(0.0, 1.0) = 0.15;

// pixel displacement of terrain-family ownership, separate from the outer edge.
// higher values make neighboring pigments meander and bleed into organic borders.
uniform float terrain_warp_strength : hint_range(0.0, 12.0) = 8.0;

// ink color for outer and water contours. dark neutrals resemble pencil or graphite;
// stronger hues make the map feel deliberately outlined and illustrated.
uniform vec4 coastline_color : source_color = vec4(0.3, 0.28, 0.22, 1.0);

// opacity of the outer island contour. higher values give the silhouette a firmer,
// more legible drawn edge; zero leaves it as an unoutlined watercolor wash.
uniform float coastline_strength : hint_range(0.0, 1.0) = 0.0;

// half-width of the outer contour in recovered distance units. small values read
// as pencil; large values become a heavy marker-like boundary.
uniform float coastline_width : hint_range(0.01, 1.0) = 0.2;

// opacity of contours separating waterlike terrain from its neighbors. higher
// values make lakes immediately legible instead of softly blending into land.
uniform float waterline_strength : hint_range(0.0, 1.0) = 0.0;

// half-width of water contours in dominance units. small values feel sketched;
// larger values produce broad shoreline bands.
uniform float waterline_width : hint_range(0.005, 0.25) = 0.03;

// dominance value around which the water contour is drawn. moving it shifts the
// line toward the water core or outward into the terrain transition.
uniform float waterline_level : hint_range(0.0, 0.5) = 0.2;

vec4 sample_terrain_cell(vec2 cell) {
	// these terrain textures are cell maps, so we sample at the center of the
	// chosen cell and clamp to valid bounds rather than letting filtered uvs bleed.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_color_texture, cell_uv);
}

vec4 sample_wash_cell(vec2 cell) {
	// same addressing logic as sample_terrain_cell(), but reading wash instead of body pigment.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_wash_texture, cell_uv);
}

float sample_control_cell(vec2 cell) {
	// dominance data is another per-cell map, so it uses the same cell-center sampling.
	vec2 map_size = max(terrain_color_texture_size, vec2(1.0));
	vec2 clamped_cell = clamp(cell, vec2(0.0), map_size - vec2(1.0));
	vec2 cell_uv = (floor(clamped_cell) + vec2(0.5)) / map_size;
	return texture(terrain_control_texture, cell_uv).r;
}

float quantize_unit(float value, int levels) {
	float intervals = max(float(levels - 1), 1.0);
	return floor(clamp(value, 0.0, 1.0) * intervals + 0.5) / intervals;
}

vec2 get_terrain_blend(vec2 cell_frac) {
	// for inter-terrain transitions we reconstruct a bilinear blend between the
	// four neighboring cells. terrain_transition_softness lets that blend happen
	// across a controllable band around the cell center instead of as a hard split.
	float half_width = terrain_transition_softness * 0.5;
	vec2 blend = step(vec2(0.5), cell_frac);

	if (terrain_transition_softness > 0.001) {
		blend = smoothstep(vec2(0.5 - half_width), vec2(0.5 + half_width), cell_frac);
	}
	return blend;
}

// blends neighboring terrain colors, but ignores blank cells. the distance field
// owns terrain presence and the edge-depth used for wash blending.
vec4 sample_terrain_map(vec2 uv) {
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
	return (c00 * v00 + c10 * v10 + c01 * v01 + c11 * v11) / valid_weight;
}

// wash uses the same valid-cell weighting as body color, so terrain edges fade
// through the local terrain's own pale pigment instead of a global scene tint.
vec4 sample_wash_map(vec2 uv) {
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

// dominant terrains, currently water, can claim color ownership instead of being
// averaged with neighboring land. this keeps lake color legible without square overlays.
vec4 sample_dominant_terrain_map(vec2 uv) {
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
	// reconstruct stable world-space coordinates. using world space for noise is
	// what prevents the texture pattern from "swimming" when the terrain rect resizes.
	vec2 world_pos = region_pixel_offset + UV * region_pixel_size;

	// distort the distance-field lookup to get the outer watercolor silhouette.
	vec2 noise_uv = world_pos * distortion_scale;
	vec2 noise_val = texture(distortion_texture, noise_uv + vec2(0.002,0.002) * TIME).rg;
	vec2 distortion_px = (noise_val - 0.5) * distortion_strength;
	vec2 distorted_uv = UV + (distortion_px / region_pixel_size);

	// the distance field controls presence and wash depth. nonzero field values
	// should become wash, not transparent; only true empty space is cut out.
	float dist_value = texture(grid_data_texture, distorted_uv).r;
	if (dist_value <= 0.001) {
		discard;
	}
	float edge_distance = dist_value / max(distance_field_step, 0.001);
	float brush_alpha = texture(brush_mask_texture, UV).a;

	// convert "distance from edge" into a wash->pigment ramp.
	// 0..cut_threshold tiles from the edge: pure wash.
	// then over edge_softness tiles: gradually gain body pigment.
	float wash_to_pigment = 1.0;
	if (edge_softness > 0.001) {
		wash_to_pigment = smoothstep(cut_threshold, cut_threshold + edge_softness, edge_distance);
	}

	// the center should generally be more pigmented than the edge.
	float vibrancy = pow(wash_to_pigment, center_falloff);

	// warp only inter-terrain ownership/color, using the same distorted domain for
	// normal blending and dominant terrain selection.
	vec2 paper_grain_uv = (world_pos - paper_grain_world_origin) * paper_grain_world_uv_scale * paper_grain_scale;
	float paper_speckle = texture(paper_grain_texture, paper_grain_uv * vec2(19.0, 23.0) + vec2(0.37, 0.61)).r;
	float paper_grain = paper_speckle;
	vec2 terrain_uv = clamp(UV + ((noise_val - 0.5) * terrain_warp_strength / region_pixel_size), vec2(0.0), vec2(1.0));
	vec4 terrain_sample = sample_terrain_map(terrain_uv);
	vec4 wash_sample = sample_wash_map(terrain_uv);
	vec4 dominant_sample = sample_dominant_terrain_map(terrain_uv);
	float terrain_sample_valid = step(0.001, max(terrain_sample.a, wash_sample.a));

	// if inter-terrain warping steps outside painted cells near the silhouette,
	// fall back to the distance-field domain so the edge still resolves to wash.
	vec2 field_uv = clamp(distorted_uv, vec2(0.0), vec2(1.0));
	terrain_sample = mix(sample_terrain_map(field_uv), terrain_sample, terrain_sample_valid);
	wash_sample = mix(sample_wash_map(field_uv), wash_sample, terrain_sample_valid);
	dominant_sample = mix(sample_dominant_terrain_map(field_uv), dominant_sample, terrain_sample_valid);
	float water_control = texture(terrain_control_texture, terrain_uv).r;

	// first build the normal multi-terrain body color, then let a dominant terrain
	// optionally override that ownership. this keeps ordinary terrain transitions soft
	// while still letting water read as "water" instead of green-with-blue-on-top.
	float dominance_strength = dominant_sample.a * terrain_color_strength;
	vec3 body_color = mix(wash_sample.rgb, terrain_sample.rgb, terrain_color_strength);
	body_color = mix(body_color, dominant_sample.rgb, dominance_strength);

	// brush alpha represents paint coverage: fuller stroke areas receive pigment,
	// while dry gaps stay closer to the same wash layer used at terrain edges.
	float paint_coverage = pow(clamp(brush_alpha * 2.0, min_paint_coverage, 1.0), 2.0);
	float dry_brush = clamp((1.0 - paint_coverage) * brush_strength * 3.0, 0.0, 1.0);
	float pigment_weight = vibrancy * (1.0 - dry_brush);
	float paper_grain_multiplier = 1.0 + (0.5 - paper_grain) * 2.0 * paper_grain_strength;
	pigment_weight = clamp(pigment_weight * paper_grain_multiplier, 0.0, 1.0);
	if (posterization_strength > 0.001) {
		float posterized_pigment = quantize_unit(pigment_weight, posterization_levels);
		pigment_weight = mix(pigment_weight, posterized_pigment, posterization_strength);
	}

	// fade from blended per-terrain wash into full per-terrain pigment. the
	// distance field only decides the silhouette; wash/pigment blending owns fade.
	vec4 final_color = vec4(
		mix(wash_sample.rgb, body_color, pigment_weight),
		mix(wash_sample.a, max(terrain_sample.a, wash_sample.a), pigment_weight)
	);

	// thin, irregular contours replace the previous full-tile dark edge wash.
	float pencil_grain = mix(0.58, 1.0, texture(paper_noise_texture, world_pos * 0.11 + vec2(0.61, 0.23)).r);
	float coastline_feather = max(fwidth(edge_distance) * 1.35, 0.008);
	float coastline_distance = abs(edge_distance - 0.5);
	float coastline_mask = 1.0 - smoothstep(coastline_width, coastline_width + coastline_feather, coastline_distance);
	float coastline_mix = coastline_mask * coastline_color.a * coastline_strength * pencil_grain;
	float waterline_feather = max(fwidth(water_control) * 1.2, 0.004);
	float waterline_distance = abs(water_control - waterline_level);
	float waterline_mask = 1.0 - smoothstep(waterline_width, waterline_width + waterline_feather, waterline_distance);
	float waterline_mix = waterline_mask * coastline_color.a * waterline_strength * pencil_grain;
	final_color.rgb = mix(final_color.rgb, coastline_color.rgb, max(coastline_mix, waterline_mix));

	// final alpha rule:
	// - empty space outside the blob has already been discarded
	// - final_color.a comes from wash/body alpha blending inside the blob
	COLOR = vec4(final_color.rgb, final_color.a);
}
