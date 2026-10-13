extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.ensure_loaded()
	var baseline := SaveService.snapshot()
	check(CampaignFlow.next_stage().is_empty(),"isolated earned chapter-clear save loaded")
	var samples: Array[Dictionary] = []
	SceneRouter.go_to("home")
	await wait_ui()
	for cycle: int in range(12):
		await button("装备背包")
		var opened: bool = get_tree().current_scene.expanded_slots.WEAPON
		await button(("▾ " if opened else "▸ ")+"武器")
		await button(("▸ " if opened else "▾ ")+"武器")
		await escape_panel()
		check(SceneRouter.get_current_key()=="home","inventory Escape retains campus origin after category rebuild")
		CampaignFlow.inspected_character_id = "minase_sara"
		await button("角色培养")
		var growth := get_tree().current_scene
		var page: int = growth._list_page
		await button("技能与天赋")
		await button("剧情档案")
		await button("▸ 第一章 · 新学期的残响  /  19 篇已读")
		await button("▾ 第一章 · 新学期的残响  /  19 篇已读")
		await escape_panel()
		check(SceneRouter.get_current_key()=="character","archive Escape returns cultivation after fold rebuild")
		check(SceneRouter.get_current_key()=="character" and get_tree().current_scene._list_page==page,"cultivation page and selected character survive submenu round trip")
		await button("角色装备")
		await button("装备背包")
		await escape_panel()
		check(SceneRouter.get_current_key()=="character_equipment","inventory Escape retains character-equipment origin")
		await button("返回校园")
		await button("设置")
		await escape_panel()
		check(SceneRouter.get_current_key()=="home","settings Escape saves and returns campus")
		await wait_ui()
		samples.append({"cycle":cycle,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			"staticBytes":Performance.get_monitor(Performance.MEMORY_STATIC),
			"textureBytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)})
		if cycle in [0,11]: await shot("stability_campus_%02d"%cycle)
	var end_save := SaveService.snapshot()
	for field: String in ["currencies","stages","characters","inventory"]:
		check(end_save.get(field,{})==baseline.get(field,{}),"navigation stress does not change "+field)
	var warm: Dictionary = samples[2]
	var last: Dictionary = samples[-1]
	check(int(last.nodes)<=int(warm.nodes)+2,"scene nodes do not accumulate after warmup")
	check(int(last.resources)<=int(warm.resources)+5,"resources remain bounded after warmup")
	check(int(last.textureBytes)<=int(warm.textureBytes)+1024*1024,"texture memory remains bounded after warmup")
	var ok := checks.all(func(c: Dictionary)->bool:return c.ok)
	var file := FileAccess.open("user://stability_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks,"samples":samples,"fixture":"isolated earned save copy; source Windows viewport automation; no battle simulation"},"\t"))
	file.close()
	if ok: App.request_quit()
	else: get_tree().quit(2)

func escape_panel() -> void:
	for pressed: bool in [true,false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = pressed
		get_viewport().push_input(key,true)
	await wait_ui()
