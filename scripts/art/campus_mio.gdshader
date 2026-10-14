shader_type canvas_item;
uniform float clock = 0.0;
uniform float breeze = 0.0;
uniform float attention = 0.0;
uniform float blink = 0.0;
uniform sampler2D blink_frame : filter_linear;
uniform sampler2D blink_base : filter_linear;
void vertex() {
	float head = 1.0-smoothstep(520.0,720.0,VERTEX.y);
	float hair = (1.0-smoothstep(270.0,299.0,VERTEX.x))*head;
	VERTEX.x += breeze*hair*0.8 + attention*head*0.6;
	VERTEX.y -= (sin(clock*1.65)*0.42+attention*0.35)*head;
}
void fragment() {
	vec4 original = texture(TEXTURE,UV);
	vec2 p = UV*vec2(1672.0,941.0);
	float eyes = 1.0-smoothstep(0.55,1.0,length((p-vec2(310.0,492.0))/vec2(16.0,8.0)));
	// Transfer only the eyelid edit, preserving the approved painting's grading.
	vec3 change = texture(blink_frame,UV).rgb-texture(blink_base,UV).rgb;
	COLOR = vec4(clamp(original.rgb+change*eyes*blink,vec3(0.0),vec3(1.0)),original.a);
}
