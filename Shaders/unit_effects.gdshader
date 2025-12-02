// combined_unit_effects.gdshader
shader_type canvas_item;

// 1. Hit Flash (Managed by Unit.gd/take_hit)
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0; // 1.0 = fully white
uniform float transparency : hint_range(0.0, 1.0) = 1.0;

// 2. Status Overlay (Managed by ModifiersComponent/StatusEffect)
uniform vec4 overlay_color : source_color = vec4(0.0, 0.0, 1.0, 0.0); // R, G, B, Alpha of the overlay

void fragment() {
	vec4 original_color = texture(TEXTURE, UV);

	// --- Step 1: Apply Hit Flash (Instantaneous) ---
	// Mix original color with white based on intensity.
	vec4 flash_applied = mix(original_color, vec4(1.0), flash_intensity);

	// --- Step 2: Apply Status Overlay (Translucent Layer) ---
	// Mix the flashed result with the overlay color.
	// Use the overlay color's alpha as the mix weight.
	vec4 final_color = mix(flash_applied, overlay_color, overlay_color.a);

	// The final color's alpha is maintained from the original texture's alpha.
	COLOR = vec4(final_color.rgb, original_color.a * transparency);
}