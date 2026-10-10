extends CampusScreen

var status: Label

func _ready() -> void:
	super._ready()
	set_background("bg_title_gate")
	page_heading("设置", "音量与显示  /  修改后立即生效")
	panel(Rect2(300, 230, 1320, 680))
	for i: int in range(3):
		var bus: String = ["Master", "BGM", "SFX"][i]
		label_at(["总音量", "音乐", "音效"][i], Rect2(360, 290 + 110 * i, 270, 70), 30, GOLD)
		var slider := HSlider.new()
		slider.position = Vector2(690, 305 + 110 * i)
		slider.size = Vector2(650, 50)
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = AudioService.get_volume(bus)
		var value := label_at("%d%%" % int(slider.value), Rect2(1410, 290 + 110 * i, 150, 70), 30)
		slider.value_changed.connect(func(amount: float) -> void:
			AudioService.set_volume(bus, amount)
			value.text = "%d%%" % int(amount))
		canvas.add_child(slider)
	label_at("显示模式", Rect2(360, 650, 270, 65), 30, GOLD)
	button_at("窗口 / 全屏", Rect2(690, 640, 650, 75), func() -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN))
	status = label_at("", Rect2(360, 790, 1100, 60), 25, MUTED)
	button_at("保存并返回", Rect2(1210, 960, 410, 75), _save, true)

func _save() -> void:
	var config := ConfigFile.new()
	for bus: String in ["Master", "BGM", "SFX"]:
		config.set_value("audio", bus, AudioService.get_volume(bus))
	config.set_value("display", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	var err := config.save(SaveService.SETTINGS_PATH)
	if err != OK:
		status.text = "设置未能保存，错误 %d" % err
		return
	SceneRouter.go_to("home" if not SaveService.get_current().is_empty() else "title")
