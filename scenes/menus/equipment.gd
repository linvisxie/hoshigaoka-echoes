extends CampusScreen

static var selected_id := ""
static var feedback := ""
var confirmation: Panel

func _ready() -> void:
	super._ready()
	set_background("bg_env_classroom_battle")
	var save := SaveService.get_current()
	var currency: Dictionary = save.get("currencies", {})
	page_heading("装备背包", "学园币 %d    /    装备零件 %d    /    待领取装备 %d" % [int(currency.get("school_coin", 0)), int(currency.get("equipment_part", 0)), EquipmentService.pending_equipment_entitlements().size()])
	panel(Rect2(70, 210, 700, 710))
	label_at("持有装备", Rect2(110, 240, 590, 65), 36, GOLD)
	var items := EquipmentService.all_instances()
	if selected_id.is_empty() and not items.is_empty():
		selected_id = str(items[0].get("instanceId", ""))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(110,335)
	scroll.size = Vector2(620,460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	canvas.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",12)
	scroll.add_child(list)
	for i: int in range(items.size()):
		var item: Dictionary = items[i]
		var template := EquipmentService.template_of(str(item.get("equipmentId", "")))
		var instance_id := str(item.get("instanceId", ""))
		var item_button := button_at("%s  +%d" % [template.get("name", "装备"), int(item.get("enhanceLevel", 0))], Rect2(110, 335 + i * 84, 610, 68), func() -> void:
			selected_id = instance_id
			SceneRouter.go_to("equipment"), instance_id == selected_id)
		item_button.reparent(list)
		item_button.custom_minimum_size = Vector2(590,76)
		var owner_id := str(item.get("boundCharacterId", ""))
		item_button.tooltip_text = EquipmentService.quality_name(str(template.get("quality", ""))) + (" · 未装备" if owner_id.is_empty() else " · " + str(DataRegistry.get_entry("characters",owner_id).get("name",owner_id)))
	if items.is_empty():
		label_at("背包中还没有装备。\n完成调查后，可在这里领取奖励。", Rect2(110, 350, 600, 180), 28, MUTED)
	var claim := button_at("领取全部装备奖励", Rect2(110, 820, 610, 65), _claim)
	claim.disabled = EquipmentService.pending_equipment_entitlements().is_empty()
	claim.tooltip_text = "完成关卡获得的装备会在此领取。" if claim.disabled else "领取已获得的全部装备奖励。"
	panel(Rect2(820, 210, 1020, 710))
	var inst := EquipmentService.find_instance(save, selected_id)
	if not inst.is_empty():
		var template := EquipmentService.template_of(str(inst.get("equipmentId", "")))
		label_at("%s  +%d" % [template.get("name", "装备"), int(inst.get("enhanceLevel", 0))], Rect2(870, 245, 900, 70), 38, GOLD)
		var lines := EquipmentService.quality_name(str(template.get("quality", ""))) + "  /  固定词条\n"
		var bonus := EquipmentService.stat_bonus_of(inst)
		for key: String in bonus:
			var names := {"hp": "生命", "attack": "攻击", "defense": "防御", "healPower": "治疗力", "attackSpeed": "攻击速度", "cdRecovery": "冷却恢复"}
			lines += "%s  +%s\n" % [names.get(key, key), ("%.0f%%" % (float(bonus[key]) * 100.0)) if key in ["attackSpeed", "cdRecovery"] else str(int(bonus[key]))]
		var bound := str(inst.get("boundCharacterId", ""))
		lines += "\n当前装备：%s" % (DataRegistry.get_entry("characters", bound).get("name", bound) if not bound.is_empty() else "未装备")
		label_at(lines, Rect2(870, 340, 850, 240), 29)
		var offset := 0
		for cid: String in ["amamiya_mio", "kamiya_yuma"]:
			if not CampaignFlow.character_unlocked(cid):
				continue
			var equip_button := button_at("装备给" + str(DataRegistry.get_entry("characters", cid).get("name", cid)), Rect2(870 + offset * 430, 610, 400, 65), func() -> void: _result(EquipmentService.equip(cid, selected_id)))
			equip_button.disabled = bound == cid
			equip_button.tooltip_text = "已装备给这名角色" if bound == cid else "替换同槽位装备；旧装备保留在背包，强化等级不变。"
			offset += 1
		var cost := EquipmentService.enhancement_cost_at(int(inst.get("enhanceLevel", 0)))
		label_at("下次强化：学园币 %d · 零件 %d" % [int(cost.get("school_coin", 0)), int(cost.get("equipment_part", 0))], Rect2(870, 710, 880, 45), 25, MUTED)
		var enhance := button_at("强化 +1", Rect2(870, 780, 260, 65), func() -> void: _result(EquipmentService.enhance(selected_id)), true)
		enhance.disabled = cost.is_empty() or int(currency.get("school_coin",0)) < int(cost.get("school_coin",0)) or int(currency.get("equipment_part",0)) < int(cost.get("equipment_part",0))
		enhance.tooltip_text = "已达到强化上限" if cost.is_empty() else ("学园币或装备零件不足，可通过关卡奖励获取。" if enhance.disabled else "消耗上方显示的资源，提升装备属性。")
		var unequip := button_at("卸下", Rect2(1160, 780, 260, 65), func() -> void:
			_result(EquipmentService.unequip(bound, str(template.get("slot", "")))))
		unequip.disabled = bound.is_empty()
		button_at("重置 / 分解", Rect2(1450, 780, 330, 65), _confirm)
	label_at(feedback, Rect2(100, 928, 1700, 40), 24, BLUE)
	button_at("返回角色", Rect2(90, 980, 360, 70), func() -> void: SceneRouter.go_to("character"))
	button_at("返回校园", Rect2(1430, 980, 410, 70), func() -> void: SceneRouter.go_to("home"))

func _claim() -> void:
	var result := EquipmentService.fulfill_all_equipment()
	feedback = "领取 %d 件装备" % result.get("fulfilled", []).size() if bool(result.get("ok", false)) else "领取失败，请检查存档。"
	SceneRouter.go_to("equipment")

func _result(result: EquipmentService.OpResult) -> void:
	feedback = result.reason
	AudioService.play_sfx("upgrade" if result.ok else "select")
	SceneRouter.go_to("equipment")

func _confirm() -> void:
	if confirmation != null:
		confirmation.show()
		return
	confirmation = modal_panel(Rect2(380, 290, 1160, 500))
	var text := label_at("重置：保留装备，返还累计强化投入的80%。\n分解：永久销毁装备，只回收基础零件。\n直接分解会放弃强化投入。", Rect2(430, 335, 1030, 180), 30)
	text.reparent(confirmation)
	text.position = Vector2(50, 45)
	for spec: Array in [["仅重置强化", 50, func() -> void: _result(EquipmentService.reset_enhancement(selected_id))], ["直接分解", 410, func() -> void: _result(EquipmentService.dismantle(selected_id, true))], ["取消", 770, func() -> void: confirmation.hide()]]:
		var button := button_at(str(spec[0]), Rect2(0, 0, 320, 70), spec[2])
		button.reparent(confirmation)
		button.position = Vector2(int(spec[1]), 350)
