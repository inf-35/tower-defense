shader_type canvas_item;

uniform vec4 source_color_value : source_color = vec4(0.41568628, 0.3764706, 0.29803923, 1.0);
uniform vec4 replacement_color : source_color = vec4(0.28627451, 0.24705882, 0.18823529, 1.0);
uniform float tolerance : hint_range(0.0, 0.5, 0.001) = 0.06;
uniform float feather : hint_range(0.001, 0.1, 0.001) = 0.015;
uniform bool enabled = true;

void fragment() {
	float difference = distance(COLOR.rgb, source_color_value.rgb);
	float strength = 1.0 - smoothstep(tolerance, tolerance + feather, difference);
	if (enabled) {
		COLOR.rgb = mix(COLOR.rgb, replacement_color.rgb, strength);
	}
}
