## Native, presentation-only battle HUD. All actions delegate to the existing scene/session.
class_name BattleHud
extends Control

var battle: Node
var canvas: Control
var normal: Control
var cards: Array[Dictionary] = []
var stage_label: Label
var location_label: Label
var defense: Label
var waves: Label
var preview: Label
var wave_marks: HBoxContainer
var ap_label: Label
var ap_rate: Label
var ap_bar: ProgressBar
var pause_button: Button
var selected: Panel
var selected_name: Label
var selected_stats: Label
var selected_skill: Label
var selected_portrait: TextureRect
var selected_hp: ProgressBar
var skill_button: Button
var retreat_button: Button
var hint: Label
var pause_layer: Control
var pause_panel: Panel
var paused_settings: Control
var leave_confirmation: Control
var menu_status: Label
var _normal_size := Vector2.ZERO
var _feedback_active := false
var overlays: BattleOverlays
var tutorial_stack: VBoxContainer
var tutorial_views: Array[Dictionary] = []
var boss_hp: ProgressBar
var _focus_scope: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = GameSkin.make_theme()
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	normal = Control.new()
	normal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(normal)
	_build_top()
	boss_hp = _bar(normal,Rect2(690,140,540,22),Color("ff223b"))
	boss_hp.visible = false
	_build_cards()
	_build_selected()
	_build_pause()
	tutorial_stack = VBoxContainer.new()
	tutorial_stack.position = Vector2(24, 166)
	tutorial_stack.size = Vector2(500, 0)
	tutorial_stack.add_theme_constant_override("separation", 12)
	tutorial_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	normal.add_child(tutorial_stack)
	hint = _label(normal, "", Rect2(550, 965, 800, 48), 24, GameSkin.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_stylebox_override("normal", _hint_style())
	overlays = BattleOverlays.new()
	overlays.hud = self
	overlays.battle = battle
	canvas.add_child(overlays)

func _panel(parent: Node, rect: Rect2, accent: Color = Color("58719b")) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", GameSkin.battle_glass())
	parent.add_child(p)
	return p

func _label(parent: Node, text: String, rect: Rect2, font_size: int = 26, color: Color = GameSkin.WHITE) -> Label:
	var l := Label.new()
	l.text = GameLocale.text(text)
	l.clip_text = true
	l.position = rect.position
	l.size = rect.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _texture(parent: Node, texture: Texture2D, rect: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.texture = texture
	t.position = rect.position
	t.size = rect.size
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

func _button(parent: Node, text: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = GameLocale.text(text)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("modal_primary",primary)
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", 25)
	GameSkin.style_button(b, primary)
	if not text.is_empty():
		var glass := GameSkin.battle_glass()
		glass.modulate_color = Color(1.12,1.16,1.12) if primary else Color.WHITE
		b.add_theme_stylebox_override("normal",glass)
		var hover := GameSkin.battle_glass()
		hover.modulate_color = Color(1.3,1.45,1.35)
		b.add_theme_stylebox_override("hover",hover)
		b.add_theme_color_override("font_color",Color("e6f5f0"))
	b.pressed.connect(func() -> void:
		AudioService.play_sfx("select", -4.0)
		action.call())
	parent.add_child(b)
	return b

func handle_escape() -> void:
	AudioService.play_sfx("ui_back",-5.0)
	if leave_confirmation != null and leave_confirmation.visible:
		leave_confirmation.hide()
	elif paused_settings != null and paused_settings.visible:
		paused_settings.hide()
	else:
		battle._toggle_pause()

func _bar(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.position = rect.position
	p.size = rect.size
	p.show_percentage = false
	p.max_value = 1.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("fill", GameSkin.bar(color))
	parent.add_child(p)
	p.size = rect.size
	return p

func _build_top() -> void:
	var left := _panel(normal, Rect2(26, 22, 445, 126), GameSkin.GOLD)
	_texture(left, GameSkin.crest(), Rect2(20, 16, 72, 85))
	stage_label = _label(left, "", Rect2(112, 11, 310, 40), 29)
	location_label = _label(left, "", Rect2(113, 50, 310, 27), 21, GameSkin.MUTED)
	defense = _label(left, "", Rect2(112, 83, 310, 33), 23, GameSkin.BLUE)
	var center := _panel(normal, Rect2(680, 22, 560, 110))
	center.name = "WavePanel"
	waves = _label(center, "", Rect2(20, 8, 520, 40), 30)
	waves.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview = _label(center, "", Rect2(20, 51, 520, 30), 22, GameSkin.MUTED)
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_marks = HBoxContainer.new()
	wave_marks.position = Vector2(200, 88)
	wave_marks.add_theme_constant_override("separation", 8)
	center.add_child(wave_marks)
	for i: int in range(battle.session.stage.total_wave_count()):
		var mark := ColorRect.new()
		mark.custom_minimum_size = Vector2(22, 3)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wave_marks.add_child(mark)
	var ap := _panel(normal, Rect2(1390, 22, 330, 110), GameSkin.BLUE)
	ap.name = "APPanel"
	_texture(ap, ArtRegistry.icon("icon_ap",64), Rect2(20, 15, 42, 42))
	ap_label = _label(ap, "", Rect2(75, 9, 235, 49), 32, GameSkin.BLUE)
	ap_bar = _bar(ap, Rect2(23, 67, 285, 7), GameSkin.BLUE)
	ap_rate = _label(ap, "", Rect2(23, 79, 285, 27), 18, GameSkin.MUTED)
	pause_button = _button(normal, "Ⅱ  暂停", Rect2(1775, 22, 120, 60), func() -> void: battle._toggle_pause())
	pause_button.tooltip_text = GameLocale.text("暂停战斗 · Space\n查看操作说明、调整音量或退出本次调查。")

func _build_cards() -> void:
	for i: int in range(battle._roster.size()):
		var cid := str(battle._roster[i])
		var cfg: Dictionary = battle.session.stage._character_configs.get(cid, {})
		var role: Color = battle._role_color_of_text(str(cfg.get("behavior", "FRONTLINE")))
		var b := _button(normal, "", Rect2(), func() -> void: battle._toggle_card_selection(cid))
		b.clip_contents = true
		b.tooltip_text = GameLocale.text("%s · %s\n部署消耗 %d AP\n点击已部署角色卡可查看技能与撤退。" % [str(cfg.get("name", "")), battle._role_label(str(cfg.get("behavior", ""))), int(cfg.get("deployCost",0))])
		var image := _texture(b, ArtRegistry.character_portrait(cid,256), Rect2(8, 8, 194, 145))
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var strip := ColorRect.new()
		strip.color = Color(0.02,0.035,0.08,0.92)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(strip)
		var key := _label(b, str(i+1), Rect2(12,10,34,38), 23)
		var key_style := GameSkin.panel(Color("14213a"),Color("52678e"))
		key_style.set_content_margin_all(0)
		key_style.set_corner_radius_all(5)
		key_style.shadow_size = 0
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_stylebox_override("normal", key_style)
		var cost_badge := _panel(b, Rect2(118,10,82,40), GameSkin.BLUE)
		var cost_style := GameSkin.panel(Color("0c1930"),Color("52678e"))
		cost_style.set_content_margin_all(0)
		cost_style.set_corner_radius_all(5)
		cost_style.shadow_size = 0
		cost_badge.add_theme_stylebox_override("panel",cost_style)
		_texture(cost_badge,ArtRegistry.icon("icon_ap",64),Rect2(7,8,24,24))
		var cost := _label(cost_badge, "", Rect2(31,0,43,40), 27, GameSkin.BLUE)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var name_label := _label(b, str(cfg.get("name","")), Rect2(12,154,186,35), 26)
		var status := _label(b, "", Rect2(12,188,186,30), 21, role)
		var hp := _bar(b, Rect2(10,224,190,5), GameSkin.GREEN)
		var cd := _bar(b, Rect2(10,233,190,4), GameSkin.GOLD)
		cards.append({"id":cid,"button":b,"image":image,"strip":strip,"cost":cost,"cost_badge":cost_badge,"name":name_label,"status":status,"hp":hp,"cd":cd,"role":role,"key":key})

func _build_selected() -> void:
	selected = _panel(normal, Rect2(1346,746,550,310), GameSkin.GOLD)
	selected.mouse_filter = Control.MOUSE_FILTER_STOP
	selected_portrait = _texture(selected,null,Rect2(20,20,92,92))
	selected_name = _label(selected,"",Rect2(132,18,390,40),30)
	selected_stats = _label(selected,"",Rect2(132,59,390,36),22,GameSkin.MUTED)
	selected_hp = _bar(selected,Rect2(132,106,390,8),GameSkin.GREEN)
	selected_skill = _label(selected,"",Rect2(20,135,510,80),24,GameSkin.BLUE)
	selected_skill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_button = _button(normal,"释放技能  Q",Rect2(),func() -> void: battle._request_skill_selected(),true)
	retreat_button = _button(normal,"撤退  R",Rect2(),func() -> void: battle._request_retreat_selected())
	retreat_button.tooltip_text = GameLocale.text("撤退会返还部分部署费用，角色进入再部署冷却。")

func _build_pause() -> void:
	pause_layer = Control.new()
	pause_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(pause_layer)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.015,0.025,0.065,0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.add_child(dim)
	pause_panel = _panel(pause_layer, Rect2(585,185,750,710),GameSkin.GOLD)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_texture(pause_panel,GameSkin.crest(),Rect2(325,24,100,110))
	var title := _label(pause_panel,"时间暂歇",Rect2(35,145,680,65),42)
	title.add_theme_font_override("font",GameSkin.serif())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label(pause_panel,"角色、残响与技能冷却均已暂停",Rect2(35,214,680,40),24,GameSkin.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(pause_panel,"继续调查   Space",Rect2(105,280,540,66),func() -> void: battle._toggle_pause(),true)
	var retry := _button(pause_panel,"重试本次调查",Rect2(105,360,540,66),func() -> void: battle._restart_investigation())
	retry.name = "RetryInvestigation"
	retry.tooltip_text = GameLocale.text("使用当前阵容从本关开头重新开始；本次未结算奖励不发放。")
	_button(pause_panel,"操作说明与音量",Rect2(105,440,540,66),_show_pause_settings)
	_button(pause_panel,"结束本次调查",Rect2(105,520,540,66),_confirm_leave)
	menu_status = _label(pause_panel,"本次尚未结算的奖励不会发放。",Rect2(80,605,590,60),23,GameSkin.MUTED)
	menu_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_layer.hide()

func _show_pause_settings() -> void:
	if paused_settings != null:
		paused_settings.show()
		return
	paused_settings = _panel(pause_layer,Rect2(390,160,1140,760),GameSkin.BLUE)
	paused_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	_label(paused_settings,"调查手册",Rect2(45,30,1050,65),40,GameSkin.GOLD)
	var instructions := _label(paused_settings,"1 / 2  选择角色卡 · 点击地面部署\n点击在场角色或角色卡 · Q 释放技能 · R 撤退\n右键 / Esc 取消选择 · Space 暂停 / 继续\n技能范围、部署费用与冷却均可悬停查看。",Rect2(45,120,1050,190),27)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i: int in range(3):
		var bus: String = ["Master","BGM","SFX"][i]
		_label(paused_settings,["总音量","音乐","音效"][i],Rect2(45,350+i*85,210,50),27)
		var slider := HSlider.new()
		slider.position = Vector2(260,365+i*85)
		slider.size = Vector2(650,40)
		slider.min_value = 0
		slider.max_value = 100
		slider.value = AudioService.get_volume(bus)
		var value := _label(paused_settings,"%d%%" % int(slider.value),Rect2(950,350+i*85,150,50),27,GameSkin.BLUE)
		slider.value_changed.connect(func(v: float) -> void:
			AudioService.set_volume(bus,v)
			value.text = GameLocale.text("%d%%" % int(v)))
		paused_settings.add_child(slider)
	_button(paused_settings,"保存并返回",Rect2(670,655,410,70),func() -> void:
		var config := ConfigFile.new()
		config.load(SaveService.SETTINGS_PATH)
		for bus: String in ["Master","BGM","SFX"]:
			config.set_value("audio",bus,AudioService.get_volume(bus))
		if config.save(SaveService.SETTINGS_PATH) == OK:
			paused_settings.hide()
		else:
			menu_status.text = GameLocale.text("音量已生效，但设置未能保存。"))

func _confirm_leave() -> void:
	if leave_confirmation != null:
		leave_confirmation.show()
		return
	leave_confirmation = _panel(pause_layer,Rect2(460,330,1000,420),GameSkin.GOLD)
	leave_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	_label(leave_confirmation,"离开当前调查？",Rect2(45,35,910,60),38)
	var note := _label(leave_confirmation,"角色培养和已领取的奖励会保留。\n本次未结算的战斗进度与奖励不会保存。",Rect2(45,120,910,120),28,GameSkin.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(leave_confirmation,"继续调查",Rect2(45,300,400,75),func() -> void: leave_confirmation.hide(),true)
	_button(leave_confirmation,"返回校园",Rect2(535,300,420,75),func() -> void:
		AudioService.stop_music()
		SceneRouter.go_to("home" if bool(CampaignFlow.state().get("campaign_active",false)) else "title"))

func _process(delta: float) -> void:
	if battle == null or battle.session == null:
		return
	var s: StageRuntime = battle.session.stage
	var factor: float = maxf(0.01,battle._render_scale)
	var vp: Vector2 = battle._viewport_size / factor
	canvas.scale = Vector2.ONE * factor
	canvas.size = vp
	overlays.sync(vp,factor)
	var modal: bool = battle._upgrade_panel_active() or battle.session.is_decided()
	normal.visible = not modal and not battle.session.is_paused()
	pause_layer.visible = not modal and battle.session.is_paused()
	var focus_scope: Control = null
	if pause_layer.visible:
		focus_scope = leave_confirmation if is_instance_valid(leave_confirmation) and leave_confirmation.visible else (paused_settings if is_instance_valid(paused_settings) and paused_settings.visible else pause_panel)
	elif is_instance_valid(overlays.layer):
		focus_scope = overlays.layer
	if focus_scope != _focus_scope:
		_focus_scope = focus_scope
		if is_instance_valid(focus_scope): GameSkin.focus_modal(focus_scope)
	(pause_layer.get_node("Dim") as ColorRect).size = vp
	pause_panel.position = (vp-pause_panel.size)*0.5
	if not pause_layer.visible:
		if paused_settings != null: paused_settings.hide()
		if leave_confirmation != null: leave_confirmation.hide()
	if not normal.visible:
		return
	var cfg: Dictionary = battle._stage_config_for_rewards
	stage_label.text = GameLocale.text("%s  %s" % [s.stage_id,str(cfg.get("stageName",""))])
	stage_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	location_label.text = GameLocale.text(str({"1-1":"教学楼 · 初次锚定","1-2":"教学楼 · 楼梯平台","1-3":"教学楼 · 测验教室","1-4":"教学楼 · 异常走廊","1-5":"旧体育馆 · 残响汇聚","1-6":"保健室 · 不熄的灯","1-7":"成绩榜 · 比较的回声","1-8":"实验楼 · 无声频率","1-9":"旧档案室 · 空白姓名","1-10":"体育馆 · 核心残响"}.get(s.stage_id,"教学楼")))
	var danger := s.core_hp <= 1
	defense.text = GameLocale.text("防线  " + "◆ ".repeat(s.core_hp) + "◇ ".repeat(maxi(0,s.core_hp_max-s.core_hp)) + "  %d / %d" % [s.core_hp,s.core_hp_max])
	defense.add_theme_color_override("font_color",GameSkin.RED if danger else GameSkin.BLUE)
	var center := normal.get_node("WavePanel") as Control
	center.position.x = (vp.x-center.size.x)*0.5
	waves.text = GameLocale.text("WAVE  %02d / %02d" % [s.display_wave_number(),s.total_wave_count()])
	var boss := s.chapter_boss()
	boss_hp.visible = boss != null
	if boss != null:
		waves.text = GameLocale.text("BOSS · 无名优等生  /  阶段 %d" % int(s.boss_state.get("phase",1)))
		waves.add_theme_font_size_override("font_size",27)
		waves.add_theme_color_override("font_color",GameSkin.GOLD)
		boss_hp.position.x = (vp.x-540)*.5
		boss_hp.tooltip_text = GameLocale.text("无名优等生 · 三阶段核心残响")
		boss_hp.value = float(boss.hp)/maxf(1,boss.hp_max)
	var next := s.incoming_wave_preview()
	preview.text = GameLocale.text("最终波 · 清除全部残响体" if next.is_empty() else "下一波 %02d · %s" % [int(next["number"]),battle._lanes_text(next["lanes"])])
	if boss != null:
		preview.text = GameLocale.text("%d / %d HP" % [boss.hp,boss.hp_max])
		if not s.boss_events.is_empty() and s.elapsed_seconds-float(s.boss_events.back().at)<4:
			preview.text = GameLocale.text(str(s.boss_events.back().name))
	for i: int in range(wave_marks.get_child_count()):
		(wave_marks.get_child(i) as ColorRect).color = GameSkin.GOLD if i<s.display_wave_number() else Color("354465")
	var ap := normal.get_node("APPanel") as Control
	ap.position.x = vp.x-510
	ap_label.text = GameLocale.text("%d / %d  AP" % [s.ap,s.ap_max])
	ap_rate.text = GameLocale.text("部署能量已充满" if s.ap == s.ap_max else "自动回复  +%.1f / 秒" % (s.ap_regen_per_second*s._ap_regen_mult()))
	ap_bar.value = lerpf(ap_bar.value,float(s.ap)/maxf(1,s.ap_max),minf(1,delta*10))
	pause_button.position = battle._pause_rect.position/factor
	pause_button.size = battle._pause_rect.size/factor
	for i: int in range(cards.size()):
		_update_card(cards[i],i,factor)
	_update_selected(factor,vp)
	_sync_tutorials()
	var feedback: bool = battle._feedback_timer > 0 and not battle._feedback_text.is_empty()
	if feedback != _feedback_active:
		_feedback_active = feedback
		hint.add_theme_stylebox_override("normal",_hint_style())
	hint.text = GameLocale.text(battle._feedback_text if feedback else _context_hint(s))
	var measured := hint.get_theme_font("font").get_string_size(GameLocale.text(hint.text),HORIZONTAL_ALIGNMENT_LEFT,-1,24).x
	var hint_width := clampf(measured+64,400,760)
	var hint_height := 98.0 if measured > 696 else 68.0
	hint.position = Vector2((vp.x-hint_width)*0.5,vp.y-hint_height-28)
	if cards.size()>3:
		hint.position = Vector2((vp.x-hint_width)*.5,166)
	hint.size = Vector2(hint_width,hint_height)
	hint.add_theme_color_override("font_color",battle._feedback_color if feedback else Color("d8eee9"))
	hint.modulate.a = clampf(battle._feedback_timer/0.3,0,1) if feedback else 1.0
	hint.visible = feedback or battle._selected_character_id == 0


func _hint_style() -> StyleBoxTexture:
	var style := GameSkin.battle_glass()
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _sync_tutorials() -> void:
	# Present the newest observation only: simultaneous cards must not cover the lanes.
	var source: Array = []
	if not battle._tutorial_cards.is_empty():
		source.append(battle._tutorial_cards.back())
	while tutorial_views.size() < source.size():
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(500, 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override("panel", GameSkin.battle_glass())
		tutorial_stack.add_child(box)
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override("separation", 7)
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lines)
		var caption := Label.new()
		caption.add_theme_font_size_override("font_size", 23)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(caption)
		var body := Label.new()
		body.custom_minimum_size.x = 464
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 26)
		body.add_theme_color_override("font_color",Color("e4f4ef"))
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(body)
		tutorial_views.append({"box":box,"caption":caption,"body":body})
	for i: int in range(tutorial_views.size()):
		var view: Dictionary = tutorial_views[i]
		(view.box as Control).visible = i < source.size()
		if i >= source.size(): continue
		var entry: Dictionary = source[i]
		var enemy := not str(entry.get("enemyId", "")).is_empty()
		(view.caption as Label).text = GameLocale.text("威胁识别  /  " + str(entry.get("title", "")) if enemy else "观测提示  /  FIELD GUIDE")
		(view.caption as Label).add_theme_color_override("font_color",GameSkin.RED if enemy else GameSkin.GREEN)
		(view.body as Label).text = GameLocale.text(str(entry.get("text", "")))
		var age: float = battle._now() - float(entry.get("at", 0))
		(view.box as Control).modulate.a = minf(clampf(age / 0.18,0,1),clampf((battle.TUTORIAL_CARD_LIFETIME-age)/0.65,0,1))

func _context_hint(s: StageRuntime) -> String:
	if battle._device_select_owner != 0:
		return "选择空站位放置实验装置 · 右键取消"
	if not battle._selected_card_id.is_empty():
		return "点击发光站位部署 · 右键取消"
	var deployed := false
	for card: Dictionary in cards:
		var unit := s.get_character_by_id(str(card.id))
		if unit != null:
			deployed = true
			if unit.skill_ready():
				return "%s技能就绪 · 选择角色后按 Q" % unit.display_name
	return "点击在场角色查看技能 · R 撤退换位" if deployed else "选择角色卡 · 点击地面部署"

func _update_card(card: Dictionary, index: int, factor: float) -> void:
	var b: Button = card.button
	var rect: Rect2 = battle._card_rects[index]
	b.position = rect.position/factor
	b.size = rect.size/factor
	var width := b.size.x
	(card.image as Control).size = Vector2(width-16,145)
	(card.strip as Control).position = Vector2(6,150)
	(card.strip as Control).size = Vector2(width-12,90)
	(card.cost_badge as Control).position.x = width-92
	(card.hp as Control).size.x = width-20
	(card.cd as Control).size.x = width-20
	var cid := str(card.id)
	var s: StageRuntime = battle.session.stage
	var cfg: Dictionary = s._character_configs.get(cid,{})
	var unit := s.get_character_by_id(cid)
	var cooldown: float = battle.session.get_redeploy_remaining(cid)
	var cost := s.deployment_cost(cid)
	if unit != null and unit.paid_deploy_cost >= 0: cost = unit.paid_deploy_cost
	var role_name: String = {"amamiya_mio":"前线","kamiya_yuma":"远程","ogawa_yui":"治疗","fujiwara_rin":"资源辅助","minase_sara":"科研","shiraishi_chinatsu":"节奏支援"}.get(cid,battle._role_label(str(cfg.get("behavior",""))))
	(card.cost as Label).text = GameLocale.text(str(cost))
	var active: bool = battle._selected_card_id == cid or (unit != null and battle._selected_character_id == unit.instance_id)
	var edge: Color = GameSkin.BLUE if active else (GameSkin.GOLD if unit != null and unit.skill_ready() else Color("52678e"))
	var signature := str(active) + edge.to_html()
	if str(card.get("style_signature", "")) != signature:
		card.style_signature = signature
		b.add_theme_stylebox_override("normal",GameSkin.panel(Color("182842") if active else Color("101d34"),edge,active))
	(card.image as TextureRect).modulate = Color(0.65,0.68,0.8) if cooldown>0 else Color.WHITE
	var status: Label = card.status
	var low_hp := unit != null and unit.hp_ratio() <= 0.25
	if bool(card.get("low_hp",false)) != low_hp:
		card.low_hp = low_hp
		(card.hp as ProgressBar).add_theme_stylebox_override("fill",GameSkin.bar(GameSkin.RED if low_hp else GameSkin.GREEN))
	if unit != null:
		var range_text := "普攻同路前方 %.2f 格 · 阻挡 %d" % [unit.attack_range_tiles,unit.block_count_max]
		if cid == "fujiwara_rin":
			range_text = "全队AP回复 +15% · 无普通攻击、无阻挡"
		if unit.allow_cross_lane and unit.max_lane_delta > 0:
			range_text = "普攻同路 %.1f 格 / 邻路 %.1f 格 · 阻挡 %d" % [unit.attack_range_tiles,unit.adjacent_lane_range_tiles,unit.block_count_max]
		b.tooltip_text = GameLocale.text("%s · %s\n生命 %d / %d · 点击选中\n%s\nQ 释放技能 · R 撤退换位" % [unit.display_name,role_name,unit.hp,unit.max_hp,range_text])
		status.text = GameLocale.text(("Q 技能就绪" if active else "技能就绪 · 点击") if unit.skill_ready() else ("技能生效中" if unit.skill_active_remaining>0 or unit.skill_charged else "技能 %.0f 秒" % ceilf(unit.skill_cooldown_remaining)))
		status.add_theme_color_override("font_color",GameSkin.GOLD if unit.skill_ready() else card.role)
		(card.hp as ProgressBar).value = unit.hp_ratio()
		var total := maxf(1,float(unit.skill_config.get("cooldownSeconds",1)))
		(card.cd as ProgressBar).value = 1.0-clampf(unit.skill_cooldown_remaining/total,0,1)
	elif cooldown>0:
		b.tooltip_text = GameLocale.text("%s\n再部署剩余 %.1f 秒" % [str(cfg.get("name",cid)),cooldown])
		status.text = GameLocale.text("再部署  %.1f 秒" % cooldown)
		status.add_theme_color_override("font_color",GameSkin.MUTED)
		(card.hp as ProgressBar).value = 0
		(card.cd as ProgressBar).value = 0
	elif cost>s.ap:
		b.tooltip_text = GameLocale.text("%s · 部署需要 %d AP\n当前 %d AP，能量恢复后即可部署。" % [str(cfg.get("name",cid)),cost,s.ap])
		var regen := s.ap_regen_per_second*s._ap_regen_mult()
		status.text = GameLocale.text("等待 %.0f 秒" % ceilf(float(cost-s.ap)/regen) if regen>0 else "AP 不足")
		status.add_theme_color_override("font_color",GameSkin.MUTED)
		(card.hp as ProgressBar).value = 1
		(card.cd as ProgressBar).value = 0
	else:
		b.tooltip_text = GameLocale.text("%s · %s\n部署消耗 %d AP\n点击后选择地面发光站位。" % [str(cfg.get("name",cid)),role_name,cost])
		status.text = GameLocale.text("选择站位" if battle._selected_card_id == cid else "可部署 · " + role_name)
		status.add_theme_color_override("font_color",card.role)
		(card.hp as ProgressBar).value = 1
		(card.cd as ProgressBar).value = 0

func _update_selected(factor: float, vp: Vector2) -> void:
	var unit: CharacterRuntime = battle.session.stage.get_character(int(battle._selected_character_id))
	selected.visible = unit != null
	skill_button.visible = unit != null
	retreat_button.visible = unit != null
	if unit == null: return
	selected.position = Vector2(vp.x-574,vp.y-334)
	if unit.character_id == "sara_device":
		selected_portrait.texture = ArtRegistry.frame_at("res://assets/art/ui/sara_device_idle.png",0,4)
		selected_name.text = GameLocale.text("实验装置")
		selected_stats.text = GameLocale.text("耐久  %d / %d" % [unit.hp,unit.max_hp])
		selected_hp.value = unit.hp_ratio()
		var remaining := maxf(0,float(battle.session.stage.device_expiry.get(unit.instance_id,0))-battle._now())
		selected_skill.text = GameLocale.text("临时诱导信标\n剩余 %.1f 秒 · 吸引并阻挡残响" % remaining)
		skill_button.text = GameLocale.text("自动运行")
		skill_button.tooltip_text = GameLocale.text("装置不占角色人数；耐久耗尽、收回或到期后释放站位。")
		skill_button.disabled = true
	else:
		_update_actor_details(unit)
	retreat_button.text = GameLocale.text("收回装置  R" if unit.character_id == "sara_device" else "撤退  R")
	skill_button.position = battle._skill_rect.position/factor
	skill_button.size = battle._skill_rect.size/factor
	retreat_button.position = battle._retreat_rect.position/factor
	retreat_button.size = battle._retreat_rect.size/factor

func _update_actor_details(unit: CharacterRuntime) -> void:
	selected_portrait.texture = ArtRegistry.character_portrait(unit.character_id,256)
	selected_name.text = GameLocale.text(unit.display_name)
	selected_stats.text = GameLocale.text("生命  %d / %d" % [unit.hp,unit.max_hp])
	selected_hp.value = unit.hp_ratio()
	var skill_state := "就绪"
	if unit.skill_charged: skill_state = "贯穿已蓄力 · 可截击相邻路线"
	elif unit.skill_active_remaining>0: skill_state = "生效中 %.1f 秒" % unit.skill_active_remaining
	elif unit.skill_cooldown_remaining>0: skill_state = "冷却 %.1f 秒" % unit.skill_cooldown_remaining
	selected_skill.text = GameLocale.text("%s\n%s" % [unit.skill_config.get("name","主动技能"),skill_state])
	skill_button.tooltip_text = GameLocale.text(str(unit.skill_config.get("description","")))
	skill_button.text = GameLocale.text("释放技能  Q" if unit.skill_ready() else ("贯穿待发" if unit.skill_charged else skill_state))
	skill_button.disabled = not unit.skill_ready()
