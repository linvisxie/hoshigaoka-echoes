## Actual Windows viewport UI events using a copied, earned chapter clear save.
extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.ensure_loaded()
	check(CampaignFlow.character_unlocked("shiraishi_chinatsu"),"chapter ending unlock survived load")
	SceneRouter.go_to("stage_select")
	await wait_ui()
	await shot("ten_stages")
	SceneRouter.go_to("character")
	await wait_ui()
	var growth := get_tree().current_scene
	check(growth._card_ids.size()==6,"six characters in growth")
	await shot("growth_page_1")
	await button("下一页 ›")
	await shot("growth_page_2")
	for card: Rect2 in growth._card_rects:
		if card.size==Vector2.ZERO: continue
		for navigation: Button in growth._navigation:
			check(not card.intersects(navigation.get_global_rect()),"page 2 cards avoid navigation")
	var event := InputEventKey.new()
	event.keycode=KEY_6
	event.pressed=true
	Input.parse_input_event(event)
	await wait_ui()
	check(growth._list_page==1,"keyboard selects visible second page")
	await shot("chinatsu_growth")
	await button("装备背包")
	await button("领取全部装备奖励")
	var reward: Dictionary={}
	for item: Dictionary in EquipmentService.all_instances():
		if item.get("equipmentId","")=="memento_ch1_boss_cleared": reward=item
	check(not reward.is_empty(),"earned Boss memento claimed")
	if not reward.is_empty():
		await button("被划掉的满分试卷  +0")
		await shot("memento_eligible_characters")
		check(find_button(get_tree().current_scene,"重置 / 分解").disabled,"unique memento cannot be destroyed in UI")
		await button("装备给白石千夏")
		check(SaveService.load_game(),"reload after memento equip")
		var bonuses: Dictionary=App.level_stats_table().shiraishi_chinatsu.get("equipmentBonuses",{})
		check(is_equal_approx(float(bonuses.get("cdRecovery",0)),.05),"memento grants actual 5 percent cooldown recovery after reload")
		check(EquipmentService.pending_equipment_entitlements().is_empty(),"claimed rewards do not reappear")
		await shot("memento_equipped")
	SceneRouter.go_to("archive")
	await wait_ui()
	await shot("archive_top")
	for child: Node in get_tree().current_scene.canvas.get_children():
		if child is ScrollContainer:
			child.scroll_vertical=10000
	await wait_ui()
	await shot("archive_bottom")
	var before_replay:=SaveService.snapshot()
	CampaignFlow.replay_story_id="ch1_1_10_after"
	SceneRouter.go_to("story")
	await wait_ui()
	var story:=get_tree().current_scene
	for i: int in range(4):
		story.dialogue.visible_ratio=1
		story.advance()
		await get_tree().process_frame
	await wait_ui()
	await shot("ending_silhouette")
	check(SaveService.snapshot()==before_replay,"ending replay preserves earned progress and inventory")
	CampaignFlow.open_stage("1-10")
	await wait_ui()
	await shot("six_character_briefing")
	CampaignFlow.launch_battle()
	await wait_ui()
	var battle:=get_tree().current_scene
	check(battle._roster.size()==6,"six-character replay roster")
	await click(battle._card_rects[battle._roster.find("amamiya_mio")].get_center())
	await click(battle._cell_screen_pos(3,1))
	var deadline:=Time.get_ticks_msec()+30000
	while battle.session.stage.ap<15 and Time.get_ticks_msec()<deadline:
		await get_tree().create_timer(.2).timeout
	await click(battle._card_rects[battle._roster.find("shiraishi_chinatsu")].get_center())
	await click(battle._cell_screen_pos(2,1))
	var chinatsu: CharacterRuntime=battle.session.stage.get_character_by_id("shiraishi_chinatsu")
	check(chinatsu!=null,"Chinatsu deploys through actual card and cell input")
	await shot("six_cards_and_chinatsu")
	if chinatsu!=null:
		while not chinatsu.skill_ready() and not battle.session.is_decided() and Time.get_ticks_msec()<deadline+30000:
			await get_tree().create_timer(.2).timeout
		await click(battle._card_rects[battle._roster.find("shiraishi_chinatsu")].get_center())
		await click(battle._native_hud.skill_button.get_global_rect().get_center())
		await wait_ui()
		check(battle.session.stage.skill_events.any(func(item: Dictionary) -> bool:return item.skillId=="chinatsu_beat"),"Chinatsu active skill triggered")
		await shot("chinatsu_active")
	var file:=FileAccess.open("user://chapter_ui_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"type":"Real Windows viewport automated UI events; copied earned chapter save", "checks":checks,"art":battle._art_drawn,"audio":AudioService.playback_status()},"\t"))
	get_tree().quit(0 if checks.all(func(item: Dictionary) -> bool:return item.ok) else 2)
