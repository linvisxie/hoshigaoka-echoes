## Real viewport input verification using an earned isolated campaign save.
extends "res://tools/verify_frontend_driver.gd"

func key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await wait_ui()

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SceneRouter.go_to("title")
	await wait_ui()
	var title := get_tree().current_scene
	check(title._rows.size()==4,"title has concept four-menu structure")
	await shot("title")
	await click(title._rows[2].get_global_rect().get_center())
	await wait_ui()
	check(SceneRouter.get_current_key()=="settings","real title settings row opens settings")
	await button("保存并返回")
	check(SceneRouter.get_current_key()=="title","settings returns to title")
	await key(KEY_ESCAPE)
	title = get_tree().current_scene
	check(title._quit_confirmation != null and title._quit_confirmation.visible,"Escape opens exit confirmation")
	await shot("exit_confirmation")
	await button("留在这里")
	check(not title._quit_confirmation.visible,"cancel exit keeps game open")
	await click(title._rows[0].get_global_rect().get_center())
	await wait_ui()
	check(SceneRouter.get_current_key()=="home","continue resumes campus")
	await shot("campus")
	await button("关卡记录")
	var stages := get_tree().current_scene
	await shot("stage_cards")
	await click((stages._stage_buttons[1] as Button).get_global_rect().get_center())
	await wait_ui()
	check(SceneRouter.get_current_key()=="briefing","second card opens actual stage briefing")
	await shot("landing_briefing")
	await button("开始战斗   →")
	await get_tree().create_timer(2).timeout
	var battle := get_tree().current_scene
	check(battle.session.stage.stage_id=="1-2","second stage launches")
	await shot("landing_battle")
	await button("Ⅱ  暂停")
	check(battle.session.is_paused(),"native pause works after compact button style")
	await button("结束本次调查")
	await button("返回校园")
	CampaignFlow.replay_story_id = "prologue_transfer"
	SceneRouter.go_to("story")
	await wait_ui()
	var story := get_tree().current_scene
	story.index = 6
	story._show_node()
	story.dialogue.visible_ratio = 1
	await wait_ui()
	check(story.portrait.texture is AtlasTexture,"emotion illustration is framed without source caption")
	check(story.next_button.get_global_rect().end.y<1000,"dialogue advance fits within panel")
	await shot("story_portrait")
	await button("历史")
	var previous: int = story.index
	await click(story.next_button.get_global_rect().get_center())
	check(story.index==previous,"history blocks underlying next button")
	await shot("story_history")
	var report := {"type":"Windows renderer; real viewport mouse/keyboard events; earned isolated save","checks":checks}
	var file := FileAccess.open("user://finish_polish_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	get_tree().quit(0 if checks.all(func(item: Dictionary) -> bool: return item.ok) else 2)
