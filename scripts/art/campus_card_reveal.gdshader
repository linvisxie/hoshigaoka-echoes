shader_type canvas_item;
uniform float photo_alpha = 1.0;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec4 painted = texture(TEXTURE,UV);
	vec2 p = UV*vec2(1672.0,941.0);
	float photo = step(1234.0,p.x)*step(p.x,1367.0)*step(703.0,p.y)*step(p.y,847.0);
	COLOR = vec4(painted.rgb,painted.a*mix(1.0,photo_alpha,photo))*tint;
}
