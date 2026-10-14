shader_type canvas_item;
uniform float clock = 0.0;
uniform float breeze = 0.0;
uniform vec2 gaze = vec2(0.0);
varying vec4 tint;
void vertex() { tint = COLOR; }
float oval(vec2 p, vec2 c, vec2 r) {
	return 1.0-smoothstep(0.62,1.0,length((p-c)/r));
}
float protected_rect(vec2 p,vec4 r) {
	return step(r.x,p.x)*step(r.y,p.y)*step(p.x,r.z)*step(p.y,r.w);
}
void fragment() {
	vec2 p = UV*vec2(1672.0,941.0);
	float branches = max(oval(p,vec2(370.0,70.0),vec2(480.0,160.0)),oval(p,vec2(1580.0,240.0),vec2(130.0,220.0)));
	float foreground = max(oval(p,vec2(60.0,840.0),vec2(175.0,160.0)),oval(p,vec2(1610.0,820.0),vec2(180.0,165.0)));
	float paper = max(oval(p,vec2(57.0,505.0),vec2(20.0,26.0))*smoothstep(486.0,523.0,p.y),oval(p,vec2(124.0,447.0),vec2(22.0,31.0))*smoothstep(427.0,474.0,p.y));
	float mask = max(max(branches,foreground),paper);
	// Keep the approved footer, waveform and its backing entirely untouched.
	float footer = (1.0-smoothstep(470.0,500.0,p.x))*smoothstep(850.0,858.0,p.y);
	mask *= 1.0-footer;
	// The glass panels are translucent. Freeze the world beneath them too.
	float ui = protected_rect(p,vec4(20.0,20.0,376.0,110.0));
	ui = max(ui,protected_rect(p,vec4(1337.0,27.0,1591.0,69.0)));
	ui = max(ui,protected_rect(p,vec4(1452.0,90.0,1661.0,476.0)));
	ui = max(ui,protected_rect(p,vec4(1218.0,693.0,1646.0,865.0)));
	mask *= 1.0-ui;
	vec2 shift = vec2(breeze*1.65,sin(clock*0.65+p.x*0.01)*0.45)*branches;
	shift += (gaze*2.4+vec2(breeze*0.65,0.0))*foreground;
	shift += vec2(sin(clock*1.1+p.x*.01)*2.2,breeze*1.1)*paper;
	vec4 scene = texture(TEXTURE,clamp(UV+shift/vec2(1672.0,941.0),vec2(0.0),vec2(1.0)));
	COLOR = vec4(scene.rgb,scene.a*mask)*tint;
}
