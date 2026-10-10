## Additional real Windows native Control input checks. Uses earned isolated save only.
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
	SceneRouter.go_to("settings")
	await wait_ui()
	await button("保存并返回")
	check(SceneRouter.get_current_key()=="title","title settings returns to title")
	CampaignFlow.resume()
	await wait_ui()
	await button("关卡记录")
	await shot("stage_cards")
	var select := get_tree().current_scene
	check(select._stage_buttons.size()==6,"five scene preview cards and return")
	await click((select._stage_buttons[4] as Button).get_global_rect().get_center())
	await wait_ui()
	check(SceneRouter.get_current_key()=="briefing","fifth card opens actual briefing")
	await shot("gym_briefing")
	CampaignFlow.launch_battle()
	await get_tree().create_timer(2).timeout
	var battle := get_tree().current_scene
	await shot("gym_hud")
	await button("Ⅱ  暂停")
	check(battle.session.is_paused(),"native pause button freezes battle")
	var frozen: float = battle.session.stage.elapsed_seconds
	await get_tree().create_timer(0.8).timeout
	check(is_equal_approx(battle.session.stage.elapsed_seconds,frozen),"pause preserves domain clock")
	await shot("pause")
	await button("操作说明与音量")
	await shot("pause_audio")
	await button("保存并返回")
	check(battle.session.is_paused(),"audio settings retain pause")
	await button("结束本次调查")
	await shot("leave_confirmation")
	await button("继续调查")
	check(battle.session.is_paused(),"cancel leave returns to pause")
	await key(KEY_SPACE)
	check(not battle.session.is_paused(),"Space resumes after native button interaction")
	await key(KEY_SPACE)
	await button("结束本次调查")
	await button("返回校园")
	check(SceneRouter.get_current_key()=="home","confirmed leave returns to campus")
	var report := {"type":"real Windows viewport; automated native mouse/key input", "checks":checks}
	var file := FileAccess.open("user://ui_polish_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	get_tree().quit(0 if checks.all(func(item: Dictionary) -> bool: return item.ok) else 2)
