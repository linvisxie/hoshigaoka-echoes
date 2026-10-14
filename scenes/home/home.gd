extends CampusScreen

const ART_SIZE := Vector2(1672,941)
const APPROVED := "res://assets/art/hub/campus_approved.png"
const CLEAN := "res://assets/art/hub/campus_clean.png"
const TEXTLESS := "res://assets/art/hub/campus_textless.png"
const MAIN_LOCATIONS: Array[String] = ["观测会活动室","教学楼","弓道场","保健室"]
const CARD := Rect2(1220,695,424,168)
const LOCATION_EVENTS := {
	"观测会活动室":["hub_ch1_mio","hub_ch1_borrow"],
	"教学楼":["hub_ch1_notice","hub_ch1_rin"],
	"弓道场":["hub_ch1_yuma"],"保健室":["hub_ch1_yui"],
}
const LOCATION_BACKGROUNDS := {
	"观测会活动室":"bg_env_classroom_dusk","教学楼":"bg_env_corridor_dusk",
	"弓道场":"bg_env_corridor_dusk","保健室":"bg_env_infirmary_battle",
}
var campus_panel: Panel
var exit_panel: Panel
var investigation: Control
var investigation_state: Dictionary = {}
var art_buttons: Dictionary = {}
var _approved: Texture2D
var _clean: Texture2D
var _textless: Texture2D
var resource_chips: Dictionary = {}
var resource_tip: ResourceDescription
var _resource_hover_id := ""
var _resource_hover_age := 0.0
var atmosphere: CampusAtmosphere
var petals: CampusPetals
var _action_epoch := 0
var _card_motion: Tween
var _feedback: Control
var _photo_reveal: ShaderMaterial

