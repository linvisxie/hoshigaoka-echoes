## Campus-only presentation. No progression, rewards, input capture or global timers.
class_name CampusAtmosphere
extends Control

const DESIGN := Vector2(1672,941)
const GOLD := Color("e8c990")
const BLUE := Color("8edcff")
var mio_outline := PackedVector2Array([
	Vector2(277,463),Vector2(295,459),Vector2(314,463),Vector2(325,477),
	Vector2(330,496),Vector2(321,515),Vector2(323,530),Vector2(332,552),
	Vector2(344,557),Vector2(359,542),Vector2(370,542),Vector2(373,550),
	Vector2(349,577),Vector2(341,593),Vector2(345,619),Vector2(353,651),
	Vector2(345,667),Vector2(330,668),Vector2(320,708),Vector2(308,749),
	Vector2(310,780),Vector2(328,791),Vector2(325,799),Vector2(305,800),
	Vector2(291,795),Vector2(278,792),Vector2(271,783),Vector2(275,740),
	Vector2(280,704),Vector2(282,670),Vector2(272,661),Vector2(271,640),
	Vector2(276,608),Vector2(266,587),Vector2(244,579),Vector2(235,565),
	Vector2(240,544),Vector2(251,526),Vector2(259,507),Vector2(266,481)])
const LIGHTS := {
	"观测会活动室":Vector2(350,537),"教学楼":Vector2(658,399),
	"弓道场":Vector2(1101,563),"保健室":Vector2(1394,574)}
const SIGNS := {
	"观测会活动室":Rect2(368,337,198,81),"教学楼":Rect2(577,274,151,49),
	"弓道场":Rect2(995,412,145,50),"保健室":Rect2(1285,427,147,43),
	"校园漫游":Rect2(756,364,169,71),"调查公告板":Rect2(75,571,144,47),
	"继续调查":Rect2(1454,401,205,73),"调查卡：继续调查":Rect2(1384,817,201,38)}

var clock := 0.0
var breeze := 0.0
var gaze := Vector2.ZERO
var hover_key := ""
var blocked := false
var attention := 0.0
var hover_strength := 0.0
var unread: Array[String] = []
var pending := false
var _last_foley := -10.0
var _click_age := 1.0
var _click_point := Vector2.ZERO
var _click_rect := Rect2()
var _blink_at := 3.8
var _blink_age := 1.0
var _foliage: ShaderMaterial
var _mio: ShaderMaterial

class Feedback extends Control:
	var atmosphere: Control
	func _draw() -> void:
		if is_instance_valid(atmosphere): atmosphere.paint_feedback(self)

func create_feedback() -> Control:
	var layer := Feedback.new()
	layer.atmosphere = self
	layer.size = DESIGN
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer

func configure(original: Texture2D, world: Texture2D) -> void:
	size = DESIGN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var foliage := TextureRect.new()
	foliage.texture = world
	foliage.size = DESIGN
	foliage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foliage = ShaderMaterial.new()
	_foliage.shader = preload("res://scripts/art/campus_foliage.gdshader")
	foliage.material = _foliage
	add_child(foliage)
	# A silhouette-only clean plate reveals less than one pixel during breathing.
	# The visible character always samples the approved original, not a redrawn cutout.
	var plates := Geometry2D.offset_polygon(mio_outline,1.25)
	if not plates.is_empty():
		var plate := Polygon2D.new()
		plate.polygon = plates[0]
		plate.uv = plates[0]
		plate.texture = preload("res://assets/art/hub/motion/mio_cleanplate_v1.png")
		add_child(plate)
	var girl := Polygon2D.new()
	girl.polygon = mio_outline
	girl.uv = mio_outline
	girl.texture = original
	_mio = ShaderMaterial.new()
	_mio.shader = preload("res://scripts/art/campus_mio.gdshader")
	_mio.set_shader_parameter("blink_frame",preload("res://assets/art/hub/motion/mio_blink_v1.png"))
	_mio.set_shader_parameter("blink_base",preload("res://assets/art/hub/campus_clean.png"))
	girl.material = _mio
	add_child(girl)

