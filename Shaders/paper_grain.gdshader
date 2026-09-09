shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 grain_color : source_color = vec4(0.34, 0.3, 0.23, 1.0);
uniform float grain_strength : hint_range(0.0, 0.25, 0.001) = 0.0;
uniform float grain_scale : hint_range(0.25, 4.0, 0.05) = 1.0;
uniform float brush_strength : hint_range(0.0, 0.25, 0.001) = 0.0;
uniform sampler2D grain_texture : repeat_enable, filter_linear;

void fragment() {
	float authored_brush = smoothstep(0.04, 0.6, texture(TEXTURE, UV).a);
	float fibre = texture(grain_texture, UV * grain_scale * vec2(4.0, 5.0)).r;
	float speckle = texture(grain_texture, UV * grain_scale * vec2(19.0, 23.0) + vec2(0.37, 0.61)).r;
	float grain = clamp(fibre * 0.32 + speckle * 0.68, 0.0, 1.0);
	float grain_opacity = grain_strength * mix(0.1, 1.0, pow(grain, 2.4));
	float brush_opacity = brush_strength * authored_brush;
	float opacity = clamp(grain_opacity + brush_opacity, 0.0, 0.5);
	COLOR = vec4(grain_color.rgb, opacity * grain_color.a);
}