func _ready() -> void:
	super._ready()
	_approved = ArtRegistry.load_texture(APPROVED)
	_clean = ArtRegistry.load_texture(CLEAN)
	_textless = ArtRegistry.load_texture(TEXTLESS)
	background.texture = _textless if GameLocale.is_english() else _approved
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	(get_child(1) as ColorRect).color.a = 0.0
	canvas.size = ART_SIZE
	_fit_canvas()
	petals = CampusPetals.new()
	add_child(petals)
	move_child(petals,2)
	AudioService.play_music("observation_club")
	# Reconstruct only occluded rectangles. Every other pixel uses the approved art.
	for rect: Rect2 in [Rect2(22,22,352,86),Rect2(1337,24,253,48),Rect2(1593,21,64,55),
		Rect2(1454,92,205,382),Rect2(577,274,151,49),Rect2(368,337,198,81),
		Rect2(756,364,169,71),Rect2(995,412,145,50),Rect2(1285,427,147,78),
		Rect2(75,571,144,47),CARD]:
		_image(_slice(_clean,rect),rect)
	_image(_slice(_textless if GameLocale.is_english() else _approved,Rect2(22,22,352,86)),Rect2(22,22,352,86))
	_image(_slice(_textless if GameLocale.is_english() else _approved,Rect2(1454,92,205,382)),Rect2(1454,92,205,382))
	_art_button("设置",Rect2(1593,21,64,55),func() -> void: SceneRouter.go_to("settings"))
	_art_button("角色培养",Rect2(1482,163,157,55),func() -> void: SceneRouter.go_to("character"))
	_art_button("装备背包",Rect2(1482,224,157,55),func() -> void: SceneRouter.go_to("equipment"))
	_art_button("关卡记录",Rect2(1482,284,157,52),func() -> void: SceneRouter.go_to("stage_select"))
	_art_button("剧情档案",Rect2(1482,344,157,52),func() -> void: SceneRouter.go_to("archive"))
	_art_button("继续调查",Rect2(1454,401,205,73),_continue_investigation)
	for place: String in ["教学楼","观测会活动室","弓道场","保健室"]:
		var rects := {"教学楼":Rect2(577,274,151,49),"观测会活动室":Rect2(368,337,198,81),"弓道场":Rect2(995,412,145,50),"保健室":Rect2(1285,427,147,43)}
		_art_button(place,rects[place],func() -> void: _show_location(place))
	_art_button("校园漫游",Rect2(756,364,169,71),_show_campus)
	_art_button("调查公告板",Rect2(75,571,144,47),_toggle_investigation)
	_art_button("与雨宫澪交谈",Rect2(244,452,120,348),func() -> void: _show_location("观测会活动室")).add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	art_buttons["与雨宫澪交谈"].tooltip_text = ""
	_art_button("查看放课后观测记录",Rect2(6,325,199,243),_toggle_investigation).add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	# These are invisible hotspots, not rectangular copies of the static painting.
	# Keep their normal/pressed skins from covering the animated character/paper.
	for hotspot: String in ["与雨宫澪交谈","查看放课后观测记录"]:
		for state: String in ["normal","hover","pressed","disabled"]:
			art_buttons[hotspot].add_theme_stylebox_override(state,StyleBoxEmpty.new())
	if _has_unread("保健室") and not GameLocale.is_english():
		_image(_slice(_approved,Rect2(1285,470,147,35)),Rect2(1285,470,147,35))
	_legacy_resource("school_coin","icon_school_coin",Rect2(1339,29,119,38))
	_legacy_resource("equipment_part","icon_material",Rect2(1470,29,119,38))
	_build_investigation()
	_build_crisp_text()
	atmosphere = CampusAtmosphere.new()
	atmosphere.configure(_textless if GameLocale.is_english() else _approved,_textless if GameLocale.is_english() else _approved)
	canvas.add_child(atmosphere)
	canvas.move_child(atmosphere,0)
	_feedback = atmosphere.create_feedback()
	canvas.add_child(_feedback)
	for place: String in MAIN_LOCATIONS:
		if _has_unread(place): atmosphere.unread.append(place)
	for event: Dictionary in CampusHub.events():
		if not CampaignFlow.done(str(event.storyId)): atmosphere.new_record = true
	for key: String in art_buttons:
		var control: Button = art_buttons[key]
		control.mouse_entered.connect(func() -> void: atmosphere.set_hover(key))
		control.mouse_exited.connect(func() -> void: atmosphere.clear_hover(key))
		control.focus_entered.connect(func() -> void:
			if App.keyboard_navigation: atmosphere.set_hover(key))
		control.focus_exited.connect(func() -> void: atmosphere.clear_hover(key))
	var investigation_key := str(investigation_state.stage) if not str(investigation_state.stage).is_empty() else "complete"
	_animate_card(SceneRouter.last_campus_investigation!=investigation_key)
	SceneRouter.last_campus_investigation = investigation_key
	resource_tip = ResourceDescription.new()
	resource_tip.z_index = 50
	add_child(resource_tip)
	resource_tip.hide()
	if CampaignFlow.open_campus_menu:
		CampaignFlow.open_campus_menu = false
		_show_menu()
	if SceneRouter.entry_origin()=="title": fade_in_content()

func _fit_canvas() -> void:
	if canvas == null: return
	var viewport := get_viewport_rect().size
	# The approved 1672x941 raster is a rounded 16:9 canvas. Match its two
	# axes to the native viewport to avoid a one-pixel drift across atlas controls.
	if absf(viewport.x/viewport.y-ART_SIZE.x/ART_SIZE.y)<.002:
		canvas.scale = viewport/ART_SIZE
		canvas.position = Vector2.ZERO
		if background != null: background.stretch_mode = TextureRect.STRETCH_SCALE
		return
	var factor := minf(viewport.x/ART_SIZE.x,viewport.y/ART_SIZE.y)
	canvas.scale = Vector2.ONE*factor
	canvas.position = ((viewport-ART_SIZE*factor)*.5).floor()
	if background != null: background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _slice(texture: Texture2D,rect: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = rect
	atlas.filter_clip = false
	return atlas

func _image(texture: Texture2D,rect: Rect2,parent: Control = null) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.position = rect.position
	image.size = rect.size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else canvas).add_child(image)
	return image

