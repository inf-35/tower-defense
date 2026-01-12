shader_type canvas_item;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);

void fragment() {
    // Get the alpha of the original texture at this pixel
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Output the shadow color, using the texture's alpha
    // This creates a solid colored shape
    COLOR = vec4(shadow_color.rgb, tex_color.a * shadow_color.a);
}