## Separate paper/ring depth planes. Presentation only; never changes targeting.
class_name BossEchoVisuals
extends RefCounted

static func draw_layer(host: Node2D, stage: StageRuntime, center: Vector2,
		now: float, pixel: float, front: bool, transition_age: float) -> void:
	var phase := int(stage.boss_state.get("phase", 1))
	var tint := Color("bca5ff") if phase == 1 else Color("ed92c2")
	if phase == 3: tint = Color("ff819d")
	var radius := (100.0 + phase * 8.0) * pixel
	var orbit_center := center + Vector2(0, -102 * pixel)
	# Ellipses cross behind the shoulders and in front of the lower torso.
	for ring: int in range(phase):
		var points := PackedVector2Array()
		for j: int in range(49):
			var angle := (0.0 if front else PI) + PI * j / 48.0
			var tilt := sin(now * .23 + ring) * .18
			var point := Vector2(cos(angle) * radius, sin(angle) * radius * .28)
			point = point.rotated(tilt + ring * .28)
			points.append(orbit_center + point + Vector2(0, ring * 7 * pixel))
		host.draw_polyline(points, Color(tint, .12), 5 * pixel, true)
		host.draw_polyline(points, Color(tint, .48 if front else .26), pixel, true)
	# Score sheets orbit with distinct silhouettes, fold highlights and red marks.
	var count := 6 + phase * 2
	for i: int in range(count):
		var angle := TAU * float(i) / count + now * (.32 + phase * .045)
		var depth := sin(angle)
		if (depth >= 0) != front: continue
		var p := orbit_center + Vector2(cos(angle) * radius,
			depth * radius * .38 + sin(now * 1.5 + i * 2.1) * 10 * pixel)
		# Foreground sheets stay below the face, avoiding a white mask over it.
		if front: p.y += 28 * pixel
		var scale := pixel * (.84 + (depth + 1) * .12)
		var turn := sin(now * .8 + i * 1.7) * .38 + cos(angle) * .25
		var xaxis := Vector2(cos(turn), sin(turn)) * scale
		var yaxis := Vector2(-sin(turn), cos(turn)) * scale
		var quad := PackedVector2Array([p-xaxis*10-yaxis*14,p+xaxis*9-yaxis*12,
			p+xaxis*11+yaxis*14,p-xaxis*9+yaxis*12])
		host.draw_colored_polygon(quad, Color(.79,.77,.91,.85 if front else .50))
		var edge := quad.duplicate(); edge.append(quad[0])
		host.draw_polyline(edge, Color(tint,.8 if front else .4), pixel, true)
		for line: int in range(3):
			var start := p-xaxis*6+yaxis*(-5+line*5)
			host.draw_line(start,start+xaxis*(10-line*2),Color(.23,.19,.36,.7),pixel,true)
		var red := Color("db7491")
		host.draw_line(p+xaxis*2-yaxis*8,p+xaxis*6-yaxis*11,red,1.5*pixel,true)
		if phase >= 2:
			host.draw_line(p-xaxis*5+yaxis*7,p+xaxis*6-yaxis*6,Color(red,.8),pixel,true)
	# A short expanding score seal makes entrance and phase transitions readable.
	if not front and transition_age >= 0 and transition_age < 1.25:
		var progress := transition_age / 1.25
		var seal_radius := radius * (.75 + progress * .65)
		host.draw_arc(orbit_center,seal_radius,0,TAU,72,Color(tint,(1-progress)*.7),2*pixel,true)
		for i: int in range(12):
			var direction := Vector2.from_angle(TAU*i/12.0+now*.15)
			host.draw_line(orbit_center+direction*seal_radius,
				orbit_center+direction*(seal_radius+12*pixel),Color(tint,(1-progress)*.6),pixel,true)
