shader_type canvas_item;
// Arcade CRT pass drawn over the whole screen: scanlines, slow rolling bar, aperture
// vignette. Pure overlay (no screen read) so it stays cheap on Web/WASM.

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.16;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float motion : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	float line = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159);
	float roll = smoothstep(0.0, 0.06, abs(fract(uv.y - TIME * 0.06 * motion) - 0.5) - 0.44);
	vec2 centered = uv - 0.5;
	float vignette = smoothstep(0.35, 0.95, length(centered * vec2(1.0, 1.25)));
	float darkness = line * scanline_strength + vignette * vignette_strength;
	vec3 tint = mix(vec3(0.0), vec3(0.35, 0.95, 0.85), (1.0 - roll) * 0.018 * motion);
	COLOR = vec4(tint, clamp(darkness, 0.0, 0.85));
}
