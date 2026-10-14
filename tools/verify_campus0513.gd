extends "res://tools/verify_frontend_driver.gd"

func hover(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	get_viewport().push_input(event,true)
	await wait_ui()

func press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event,true)
	await wait_ui()

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.new_game("动效验收")
	var before := SaveService.snapshot()
	for locale: String in ["zh","en"]:
		GameLocale.set_language(locale)
		SceneRouter.go_to("home")
		await wait_ui()
		var home := get_tree().current_scene
		var baseline: Dictionary = {}
		for key: String in home.art_buttons: baseline[key] = home.art_buttons[key].get_global_rect()
		var count: int = home.atmosphere.get_child_count()
		await hover(Vector2(50,40))
		home.petals.hide()
		home.atmosphere.hide()
		await shot("static_reference_"+locale)
		home.atmosphere.show()
		await shot("motion_reference_"+locale)
		home.petals.show()
		await shot("campus_"+locale)
		for key: String in ["弓道场","保健室","与雨宫澪交谈","调查公告板"]:
			await hover(home.art_buttons[key].get_global_rect().get_center())
			check(home.atmosphere.hover_key==key,"hover feedback: "+key+locale)
			await shot("hover_"+str(["弓道场","保健室","与雨宫澪交谈","调查公告板"].find(key))+"_"+locale)
		await hover(Vector2(50,40))
		for i: int in range(12):
			await get_tree().create_timer(.08).timeout
			await shot("motion_"+str(i)+"_"+locale)
		for key: String in home.art_buttons:
			check(home.art_buttons[key].get_global_rect()==baseline[key],"fixed click rectangle: "+key+locale)
		check(home.atmosphere.get_child_count()==count,"no growing ambient node count"+locale)
		check(home.art_buttons["与雨宫澪交谈"].tooltip_text.is_empty(),"no character tooltip box"+locale)
		# Real native Control events; repeated clicks produce one delayed action.
		var place: Button = home.art_buttons["弓道场"]
		await click(place.get_global_rect().get_center())
		await click(place.get_global_rect().get_center())
		await wait_ui()
		check(home._has_campus_modal(),"location modal opens once"+locale)
		check(home.atmosphere.blocked,"modal blocks behind-panel hover"+locale)
		await shot("location_"+locale)
		await press_escape()
		check(not home._has_campus_modal(),"Escape closes location"+locale)
		# Escape while the click transition is pending cancels that stale action.
		await click(home.art_buttons["设置"].get_global_rect().get_center())
		await press_escape()
		check(SceneRouter.get_current_key()=="home","Escape cancels pending settings navigation"+locale)
		check(home._has_campus_modal(),"Escape opens campus menu during pending action"+locale)
		await press_escape()
		await button("与雨宫澪交谈")
		check(home._has_campus_modal(),"Mio response opens location"+locale)
		await press_escape()
		await button("调查公告板")
		check(not home.investigation.visible,"board collapses"+locale)
		await button("调查公告板")
		check(home.investigation.visible and home.investigation.modulate.a>.99,"card fade restores fully"+locale)
		check(SaveService.snapshot()==before,"all ambient interactions preserve save"+locale)
		await shot("campus_final_"+locale)
	var ok := true
	for result: Dictionary in checks: ok = ok and result.ok
	var report := {"ok":ok,"checks":checks,"viewport":get_viewport().get_visible_rect().size,"type":"Source rendered viewport and synthetic native Control input"}
	var file := FileAccess.open("user://campus_motion_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	get_tree().quit(0 if ok else 1)
