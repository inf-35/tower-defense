shader_type canvas_item;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform vec2 spotlight_center = vec2(0.5, 0.5); // Screen UV (0-1)
uniform vec2 spotlight_size = vec2(0.1, 0.1);   // Screen UV size
uniform bool is_active = false;

void fragment() {
    if (!is_active) {
        COLOR = vec4(0.0); // Invisible if inactive
    } else {
        // Calculate distance from current pixel to the spotlight box
        // We do a simple box SDF (Signed Distance Field) approximation
        vec2 uv = SCREEN_UV;
        
        // Check if inside rect
        bool inside_x = uv.x > (spotlight_center.x - spotlight_size.x/2.0) && uv.x < (spotlight_center.x + spotlight_size.x/2.0);
        bool inside_y = uv.y > (spotlight_center.y - spotlight_size.y/2.0) && uv.y < (spotlight_center.y + spotlight_size.y/2.0);
        
        if (inside_x && inside_y) {
            COLOR = vec4(0.0); // Transparent (The Hole)
        } else {
            COLOR = color; // Dark Dimmer
        }
    }
}