func _art_button(caption: String,rect: Rect2,action: Callable,parent: Control = null) -> CampusArtButton:
	var button := CampusArtButton.new()
	button.configure(caption,preload("res://assets/art/ui/campus_settings.svg") if caption == "设置" else _slice(_textless if GameLocale.is_english() else _approved,rect),func() -> void: _campus_action(caption,rect,action))
	button.position = rect.position
	button.size = rect.size
	(parent if parent != null else canvas).add_child(button)
	art_buttons[caption] = button
	return button

func _legacy_resource(currency_id: String,icon_id: String,rect: Rect2) -> void:
	var group := Control.new()
	group.name = currency_id+"Chip"
	group.position = rect.position
	group.size = rect.size
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(group)
	resource_chips[currency_id] = group
	# Identical fine gold frames; original resource art, fitted to one icon box.
	_image(preload("res://assets/art/ui/campus_resource.svg"),Rect2(Vector2.ZERO,rect.size),group)
	var icon := ArtRegistry.icon(icon_id,64)
	var used := icon.get_image().get_used_rect()
	_image(_slice(icon,Rect2(used)),Rect2(10,8,22,22),group)
	var number := _native_text(str(int(SaveService.get_current().get("currencies",{}).get(currency_id,0))),Rect2(42,0,73,38),17,WHITE,group)
	number.add_theme_font_override("font",GameSkin.body_font())

func _build_investigation() -> void:
	var sid := CampaignFlow.next_stage()
	var cfg := DataRegistry.get_entry("stages",sid)
	investigation_state = {"stage":sid,"title":str(cfg.get("stageName","第一章调查已归档")),"complete":sid.is_empty()}
	investigation = Control.new()
	investigation.position = CARD.position
	investigation.size = CARD.size
	investigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(investigation)
	var card_image := _image(_slice(_textless if GameLocale.is_english() else _approved,CARD),Rect2(Vector2.ZERO,CARD.size),investigation)
	_photo_reveal = ShaderMaterial.new()
	_photo_reveal.shader = preload("res://scripts/art/campus_card_reveal.gdshader")
	card_image.material = _photo_reveal
	var clue := _investigation_clue(sid)
	investigation_state["clue"] = clue
	_image(_slice(_textless,Rect2(1378,703,251,109)),Rect2(158,8,251,109),investigation)
	_card_label("当前调查 · "+sid if not sid.is_empty() else "第一章 · 已归档",Rect2(163,7,238,25),14,MUTED)
	_card_label(str(investigation_state.title),Rect2(163,30,238,37),22,WHITE)
	_card_label(clue,Rect2(163,67,238,49),15,WHITE)
	var action := _art_button("调查卡：继续调查",Rect2(1384,817,201,38),_continue_investigation,investigation)
	action.position -= CARD.position
	action.tooltip_text = GameLocale.text("重访已开放关卡" if sid.is_empty() else "前往 "+sid+" · "+str(investigation_state.title))
	art_buttons["继续调查"].tooltip_text = GameLocale.text(action.tooltip_text)
	_text_patch(Rect2(1410,821,146,26) if GameLocale.is_english() else Rect2(1444,821,86,26),"Continue" if GameLocale.is_english() else "继续调查",18,WHITE,investigation,CARD.position)

func _native_text(value: String,rect: Rect2,font_size: int,color: Color,parent: Control) -> Label:
	var label := Label.new()
	label.text = GameLocale.text(value)
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",GameSkin.serif())
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.add_theme_font_size_override("font_size",font_size)
	if GameLocale.is_english():
		var fitted := font_size
		while fitted>11 and GameSkin.serif().get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,fitted).x>rect.size.x:
			fitted -= 1
		label.add_theme_font_size_override("font_size",fitted)
	label.add_theme_color_override("font_color",color)
	if GameLocale.is_english():
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _text_patch(rect: Rect2,value: String,font_size: int,color: Color = WHITE,parent: Control = null,origin: Vector2 = Vector2.ZERO) -> Label:
	var owner := parent if parent != null else canvas
	_image(_slice(_textless,rect),Rect2(rect.position-origin,rect.size),owner)
	return _native_text(value,Rect2(rect.position-origin,rect.size),font_size,color,owner)

