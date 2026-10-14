extends CampusScreen

var status: Label
var return_key := "title"
var speed_slider: HSlider
var scroll: ScrollContainer
var rows: VBoxContainer
var display: Button

func _ready() -> void:
	super._ready()
	var origin := SceneRouter.entry_origin()
	if origin not in ["settings","credits"]:
		SceneRouter.settings_return_key = "home" if origin=="home" else "title"
		SceneRouter.settings_scroll = 0
	return_key = SceneRouter.settings_return_key
	set_background("bg_title_gate")
	page_heading("设置", "音量、显示与语言  /  修改后立即生效")
	panel(Rect2(300,205,1320,745))
	scroll = ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.position = Vector2(340,245)
	scroll.size = Vector2(1240,635)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "SettingRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",26)
	scroll.add_child(rows)
	for bus: String in ["Master","BGM","SFX"]:
		var row := _row({"Master":"总音量","BGM":"音乐","SFX":"音效"}[bus],bus)
		var slider := _slider(row,0,100,1,AudioService.get_volume(bus))
		var value := _value(row,"%d%%" % int(slider.value))
		slider.value_changed.connect(func(amount: float) -> void:
			AudioService.set_volume(bus,amount)
			value.text = "%d%%" % int(amount))
	var saved := ConfigFile.new()
	saved.load(SaveService.SETTINGS_PATH)
	var speed_row := _row("文字显示速度","TextSpeed")
	speed_slider = _slider(speed_row,15,90,5,float(saved.get_value("story","text_speed",42.0)))
	var speed := _value(speed_row,GameLocale.text("%.0f 字/秒" % speed_slider.value))
	speed.add_theme_font_size_override("font_size",24)
	speed.add_theme_color_override("font_color",BLUE)
	speed_slider.value_changed.connect(func(amount: float) -> void: speed.text = GameLocale.text("%.0f 字/秒" % amount))
	var display_row := _row("显示模式","Display")
	display = _row_button(display_row,"全屏显示" if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else "窗口显示",_toggle_display)
	display.name = "DisplayMode"
	var language_row := _row("语言","Language")
	_row_button(language_row,"English" if GameLocale.is_english() else "中文",_toggle_language).name = "LanguageButton"
	var credits_row := _row("关于游戏","About")
	_row_button(credits_row,"鸣谢与许可证",_open_credits).name = "CreditsButton"
	status = label_at("设置自动保留 · 滚动卡片查看更多",Rect2(360,902,1180,32),22,MUTED)
	button_at("保存并返回",Rect2(1210,975,410,65),_save,true)
	if return_key=="home": button_at("校园菜单",Rect2(300,975,410,65),func() -> void: _save(true))
	_restore_scroll.call_deferred()
	fade_in_content()

func _row(caption: String,key: String) -> Control:
	var row := Control.new()
	row.name = key
	row.custom_minimum_size = Vector2(1204,84)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	rows.add_child(row)
	var label := label_at(caption,Rect2(20,0,300,84),30,GOLD)
	canvas.remove_child(label)
	row.add_child(label)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row

func _slider(row: Control,minimum: float,maximum: float,step: float,value: float) -> HSlider:
	var slider := HSlider.new()
	slider.position = Vector2(350,17)
	slider.size = Vector2(650,50)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.scrollable = false
	slider.value = value
	row.add_child(slider)
	return slider

func _value(row: Control,text: String) -> Label:
	var label := label_at(text,Rect2(1040,0,150,84),30)
	canvas.remove_child(label)
	row.add_child(label)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _row_button(row: Control,text: String,action: Callable) -> Button:
	var button := button_at(text,Rect2(350,8,650,68),action)
	canvas.remove_child(button)
	row.add_child(button)
	return button

func _restore_scroll() -> void:
	scroll.scroll_vertical = SceneRouter.settings_scroll

func _toggle_display() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	display.text = GameLocale.text("全屏显示" if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else "窗口显示")

func _persist(locale: String) -> bool:
	var config := ConfigFile.new()
	config.load(SaveService.SETTINGS_PATH)
	for bus: String in ["Master","BGM","SFX"]: config.set_value("audio",bus,AudioService.get_volume(bus))
	config.set_value("display","fullscreen",DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.set_value("story","text_speed",speed_slider.value)
	config.set_value("language","locale",locale)
	var err := config.save(SaveService.SETTINGS_PATH)
	if err!=OK:
		status.text = GameLocale.text("设置未能保存，错误 %d" % err)
		return false
	SceneRouter.settings_scroll = scroll.scroll_vertical
	return true

func _save(open_menu: bool = false) -> void:
	if not _persist(GameLocale.language): return
	CampaignFlow.open_campus_menu = open_menu and return_key=="home"
	SceneRouter.go_to(return_key)

func _toggle_language() -> void:
	var desired := "zh" if GameLocale.is_english() else "en"
	if not _persist(desired): return
	GameLocale.set_language(desired)
	SceneRouter.go_to("settings")

func _open_credits() -> void:
	if _persist(GameLocale.language): SceneRouter.go_to("credits")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_save.call_deferred()
