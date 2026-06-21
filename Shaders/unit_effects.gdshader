shader_type canvas_item;

instance uniform vec4 overlay_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float overlay_intensity = 0.0;

void fragment() {
	//color already contains the sampled sprite after node modulate/self_modulate.
	//that means shader overlays naturally stack on top of the shared root-modulate tint pipeline.
	vec4 base_color = COLOR;
	float overlay_strength = clamp(overlay_intensity, 0.0, 1.0);
	vec3 pushed_color = mix(base_color.rgb, clamp(overlay_color.rgb, 0.0, 1.0), overlay_strength);
	COLOR = vec4(pushed_color, base_color.a);
}
