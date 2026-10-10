## Real Windows viewport and UI mouse events, seeded only from an earlier
## isolated normal five-stage playthrough. Never edits player stats or grants loot.
extends Node

var checks: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func wait_ui() -> void:
	await get_tree().create_timer(0.7).timeout

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://frontend_shots")
	get_viewport().get_texture().get_image().save_png("user://frontend_shots/" + label + ".png")

func check(ok: bool, name: String) -> void:
	checks.append({"ok": ok, "name": name})
	GameLog.info("FrontendEvidence", "%s: %s" % [name, ok])

func click(pos: Vector2) -> void:
	var canvas_size := get_viewport().get_visible_rect().size
	var window_size := Vector2(get_window().size)
	pos = Vector2(pos.x * window_size.x / canvas_size.x, pos.y * window_size.y / canvas_size.y)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = pos
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child: Node in node.get_children():
		var found := find_button(child, text)
		if found != null:
			return found
	return null

func button(text: String) -> void:
	var found := find_button(get_tree().current_scene, text)
	check(found != null, "button exists: " + text)
	if found != null:
		await click(found.get_global_rect().get_center())
	await wait_ui()

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	check(CampaignFlow.next_stage().is_empty(), "seed is completed normal five-stage save")
	CampaignFlow.resume()
	await wait_ui()
	await shot("campus")
	await button("角色培养 · 装备")
	await shot("character")
	var character := get_tree().current_scene
	var before := int(App.growth.get_progress("amamiya_mio").level)
	for spec: Dictionary in character._btn_rects:
		if spec.action == "preview" and int(spec.get("arg", 0)) == 1:
			await click((spec.rect as Rect2).get_center())
			break
	await wait_ui()
	for spec: Dictionary in character._btn_rects:
		if spec.action == "levelup":
			await click((spec.rect as Rect2).get_center())
			break
	await wait_ui()
	check(App.growth.get_progress("amamiya_mio").level > before, "real growth input consumes earned study record")
	await shot("growth_after")
	await button("技能与天赋")
	check(SceneRouter.get_current_key() == "character_details", "character details reachable")
	await shot("character_details")
	await button("返回培养")
	await button("装备背包")
	await button("领取全部装备奖励")
	check(EquipmentService.instance_count() >= 1, "earned 1-2 weapon fulfilled")
	await shot("equipment_claimed")
	var base := int(App.level_stats_table()["kamiya_yuma"].attack)
	await button("装备给神谷悠真")
	check(int(App.level_stats_table()["kamiya_yuma"].attack) > base, "equipment adds actual combat attack")
	await button("强化 +1")
	check(int(EquipmentService.all_instances()[0].enhanceLevel) == 1, "equipment enhancement saved")
	await shot("equipment_enhanced")
	await button("卸下")
	check(int(App.level_stats_table()["kamiya_yuma"].attack) == base, "unequip restores base attack")
	await button("装备给神谷悠真")
	check(SaveService.load_game(), "reload after equipment mutation")
	check(int(App.level_stats_table()["kamiya_yuma"].attack) > base, "gear combat bonus survives reload")
	var char_cfg := DataRegistry.get_entry("characters", "kamiya_yuma")
	var runtime := CharacterRuntime.from_config(char_cfg, 1, 1, 1, App.level_stats_table()["kamiya_yuma"])
	check(runtime.effective_attack_interval() < runtime.attack_interval, "equipment attack-speed affix affects combat interval")
	await button("返回校园")
	await button("设置")
	await shot("settings")
	await button("保存并返回")
	check(FileAccess.file_exists(SaveService.SETTINGS_PATH), "settings file persisted")
	await button("剧情档案")
	await shot("archive")
	var archive := get_tree().current_scene
	var target: Button
	for child: Node in archive.canvas.get_children():
		if child is Button and child.text != "返回校园":
			target = child
			break
	var before_replay := SaveService.snapshot()
	if target != null:
		await click(target.get_global_rect().get_center())
		await wait_ui()
		var story := get_tree().current_scene
		check(story.replay, "archive launches replay mode")
		story.dialogue.visible_ratio = 1
		story.advance()
		await wait_ui()
		await shot("archive_replay")
		check(SaveService.get_current() == before_replay, "archive replay does not mutate progress or rewards")
	var report := {"type": "real Windows viewport; automated UI mouse input, not human play", "checks": checks, "save": SaveService.snapshot(), "audio": AudioService.playback_status()}
	var file := FileAccess.open("user://frontend_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if checks.all(func(item: Dictionary) -> bool: return item.ok) else 2)
