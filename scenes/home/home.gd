extends CampusScreen

const ART_SIZE := Vector2(1672,941)
const APPROVED := "res://assets/art/hub/campus_approved.png"
const CLEAN := "res://assets/art/hub/campus_clean.png"
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

func _ready() -> void:
	super._ready()
	_approved = ArtRegistry.load_texture(APPROVED)
	_clean = ArtRegistry.load_texture(CLEAN)
	background.texture = _approved
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	(get_child(1) as ColorRect).color.a = 0.0
	canvas.size = ART_SIZE
	_fit_canvas()
	AudioService.play_music("observation_club")
	# Reconstruct only occluded rectangles. Every other pixel uses the approved art.
	for rect: Rect2 in [Rect2(22,22,352,86),Rect2(1337,24,253,48),Rect2(1593,21,64,55),
		Rect2(1454,92,205,382),Rect2(577,274,151,49),Rect2(368,337,198,81),
		Rect2(756,364,169,71),Rect2(995,412,145,50),Rect2(1285,427,147,78),
		Rect2(75,571,144,47),CARD]:
		_image(_slice(_clean,rect),rect)
	_image(_slice(_approved,Rect2(22,22,352,86)),Rect2(22,22,352,86))
	_image(_slice(_approved,Rect2(1454,92,205,382)),Rect2(1454,92,205,382))
	_art_button("设置",Rect2(1593,21,64,55),func() -> void: SceneRouter.go_to("settings"))
	_art_button("角色培养",Rect2(1482,163,157,55),func() -> void: SceneRouter.go_to("character"))
	_art_button("角色装备",Rect2(1482,224,157,55),func() -> void: SceneRouter.go_to("character_equipment"))
	_art_button("关卡记录",Rect2(1482,284,157,52),func() -> void: SceneRouter.go_to("stage_select"))
	_art_button("剧情档案",Rect2(1482,344,157,52),func() -> void: SceneRouter.go_to("archive"))
	_art_button("继续调查",Rect2(1454,401,205,73),_continue_investigation)
	for place: String in ["教学楼","观测会活动室","弓道场","保健室"]:
		var rects := {"教学楼":Rect2(577,274,151,49),"观测会活动室":Rect2(368,337,198,81),"弓道场":Rect2(995,412,145,50),"保健室":Rect2(1285,427,147,43)}
		_art_button(place,rects[place],func() -> void: _show_location(place))
	_art_button("校园漫游",Rect2(756,364,169,71),_show_campus)
	_art_button("调查公告板",Rect2(75,571,144,47),_toggle_investigation)
	_art_button("与雨宫澪交谈",Rect2(244,452,120,348),func() -> void: _show_location("观测会活动室")).add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	_art_button("查看放课后观测记录",Rect2(6,325,199,243),_toggle_investigation).add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	if _has_unread("保健室"):
		_image(_slice(_approved,Rect2(1285,470,147,35)),Rect2(1285,470,147,35))
	else:
		_image(_slice(_clean,Rect2(1404,427,25,22)),Rect2(1404,427,25,22))
	_legacy_resource("school_coin","icon_school_coin",Rect2(1339,29,119,38))
	_legacy_resource("equipment_part","icon_material",Rect2(1470,29,119,38))
	_build_investigation()

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
	button.configure(caption,_slice(_approved,rect),action)
	button.position = rect.position
	button.size = rect.size
	(parent if parent != null else canvas).add_child(button)
	art_buttons[caption] = button
	return button

func _legacy_resource(currency_id: String,icon_id: String,rect: Rect2) -> void:
	var group := Control.new()
	group.position = rect.position
	var factor := rect.size.y/64.0
	group.scale = Vector2.ONE*factor
	group.size = Vector2(rect.size.x/factor,64)
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.tooltip_text = "学园币\n用于角色突破、技能与装备培养。" if currency_id == "school_coin" else "装备零件\n用于强化装备，可通过调查奖励获得。"
	canvas.add_child(group)
	var previous := canvas
	canvas = group
	resource_chip(currency_id,icon_id,Rect2(Vector2.ZERO,group.size))
	canvas = previous

