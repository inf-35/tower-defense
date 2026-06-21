shader_type canvas_item;

uniform vec4 vignette_color: source_color = vec4(0.85, 0.08, 0.08, 1.0);
uniform float intensity: hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius: hint_range(0.0, 1.0) = 0.52;
uniform float feather: hint_range(0.001, 0.5) = 0.2;
uniform vec2 center = vec2(0.5, 0.5);

void fragment() {
	vec2 uv = SCREEN_UV - center;
	float dist = length(uv);
	float vignette = smoothstep(inner_radius, inner_radius + feather, dist);
	float alpha = vignette * intensity * vignette_color.a;
	COLOR = vec4(vignette_color.rgb, alpha);
}
