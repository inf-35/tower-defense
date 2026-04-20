shader_type canvas_item;

// The screen texture (everything rendered before this node)
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// --- Boil Effect ---
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float boil_speed : hint_range(0.0, 10.0) = 4.0;
uniform float boil_strength : hint_range(0.0, 0.02) = 0.005; // Keep this very small!
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;

void fragment() {
    // 1. Sample original screen pixel
    vec4 original_color = texture(screen_texture, SCREEN_UV);
    // 3. Calculate "Boil" Distortion (only if it's a target pixel)
    vec4 final_color = original_color;

        // Create animated, stepped time for that "stop-motion" hand-drawn feel.
        // Instead of smooth time, we round it so it jumps every few frames.
        float stepped_time = floor(TIME * boil_speed);
        
        // Offset the noise UV based on time to create the "boiling" change
        vec2 noise_uv = (SCREEN_UV * noise_scale) + vec2(stepped_time * 0.13, stepped_time * 0.27);
        
        // Sample noise
        vec2 noise_val = texture(noise_texture, noise_uv).rg;
        
        // Shift UVs around 0.0 (-0.5 to 0.5)
        vec2 distortion = (noise_val - 0.5) * boil_strength;
        
        // 4. Sample the screen AGAIN, but slightly offset
        // We multiply the distortion by the mask so ONLY pencil lines get warped
        vec2 warped_uv = SCREEN_UV + distortion;
        
        final_color = texture(screen_texture, warped_uv);
    // Output the final color
    COLOR = final_color;
}