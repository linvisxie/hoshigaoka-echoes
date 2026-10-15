extends "res://tools/verify_frontend_driver.gd"

func wait_ui() -> void:
	await get_tree().create_timer(.9).timeout

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	check(SaveService.ensure_loaded(),"earned seed loaded")
	for locale: String in ["zh","en"]:
		GameLocale.set_language(locale)
		GameSkin.motion_level = 2
		SceneRouter.go_to("home")
		await wait_ui()
		var home := get_tree().current_scene
		check(home.art_buttons["保健室"].tooltip_text==GameLocale.text("保健室 · "+home._location_status("保健室")),"location status hint "+locale)
		await shot("campus_"+locale)
		SceneRouter.go_to("settings")
		await wait_ui()
		var settings := get_tree().current_scene
		check(settings.rows.get_node_or_null("AutoDelay")!=null,"auto delay setting "+locale)
		check(settings.rows.get_node_or_null("Motion")!=null,"motion strength setting "+locale)
		await shot("settings_top_"+locale)
		settings.scroll.scroll_vertical = 220
		await wait_ui()
		await shot("settings_middle_"+locale)
		await click(settings.motion_button.get_global_rect().get_center())
		await wait_ui()
		check(GameSkin.motion_level==0,"motion cycles to off "+locale)
		var saved := ConfigFile.new()
		saved.load(SaveService.SETTINGS_PATH)
		check(saved.get_value("presentation","motion_level",-1)==0,"motion choice persisted "+locale)
		await click(settings.motion_button.get_global_rect().get_center())
		await wait_ui()
		check(GameSkin.motion_level==1,"motion cycles to gentle "+locale)
		await click(settings.motion_button.get_global_rect().get_center())
		await wait_ui()
		settings.auto_delay_slider.value = 4
		settings._persist(locale)
		saved.load(SaveService.SETTINGS_PATH)
		check(float(saved.get_value("story","auto_delay",0))==4,"auto delay persisted "+locale)
		settings.scroll.scroll_vertical = 9999
		await wait_ui()
		await shot("settings_bottom_"+locale)
		SceneRouter.go_to("archive")
		await wait_ui()
		var archive := get_tree().current_scene
		var before := SaveService.snapshot()
		await shot("archive_original_"+locale)
		var replay_id := "prologue_transfer"
		check(CampaignFlow.done(replay_id),"completed prologue available for replay "+locale)
		archive._replay(replay_id)
		await wait_ui()
		var story := get_tree().current_scene
		check(story.auto_delay==4,"story loads selected dwell "+locale)
		await shot("story_replay_"+locale)
		check(find_button(story,GameLocale.text("跳过已读"))==null,"skip-read addition removed "+locale)
		check(SaveService.snapshot()==before,"replay opening preserves progress "+locale)
		SceneRouter.go_to("equipment")
		await wait_ui()
		var equipment := get_tree().current_scene
		if not EquipmentService.pending_equipment_entitlements().is_empty():
			equipment._claim()
			await wait_ui()
			equipment = get_tree().current_scene
		var iid := ""
		for item: Dictionary in EquipmentService.all_instances():
			if str(item.equipmentId)=="equip_ch1_1_2_fine_weapon": iid = str(item.instanceId); break
		check(not iid.is_empty(),"earned bow exists "+locale)
		equipment.selected_id = iid
		SceneRouter.go_to("equipment")
		await wait_ui()
		equipment = get_tree().current_scene
		before = SaveService.snapshot()
		equipment._preview("equip","kamiya_yuma")
		await wait_ui()
		check(SaveService.snapshot()==before,"preview opening preserves save "+locale)
		_check_preview(equipment.preview_panel,locale)
		await shot("equipment_swap_preview_"+locale)
		await button(GameLocale.text("取消"))
		check(SaveService.snapshot()==before,"cancel preserves save "+locale)
		equipment._preview("equip","kamiya_yuma")
		await wait_ui()
		await button(GameLocale.text("确认操作"))
		check(EquipmentService.equipped_of(SaveService.get_current(),"kamiya_yuma").get("WEAPON","")==iid,"confirmed equip updates slot "+locale)
		equipment = get_tree().current_scene
		before = SaveService.snapshot()
		var expected := EquipmentService.preview_operation(before,iid,"enhance")
		equipment._preview("enhance")
		await wait_ui()
		_check_preview(equipment.preview_panel,locale)
		await shot("equipment_enhance_preview_"+locale)
		check(SaveService.snapshot()==before,"enhancement preview preserves save "+locale)
		await button(GameLocale.text("确认操作"))
		for currency: String in expected.remaining:
			check(int(SaveService.get_current().currencies[currency])==int(expected.remaining[currency]),"confirmed enhancement cost "+currency+locale)
		# Rendering fixture for the widest two-character preview, never committed.
		equipment = get_tree().current_scene
		var real_save := SaveService.snapshot()
		var fixture := real_save.duplicate(true)
		var accessory := EquipmentService.build_instance("equip_ch1_1_6_heal_accessory","preview_fixture")
		accessory.boundCharacterId = "amamiya_mio"
		fixture.inventory[EquipmentService.ITEMS_KEY].append(accessory)
		EquipmentService._ensure_character(fixture,"amamiya_mio")
		fixture.characters.amamiya_mio.equipment.ACCESSORY = "preview_fixture"
		SaveService._current = fixture
		equipment.selected_id = "preview_fixture"
		equipment._preview("equip","kamiya_yuma")
		await wait_ui()
		_check_preview(equipment.preview_panel,locale)
		await shot("equipment_two_characters_fixture_"+locale)
		equipment.preview_panel.hide()
		SaveService._current = real_save
		equipment.selected_id = iid
		SceneRouter.go_to("home")
		await wait_ui()
		GameSkin.motion_level = 0
		home = get_tree().current_scene
		await wait_ui()
		check(not home.atmosphere.visible,"motion off hides environmental shader layer "+locale)
		check(not home.petals.visible,"motion off removes cached petals "+locale)
		await shot("motion_off_"+locale)
		GameSkin.motion_level = 1
		await wait_ui()
		check(home.atmosphere.visible,"gentle motion restores atmosphere "+locale)
		await shot("motion_gentle_"+locale)
		GameSkin.motion_level = 2
	var ok := true
	for result: Dictionary in checks: ok = ok and result.ok
	var file := FileAccess.open("user://features_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks},"\t"))
	file.close()
	if ok: App.request_quit()
	else: get_tree().quit(1)

func _check_preview(dialog: Panel,locale: String) -> void:
	var inside := true
	var text_fits := true
	var localized := true
	var cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
	for child: Node in dialog.get_children():
		if child is Label or child is Button:
			inside = inside and Rect2(Vector2.ZERO,dialog.size).encloses(Rect2(child.position,child.size))
			if locale=="en": localized = localized and cjk.search(child.text)==null
		if child is Label:
			text_fits = text_fits and child.get_line_count()*child.get_line_height()<=child.size.y+2
	check(inside,"preview content stays inside its card "+locale)
	check(text_fits,"preview text fits its allotted height "+locale)
	check(localized,"preview text has no Chinese residue in English "+locale)
