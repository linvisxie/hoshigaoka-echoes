## A real rotating hexagonal bipyramid, with depth-sorted lit facets.
## The clock is battle time, so pause and upgrade choices freeze it naturally.
class_name ResonanceCrystal
extends RefCounted

static func draw_on(canvas: CanvasItem, center: Vector2, scale: float, seconds: float, danger: bool, flash: float) -> void:
	var angle := seconds * 0.72
	var top := center + Vector2(0,-51) * scale
	var bottom := center + Vector2(0,53) * scale
	var facets: Array[Dictionary] = []
	var base := Color("8360e9") if not danger else Color("ef638d")
	for i: int in range(6):
		var a := angle + TAU * i / 6.0
		var b := angle + TAU * (i+1) / 6.0
		var p := center + Vector2(cos(a)*33,sin(a)*8) * scale
		var q := center + Vector2(cos(b)*33,sin(b)*8) * scale
		var z := (sin(a)+sin(b))*0.5
		var light := clampf(0.48 + cos((a+b)*0.5-0.8)*0.34,0.10,0.94)
		facets.append({"points":PackedVector2Array([top,p,q]),"depth":z,"color":base.lerp(Color("c4eaff"),light)})
		facets.append({"points":PackedVector2Array([bottom,q,p]),"depth":z+0.001,"color":base.lerp(Color("8ba4ff"),light*0.72)})
	facets.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.depth)<float(b.depth))
	for face: Dictionary in facets:
		var points: PackedVector2Array = face.points
		canvas.draw_colored_polygon(points,(face.color as Color).lerp(Color.WHITE,flash*0.65))
		canvas.draw_polyline(points+PackedVector2Array([points[0]]),Color(0.78,0.85,1,0.48),maxf(0.7,scale),true)
	var glow := 0.55 + 0.18*sin(seconds*2.3)
	canvas.draw_circle(center,7*scale,Color(0.70,0.86,1,glow*0.24))
	canvas.draw_line(center-Vector2(0,14)*scale,center+Vector2(0,14)*scale,Color(0.9,0.96,1,glow),1.4*scale,true)
	canvas.draw_line(center-Vector2(11,0)*scale,center+Vector2(11,0)*scale,Color(0.9,0.96,1,glow),1.4*scale,true)
