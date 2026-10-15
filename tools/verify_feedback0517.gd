extends "res://tools/verify_features0516.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	check(SaveService.ensure_loaded(),"player seed loaded")
	var original := SaveService.snapshot()
	for locale: String in ["zh","en"]:
		GameLocale.set_language(locale)
		SceneRouter.go_to("equipment")
		await wait_ui()
		var equipment := get_tree().current_scene
		var selected: String = equipment.selected_id
		var preview := EquipmentService.preview_operation(original,selected,"enhance")
		check(not preview.affordable,"player seed lacks required materials "+locale)
		check(int(preview.remaining.equipment_part)>=0,"no negative remaining parts "+locale)
		equipment._preview("enhance")
		await wait_ui()
		_check_preview(equipment.preview_panel,locale)
		check(find_button(equipment,GameLocale.text("确认操作")).disabled,"insufficient preview cannot confirm "+locale)
		await shot("insufficient_preview_"+locale)
		equipment.preview_panel.hide()
		# Feedback text is a presentation fixture, never a fabricated enhancement.
		equipment._set_feedback("强化成功 → +3")
		var deadline: int = equipment.feedback_expires_at
		SceneRouter.go_to("equipment")
		await get_tree().create_timer(.15).timeout
		equipment = get_tree().current_scene
		check(equipment.canvas.get_node_or_null("EquipmentFeedback")!=null,"feedback appears "+locale)
		await shot("feedback_visible_"+locale)
		await get_tree().create_timer(1.0).timeout
		SceneRouter.go_to("equipment")
		await get_tree().create_timer(.15).timeout
		equipment = get_tree().current_scene
		check(equipment.feedback_expires_at==deadline,"same-page refresh preserves expiry "+locale)
		await get_tree().create_timer(2.0).timeout
		check(equipment.canvas.get_node_or_null("EquipmentFeedback")==null,"feedback expires after three seconds "+locale)
		check(equipment.feedback.is_empty(),"expired static message cleared "+locale)
		await shot("feedback_expired_"+locale)
		equipment._set_feedback("强化成功 → +4")
		SceneRouter.go_to("equipment")
		await get_tree().create_timer(1.0).timeout
		equipment = get_tree().current_scene
		equipment._set_feedback("强化成功 → +5")
		SceneRouter.go_to("equipment")
		await get_tree().create_timer(2.2).timeout
		equipment = get_tree().current_scene
		check(equipment.canvas.get_node_or_null("EquipmentFeedback")!=null,"older feedback cannot clear a newer message "+locale)
		await get_tree().create_timer(1.0).timeout
		check(equipment.canvas.get_node_or_null("EquipmentFeedback")==null,"newer feedback also expires "+locale)
		equipment._set_feedback("强化成功 → +6")
		SceneRouter.go_to("home")
		await get_tree().create_timer(.15).timeout
		SceneRouter.go_to("equipment")
		await wait_ui()
		equipment = get_tree().current_scene
		check(equipment.canvas.get_node_or_null("EquipmentFeedback")==null,"returning from campus does not revive feedback "+locale)
		check(SaveService.snapshot()==original,"presentation checks never spend player resources "+locale)
	var ok := true
	for result: Dictionary in checks: ok = ok and result.ok
	var file := FileAccess.open("user://feedback_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks},"\t"))
	file.close()
	if ok: App.request_quit()
	else: get_tree().quit(1)
