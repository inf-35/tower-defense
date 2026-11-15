shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(0.96, 0.68, 0.16, 1.0);

void fragment() {
	//the original panel covers the silhouettes' interiors, leaving their displaced edges visible.
	COLOR = vec4(outline_color.rgb, COLOR.a * outline_color.a);
}
