extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.new_game("语言验收")
	GameLocale.set_language("zh")
	SceneRouter.go_to("home")
	await wait_ui()
	SceneRouter.go_to("settings")
	await wait_ui()
	await button("中文")
	check(GameLocale.is_english(),"setting switches to English immediately")
	check(get_tree().current_scene.return_key=="home","language rebuild preserves campus return source")
	await shot("settings_en")
	await button("Save & Return")
	check(SceneRouter.get_current_key()=="home","English save returns to campus")
	await shot("campus_en")
	_scan(get_tree().current_scene)
	var before := SaveService.snapshot()
	for key: String in ["character","character_details","character_equipment","equipment","archive","stage_select","title","new_game"]:
		SceneRouter.go_to(key)
		await wait_ui()
		_scan(get_tree().current_scene)
		if key=="character":
			for chip: Dictionary in get_tree().current_scene._resource_chips:
				check(chip.rect.end.x<=get_viewport().get_visible_rect().size.x,"resource chip fits viewport: "+str(chip.id))
		await shot(key+"_en")
	check(SaveService.snapshot()==before,"English menu navigation preserves save")
	CampaignFlow.start_new("保留中文玩家名")
	await wait_ui()
	var story := get_tree().current_scene
	check(story.dialogue.text.begins_with("On your first day"),"prologue displays English dialogue")
	check(story.speaker.text=="Observation Record","narrator fallback is translated")
	story.dialogue.visible_ratio = 1
	await shot("story_en")
	story.advance()
	check(story.speaker.text=="保留中文玩家名","user name is preserved verbatim")
	for i: int in range(100):
		if SceneRouter.get_current_key()!="story": break
		get_tree().current_scene.dialogue.visible_ratio = 1
		get_tree().current_scene.advance()
		await get_tree().process_frame
	await wait_ui()
	_scan(get_tree().current_scene)
	await shot("briefing_en")
	await button("Start Battle   →")
	var battle := get_tree().current_scene
	await wait_ui()
	_scan(battle)
	await shot("battle_en")
	battle._toggle_pause()
	await wait_ui()
	_scan(battle)
	await shot("pause_en")
	var config := ConfigFile.new()
	config.load(SaveService.SETTINGS_PATH)
	check(str(config.get_value("language","locale",""))=="en","English preference persisted independently of new-game save")
	SceneRouter.go_to("home")
	await wait_ui()
	SceneRouter.go_to("settings")
	await wait_ui()
	await button("English")
	check(GameLocale.language=="zh","setting switches back to Chinese immediately")
	await shot("settings_zh")
	await button("保存并返回")
	await shot("campus_zh")
	# Earned-save fixture: no synthetic currency, levels or unlocks.
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--seed-save="): continue
		var seed := FileAccess.get_file_as_string(arg.trim_prefix("--seed-save="))
		var target := FileAccess.open(SaveService.SAVE_PATH,FileAccess.WRITE)
		target.store_string(seed)
		target.close()
		check(SaveService.load_game(),"load prior earned-save copy for full content checks")
		GameLocale.set_language("en")
		var earned := SaveService.snapshot()
		for cid: String in DataRegistry.get_ids("characters"):
			CampaignFlow.inspected_character_id = cid
			SceneRouter.go_to("character_details")
			await wait_ui()
			_scan(get_tree().current_scene)
			await shot("skills_"+cid)
		SceneRouter.go_to("equipment")
		await wait_ui()
		await button("Claim All Equipment Rewards")
		_scan(get_tree().current_scene)
		await shot("equipment_claimed_en")
		for sid: String in DataRegistry.get_ids("story"):
			CampaignFlow.replay_story_id = sid
			SceneRouter.go_to("story")
			await get_tree().create_timer(.1).timeout
			var view := get_tree().current_scene
			for i: int in range(view.nodes.size()):
				view.index = i
				view._show_node()
				view.dialogue.visible_ratio = 1
				await get_tree().process_frame
				check(view.dialogue.get_content_height()<=view.dialogue.size.y,"dialogue fits: "+sid+"/"+str(i))
			await shot("story_last_"+sid)
		CampaignFlow.replay_story_id = ""
		check(SaveService.get_current().currencies==earned.currencies,"archive replay does not spend or grant resources")
		SceneRouter.go_to("home")
		await wait_ui()
		SceneRouter.go_to("settings")
		await wait_ui()
		# Save the English preference through the real UI for a fresh-process check.
		await button("Save & Return")
	var file := FileAccess.open("user://localization_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"checks":checks,"type":"rendered source UI with synthetic viewport input; isolated saves"},"\t"))
	if checks.all(func(c:Dictionary)->bool:return c.ok): App.request_quit()
	else: get_tree().quit(1)

func _scan(node: Node) -> void:
	var cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
	if node is Control and node.is_visible_in_tree():
		var value := ""
		if node is Label or node is RichTextLabel or node is Button: value = node.text
		if node is Button and node.get_theme_font_size("font_size")==1: value = "" # invisible art-button identifier
		if not value.is_empty(): check(cjk.search(value)==null,"English native text: "+value)
		if not node.tooltip_text.is_empty(): check(cjk.search(node.tooltip_text)==null,"English tooltip: "+node.tooltip_text)
	for child: Node in node.get_children(): _scan(child)
