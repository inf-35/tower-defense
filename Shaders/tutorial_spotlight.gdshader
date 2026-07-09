shader_type canvas_item;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform vec2 spotlight_center = vec2(0.5, 0.5); // Screen UV (0-1)
uniform vec2 spotlight_size = vec2(0.1, 0.1);   // Screen UV size
uniform vec2 spotlight_center_2 = vec2(0.5, 0.5); // Optional second cutout
uniform vec2 spotlight_size_2 = vec2(0.0, 0.0);   // Zero size disables it
uniform bool is_active = false;

void fragment() {
    if (!is_active) {
        COLOR = vec4(0.0); // Invisible if inactive
    } else {
        // Calculate distance from current pixel to the spotlight box
        // We do a simple box SDF (Signed Distance Field) approximation
        vec2 uv = SCREEN_UV;
        
        // Check if inside primary rect
        bool inside_x = uv.x > (spotlight_center.x - spotlight_size.x/2.0) && uv.x < (spotlight_center.x + spotlight_size.x/2.0);
        bool inside_y = uv.y > (spotlight_center.y - spotlight_size.y/2.0) && uv.y < (spotlight_center.y + spotlight_size.y/2.0);
        bool inside_primary = inside_x && inside_y;

        // Optional second rect for cases like the stats label + wave banner.
        bool second_enabled = spotlight_size_2.x > 0.0 && spotlight_size_2.y > 0.0;
        bool inside_secondary = false;
        if (second_enabled) {
            bool inside_x_2 = uv.x > (spotlight_center_2.x - spotlight_size_2.x/2.0) && uv.x < (spotlight_center_2.x + spotlight_size_2.x/2.0);
            bool inside_y_2 = uv.y > (spotlight_center_2.y - spotlight_size_2.y/2.0) && uv.y < (spotlight_center_2.y + spotlight_size_2.y/2.0);
            inside_secondary = inside_x_2 && inside_y_2;
        }

        if (inside_primary || inside_secondary) {
            COLOR = vec4(0.0); // Transparent (The Hole)
        } else {
            COLOR = color; // Dark Dimmer
        }
    }
}
