shader_type canvas_item;

uniform float offset: hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float timescale = 0.5;

void fragment() {
    COLOR = vec4(COLOR.rgb, sin(TIME * timescale + offset) + 0.5);
}