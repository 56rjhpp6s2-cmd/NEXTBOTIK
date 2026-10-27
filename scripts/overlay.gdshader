shader_type canvas_item;
render_mode unshaded;
uniform float danger : hint_range(0.0, 1.0) = 0.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform float grain_strength = 0.025;
void fragment() {
	vec2 uv = UV;
	float vignette = smoothstep(0.24, 0.78, distance(uv, vec2(0.5)));
	float grain = fract(sin(dot(uv * vec2(1600.0, 900.0) + floor(TIME * 24.0), vec2(12.9898, 78.233))) * 43758.5453);
	float scanline = sin(uv.y * 900.0 * 1.6) * 0.008;
	float pulse = 0.7 + 0.3 * sin(TIME * 7.0);
	vec3 tint = mix(vec3(0.015, 0.025, 0.03), vec3(0.25, 0.015, 0.01), danger * pulse);
	COLOR = vec4(tint + (grain - 0.5) * grain_strength + scanline, clamp(vignette * (0.7 + danger * 0.2) + darkness, 0.0, 0.98));
}
