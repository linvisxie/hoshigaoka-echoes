## Normal-clock rendered victory/defeat, no forced outcome or stats injection.
extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	check(CampaignFlow.start_new("结算验收"),"new isolated campaign")
	await wait_ui()
	for i: int in range(100):
		if SceneRouter.get_current_key()!="story":break
		var story:=get_tree().current_scene
		await click(story.next_button.get_global_rect().get_center())
		await get_tree().create_timer(.1).timeout
	check(SceneRouter.get_current_key()=="briefing","prologue reaches briefing normally")
	await button("开始战斗   →")
	var failed:=get_tree().current_scene
	var before:=SaveService.snapshot()
	await wait_outcome(failed,false)
	await shot("defeat_settlement")
	await get_tree().create_timer(6).timeout
	check(SceneRouter.get_current_key()=="battle" and get_tree().current_scene==failed,"defeat stays until player input")
	await shot("defeat_waiting_for_player")
	check(failed.session.outcome==BattleTypes.Outcome.DEFEAT,"idle defenders genuinely lose")
	check(SaveService.snapshot().currencies==before.currencies,"defeat grants no reward")
	check(str(CampaignFlow.state().get("pending_story_after",""))=="","defeat has no after-story")
	await click(failed._quit_rect.get_center())
	await wait_ui()
	check(SceneRouter.get_current_key()=="home" and CampaignFlow.next_stage()=="1-1","defeat returns to campus at same challenge")
	check(not CampaignFlow.open_stage("1-2"),"later stage cannot be launched after defeat")
	CampaignFlow.open_stage("1-1")
	await wait_ui()
	await button("开始战斗   →")
	var won:=get_tree().current_scene
	await wait_outcome(won,true)
	await get_tree().create_timer(3.2).timeout
	await shot("victory_settlement")
	await get_tree().create_timer(6).timeout
	check(SceneRouter.get_current_key()=="battle" and get_tree().current_scene==won,"victory stays until player input")
	await shot("victory_waiting_for_player")
	check(won.session.outcome==BattleTypes.Outcome.VICTORY,"normal deployment and skills genuinely win")
	check(not won._reward_summary.get("granted",{}).is_empty(),"victory displays earned rewards")
	check(won._relaunch_rect.size.y>0 and won._quit_rect.size.y>0,"both settlement buttons have hit areas")
	var paid: Dictionary=SaveService.snapshot().currencies.duplicate(true)
	await click(won._relaunch_rect.get_center())
	await wait_ui()
	check(SceneRouter.get_current_key()=="battle" and get_tree().current_scene.session.is_running(),"settlement retry starts a fresh fight")
	check(SaveService.snapshot().currencies==paid,"retry does not duplicate settled rewards")
	var file:=FileAccess.open("user://settlement_ui_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"checks":checks,"type":"Real Windows rendered normal-clock campaign; automated viewport input; no forced result"},"\t"))
	if checks.all(func(c:Dictionary)->bool:return c.ok):App.request_quit()
	else:get_tree().quit(1)

func wait_outcome(scene: Node, play: bool) -> void:
	var deadline:=Time.get_ticks_msec()+240000
	while not scene.session.is_decided() and Time.get_ticks_msec()<deadline:
		if play:
			var rt:StageRuntime=scene.session.stage
			var mio:=rt.get_character_by_id("amamiya_mio")
			if mio==null and rt.query_deploy("amamiya_mio",3,1).ok:
				await click(scene._card_rects[0].get_center())
				await click(scene._cell_screen_pos(3,1))
			elif mio!=null and mio.skill_ready() and rt.has_living_enemies():
				scene._selected_character_id=mio.instance_id
				var key:=InputEventKey.new();key.keycode=KEY_Q;key.pressed=true
				get_viewport().push_input(key,true)
		await get_tree().create_timer(.25).timeout
	check(scene.session.is_decided(),"normal battle resolves within bounded wait")
