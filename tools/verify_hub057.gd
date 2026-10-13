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
	await click(Vector2(900,900))
	var layout: Array = []
	for child: Node in home.canvas.get_children():
		if child is TextureRect:
			layout.append({"position":[child.position.x,child.position.y],"size":[child.size.x,child.size.y],"region":str(child.texture.region),"atlas":child.texture.atlas.resource_path})
	var layout_file:=FileAccess.open("user://hub_layout.json",FileAccess.WRITE)
	layout_file.store_string(JSON.stringify(layout,"\t"))
	layout_file.close()
	await shot("hub_reference")
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
	await button("角色装备")
	check(SceneRouter.get_current_key()=="character_equipment","handbook equipment works")
	await button("返回校园")
	await button("剧情档案")
	check(SceneRouter.get_current_key()=="archive","handbook archive works")
	await escape_panel()
	await button("关卡记录")
	check(SceneRouter.get_current_key()=="stage_select","handbook stage records works")
	await escape_panel()
	await button("设置")
	check(SceneRouter.get_current_key()=="settings","settings icon works")
	await escape_panel()
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
