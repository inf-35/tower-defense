shader_type canvas_item;

#include "res://Shaders/combat_light_mix.gdshaderinc"

uniform float posterization_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform int alpha_levels : hint_range(2, 32, 1) = 6;

void fragment() {
	float intervals = max(float(alpha_levels - 1), 1.0);
	float posterized_alpha = floor(COLOR.a * intervals + 0.5) / intervals;
	COLOR.a = mix(COLOR.a, posterized_alpha, posterization_strength);
}
