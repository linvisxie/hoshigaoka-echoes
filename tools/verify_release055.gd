extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.ensure_loaded()
	App.ensure_growth()
	check(App.growth.get_progress("amamiya_mio").level > 1, "existing earned save has trained characters")
	SceneRouter.go_to("character")
	await wait_ui()
	await shot("old_save_growth")
	await button("装备背包")
	await button("领取全部装备奖励")
	var backpack := get_tree().current_scene
	var selected: String = backpack.selected_id
	check(not selected.is_empty(), "earned equipment selected after claiming")
	if not selected.is_empty():
		check(EquipmentService.dismantle(selected, true).ok, "dismantle selected ordinary equipment")
		SceneRouter.go_to("equipment")
		await wait_ui()
		backpack = get_tree().current_scene
		check(not EquipmentService.find_instance(SaveService.get_current(), backpack.selected_id).is_empty(), "selection recovers after selected item removed")
		await shot("backpack_selection_recovered")
	SceneRouter.go_to("new_game")
	await wait_ui()
	get_tree().current_scene.name_input.text = "新同学"
	await button("开始新学期   →")
	check(SceneRouter.get_current_key() == "new_game", "first click only confirms replacement")
	await shot("new_save_confirmation")
	await button("开始新学期   →")
	check(SceneRouter.get_current_key() == "story", "confirmed new game starts prologue")
	SceneRouter.go_to("character")
	await wait_ui()
	for cid: String in App.growth.all_character_ids():
		var p := App.growth.get_progress(cid)
		check(p.level == 1 and p.exp == 0 and p.breakthrough == 0, "new growth cleared: " + cid)
	check(EquipmentService.all_instances().is_empty(), "new save has empty equipment")
	check(CampaignFlow.next_stage() == "1-1", "new campaign starts first stage")
	check(App.growth.commit() and SaveService.load_game(), "new progress commits and reloads")
	App.ensure_growth()
	check(App.growth.get_progress("amamiya_mio").level == 1, "old growth never returns after reload")
	await shot("new_save_growth")
	await button("装备背包")
	await shot("empty_backpack")
	await button("▸ 饰品")
	await button("▸ 校园纪念物")
	await shot("empty_backpack_expanded")
	var scene := get_tree().current_scene
	var previous := Rect2()
	for label: String in ["▾ 武器", "▾ 饰品", "▾ 校园纪念物"]:
		var b := find_button(scene, label)
		check(b != null, "empty category remains accessible: " + label)
		if b != null:
			check(previous == Rect2() or b.get_global_rect().position.y >= previous.end.y + 10, "category spacing: " + label)
			previous = b.get_global_rect()
	await button("返回角色")
	check(get_tree().current_scene._selected_id == "amamiya_mio", "new save selects default character")
	await shot("new_growth_return")
	var ok := checks.all(func(c: Dictionary) -> bool: return c.ok)
	var file := FileAccess.open("user://release055_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok": ok, "checks": checks}, "\t"))
	file.close()
	if ok: App.request_quit()
	else: get_tree().quit(1)

