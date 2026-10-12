extends CampusScreen

func _ready() -> void:
	super._ready()
	var cid := CampaignFlow.inspected_character_id
	var cfg := DataRegistry.get_entry("characters", cid)
	page_heading(str(cfg.get("name", cid)) + " · 角色装备", "武器、饰品、校园纪念物各一件 · 换装保留强化等级")
	set_background("bg_env_corridor_battle")
	texture_at(ArtRegistry.character_story(cid), Rect2(100,180,650,760))
	panel(Rect2(810,210,1030,710))
	label_at("装备面板",Rect2(860,240,900,60),36,GOLD)
	var equipped := EquipmentService.equipped_of(SaveService.get_current(),cid)
	for i: int in range(EquipmentService.VALID_SLOTS.size()):
		var slot: String = EquipmentService.VALID_SLOTS[i]
		var y := 340 + i * 150
		panel(Rect2(860,y,930,130))
		texture_at(ArtRegistry.icon(EquipmentService.slot_icon(slot),64),Rect2(885,y+22,44,44))
		label_at(EquipmentService.slot_name(slot),Rect2(950,y+12,700,40),26,BLUE)
		var inst := EquipmentService.find_instance(SaveService.get_current(),str(equipped.get(slot,"")))
		var title := "尚未装备 · 在背包中选择" if inst.is_empty() else "%s  +%d" % [EquipmentService.template_of(str(inst.get("equipmentId",""))).get("name","装备"),int(inst.get("enhanceLevel",0))]
		label_at(title,Rect2(950,y+60,720,50),29,WHITE)
	button_at("装备背包",Rect2(1440,835,350,60),func() -> void: SceneRouter.go_to("equipment"),true)
	button_at("返回培养",Rect2(90,970,360,75),func() -> void: SceneRouter.go_to("character"))
	button_at("返回校园",Rect2(1430,970,410,75),func() -> void: SceneRouter.go_to("home"))