func _build_crisp_text() -> void:
	if GameLocale.is_english():
		_build_english_text()
		return
	# Keep the original painted sign glyphs, spacing and positions. Handbook
	# captions share one native font so inventory matches the other three.
	for rect: Rect2 in [Rect2(121,37,229,40),Rect2(124,77,180,24),
		Rect2(1528,118,93,31),Rect2(1535,417,95,31),Rect2(630,281,78,30),
		Rect2(425,351,125,32),Rect2(426,388,105,23),Rect2(810,374,91,30),
		Rect2(796,408,109,23),Rect2(1051,423,68,31),Rect2(1335,441,68,30),
		Rect2(122,581,78,26),Rect2(77,870,344,31),Rect2(41,334,146,73),
		Rect2(209,364,27,115)]:
		_glyph_patch(rect)
	if _has_unread("保健室"): _glyph_patch(Rect2(1341,474,70,23))
	for entry: Array in [["角色培养",177],["装备背包",237],["关卡记录",297],["剧情档案",357]]:
		var index: int = ["角色培养","装备背包","关卡记录","剧情档案"].find(str(entry[0]))
		var center := 188.0+60.0*index
		var source_y: float = [174.0,232.0,291.0,349.0][index]
		_image(_slice(_textless,Rect2(1540,source_y-2,38,38)),Rect2(1490,source_y-2,38,38))
		var icon := _image(_slice(_approved,Rect2(1493,source_y,31,33)),Rect2(1493,center-16.5,31,33))
		icon.name = "HandbookIcon%d"%index
		_text_patch(Rect2(1540,center-15,91,30),str(entry[0]),19).set_meta("handbook_caption",true)

func _build_english_text() -> void:
	# Use the existing textless plate only in English; Chinese keeps approved art.
	var captions := [
		["Hoshigaoka High School",Rect2(121,37,229,40),22],
		["After School · Campus",Rect2(124,77,220,24),16],
		["Handbook",Rect2(1528,118,102,31),20],
		["Continue",Rect2(1535,417,95,31),19],
		["Classrooms",Rect2(621,277,92,40),18],
		["Observation Club",Rect2(418,345,135,44),18],
		["Mio is here",Rect2(426,388,120,23),15],
		["Campus Stroll",Rect2(802,369,110,39),18],
		["Explore other areas",Rect2(783,408,130,23),14],
		["Kyudo",Rect2(1042,416,85,40),20],
		["Infirmary",Rect2(1326,431,85,40),19],
		["Case Board",Rect2(117,576,87,35),16],
		["Listen for the voices still unheard.",Rect2(77,870,344,31),19],
		["After-School Records",Rect2(30,344,167,38),16],
	]
	if _has_unread("保健室"): captions.append(["New conversation",Rect2(1341,474,85,23),12])
	for entry: Array in captions:
		var label := _native_text(str(entry[0]),entry[1],int(entry[2]),GOLD if entry[1].position.y>570 else WHITE,canvas)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i: int in range(4):
		var center := 188.0+60.0*i
		var caption: String = ["Growth","Equipment","Stage Records","Story Archive"][i]
		_native_text(caption,Rect2(1534,center-15,104,30),17,WHITE,canvas).set_meta("handbook_caption",true)

