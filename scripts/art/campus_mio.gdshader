shader_type canvas_item;
uniform float strength = 1.0;
uniform float clock = 0.0;
uniform float breeze = 0.0;
uniform float attention = 0.0;
uniform float blink = 0.0;
uniform sampler2D blink_frame : filter_linear;
uniform sampler2D blink_base : filter_linear;
varying vec4 tint;
void vertex() { tint = COLOR; }
float oval(vec2 p,vec2 center,vec2 radius) {
	return 1.0-smoothstep(.45,1.0,length((p-center)/radius));
}
void fragment() {
	vec2 p = UV*vec2(1672.0,941.0);
	float hair = oval(p,vec2(267.0,545.0),vec2(34.0,69.0));
	float head = oval(p,vec2(304.0,489.0),vec2(29.0,35.0));
	float body = oval(p,vec2(310.0,578.0),vec2(36.0,82.0));
	float mask = max(max(hair,head),body);
	vec2 shift = vec2(breeze*hair*.8+attention*head*.35,-sin(clock*1.65)*(body+head)*.32);
	vec2 sample_uv = UV+shift*strength/vec2(1672.0,941.0);
	vec4 original = texture(TEXTURE,sample_uv);
	float eyes = 1.0-smoothstep(0.55,1.0,length((p-vec2(310.0,492.0))/vec2(16.0,8.0)));
	// Transfer only the eyelid edit, preserving the approved painting's grading.
	vec3 change = texture(blink_frame,sample_uv).rgb-texture(blink_base,sample_uv).rgb;
	COLOR = vec4(clamp(original.rgb+change*eyes*blink,vec3(0.0),vec3(1.0)),original.a*mask)*tint;
}