func tick(delta: float, pointer: Vector2, modal: bool, active_window: bool) -> void:
	blocked = modal or not active_window
	if blocked:
		hover_key = ""
		queue_redraw()
		return
	clock += minf(delta,0.05)
	breeze = sin(clock*0.45)*0.62+sin(clock*0.91)*0.22
	var target := (pointer/DESIGN-Vector2(.5,.5)).clamp(-Vector2.ONE*.5,Vector2.ONE*.5)
	gaze = gaze.lerp(target,1.0-exp(-delta*3.0))
	hover_strength = move_toward(hover_strength,0.0 if hover_key.is_empty() else 1.0,delta*5.0)
	var idle := pow(maxf(0.0,sin(clock*.18)),24.0)*.45
	attention = move_toward(attention,1.0 if hover_key=="与雨宫澪交谈" else idle,delta*3.0)
	_click_age += delta
	if clock>=_blink_at:
		_blink_age = 0.0
		_blink_at = clock+4.1+sin(clock*0.31)*0.8
	_blink_age += delta
	var blink := sin(clampf(_blink_age/.16,0.0,1.0)*PI) if _blink_age<.16 else 0.0
	_foliage.set_shader_parameter("clock",clock)
	_foliage.set_shader_parameter("breeze",breeze)
	_foliage.set_shader_parameter("gaze",gaze)
	_mio.set_shader_parameter("clock",clock)
	_mio.set_shader_parameter("breeze",breeze)
	_mio.set_shader_parameter("attention",attention)
	_mio.set_shader_parameter("blink",blink)
	queue_redraw()

func set_hover(key: String) -> void:
	if blocked or pending or hover_key==key: return
	hover_key = key
	hover_strength = 0.0
	if clock-_last_foley<3.0: return
	var cue := "campus_bow" if key=="弓道场" else "campus_paper" if key in ["调查公告板","查看放课后观测记录"] else ""
	if cue.is_empty(): return
	_last_foley = clock
	AudioService.play_sfx(cue,-14.0)

func clear_hover(key: String) -> void:
	if hover_key==key: hover_key = ""

func feedback(key: String, rect: Rect2) -> void:
	_click_point = rect.get_center()
	_click_rect = rect
	_click_age = 0.0
	if key=="与雨宫澪交谈":
		_click_age = 1.0
		_blink_age = 0.0
	AudioService.play_sfx("campus_paper",-20.0)

func paint_feedback(surface: Control) -> void:
	if blocked or _click_age>=.24: return
	var progress := _click_age/.24
	var edge := _click_rect.grow(1.5+progress*2.0)
	surface.draw_line(edge.position+Vector2(12,0),edge.position+Vector2(edge.size.x-12,0),Color(.91,.83,.64,(1-progress)*.65),1.2,true)
	surface.draw_line(edge.end-Vector2(edge.size.x-12,0),edge.end-Vector2(12,0),Color(.91,.83,.64,(1-progress)*.65),1.2,true)

func _draw() -> void:
	if blocked: return
	# Warm pools are additive glows, drawn behind labels and modal veils.
	for key: String in LIGHTS:
		var strength := (0.036+0.008*sin(clock*.6+float(key.length())))
		if hover_key==key: strength += .055*hover_strength
		var center: Vector2 = LIGHTS[key]
		for ring: int in range(7):
			var radius := 26.0+float(ring)*13.0
			draw_circle(center,radius,Color(1.0,.67,.30,strength*(1.0-float(ring)/8.0)/7.0))
	# Sparse resonance traces remain in the existing purple sky.
	for i: int in range(3):
		var points := PackedVector2Array()
		for j: int in range(37):
			var a := float(j)/36.0*PI*1.35+clock*.025+float(i)*.2
			points.append(Vector2(1205+cos(a)*(80+i*12),76+sin(a)*(15+i*4)))
		draw_polyline(points,Color(.72,.50,1.0,.10+sin(clock*.5+i)*.025),1.0,true)
	for i: int in range(8):
		var star := Vector2(1055+fmod(i*71.0,330.0),25+fmod(i*37.0,120.0))
		if Rect2(1337,27,254,42).has_point(star): continue
		var intensity := pow(maxf(0.0,sin(clock*.65+i*1.7)),4.0)*.55
		draw_circle(star,1.2,Color(.77,.68,1.0,intensity))
	# Hover accents surround a sign; the sign and its glyphs never translate.
	if SIGNS.has(hover_key):
		var rect: Rect2 = SIGNS[hover_key]
		var color := GOLD if hover_key in ["观测会活动室","调查公告板","继续调查"] else BLUE
		color.a = .36*hover_strength
		draw_line(rect.position+Vector2(14,-3),rect.position+Vector2(rect.size.x-14,-3),color,1.0,true)
		draw_circle(rect.position+Vector2(6,rect.size.y*.5),2.0+sin(clock*3.0)*.4,color)
	for key: String in unread:
		if not SIGNS.has(key): continue
		var rect: Rect2 = SIGNS[key]
		var center := rect.position+Vector2(rect.size.x-7,4)
		var alpha := .32+.22*(sin(clock*1.7+key.length())*.5+.5)
		draw_circle(center,6.0,Color(1.0,.83,.40,alpha*.18))
		draw_circle(center,2.4,Color(1.0,.85,.45,alpha))
	if _click_age<.24:
		var progress := _click_age/.24
		draw_arc(_click_point,6+progress*13,0,TAU,28,Color(.91,.83,.64,(1-progress)*.5),1.2,true)
