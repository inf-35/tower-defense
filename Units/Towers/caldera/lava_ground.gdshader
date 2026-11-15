shader_type canvas_item;
render_mode blend_mix;

#include "res://Shaders/combat_light_mix.gdshaderinc"

uniform sampler2D lava_noise : repeat_enable, filter_linear;
uniform sampler2D brush_mask_texture : repeat_disable, filter_linear;
uniform vec2 brush_uv_origin = vec2(0.0);
uniform vec2 brush_uv_span = vec2(0.0);
//lower values keep more of the solid wash where the brush is thin.
uniform float brush_strength : hint_range(0.0, 1.0) = 1.0;
uniform float lavaness : hint_range(0.0, 1.0) = 1.0;
uniform vec4 crust_color : source_color = vec4(0.62, 0.29, 0.19, 0.78);
uniform vec4 molten_color : source_color = vec4(0.84, 0.55, 0.30, 0.83);
uniform vec4 pencil_color : source_color = vec4(0.31, 0.26, 0.19, 0.72);

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float phase = TIME * 0.65;
	vec2 flow = vec2(sin(phase + world_position.y * 0.13), cos(phase * 0.8 + world_position.x * 0.13));
	float noise_value = texture(lava_noise, world_position * 0.047 + flow * 0.08).r;
	vec2 from_center = abs(UV - vec2(0.5));
	float edge = max(from_center.x, from_center.y);
	//raise the noise threshold towards the tile edge to break up the pools.
	float threshold = 0.2 + 0.68 * smoothstep(0.08, 0.5, edge);
	float field = noise_value - threshold - (1.0 - lavaness) * 0.5;
	float feather = max(fwidth(field), 0.008);
	float ink_width = 0.048;
	float fill = smoothstep(-feather, feather, field);
	float contour = 1.0 - smoothstep(ink_width, ink_width + feather, abs(field));
	float pencil_grain = mix(0.69, 1.0, texture(lava_noise, world_position * 0.9).r);
	vec4 pigment = mix(crust_color, molten_color, smoothstep(0.03, 0.24, field));
	float ink = contour * pencil_grain * pencil_color.a;
	vec3 rgb = mix(pigment.rgb, pencil_color.rgb, ink);
	float edge_fade = 1.0 - smoothstep(0.28, 0.5, edge);
	float pigment_alpha = pigment.a * fill;
	if (brush_uv_span.x > 0.0 && brush_strength > 0.0) {
		float brush_alpha = texture(brush_mask_texture, brush_uv_origin + UV * brush_uv_span).a;
		pigment_alpha *= mix(1.0, min(brush_alpha * 2.0, 1.0), brush_strength);
	}
	float alpha = max(pigment_alpha, ink) * edge_fade * smoothstep(0.0, 0.15, lavaness);
	COLOR = vec4(rgb, alpha);
}
