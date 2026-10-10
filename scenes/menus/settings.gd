extends CampusScreen

var status: Label
var return_key := "title"
var speed_slider: HSlider

func _ready() -> void:
	super._ready()
	return_key = "home" if SceneRouter.previous_key() == "home" else "title"
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
	var display := button_at("全屏显示" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "窗口显示", Rect2(690, 640, 650, 75), _toggle_display)
	display.name = "DisplayMode"
	label_at("文字显示速度",Rect2(360,750,300,60),30,GOLD)
	speed_slider = HSlider.new()
	speed_slider.position = Vector2(690,770)
	speed_slider.size = Vector2(650,45)
	speed_slider.min_value = 15
	speed_slider.max_value = 90
	speed_slider.step = 5
	var saved := ConfigFile.new()
	saved.load(SaveService.SETTINGS_PATH)
	speed_slider.value = float(saved.get_value("story","text_speed",42.0))
	var speed := label_at("%.0f 字/秒" % speed_slider.value,Rect2(1380,750,220,60),25,BLUE)
	speed_slider.value_changed.connect(func(v: float) -> void: speed.text = "%.0f 字/秒" % v)
	canvas.add_child(speed_slider)
	status = label_at("设置会保留到下次启动。", Rect2(360, 850, 1100, 45), 25, MUTED)
	button_at("保存并返回", Rect2(1210, 960, 410, 75), _save, true)
	fade_in_content()

func _toggle_display() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	var display := canvas.get_node("DisplayMode") as Button
	display.text = "全屏显示" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "窗口显示"

func _save() -> void:
	var config := ConfigFile.new()
	config.load(SaveService.SETTINGS_PATH)
	for bus: String in ["Master", "BGM", "SFX"]:
		config.set_value("audio", bus, AudioService.get_volume(bus))
	config.set_value("display", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.set_value("story","text_speed",speed_slider.value)
	var err := config.save(SaveService.SETTINGS_PATH)
	if err != OK:
		status.text = "设置未能保存，错误 %d" % err
		return
	SceneRouter.go_to(return_key)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_save()