func _build_investigation() -> void:
	var sid := CampaignFlow.next_stage()
	var cfg := DataRegistry.get_entry("stages",sid)
	investigation_state = {"stage":sid,"title":str(cfg.get("stageName","第一章调查已归档")),"complete":sid.is_empty()}
	investigation = Control.new()
	investigation.position = CARD.position
	investigation.size = CARD.size
	investigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(investigation)
	_image(_slice(_approved,CARD),Rect2(Vector2.ZERO,CARD.size),investigation)
	var clue := _investigation_clue(sid)
	investigation_state["clue"] = clue
	if sid != "1-3":
		var material := GradientTexture2D.new()
		material.gradient = Gradient.new()
		material.gradient.colors = PackedColorArray([Color("202939"),Color("101c2d")])
		material.fill_to = Vector2(0,1)
		_image(material,Rect2(158,8,251,109),investigation)
		_card_label("当前调查 · "+sid if not sid.is_empty() else "第一章 · 已归档",Rect2(163,7,238,25),14,MUTED)
		_card_label(str(investigation_state.title),Rect2(163,30,238,37),22,WHITE)
		_card_label(clue,Rect2(163,67,238,49),15,WHITE)
	var action := _art_button("调查卡：继续调查",Rect2(1384,817,201,38),_continue_investigation,investigation)
	action.position -= CARD.position
	action.tooltip_text = "重访已开放关卡" if sid.is_empty() else "前往 "+sid+" · "+str(investigation_state.title)
	art_buttons["继续调查"].tooltip_text = action.tooltip_text

func _card_label(value: String,rect: Rect2,font_size: int,color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_override("font",GameSkin.serif())
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	investigation.add_child(label)
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
	var flow := CampaignFlow.state()
	if not str(flow.get("pending_story_after", "")).is_empty() or (str(flow.get("mode", "")) == "story" and not str(flow.get("current_story_id", "")).is_empty()):
		CampaignFlow.resume()
		return
	var sid := CampaignFlow.next_stage()
	if sid.is_empty(): SceneRouter.go_to("stage_select")
	else: CampaignFlow.open_stage(sid)

func _toggle_investigation() -> void:
	investigation.visible = not investigation.visible
	GameLog.info("CampusHub", "调查公告板：" + ("展开" if investigation.visible else "收起"))

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
	_in_panel(label_at(title,Rect2(0,0,1110,60),36,GOLD),campus_panel,Vector2(45,25))
	_in_panel(label_at(subtitle,Rect2(0,0,1110,45),23,MUTED),campus_panel,Vector2(45,90))
	_in_panel(button_at("返回校园  Esc",Rect2(0,0,280,60),func() -> void: campus_panel.hide()),campus_panel,Vector2(880,590))

func _show_campus() -> void:
	_new_campus_panel("校园漫游","已经开放的地点 · 新的放课后记录会随调查逐步出现")
	var locations: Array[String] = ["观测会活动室","教学楼","弓道场","保健室"]
	for event: Dictionary in CampusHub.events():
		var place := str(event.get("hubLocation","校园"))
		if not locations.has(place): locations.append(place)
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
	for place: String in locations:
		var events := _location_events(place)
		var detail := "%d 条记录" % events.size() if not events.is_empty() else "暂时没有可阅读的记录"
		if _has_unread(place): detail += " · 新"
		var tile := button_at(place+"\n"+detail,Rect2(),func() -> void: _show_location(place),_has_unread(place))
		tile.reparent(grid)
		tile.custom_minimum_size = Vector2(354,106)
		tile.add_theme_font_size_override("font_size",24)

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
	_in_panel(label_at("校园菜单",Rect2(0,0,520,60),36,GOLD),exit_panel,Vector2(80,40))
	_in_panel(label_at("进度已自动保存。",Rect2(0,0,520,45),25,MUTED),exit_panel,Vector2(80,110))
	for spec: Array in [["继续留在校园",190,func() -> void: exit_panel.hide()],["返回标题",290,func() -> void: SceneRouter.go_to("title")],["退出游戏…",390,_confirm_exit]]:
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
