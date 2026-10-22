shader_type canvas_item;

#include "res://Shaders/combat_light_mix.gdshaderinc"

//match authored ink before placement tints change its color.
uniform vec4 ink_color : source_color = vec4(0.30980392, 0.25882353, 0.18823529, 1.0);
uniform vec4 paper_color : source_color = vec4(0.99215686, 0.95294118, 0.89411765, 1.0);
uniform float ink_tolerance : hint_range(0.0, 2.0, 0.005) = 1.5;

varying vec4 preview_modulate;

void vertex() {
	preview_modulate = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	vec3 ink_difference = texel.rgb - ink_color.rgb;
	float ink_mask = step(dot(ink_difference, ink_difference), ink_tolerance * ink_tolerance);
	vec3 sketch_color = mix(paper_color.rgb, ink_color.rgb, ink_mask);
	COLOR = vec4(sketch_color, texel.a) * preview_modulate;
}