func _process(delta: float) -> void:
	var modal := _has_campus_modal()
	var active_window := DisplayServer.window_is_focused()
	if is_instance_valid(atmosphere):
		atmosphere.tick(delta,canvas.get_local_mouse_position(),modal,active_window)
		_feedback.queue_redraw()
	if is_instance_valid(petals):
		petals.suspended = not active_window
		petals.breeze = atmosphere.breeze if is_instance_valid(atmosphere) else 0.0
	if not is_instance_valid(resource_tip): return
	var currency_id := ""
	if not modal:
		for key: String in resource_chips:
			if resource_chips[key].get_global_rect().has_point(get_global_mouse_position()): currency_id = key
	if currency_id != _resource_hover_id:
		_resource_hover_id = currency_id
		_resource_hover_age = 0.0
		if not currency_id.is_empty():
			var description := ResourceDescription.definition(currency_id)
			GameLog.debug("CampusTip","%s | %s | %s"%[currency_id,description.get("uiDescription",""),description.get("flavorText","")])
	_resource_hover_age += delta
	resource_tip.visible = not currency_id.is_empty() and _resource_hover_age>=.22
	if not resource_tip.visible: return
	var factor := minf(get_viewport_rect().size.x/1920.0,get_viewport_rect().size.y/1080.0)
	resource_tip.set_ui_scale(factor)
	resource_tip.set_currency(currency_id)
	var anchor: Rect2 = resource_chips[currency_id].get_global_rect()
	resource_tip.position = Vector2(clampf(anchor.end.x-resource_tip.size.x,24*factor,get_viewport_rect().size.x-resource_tip.size.x-24*factor),116*factor)

func _glyph_patch(rect: Rect2) -> void:
	var image := _image(_slice(_approved,rect),rect)
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var clarity := ShaderMaterial.new()
	clarity.shader = preload("res://scripts/art/campus_glyph_clarity.gdshader")
	image.material = clarity

func _card_label(value: String,rect: Rect2,font_size: int,color: Color) -> void:
	var label := Label.new()
	label.text = GameLocale.text(value)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_override("font",GameSkin.serif())
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	investigation.add_child(label)
	label.set_meta("card_text",true)
	label.position = rect.position
	label.size = rect.size

func _investigation_clue(sid: String) -> String:
	var clues := {
		"1-1":"放课后的教室里，陌生的回声迟迟没有散去。","1-2":"走廊尽头的人影，还在等待一声没有响起的铃。",
		"1-3":"空白的试卷上，浮现了不属于任何人的批注。","1-4":"被悄悄压进书包的心事，渐渐有了重量。",
		"1-5":"铃声停下之后，体育馆里仍有人在点名。","1-6":"保健室的灯，为尚未说出口的伤口亮着。",
		"1-7":"名次表上的名字，正在抹去别的声音。","1-8":"有些答案，藏在无法开口的实验记录中。",
		"1-9":"满分的纸页之间，留下了重复的呼吸。","1-10":"这一次，听见那个没有名字的声音。",
	}
	return str(clues.get(sid,"十次调查已收入学生手册。\n可以重访已开放关卡。"))

func _continue_investigation() -> void:
	CampaignFlow.briefing_return_key = "home"
	var flow := CampaignFlow.state()
	if not str(flow.get("pending_story_after", "")).is_empty() or (str(flow.get("mode", "")) == "story" and not str(flow.get("current_story_id", "")).is_empty()):
		CampaignFlow.resume()
		return
	var sid := CampaignFlow.next_stage()
	if sid.is_empty(): SceneRouter.go_to("stage_select")
	else: CampaignFlow.open_stage(sid)

func _toggle_investigation() -> void:
	investigation.visible = not investigation.visible
	if investigation.visible: _animate_card()
	GameLog.info("CampusHub", "调查公告板：" + ("展开" if investigation.visible else "收起"))

func _has_campus_modal() -> bool:
	for child: Node in canvas.get_children():
		if child is Control and child.has_meta("campus_modal") and child.visible and not child.is_queued_for_deletion(): return true
	return false

