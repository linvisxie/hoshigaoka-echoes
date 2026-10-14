extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.new_game("界面验收")
	for locale: String in ["zh","en"]:
		GameLocale.set_language(locale)
		SceneRouter.go_to("title")
		await wait_ui()
		await shot("title_"+locale)
		for key: String in ["character","equipment","stage_select","archive"]:
			SceneRouter.go_to("home")
			await get_tree().create_timer(.9).timeout
			var home := get_tree().current_scene
			var caption: String = {"character":"角色培养","equipment":"装备背包","stage_select":"关卡记录","archive":"剧情档案"}[key]
			await click(home.art_buttons[caption].get_global_rect().get_center())
			await get_tree().create_timer(.3).timeout
			check(is_instance_valid(SceneRouter._menu_snapshot),"snapshot covers hub to "+key+locale)
			await get_tree().create_timer(.8).timeout
			check(SceneRouter.get_current_key()==key,"hub route reaches "+key+locale)
			check(not is_instance_valid(SceneRouter._menu_snapshot),"snapshot released "+key+locale)
			if key=="stage_select":
				var page: Control = get_tree().current_scene._native_page
				check(page.get_node_or_null("SchoolGatePlaque")!=null,"school plaque present "+locale)
				check(page.get_child(1).name=="SchoolGatePlaque","plaque stays beneath shade and content "+locale)
			await shot(key+"_"+locale)
		SceneRouter.go_to("home")
		await get_tree().create_timer(.9).timeout
		var home := get_tree().current_scene
		home.petals.hide()
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(20,20)
		get_viewport().push_input(motion,true)
		await wait_ui()
		await shot("warm_before_"+locale)
		motion.position = home.art_buttons["观测会活动室"].get_global_rect().get_center()
		get_viewport().push_input(motion,true)
		await get_tree().create_timer(.3).timeout
		check(home.atmosphere.hover_strength>.9,"warm light ramp "+locale)
		await shot("warm_after_"+locale)
		for caption: String in ["保健室","调查卡：继续调查"]:
			motion.position = home.art_buttons[caption].get_global_rect().get_center()
			get_viewport().push_input(motion,true)
			await get_tree().create_timer(.3).timeout
			await shot("hover_"+str(home.art_buttons.keys().find(caption))+"_"+locale)
	var ok := true
	for result: Dictionary in checks: ok = ok and result.ok
	var file := FileAccess.open("user://navigation_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks},"\t"))
	file.close()
	if ok: App.request_quit()
	else: get_tree().quit(1)
