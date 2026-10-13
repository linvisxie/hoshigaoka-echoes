shader_type canvas_item;
render_mode unshaded;

// Enhance only existing painted lettering: preserve glyphs, spacing and hue.
void fragment() {
	vec4 center = texture(TEXTURE, UV);
	vec2 step_uv = TEXTURE_PIXEL_SIZE;
	vec3 blur = (texture(TEXTURE, UV + vec2(step_uv.x,0.0)).rgb
		+ texture(TEXTURE, UV - vec2(step_uv.x,0.0)).rgb
		+ texture(TEXTURE, UV + vec2(0.0,step_uv.y)).rgb
		+ texture(TEXTURE, UV - vec2(0.0,step_uv.y)).rgb) * 0.25;
	vec3 weights = vec3(0.2126,0.7152,0.0722);
	float luminance = dot(center.rgb,weights);
	float detail = luminance - dot(blur,weights);
	float ink = smoothstep(0.28,0.62,luminance);
	float correction = clamp(detail * 0.85,-0.075,0.075) * ink;
	COLOR = vec4(clamp(center.rgb + vec3(correction),vec3(0.0),vec3(1.0)),center.a);
}
