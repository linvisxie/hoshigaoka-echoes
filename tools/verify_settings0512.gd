extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.new_game("设置页验收")
	var before := SaveService.snapshot()
	for locale: String in ["zh","en"]:
		GameLocale.set_language(locale)
		SceneRouter.go_to("title")
		await wait_ui()
		await shot("title_"+locale)
		var title := get_tree().current_scene
		title._activate(0)
		title._activate(0)
		check(title._busy,"continue locks repeated activation during feedback")
		check(SceneRouter.get_current_key()=="title","continue leaves time for click animation")
		var visibly_animated := false
		for i: int in range(20):
			if SceneRouter.get_current_key()!="title": break
			if title._rows[0].modulate.a<1.0: visibly_animated = true
			await get_tree().process_frame
		check(visibly_animated,"continue row visibly animates")
		await wait_ui()
		check(SceneRouter.get_current_key()=="home","animated continue reaches campus")
		check(SaveService.snapshot()==before,"continue animation preserves progression")
		SceneRouter.go_to("settings")
		await wait_ui()
		var settings := get_tree().current_scene
		check(settings.rows.get_node("TextSpeed").position.y<settings.rows.get_node("Display").position.y,"text speed precedes display mode")
		check(settings.scroll.size.y==635,"settings viewport has fixed height")
		check(settings.return_key=="home","campus settings remembers campus origin")
		settings.speed_slider.value = 75
		await shot("settings_top_"+locale)
		await wheel(settings.scroll.get_global_rect().get_center(),10)
		check(settings.scroll.scroll_vertical>0,"mouse wheel scrolls card contents")
		var offset: int = settings.scroll.scroll_vertical
		await shot("settings_bottom_"+locale)
		await button(GameLocale.text("鸣谢与许可证"))
		check(SceneRouter.get_current_key()=="credits","credits button opens independent page")
		var credits := get_tree().current_scene
		var back := find_button(credits,GameLocale.text("返回设置"))
		check(back.position.x==70 and back.size.x==430,"credits return aligns with project panel edges")
		for i: int in range(credits.projects.size()):
			credits._select(i)
			for j: int in range(credits.projects[i].files.size()):
				credits.documents.select(j)
				credits._read_document(j)
				var filename: String = credits.projects[i].files[j]
				check(credits.license_text.text==FileAccess.get_file_as_string("res://assets/licenses/"+filename) and not credits.license_text.text.is_empty(),"bundled notice is readable verbatim: "+filename)
			await shot("credits_"+str(i)+"_"+locale)
		credits._select(0)
		credits.documents.select(1)
		credits._read_document(1)
		await wait_ui()
		await wheel(credits.license_text.get_global_rect().get_center(),10)
		check(credits.license_text.get_v_scroll_bar().value>0,"long third-party notice scrolls independently")
		await press(KEY_ESCAPE)
		settings = get_tree().current_scene
		check(SceneRouter.get_current_key()=="settings","credits Escape returns to settings")
		check(settings.scroll.scroll_vertical==offset,"credits return restores exact scroll offset")
		check(settings.speed_slider.value==75,"credits roundtrip preserves changed text speed")
		check(settings.return_key=="home","credits roundtrip preserves campus origin")
		var previous_height: float = settings.scroll.size.y
		for i: int in range(12): settings._row("Future option","Future%d"%i)
		await wait_ui()
		check(settings.scroll.size.y==previous_height,"future settings do not expand card")
		check(settings.rows.get_node("Master").size.y==84,"future settings do not squeeze existing rows")
		await press(KEY_ESCAPE)
		check(SceneRouter.get_current_key()=="home","settings Escape returns to original campus")
	SceneRouter.go_to("title")
	await wait_ui()
	SceneRouter.go_to("settings")
	await wait_ui()
	var settings := get_tree().current_scene
	settings.scroll.scroll_vertical = 999
	await wait_ui()
	await button(GameLocale.text("鸣谢与许可证"))
	await button(GameLocale.text("返回设置"))
	check(get_tree().current_scene.return_key=="title","credits preserves title settings origin")
	await button(GameLocale.text("保存并返回"))
	check(SceneRouter.get_current_key()=="title","save returns to title after credits")
	check(SaveService.snapshot()==before,"settings and credits never change save progression")
	var file := FileAccess.open("user://settings_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"checks":checks,"type":"source rendered viewport with synthetic input; isolated save; future rows are test-only"},"\t"))
	if checks.all(func(c:Dictionary)->bool:return c.ok): App.request_quit()
	else: get_tree().quit(1)

func wheel(position: Vector2,count: int) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	get_viewport().push_input(motion,true)
	for i: int in range(count):
		for pressed: bool in [true,false]:
			var event := InputEventMouseButton.new()
			event.position = position
			event.button_index = MOUSE_BUTTON_WHEEL_DOWN
			event.pressed = pressed
			get_viewport().push_input(event,true)
		await get_tree().process_frame
	await wait_ui()

func press(keycode: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await wait_ui()