func _animate_card(updated: bool = false) -> void:
	if _card_motion != null: _card_motion.kill()
	investigation.modulate.a = 0.0
	_photo_reveal.set_shader_parameter("photo_alpha",0.0 if updated else 1.0)
	_card_motion = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_card_motion.tween_property(investigation,"modulate:a",1.0,.38)
	if updated:
		_card_motion.tween_method(func(alpha: float) -> void: _photo_reveal.set_shader_parameter("photo_alpha",alpha),0.0,1.0,.36)
	for child: Node in investigation.get_children():
		if child is Control and child.has_meta("card_text"):
			child.modulate.a = 0.0 if updated else 1.0
			if updated: _card_motion.tween_property(child,"modulate:a",1.0,.40).set_delay(.18)

func _campus_action(caption: String,rect: Rect2,action: Callable) -> void:
	if not is_instance_valid(atmosphere):
		action.call()
		return
	if atmosphere.pending or _has_campus_modal(): return
	_action_epoch += 1
	var ticket := _action_epoch
	atmosphere.pending = true
	atmosphere.feedback(caption,rect)
	await get_tree().create_timer(.32 if caption=="与雨宫澪交谈" else .18).timeout
	if not is_inside_tree() or is_queued_for_deletion(): return
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	if not is_inside_tree() or is_queued_for_deletion(): return
	atmosphere.pending = false
	if ticket!=_action_epoch or _has_campus_modal(): return
	action.call()

