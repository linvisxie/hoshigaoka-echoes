extends CampusScreen

static var selected_id := ""
static var feedback := ""
static var expanded_slots := {"WEAPON": true, "ACCESSORY": false, "MEMENTO": false}
static var save_generation := -1
static var return_key := "home"
var confirmation: Panel
var preview_panel: Panel

func _ready() -> void:
	super._ready()
	set_background("bg_env_classroom_battle")
	var save := SaveService.get_current()
	if save_generation != SaveService.save_generation():
		selected_id = ""
		feedback = ""
		expanded_slots = {"WEAPON": true, "ACCESSORY": false, "MEMENTO": false}
		save_generation = SaveService.save_generation()
	var origin := SceneRouter.entry_origin()
	if origin in ["home","character","character_equipment"]:
		return_key = origin
	var currency: Dictionary = save.get("currencies", {})
	page_heading("装备背包", "学园币 %d    /    装备零件 %d    /    待领取装备 %d" % [int(currency.get("school_coin", 0)), int(currency.get("equipment_part", 0)), EquipmentService.pending_equipment_entitlements().size()])
	panel(Rect2(70, 210, 700, 710))
	label_at("持有装备", Rect2(110, 240, 590, 65), 36, GOLD)
	var items := EquipmentService.all_instances()
	if items.is_empty() and origin != "equipment":
		expanded_slots = {"WEAPON":false,"ACCESSORY":false,"MEMENTO":false}
	if EquipmentService.find_instance(save, selected_id).is_empty():
		selected_id = "" if items.is_empty() else str(items[0].get("instanceId", ""))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(110,335)
	scroll.size = Vector2(620,460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	canvas.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",12)
	scroll.add_child(list)
	for slot: String in EquipmentService.VALID_SLOTS:
		var category: Array = items.filter(func(item: Dictionary) -> bool: return str(EquipmentService.template_of(str(item.get("equipmentId",""))).get("slot","")) == slot)
		var heading := button_at(("▾ " if expanded_slots[slot] else "▸ ") + EquipmentService.slot_name(slot),Rect2(),func() -> void:
			expanded_slots[slot] = not expanded_slots[slot]
			SceneRouter.go_to("equipment"))
		heading.reparent(list)
		heading.custom_minimum_size = Vector2(590,60)
		if not expanded_slots[slot]: continue
		if category.is_empty():
			var hint := Label.new()
			hint.text = GameLocale.text("尚未获得" + EquipmentService.slot_name(slot))
			hint.custom_minimum_size = Vector2(590, 48)
			hint.add_theme_font_size_override("font_size", 24)
			hint.add_theme_color_override("font_color", MUTED)
			list.add_child(hint)
		for item: Dictionary in category:
			var template := EquipmentService.template_of(str(item.get("equipmentId", "")))
			var instance_id := str(item.get("instanceId", ""))
			var item_button := button_at("%s  +%d" % [template.get("name", "装备"), int(item.get("enhanceLevel", 0))], Rect2(), func() -> void:
				selected_id = instance_id
				SceneRouter.go_to("equipment"), instance_id == selected_id)
			item_button.icon = ArtRegistry.icon(EquipmentService.slot_icon(slot),32)
			item_button.expand_icon = true
			item_button.add_theme_constant_override("icon_max_width",32)
			item_button.reparent(list)
			item_button.custom_minimum_size = Vector2(590,70)
			var owner_id := str(item.get("boundCharacterId", ""))
			item_button.tooltip_text = GameLocale.text(EquipmentService.slot_name(slot) + " · " + EquipmentService.quality_name(str(template.get("quality", ""))) + (" · 未装备" if owner_id.is_empty() else " · " + str(DataRegistry.get_entry("characters",owner_id).get("name",owner_id))))
	var claim := button_at("领取全部装备奖励", Rect2(110, 820, 610, 65), _claim)
	claim.disabled = EquipmentService.pending_equipment_entitlements().is_empty()
	claim.tooltip_text = GameLocale.text("完成关卡获得的装备会在此领取。" if claim.disabled else "领取已获得的全部装备奖励。")
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
		label_at(lines, Rect2(870, 340, 850, 200), 27)
		label_at("当前装备：%s" % (DataRegistry.get_entry("characters", bound).get("name", bound) if not bound.is_empty() else "未装备"),Rect2(870,535,850,40),25,BLUE)
		var offset := 0
		for cfg: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
			var cid := str(cfg.get("id", ""))
			if not CampaignFlow.character_unlocked(cid) or not EquipmentService.can_equip(str(inst.get("equipmentId", "")), cid):
				continue
			var equip_button := button_at("装备给" + str(DataRegistry.get_entry("characters", cid).get("name", cid)), Rect2(870 + (offset % 3) * 300, 585 + int(offset / 3) * 74, 280, 65), func() -> void: _preview("equip",cid))
			equip_button.disabled = bound == cid
			equip_button.tooltip_text = GameLocale.text("已装备给这名角色" if bound == cid else "替换同槽位装备；旧装备保留在背包，强化等级不变。")
			offset += 1
		var cost := EquipmentService.enhancement_cost_at(int(inst.get("enhanceLevel", 0)))
		var permanent := not EquipmentService.can_enhance_template(str(inst.get("equipmentId", "")))
		label_at("章节纪念 · 不可强化或分解" if permanent else "下次强化：学园币 %d · 零件 %d" % [int(cost.get("school_coin", 0)), int(cost.get("equipment_part", 0))], Rect2(870, 735, 880, 40), 25, MUTED)
		var enhance := button_at("强化 +1", Rect2(870, 780, 260, 65), func() -> void: _preview("enhance"), true)
		enhance.disabled = permanent or cost.is_empty()
		enhance.tooltip_text = GameLocale.text("已达到强化上限" if cost.is_empty() else ("学园币或装备零件不足，可通过关卡奖励获取。" if enhance.disabled else "消耗上方显示的资源，提升装备属性。"))
		var unequip := button_at("卸下", Rect2(1160, 780, 260, 65), func() -> void:
			_preview("unequip"))
		unequip.disabled = bound.is_empty()
		var reset := button_at("重置 / 分解", Rect2(1450, 780, 330, 65), _confirm)
		reset.disabled = bool(template.get("unique",false))
		reset.tooltip_text = GameLocale.text("章节纪念物永久保留" if reset.disabled else "查看重置强化与分解选项")
	else:
		label_at("装备档案", Rect2(870, 245, 900, 70), 38, GOLD)
		label_at("背包中还没有装备", Rect2(870, 380, 900, 60), 32, BLUE)
		var has_rewards := not EquipmentService.pending_equipment_entitlements().is_empty()
		label_at("调查带回的奖励正在等待领取。\n点击左下方「领取全部装备奖励」，查看它们的属性。" if has_rewards else "完成调查可获得装备奖励，在左下方领取。\n武器、饰品与校园纪念物各有独立的装备槽位。\n每名角色每种类型最多装备一件。", Rect2(870, 465, 900, 230), 27, MUTED)
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

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and confirmation!=null and confirmation.visible:
		confirmation.hide()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_key_input(event)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if is_instance_valid(preview_panel) and preview_panel.visible:
			preview_panel.hide()
		elif is_instance_valid(confirmation) and confirmation.visible:
			confirmation.hide()
		else:
			SceneRouter.go_to.call_deferred(return_key)

func _preview(operation: String,cid: String = "") -> void:
	var save := SaveService.snapshot()
	var instance_id := selected_id
	var preview := EquipmentService.preview_operation(save,instance_id,operation,cid)
	if preview.is_empty(): return
	if is_instance_valid(preview_panel): preview_panel.queue_free()
	preview_panel = modal_panel(Rect2(280,185,1360,720))
	preview_panel.name = "EquipmentPreview"
	_preview_label({"equip":"换装预览","unequip":"卸下预览","enhance":"强化预览"}[operation],Rect2(40,25,1280,60),36,GOLD)
	var inst := EquipmentService.find_instance(save,instance_id)
	var title := str(EquipmentService.template_of(str(inst.get("equipmentId",""))).get("name","装备"))
	var level := int(inst.get("enhanceLevel",0))
	_preview_label(title + ("  +%d → +%d" % [level,level+1] if operation=="enhance" else "  +%d" % level),Rect2(40,88,1280,42),25,MUTED)
	var columns := 0
	for character_id: String in preview.changes:
		var base := {}
		if App.growth != null and App.growth.is_ready():
			var p: CharacterProgress = App.growth.get_progress(character_id)
			if p != null: base = p.compute_stats()
		var delta: Dictionary = preview.changes[character_id]
		var name := str(DataRegistry.get_entry("characters",character_id).get("name",character_id))
		_preview_label(name,Rect2(40+columns*650,142,620,45),28,BLUE)
		_preview_label(_stat_changes(base,delta.before,delta.after),Rect2(40+columns*650,195,620,240),25)
		columns += 1
	if columns==0:
		_preview_label("装备属性",Rect2(40,142,1280,45),28,BLUE)
		_preview_label(_stat_changes({},preview.equipmentBefore,preview.equipmentAfter),Rect2(40,195,1280,240),25)
	var details := "换装不消耗资源，旧装备保留在背包。"
	if operation=="unequip": details = "卸下不消耗资源，装备与强化等级保留。"
	if operation=="enhance":
		details = "消耗：学园币 %d · 装备零件 %d\n剩余：学园币 %d · 装备零件 %d" % [int(preview.cost.get("school_coin",0)),int(preview.cost.get("equipment_part",0)),int(preview.remaining.get("school_coin",0)),int(preview.remaining.get("equipment_part",0))]
		if not preview.affordable: details += "\n资源不足，无法确认强化。"
	_preview_label(details,Rect2(40,460,1280,112),25,MUTED)
	var confirm := button_at("确认操作",Rect2(0,0,420,70),func() -> void:
		if SaveService.snapshot()!=save:
			preview_panel.hide()
			feedback = "状态已变化，请重新查看预览。"
			SceneRouter.go_to("equipment")
			return
		if operation=="equip": _result(EquipmentService.equip(cid,instance_id))
		elif operation=="enhance": _result(EquipmentService.enhance(instance_id))
		else:
			var current_item := EquipmentService.find_instance(save,instance_id)
			_result(EquipmentService.unequip(str(current_item.get("boundCharacterId","")),str(EquipmentService.template_of(str(current_item.get("equipmentId",""))).get("slot","")))),true)
	confirm.disabled = not bool(preview.affordable)
	confirm.reparent(preview_panel)
	confirm.position = Vector2(880,610)
	var cancel := button_at("取消",Rect2(0,0,420,70),func() -> void: preview_panel.hide())
	cancel.reparent(preview_panel)
	cancel.position = Vector2(40,610)

func _preview_label(value: String,rect: Rect2,font_size: int,color: Color = WHITE) -> Label:
	var label := label_at(value,rect,font_size,color)
	label.reparent(preview_panel)
	label.position = rect.position
	return label

func _stat_changes(base: Dictionary,before: Dictionary,after: Dictionary) -> String:
	var lines: Array[String] = []
	for key: String in ["hp","attack","defense","healPower","attackSpeed","cdRecovery"]:
		if not base.has(key) and not before.has(key) and not after.has(key): continue
		var a := float(base.get(key,0))+float(before.get(key,0))
		var b := float(base.get(key,0))+float(after.get(key,0))
		var caption: String = {"hp":"生命","attack":"攻击","defense":"防御","healPower":"治疗力","attackSpeed":"攻击速度加成","cdRecovery":"冷却恢复加成"}[key]
		var percent := key in ["attackSpeed","cdRecovery"]
		var values := "%.1f%% → %.1f%% (%+.1f%%)" % [a*100,b*100,(b-a)*100] if percent else "%d → %d (%+d)" % [int(a),int(b),int(b-a)]
		lines.append(GameLocale.text(caption)+"  "+values)
	return "\n".join(lines)
