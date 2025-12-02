shader_type canvas_item;

uniform sampler2D mask_texture : filter_linear;
uniform vec4 tint_color : source_color;

void fragment() {
    float alpha = texture(mask_texture, UV).a - 0.2;
    
    // Output the tint color, but fade it out by the mask alpha
    // We assume the node has "Multiply" blend mode enabled via render_mode or Material settings.
    // However, in shaders, we usually control mixing manually. 
    // Let's just output standard alpha blending, and you set the node to Multiply in Godot.
    
    COLOR = vec4(tint_color.rgb, alpha * tint_color.a);
}