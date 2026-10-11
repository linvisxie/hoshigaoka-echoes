extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.ensure_loaded()
	SceneRouter.go_to("character")
	await wait_ui()
	var growth := get_tree().current_scene
	for card: Rect2 in growth._card_rects:
		for navigation: Button in growth._navigation:
			check(not card.intersects(navigation.get_global_rect()),"navigation does not intersect character card")
	await shot("growth_layout")
	get_window().grab_focus()
	await wait_ui()
	for chip: Dictionary in growth._resource_chips.duplicate():
		get_viewport().warp_mouse((chip.rect as Rect2).get_center())
		await wait_ui()
		if not growth._resource_tip.visible:
			get_window().grab_focus()
			get_viewport().warp_mouse((chip.rect as Rect2).get_center())
			await wait_ui()
		check(growth._resource_tip.visible,"resource tooltip: "+str(chip.id))
		await shot("resource_"+str(chip.id))
	get_viewport().warp_mouse(Vector2(630,1030))
	await button("技能与天赋")
	await shot("portrait_details")
	await button("返回培养")
	await button("装备背包")
	var claim := find_button(get_tree().current_scene,"领取全部装备奖励")
	if claim != null and not claim.disabled:
		await button("领取全部装备奖励")
	check(find_button(get_tree().current_scene,"装备给雨宫澪")==null,"bow offers no sword-user equip action")
	check(find_button(get_tree().current_scene,"装备给神谷悠真")!=null,"bow offers eligible archer")
	await shot("equipment_bow_only")
	var archer := find_button(get_tree().current_scene,"装备给神谷悠真")
	if archer != null and not archer.disabled:
		await button("装备给神谷悠真")
	var before_battle := SaveService.snapshot()
	PrototypeEntry.set_pending_stage_id("1-5")
	SceneRouter.go_to("battle")
	await wait_ui()
	var battle := get_tree().current_scene
	for index: int in range(16):
		await shot("core_turn_%02d" % index)
		await get_tree().create_timer(.16).timeout
	await click(battle._card_rects[battle._roster.find("amamiya_mio")].get_center())
	await wait_ui()
	await shot("horizontal_deployment_preview")
	await click(battle._cell_screen_pos(2,1))
	await wait_ui()
	check(battle.session.stage.get_character_by_id("amamiya_mio")!=null,"projected center deploys Mio")
	await click(battle._native_hud.pause_button.get_global_rect().get_center())
	await wait_ui()
	check(battle.session.is_paused(),"pause before retry")
	var frozen: float = battle._now()
	await shot("pause_with_retry")
	await wait_ui()
	check(battle._now()==frozen,"pause freezes core animation clock")
	await button("重试本次调查")
	battle=get_tree().current_scene
	check(battle.session.stage.stage_id=="1-5","retry retains stage")
	check(battle._now()<2.0,"retry resets battle clock")
	check(battle.session.stage.characters.is_empty(),"retry clears deployed characters")
	check(battle.session.stage.enemies.is_empty(),"retry resets enemy progression")
	check(battle.session.stage.core_hp==battle.session.stage.core_hp_max,"retry restores core")
	check(not battle.session.is_paused(),"retry resumes fresh investigation")
	check(SaveService.snapshot()==before_battle,"retry grants no rewards or save progression")
	await shot("retry_fresh_battle")
	battle._autoplay = true
	battle._autoplay_hold_upgrade = true
	# Let the normal battle clock reach its first real upgrade choice.
	var deadline := Time.get_ticks_msec()+100000
	while not battle._upgrade_panel_active() and not battle.session.is_decided() and Time.get_ticks_msec()<deadline:
		for cid: String in ["amamiya_mio","kamiya_yuma"]:
			var hero: CharacterRuntime = battle.session.stage.get_character_by_id(cid)
			if hero != null and hero.skill_ready():
				await click(battle._card_rects[battle._roster.find(cid)].get_center())
				await get_tree().process_frame
				await click(battle._native_hud.skill_button.get_global_rect().get_center())
		await get_tree().create_timer(.2).timeout
	check(battle._upgrade_panel_active(),"real first-wave upgrade offer reached")
	if battle._upgrade_panel_active():
		await wait_ui()
		await shot("upgrade_spacing")
		var rect: Rect2=battle._upgrade_card_rects[0]
		check(rect.position.y/battle._render_scale>=230,"cards separated from title and subtitle")
		await click(rect.get_center())
		await wait_ui()
		check(not battle._upgrade_panel_active(),"upgrade card remains clickable after moving")
	var report := {"type":"Real Windows renderer and viewport UI events; earned isolated campaign save", "checks":checks,"normalBattleClock":true,"art":battle._art_drawn}
	var file:=FileAccess.open("user://round10_ui_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	get_tree().quit(0 if checks.all(func(item: Dictionary) -> bool:return item.ok) else 2)
