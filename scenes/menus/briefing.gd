extends CampusScreen

var party: Array = []
var selected: Array = []
var cards: Dictionary = {}
var pressed_id := ""
var press_position := Vector2.ZERO
var drag_offset := Vector2.ZERO
var dragging := false
var pointer := Vector2.ZERO
var hint: Label
var hint_time := 0.0

func _ready() -> void:
	super._ready()
	var sid := str(CampaignFlow.state().get("pending_stage_id", "1-1"))
	var cfg := CampaignFlow.effective_stage_config(DataRegistry.get_entry("stages", sid))
	set_background(ArtRegistry.STAGE_ENV.get(sid, ArtRegistry.DEFAULT_ENV))
	page_heading("%s  ·  %s" % [sid, cfg.get("stageName", "关卡情报")], "残响时刻即将开始  /  部署确认")
	panel(Rect2(80, 210, 850, 720))
	label_at("观测记录", Rect2(120, 245, 740, 65), 36, GOLD)
	var note := label_at(str(cfg.get("briefing", "守住核心，清除所有残响体。")), Rect2(120, 340, 740, 140), 30)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var names: Array[String] = []
	for spawn: Dictionary in cfg.get("enemySpawnTimeline", []):
		var enemy := DataRegistry.get_entry("enemies", str(spawn.get("enemy", "")))
		var enemy_name := str(enemy.get("name", spawn.get("enemy", "")))
		if not names.has(enemy_name):
			names.append(enemy_name)
	var enemy_label := label_at("残响体\n%s" % " · ".join(names), Rect2(120, 540, 740, 145), 28, MUTED)
	enemy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_at("防线 %d   /   初始 AP %d   /   3 条路线" % [int(cfg.get("coreHp", 3)), int(cfg.get("startingAp", 10))], Rect2(120, 760, 740, 60), 27, BLUE)
	panel(Rect2(990, 210, 850, 720))
	label_at("本关出战角色", Rect2(1030, 245, 760, 65), 36, GOLD)
	var roster: Array = cfg.get("availableCharacters", [])
	party = roster.duplicate()
	var saved: Array = CampaignFlow.state().get("party_order", [])
	var unique_saved: Dictionary = {}
	for cid: Variant in saved:
		unique_saved[cid] = true
	if saved.size() == party.size() and unique_saved.size() == party.size() and saved.all(func(cid: Variant) -> bool: return party.has(cid)):
		party = saved.duplicate()
	selected = party.duplicate()
	if str(CampaignFlow.state().get("party_stage", "")) == sid:
		selected = CampaignFlow.state().get("party_selected", party).filter(func(cid: Variant) -> bool: return party.has(cid))
	for i: int in range(party.size()):
		var cid := str(party[i])
		var char_cfg := DataRegistry.get_entry("characters", cid)
		var card := panel(Rect2(1025 + (i%3)*260, 330 + int(i/3)*260, 240, 245))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards[cid] = card
		var portrait := texture_at(ArtRegistry.character_portrait(cid,256),Rect2(0,0,224,168))
		portrait.reparent(card)
		portrait.position = Vector2(8,8)
		var name_label := label_at(str(char_cfg.get("name",cid)),Rect2(0,0,216,34),24)
		name_label.reparent(card)
		name_label.position = Vector2(12,179)
		var cost := label_at("%d AP" % int(char_cfg.get("deployCost",0)),Rect2(0,0,210,26),21,BLUE)
		cost.reparent(card)
		cost.position = Vector2(12,215)
		_refresh_card(cid)
	label_at("单击选择 / 再次单击取消 · 拖动头像调整顺序",Rect2(1030,875,760,40),23,MUTED)
	button_at("返回关卡记录" if CampaignFlow.briefing_back_key() == "stage_select" else "返回校园", Rect2(90, 970, 380, 75), _back)
	button_at("开始战斗   →", Rect2(1390, 970, 450, 75), _start, true).grab_focus()
	hint = label_at("",Rect2(540,970,840,75),25,Color("ffacb0"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.hide()

func _process(delta: float) -> void:
	if hint_time > 0.0:
		hint_time = maxf(0.0,hint_time-delta)
		hint.modulate.a = clampf(hint_time/.35,0.0,1.0)
		if hint_time <= 0.0: hint.hide()
	for cid: String in cards:
		var index := party.find(cid)
		var target := Vector2(1025 + (index%3)*260,330+int(index/3)*260)
		if cid == pressed_id and dragging:
			target = pointer - drag_offset
		var card: Panel = cards[cid]
		card.position = card.position.lerp(target,1.0-exp(-delta*22.0))
		card.z_index = 20 if cid == pressed_id and dragging else 0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_back()
		return
	if event is InputEventMouse:
		pointer = canvas.get_global_transform_with_canvas().affine_inverse() * event.position
	if event is InputEventMouseMotion and not pressed_id.is_empty():
		if pointer.distance_to(press_position)>10:
			dragging = true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := pointer
		if event.pressed:
			for cid: String in cards:
				var card: Panel = cards[cid]
				if Rect2(card.position,card.size).has_point(pos):
					pressed_id = cid
					press_position = pos
					drag_offset = pos-card.position
					dragging = false
					break
		elif not pressed_id.is_empty():
			if dragging:
				for i: int in range(party.size()):
					if Rect2(1025+(i%3)*260,330+int(i/3)*260,240,245).has_point(pos):
						party.erase(pressed_id)
						party.insert(i,pressed_id)
						break
			elif selected.has(pressed_id):
				selected.erase(pressed_id)
			else:
				selected.append(pressed_id)
			_refresh_card(pressed_id)
			AudioService.play_sfx("select")
			pressed_id = ""
			dragging = false
			_save_party()

func _refresh_card(cid: String) -> void:
	var card: Panel = cards[cid]
	var style := GameSkin.panel(Color(0.05,0.09,0.17,0.28),BLUE if selected.has(cid) else Color(0.24,0.31,0.43,0.35))
	style.set_border_width_all(2 if selected.has(cid) else 1)
	style.set_corner_radius_all(3)
	card.add_theme_stylebox_override("panel",style)
	var tween := create_tween()
	tween.tween_property(card,"modulate",Color.WHITE if selected.has(cid) else Color(0.65,0.7,0.8,0.65),0.16)

func _save_party() -> bool:
	var sid := str(CampaignFlow.state().get("pending_stage_id",""))
	return CampaignFlow.persist({"party_order":party,"party_selected":selected,"party_stage":sid})

func _start() -> void:
	if selected.is_empty():
		_show_hint("请至少选择一名出战角色。")
		return
	if _save_party(): CampaignFlow.launch_battle()
	else: _show_hint("阵容保存失败，请重试。")

func _show_hint(message: String) -> void:
	hint.text = GameLocale.text(message)
	hint_time = 2.5
	hint.modulate.a = 1.0
	hint.show()

func _back() -> void:
	# Finish the native input dispatch before detaching its current scene.
	SceneRouter.go_to.call_deferred(CampaignFlow.briefing_back_key())