func _location_events(location: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in CampusHub.events():
		if str(event.get("hubLocation","")) == location or str(event.storyId) in LOCATION_EVENTS.get(location,[]):
			result.append(event)
	return result

func _has_unread(location: String) -> bool:
	for event: Dictionary in _location_events(location):
		if not CampaignFlow.done(str(event.storyId)): return true
	return false

func _in_panel(control: Control,parent: Panel,position: Vector2) -> void:
	control.reparent(parent)
	control.position = position

func _new_campus_panel(title: String,subtitle: String) -> void:
	GameLog.info("CampusHub", "打开地点：" + title)
	if is_instance_valid(campus_panel): campus_panel.queue_free()
	campus_panel = modal_panel(Rect2(230,130,1210,680))
	_reveal_panel(campus_panel)
	_in_panel(label_at(title,Rect2(0,0,1110,60),36,GOLD),campus_panel,Vector2(45,25))
	_in_panel(label_at(subtitle,Rect2(0,0,1110,45),23,MUTED),campus_panel,Vector2(45,90))
	_in_panel(button_at("返回校园  Esc",Rect2(0,0,280,60),func() -> void: campus_panel.hide()),campus_panel,Vector2(880,590))

func _reveal_panel(dialog: Panel) -> void:
	dialog.modulate.a = .65
	var motion := dialog.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	motion.tween_property(dialog,"modulate:a",1.0,.18)

func _show_campus() -> void:
	_new_campus_panel("校园漫游","已经开放的地点 · 新的放课后记录会随调查逐步出现")
	var locations := _roaming_locations()
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(45,150)
	scroll.size = Vector2(1120,410)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	campus_panel.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",16)
	scroll.add_child(grid)
	if locations.is_empty():
		_in_panel(label_at("其他地区尚未开放。\n继续调查后，新的地点会在这里出现。",Rect2(0,0,1000,120),27,MUTED),campus_panel,Vector2(45,180))
	for place: String in locations:
		var events := _location_events(place)
		var detail := "%d 条记录" % events.size() if not events.is_empty() else "暂时没有可阅读的记录"
		if _has_unread(place): detail += " · 新"
		var tile := button_at(place+"\n"+detail,Rect2(),func() -> void: _show_location(place),_has_unread(place))
		tile.reparent(grid)
		tile.custom_minimum_size = Vector2(354,106)
		tile.add_theme_font_size_override("font_size",24)

func _roaming_locations() -> Array[String]:
	var locations: Array[String] = []
	for event: Dictionary in CampusHub.events():
		var place := str(event.get("hubLocation","校园"))
		# Main-place aliases are grouped into their visible doorway, not duplicated.
		var represented := MAIN_LOCATIONS.has(place)
		for main_place: String in MAIN_LOCATIONS:
			if str(event.storyId) in LOCATION_EVENTS.get(main_place,[]): represented = true
		if not represented and not locations.has(place): locations.append(place)
	return locations

func _show_location(location: String) -> void:
	var events := _location_events(location)
	_new_campus_panel(location,"同伴交谈与校园记录 · 阅读不会消耗资源，也不替代主线调查")
	var backdrop := str(events[0].get("background","bg_env_classroom_dusk")) if not events.is_empty() else str(LOCATION_BACKGROUNDS.get(location,"bg_env_classroom_dusk"))
	var scene_image := texture_at(ArtRegistry.environment(backdrop),Rect2(0,0,470,390))
	scene_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene_image.clip_contents = true
	_in_panel(scene_image,campus_panel,Vector2(45,155))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(550,155)
	scroll.size = Vector2(610,390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	campus_panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",15)
	scroll.add_child(list)
	for event: Dictionary in events:
		var sid := str(event.storyId)
		var status := "重温记录" if CampaignFlow.done(sid) else "新的交谈" if str(event.category) == "character_event" else "新的记录"
		var entry := button_at(str(event.title)+"\n"+status,Rect2(),func() -> void: CampusHub.visit(sid),not CampaignFlow.done(sid))
		entry.reparent(list)
		entry.custom_minimum_size = Vector2(580,92)
		entry.add_theme_font_size_override("font_size",24)
	if events.is_empty():
		_in_panel(label_at("这里暂时没有新的记录。\n继续调查后，再来听听放课后的声音。",Rect2(0,0,570,180),27,MUTED),campus_panel,Vector2(555,205))
	if location in ["教学楼","观测会活动室"]:
		var start := button_at("查看当前调查",Rect2(0,0,470,60),func() -> void:
			campus_panel.hide()
			investigation.show()
			art_buttons["调查卡：继续调查"].grab_focus(),true)
		_in_panel(start,campus_panel,Vector2(45,580))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_action_epoch += 1
		if is_instance_valid(campus_panel) and campus_panel.visible: campus_panel.hide()
		elif is_instance_valid(exit_panel) and exit_panel.visible: exit_panel.hide()
		else: _show_menu()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# A focused native button can consume ui_cancel before unhandled input.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_unhandled_key_input(event)

func _show_menu() -> void:
	GameLog.info("CampusHub", "打开校园菜单")
	if is_instance_valid(exit_panel): exit_panel.queue_free()
	exit_panel = modal_panel(Rect2(496,190,680,590))
	_reveal_panel(exit_panel)
	_in_panel(label_at("校园菜单",Rect2(0,0,520,60),36,GOLD),exit_panel,Vector2(80,40))
	_in_panel(label_at("进度已自动保存。",Rect2(0,0,520,45),25,MUTED),exit_panel,Vector2(80,110))
	for spec: Array in [["继续留在校园",190,func() -> void: exit_panel.hide()],["返回标题",290,func() -> void: SceneRouter.go_to("title")],["退出游戏",390,_confirm_exit]]:
		_in_panel(button_at(str(spec[0]),Rect2(0,0,520,75),spec[2]),exit_panel,Vector2(80,int(spec[1])))

func _confirm_exit() -> void:
	GameLog.info("CampusHub", "打开退出确认")
	exit_panel.hide()
	var confirm := modal_panel(Rect2(496,275,680,390))
	_in_panel(label_at("结束今天的观测？",Rect2(0,0,520,70),34,GOLD),confirm,Vector2(80,45))
	_in_panel(label_at("已保存的调查和培养进度会保留。",Rect2(0,0,560,50),24,MUTED),confirm,Vector2(60,125))
	_in_panel(button_at("取消",Rect2(0,0,250,75),func() -> void: confirm.queue_free()),confirm,Vector2(60,250))
	_in_panel(button_at("退出游戏",Rect2(0,0,250,75),App.request_quit,true),confirm,Vector2(370,250))
	exit_panel = confirm
