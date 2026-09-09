shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float contrast : hint_range(0.0, 2.0, 0.01) = 1.1;

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 contrasted_color = (screen_color.rgb - vec3(0.5)) * contrast + vec3(0.5);
	COLOR = vec4(clamp(contrasted_color, vec3(0.0), vec3(1.0)), screen_color.a);
}
