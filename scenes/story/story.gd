extends CampusScreen

var story_id := ""
var nodes: Array = []
var index := 0
var replay := false
var dialogue: RichTextLabel
var speaker: Label
var page: Label
var portrait: TextureRect
var figure: TextureRect
var history: Array[String] = []
var auto := false
var auto_timer := 0.0
var history_panel: Panel
var menu_panel: Panel
var text_speed := 42.0

func _ready() -> void:
	super._ready()
	replay = not CampaignFlow.replay_story_id.is_empty()
	story_id = CampaignFlow.replay_story_id if replay else str(CampaignFlow.state().get("current_story_id", "prologue_transfer"))
	var data := DataRegistry.get_entry("story", story_id)
	nodes = data.get("nodes", [])
	index = 0 if replay else int(CampaignFlow.state().get("current_story_node", "0"))
	set_background(str(data.get("background", "bg_env_corridor_dusk")))
	AudioService.play_music(str(data.get("music", "after_school")))
	figure = texture_at(null, Rect2(1040, 100, 680, 750))
	panel(Rect2(70, 740, 1780, 260))
	panel(Rect2(85, 700, 400, 70), BLUE)
	speaker = label_at("", Rect2(115, 714, 500, 55), 32, GOLD)
	portrait = texture_at(null, Rect2(95, 785, 170, 170))
	dialogue = RichTextLabel.new()
	dialogue.position = Vector2(300, 790)
	dialogue.size = Vector2(1460, 165)
	dialogue.add_theme_font_size_override("normal_font_size", 34)
	dialogue.add_theme_color_override("default_color", WHITE)
	dialogue.scroll_active = false
	dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(dialogue)
	page = label_at("", Rect2(1540, 1005, 300, 40), 22, MUTED)
	button_at("历史", Rect2(80, 1010, 150, 50), _show_history)
	button_at("自动", Rect2(250, 1010, 150, 50), func() -> void: auto = not auto)
	button_at("菜单", Rect2(420, 1010, 150, 50), _show_menu)
	button_at("下一句  ▸", Rect2(1510, 920, 290, 60), advance)
	label_at(str(data.get("title", "")), Rect2(80, 45, 1400, 60), 30, GOLD)
	_show_node()

func _process(delta: float) -> void:
	if dialogue == null or (menu_panel != null and menu_panel.visible) or (history_panel != null and history_panel.visible):
		return
	if dialogue.visible_ratio < 1.0:
		dialogue.visible_ratio = minf(1.0, dialogue.visible_ratio + delta * text_speed / maxf(1, dialogue.get_total_character_count()))
		auto_timer = 0
	elif auto:
		auto_timer += delta
		if auto_timer > 2.5:
			advance()

func _show_node() -> void:
	if index >= nodes.size():
		_finish()
		return
	var node: Dictionary = nodes[index]
	var cid := str(node.get("character", ""))
	speaker.text = str(node.get("speaker", "")).replace("{player}", str(SaveService.get_current().get("profile", {}).get("playerName", "转校生")))
	dialogue.text = str(node.get("text", "")).replace("{player}", str(SaveService.get_current().get("profile", {}).get("playerName", "转校生")))
	dialogue.visible_ratio = 0.0
	portrait.texture = ArtRegistry.character_portrait(cid, 256) if not cid.is_empty() else null
	if cid == "amamiya_mio" and node.has("emotion"):
		var emotion_tex := ArtRegistry.load_texture("res://assets/art/characters/amamiya_mio/amamiya_mio_portrait_%s.png" % str(node["emotion"]))
		if emotion_tex != null:
			portrait.texture = emotion_tex
	var figure_path := "res://assets/art/characters/%s/%s_story.png" % [cid, cid]
	figure.texture = ArtRegistry.load_texture(figure_path) if not cid.is_empty() else null
	if node.has("background"):
		set_background(str(node["background"]))
	if node.has("sound"):
		AudioService.play_sfx(str(node["sound"]))
	page.text = "%d / %d    Enter · 下一句" % [index + 1, nodes.size()]
	history.append("%s：%s" % [speaker.text, dialogue.text])
	if not replay and not CampaignFlow.record_node(story_id, index):
		show_error("剧情进度未能保存，请检查磁盘后再继续。")

func advance() -> void:
	if menu_panel != null and menu_panel.visible or history_panel != null and history_panel.visible:
		return
	if dialogue.visible_ratio < 1.0:
		dialogue.visible_ratio = 1.0
		return
	index += 1
	auto_timer = 0
	_show_node()

func _finish() -> void:
	if replay:
		CampaignFlow.replay_story_id = ""
		SceneRouter.go_to("archive")
	elif not CampaignFlow.finish_story(story_id):
		index = maxi(0, nodes.size() - 1)
		show_error("剧情结算保存失败，未推进进度。")

func _show_history() -> void:
	if history_panel != null:
		for child: Node in history_panel.get_children():
			if child is RichTextLabel:
				child.text = "\n\n".join(history)
		history_panel.visible = true
		return
	history_panel = panel(Rect2(240, 160, 1440, 790))
	var log_view := RichTextLabel.new()
	log_view.position = Vector2(35, 35)
	log_view.size = Vector2(1370, 640)
	log_view.text = "\n\n".join(history)
	log_view.add_theme_font_size_override("normal_font_size", 29)
	history_panel.add_child(log_view)
	var close := button_at("关闭历史", Rect2(1370, 860, 260, 60), func() -> void: history_panel.hide())
	close.reparent(history_panel)
	close.position = Vector2(1130, 700)

func _show_menu() -> void:
	if menu_panel != null:
		menu_panel.visible = true
		return
	menu_panel = panel(Rect2(620, 270, 680, 440))
	var hint := label_at("剧情进度已自动保存", Rect2(700, 315, 550, 70), 30, GOLD)
	hint.reparent(menu_panel)
	hint.position = Vector2(80, 45)
	for spec: Array in [["继续阅读", 140, func() -> void: menu_panel.hide()], ["返回标题", 240, func() -> void: SceneRouter.go_to("title")]]:
		var button := button_at(str(spec[0]), Rect2(700, 270 + int(spec[1]), 520, 75), spec[2])
		button.reparent(menu_panel)
		button.position = Vector2(80, int(spec[1]))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			advance()
		elif event.keycode == KEY_ESCAPE:
			if history_panel != null and history_panel.visible:
				history_panel.hide()
			elif menu_panel != null and menu_panel.visible:
				menu_panel.hide()
			else:
				_show_menu()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
