extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	# Explicit rendering fixture. Battle outcome is set for presentation testing;
	# rewards still pass through the real settlement service and its ledger.
	for locale: String in ["zh","en"]:
		GameLocale.set_language(locale)
		for sid: String in ["1-2","1-6","1-9","1-10"]:
			SaveService.new_game("结算表现夹具")
			PrototypeEntry.set_pending_stage_id(sid)
			SceneRouter.go_to("battle")
			await get_tree().create_timer(.2).timeout
			var battle := get_tree().current_scene
			battle.set_process(false)
			battle.session.outcome = BattleTypes.Outcome.VICTORY
			battle._result_animation_time = 10
			battle._layout_buttons()
			battle._grant_battle_rewards()
			await wait_ui()
			var items := BattleOverlays.equipment_rewards(battle._reward_summary)
			check(items.size()==1,"equipment reward included in "+sid+locale)
			var pending := EquipmentService.pending_equipment_entitlements().duplicate(true)
			check(pending.size()==1,"one actual pending entitlement registered "+sid+locale)
			var overlay: Control = battle._native_hud.overlays.layer
			check(_has_text(overlay,GameLocale.text(str(items[0].name))),"reward card shows equipment name "+sid+locale)
			check(_has_text(overlay,GameLocale.text("前往装备背包领取")),"reward card explains collection "+sid+locale)
			var icon_view := overlay.find_child("RewardEquipmentIcon",true,false) as TextureRect
			check(icon_view!=null and icon_view.texture!=null,"reward icon has an exported asset "+sid+locale)
			check(_localized(overlay,locale),"result has no Chinese residue in English "+sid+locale)
			check(_text_fits(overlay),"result card labels fit their rows "+sid+locale)
			await shot("result_"+sid+"_"+locale)
			var scroll := overlay.find_child("ResultRewards",true,false) as ScrollContainer
			if scroll.get_v_scroll_bar().max_value>scroll.size.y:
				var point := scroll.get_global_rect().get_center()
				var motion := InputEventMouseMotion.new()
				motion.position = point
				get_viewport().push_input(motion,true)
				for n: int in range(6):
					var wheel := InputEventMouseButton.new()
					wheel.position = point
					wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
					wheel.pressed = true
					get_viewport().push_input(wheel,true)
					await get_tree().process_frame
				await get_tree().create_timer(.1).timeout
				check(scroll.scroll_vertical>0,"reward list accepts mouse-wheel scrolling "+sid+locale)
				var rows := scroll.get_child(0)
				var last := rows.get_child(rows.get_child_count()-1) as Control
				check(scroll.get_global_rect().grow(2).encloses(last.get_global_rect()),"last resource row can be fully revealed "+sid+locale)
				await shot("result_scrolled_"+sid+"_"+locale)
			check(EquipmentService.pending_equipment_entitlements()==pending,"rendering does not consume or duplicate pending items "+sid+locale)
			if sid=="1-2":
				battle._rewards_granted = false
				battle._grant_battle_rewards()
				await wait_ui()
				check(BattleOverlays.equipment_rewards(battle._reward_summary).is_empty(),"repeat win does not show the old first-clear item "+locale)
				await shot("result_repeat_"+locale)
				battle.session.outcome = BattleTypes.Outcome.DEFEAT
				battle._rewards_granted = false
				battle._grant_battle_rewards()
				await wait_ui()
				check(BattleOverlays.equipment_rewards(battle._reward_summary).is_empty(),"defeat shows no new item "+locale)
				await shot("result_defeat_"+locale)
	SceneRouter.go_to("title")
	await wait_ui()
	var ok := true
	for result: Dictionary in checks: ok = ok and result.ok
	var file := FileAccess.open("user://result_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks},"\t"))
	file.close()
	if ok: App.request_quit()
	else: get_tree().quit(1)

func _has_text(node: Node,value: String) -> bool:
	if node is Label and node.text.contains(value): return true
	for child: Node in node.get_children():
		if _has_text(child,value): return true
	return false

func _text_fits(node: Node) -> bool:
	if node is Label and not node.text.is_empty():
		if node.get_line_count()*node.get_line_height()>node.size.y+2: return false
	for child: Node in node.get_children():
		if not _text_fits(child): return false
	return true

func _localized(node: Node,locale: String) -> bool:
	if locale!="en": return true
	if node is Label:
		var cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
		if cjk.search(node.text)!=null: return false
	for child: Node in node.get_children():
		if not _localized(child,locale): return false
	return true
