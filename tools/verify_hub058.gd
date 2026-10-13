extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	# Explicit isolated fixture for the approved 1-3 investigation state.
	SaveService.new_game("界面验收")
	for sid: String in ["1-1","1-2"]:
		StageRewardService.settle(DataRegistry.get_entry("stages",sid),true,true)
	SceneRouter.go_to("home")
	await wait_ui()
	var home := get_tree().current_scene
	check(home.investigation_state.stage == "1-3","reference-stage fixture uses real next-stage selection")
	check(home.art_buttons.size()==15,"native buttons cover handbook, locations, board and person")
	var coin := home.canvas.get_node("school_coinChip") as Control
	var parts := home.canvas.get_node("equipment_partChip") as Control
	check(coin.size == parts.size and coin.position.y == parts.position.y,"resource frames have identical size and vertical position")
	check(coin.get_child(0).texture == parts.get_child(0).texture,"resource frames share identical bevel geometry")
	check(coin.get_child(1).size == parts.get_child(1).size,"resource artwork shares identical icon boxes")
	var uniform_captions := 0
	for child: Node in home.canvas.get_children():
		if child is Label and child.has_meta("handbook_caption"):
			if child.get_theme_font_size("font_size")==19 and child.vertical_alignment == VERTICAL_ALIGNMENT_CENTER: uniform_captions += 1
	check(uniform_captions==4,"all four handbook captions use same font size and centered baselines")
	await click(Vector2(900,900))
	var layout: Array = []
	for child: Node in home.canvas.get_children():
		if child is TextureRect:
			layout.append({"position":[child.position.x,child.position.y],"size":[child.size.x,child.size.y],"region":str(child.texture.region),"atlas":child.texture.atlas.resource_path})
	var layout_file:=FileAccess.open("user://hub_layout.json",FileAccess.WRITE)
	layout_file.store_string(JSON.stringify(layout,"\t"))
	layout_file.close()
	await shot("hub_reference")
	await get_tree().create_timer(1.0).timeout
	await shot("hub_petals_later")
	await button("调查公告板")
	check(not home.investigation.visible,"board collapses real investigation control")
	await shot("hub_board_collapsed")
	await button("调查公告板")
	check(home.investigation.visible,"board restores investigation control")
	await button("校园漫游")
	check(home.campus_panel.visible,"roam opens discovered places")
	await shot("hub_roam_early")
	check(home._location_events("保健室").is_empty(),"infirmary events remain locked before sixth clear")
	await escape_panel()
	await button("弓道场")
	check(home.campus_panel.visible,"archery scene opens even with no available conversation")
	await shot("hub_archery_empty")
	await escape_panel()
	await button("与雨宫澪交谈")
	await shot("hub_mio_location")
	var before := SaveService.snapshot()
	await button("刀鞘里的暮色\n新的交谈")
	check(SceneRouter.get_current_key()=="story","person opens existing unlocked conversation")
	await finish_story()
	check(SceneRouter.get_current_key()=="home" and CampaignFlow.done("hub_ch1_mio"),"conversation returns home and persists")
	check(SaveService.snapshot().currencies==before.currencies and SaveService.snapshot().stages==before.stages,"conversation creates no resources or stage unlocks")
	home=get_tree().current_scene
	await button("角色培养")
	check(SceneRouter.get_current_key()=="character","handbook cultivation works")
	await button("返回校园")
	await button("装备背包")
	check(SceneRouter.get_current_key()=="equipment","handbook inventory works")
	await button("返回校园")
	await button("剧情档案")
	check(SceneRouter.get_current_key()=="archive","handbook archive works")
	await button("▾ 校园随记 · 已读同伴交谈与环境记录")
	check(not get_tree().current_scene.find_child("CampusEntries",true,false).visible,"campus archive collapses")
	await shot("campus_archive_collapsed")
	await button("▸ 校园随记 · 已读同伴交谈与环境记录")
	check(get_tree().current_scene.find_child("CampusEntries",true,false).visible,"campus archive expands")
	await shot("campus_archive_expanded")
	await escape_panel()
	await button("关卡记录")
	check(SceneRouter.get_current_key()=="stage_select","handbook stage records works")
	await escape_panel()
	home=get_tree().current_scene
	check(home._roaming_locations().is_empty(),"early roam excludes all main doorway aliases")
	await button("设置")
	check(SceneRouter.get_current_key()=="settings","settings icon works")
	await button("校园菜单")
	check(SceneRouter.get_current_key()=="home" and get_tree().current_scene.exit_panel.visible,"settings campus menu opens actual home menu")
	await button("继续留在校园")
	await button("调查卡：继续调查")
	check(SceneRouter.get_current_key() in ["story","briefing"],"live investigation enters original story/briefing flow")
	SceneRouter.go_to("home")
	await wait_ui()
	home=get_tree().current_scene
	home._show_menu()
	await wait_ui()
	await shot("hub_menu")
	await button("继续留在校园")
	check(not home.exit_panel.visible,"campus menu resume works")
	# A second isolated save validates fresh empty state and cache invalidation.
	SaveService.new_game("全新调查")
	SceneRouter.go_to("home")
	await wait_ui()
	home=get_tree().current_scene
	check(home.investigation_state.stage=="1-1","new save card shows first investigation")
	check(home._location_events("观测会活动室").is_empty(),"fresh save exposes no locked story")
	await shot("hub_fresh")
	# Saved unfinished briefing: title Continue must land in campus without
	# consuming the pending investigation or rewriting progression.
	var fixture := SaveService.snapshot()
	fixture.story.flags["done:"+str(DataRegistry.get_entry("stages","1-1").get("storyBefore",""))] = true
	fixture.flow_state.merge({"campaign_active":true,"mode":"pre_battle","pending_stage_id":"1-1","current_story_id":"","pending_story_after":""},true)
	SaveService.commit(fixture)
	SceneRouter.go_to("title")
	await wait_ui()
	var before_continue := SaveService.snapshot()
	get_tree().current_scene._activate(0)
	await wait_ui()
	check(SceneRouter.get_current_key()=="home","title Continue lands in campus despite unfinished briefing")
	check(SaveService.snapshot()==before_continue,"title Continue preserves pending progress")
	await button("继续调查")
	check(SceneRouter.get_current_key()=="briefing","main investigation opens briefing")
	var briefing := get_tree().current_scene
	await click(briefing.cards["amamiya_mio"].get_global_rect().get_center())
	await button("开始战斗   →")
	check(SceneRouter.get_current_key()=="briefing" and briefing.hint.visible,"empty party refuses battle and shows hint")
	check(is_equal_approx(briefing.hint.position.x+briefing.hint.size.x*.5,960.0),"hint centered between bottom buttons")
	await shot("briefing_empty_party_hint")
	await get_tree().create_timer(2.8).timeout
	check(not briefing.hint.visible,"empty-party hint automatically disappears")
	await shot("briefing_hint_expired")
	await escape_panel()
	check(SceneRouter.get_current_key()=="home","main investigation Escape returns campus")
	await button("关卡记录")
	get_tree().current_scene._on_row_activated("1-1")
	await wait_ui()
	check(SceneRouter.get_current_key()=="briefing","record entry opens briefing")
	await button("返回关卡记录")
	check(SceneRouter.get_current_key()=="stage_select","record entry return button returns records")
	get_tree().current_scene._on_row_activated("1-1")
	await wait_ui()
	await escape_panel()
	check(SceneRouter.get_current_key()=="stage_select","record entry Escape returns records")
	var ok:=checks.all(func(c:Dictionary)->bool:return c.ok)
	var file:=FileAccess.open("user://hub_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks,"fixture":"isolated domain settlements for UI, not a campaign playthrough"},"\t"))
	file.close()
	if ok: App.request_quit()
	else: get_tree().quit(1)

func escape_panel() -> void:
	for pressed: bool in [true,false]:
		var key:=InputEventKey.new()
		key.keycode=KEY_ESCAPE
		key.pressed=pressed
		get_viewport().push_input(key,true)
	await wait_ui()

func finish_story() -> void:
	for i: int in range(50):
		if SceneRouter.get_current_key()!="story": break
		var story := get_tree().current_scene
		await click(story.next_button.get_global_rect().get_center())
		await wait_ui()
