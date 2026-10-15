## Native offer/result presentation. Existing battle methods remain the sole action owners.
class_name BattleOverlays
extends Control

var hud: Node
var battle: Node
var layer: Control
var signature := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func sync(viewport: Vector2, factor: float) -> void:
	var mode := ""
	if battle._upgrade_panel_active():
		mode = "offer:" + JSON.stringify(battle._upgrade_card_views) + str(battle.session.stage.pending_offer.get("rerollsRemaining",0))
	elif battle.session.is_decided() and battle._result_animation_time >= (2.8 if battle.session.outcome == BattleTypes.Outcome.VICTORY else 0.75):
		mode = "result:" + JSON.stringify(battle._reward_summary)
	mode += str(viewport) if not mode.is_empty() else ""
	if mode == signature:
		return
	signature = mode
	if layer != null:
		remove_child(layer)
		layer.queue_free()
		layer = null
	if mode.is_empty():
		return
	layer = Control.new()
	layer.size = viewport
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.015,0.025,0.065,0.82)
	dim.size = viewport
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	if mode.begins_with("offer:"):
		_build_offer(viewport,factor)
	else:
		_build_result(viewport,factor)
	layer.modulate.a = 0
	create_tween().tween_property(layer,"modulate:a",1.0,0.20)

func text(parent: Node, value: String, rect: Rect2, font_size: int = 26, color: Color = GameSkin.WHITE, centered: bool = false) -> Label:
	var l: Label = hud._label(parent,value,rect,font_size,color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func heading(parent: Node, value: String, rect: Rect2, font_size: int, color: Color = GameSkin.GOLD, centered: bool = false) -> Label:
	var l := text(parent,value,rect,font_size,color,centered)
	l.add_theme_font_override("font",GameSkin.serif())
	return l

func unscale(rect: Rect2, factor: float) -> Rect2:
	return Rect2(rect.position/factor,rect.size/factor)

func _build_offer(viewport: Vector2, factor: float) -> void:
	battle._layout_upgrade_cards()
	heading(layer,"残响强化",Rect2(0,38,viewport.x,64),44,GameSkin.GOLD,true)
	var subtitle := "首次教学 · 选择一项强化，立即生效 · 仅本局有效" if battle._upgrade_is_tutorial else "选择一项，让残响成为你的力量 · 仅本局有效"
	text(layer,subtitle,Rect2(0,107,viewport.x,42),24,GameSkin.BLUE if battle._upgrade_is_tutorial else GameSkin.MUTED,true)
	for i: int in range(battle._upgrade_card_views.size()):
		var view: Dictionary = battle._upgrade_card_views[i]
		var rect := unscale(battle._upgrade_card_rects[i],factor)
		var card: Button = hud._button(layer,"",rect,func() -> void: battle._choose_upgrade_index(i))
		card.name = "UpgradeChoice%d" % i
		var tier := str(view.get("tier","COMMON"))
		var accent := GameSkin.GOLD if tier == "CORE" else (GameSkin.BLUE if tier == "ADVANCED" else Color("a8b7d8"))
		card.add_theme_stylebox_override("normal",GameSkin.glass(accent,.94))
		var category := str(view.get("category","残响强化"))
		text(card,category,Rect2(24,12,220,34),21,accent)
		text(card,str({"COMMON":"普通","ADVANCED":"进阶","CORE":"核心"}.get(tier,"强化")),Rect2(302,12,75,34),19,accent,true)
		text(card,str(i+1),Rect2(24,65,40,38),24,GameSkin.MUTED,true)
		hud._texture(card,ArtRegistry.icon(battle._upgrade_icon_name(view),64),Rect2(156,65,88,88))
		heading(card,str(view.get("name","强化")),Rect2(22,169,rect.size.x-44,58),31,GameSkin.WHITE,true)
		text(card,battle._upgrade_effect_text(view),Rect2(22,228,rect.size.x-44,54),28,GameSkin.GOLD,true)
		var guidance := str(view.get("guidance",""))
		if guidance.is_empty():
			guidance = str(view.get("description",""))
		text(card,guidance,Rect2(28,292,rect.size.x-56,105),23,GameSkin.MUTED,true)
		var maximum := int(view.get("maxStacks",1))
		var stack := "不可叠加" if maximum<=1 else "叠加 %d / %d" % [int(view.get("stacks",0)),maximum]
		text(card,"%s · %s" % [battle._upgrade_target_text(view),stack],Rect2(20,408,rect.size.x-40,36),21,GameSkin.BLUE,true)
		card.tooltip_text = GameLocale.text("点击或按 %d 选择，立即生效。" % (i+1))
	var rerolls := int(battle.session.stage.pending_offer.get("rerollsRemaining",0))
	var reroll: Button = hud._button(layer,"重掷（R） · %d" % rerolls,unscale(battle._upgrade_reroll_rect,factor),func() -> void: battle._reroll_upgrade())
	reroll.disabled = rerolls<=0
	reroll.tooltip_text = GameLocale.text("本次剩余重掷次数：%d" % rerolls)
	hud._button(layer,"跳过（S）",unscale(battle._upgrade_skip_rect,factor),func() -> void: battle._skip_upgrade())
	var gained: Array = battle.session.stage.upgrade_summary()
	var names: Array[String] = []
	for item: Dictionary in gained:
		names.append("%s ×%d" % [item.get("name",""),int(item.get("stacks",1))])
	text(layer,"本局构筑  /  " + ("尚未获得强化" if names.is_empty() else "   ·   ".join(names)),Rect2(260,viewport.y-160,viewport.x-520,95),22,GameSkin.MUTED,true)

func _build_result(viewport: Vector2, factor: float) -> void:
	var summary: Dictionary = battle.session.result_summary()
	var victory := bool(summary.get("victory",false))
	var accent := GameSkin.GOLD if victory else GameSkin.RED
	var rect := unscale(battle._result_panel_rect(summary),factor)
	var p: Panel = hud._panel(layer,rect,accent)
	hud._texture(p,GameSkin.crest(),Rect2(48,34,68,84))
	heading(p,"残响平息" if victory else "锚点失守",Rect2(143,28,730,70),48,accent)
	var saved := "调查记录已保存" if bool(battle._reward_summary.get("ok",false)) else "结算状态：" + str(battle._reward_summary.get("reason","没有奖励"))
	text(p,battle._stage_display_name()+"  ·  "+saved,Rect2(146,104,1100,42),23,GameSkin.MUTED)
	var stats: Array = [["核心防线","%d / %d" % [summary["coreHp"],summary["coreHpMax"]]],["击退残响",str(summary["kills"])],["突破防线",str(summary["leaked"])],["角色失能",str(summary["lost"])],["战斗用时","%02d:%02d" % [int(summary["elapsed"])/60,int(summary["elapsed"])%60]],["完成波次","%d / %d" % [summary["wave"],summary["waveTotal"]]]]
	for i: int in range(stats.size()):
		var x := 55+float(i%3)*225
		var y := 190+float(i/3)*110
		text(p,stats[i][0],Rect2(x,y,215,35),22,GameSkin.MUTED)
		text(p,stats[i][1],Rect2(x,y+37,215,57),38)
	var reward: Panel = hud._panel(p,Rect2(790,186,472,376),accent)
	heading(reward,"本次奖励" if victory else "重新整备",Rect2(28,20,410,48),29,accent)
	var scroll := ScrollContainer.new()
	scroll.name = "ResultRewards"
	scroll.position = Vector2(24,82)
	scroll.size = Vector2(424,268)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	reward.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",6)
	scroll.add_child(rows)
	# Newly registered items come first so they are visible without scrolling.
	for item: Dictionary in equipment_rewards(battle._reward_summary):
		var row := Control.new()
		row.custom_minimum_size = Vector2(400,100)
		rows.add_child(row)
		var icon_view: TextureRect = hud._texture(row,ArtRegistry.icon(str(item.icon),32),Rect2(0,8,36,36))
		icon_view.name = "RewardEquipmentIcon"
		text(row,GameLocale.text(str(item.name))+" ×%d"%int(item.count),Rect2(46,0,350,66),22,GameSkin.BLUE)
		text(row,"前往装备背包领取",Rect2(46,66,350,30),19,GameSkin.MUTED)
	var granted: Dictionary = battle._reward_summary.get("granted",{})
	for currency: String in granted:
		var line := text(rows,"%s    +%d" % [battle._currency_display_name(currency),int(granted[currency])],Rect2(),24,GameSkin.GREEN)
		line.custom_minimum_size = Vector2(400,44)
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
	if granted.is_empty() and equipment_rewards(battle._reward_summary).is_empty():
		var note := text(rows,"失败不扣除已有资源" if not victory else str(battle._reward_summary.get("reason","本次没有奖励")),Rect2(),24,GameSkin.MUTED)
		note.custom_minimum_size = Vector2(400,166)
	heading(p,"本局构筑",Rect2(55,443,690,46),28,GameSkin.BLUE)
	var gained: Array = battle.session.stage.upgrade_summary()
	var names: Array[String] = []
	for item: Dictionary in gained:
		names.append("%s ×%d" % [item.get("name",""),int(item.get("stacks",1))])
	text(p,"未获得强化" if names.is_empty() else "   ·   ".join(names),Rect2(55,491,682,85),23,GameSkin.MUTED)
	var review: Array = battle._build_review_lines(summary)
	var localized_review: Array[String] = []
	for line: String in review.slice(0,3): localized_review.append(GameLocale.text(line))
	text(p,"\n".join(localized_review),Rect2(55,590,1210,125),23,GameSkin.MUTED)
	hud._button(layer,"重新挑战",unscale(battle._relaunch_rect,factor),func() -> void: battle._handle_result_click(battle._relaunch_rect.get_center()))
	var next := "返回关卡"
	if bool(CampaignFlow.state().get("campaign_active",false)):
		next = "继续剧情" if victory and not str(CampaignFlow.state().get("pending_story_after","")).is_empty() else "返回校园"
	hud._button(layer,next,unscale(battle._quit_rect,factor),func() -> void: battle._handle_result_click(battle._quit_rect.get_center()),true)

## Presentation reads only this settlement's new entitlements, never the account's pending list.
static func equipment_rewards(summary: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not bool(summary.get("ok",false)): return rows
	var seen := {}
	var by_item := {}
	for entitlement: Dictionary in summary.get("pendingRegistered",[]):
		if str(entitlement.get("kind","")) not in ["EQUIPMENT","MEMENTO"]: continue
		var id := str(entitlement.get("itemId",""))
		var token := str(entitlement.get("entitlementId",""))
		if not token.is_empty() and seen.has(token): continue
		seen[token] = true
		var template := EquipmentService.template_of(id)
		if template.is_empty(): continue
		if by_item.has(id):
			rows[int(by_item[id])].count += 1
		else:
			by_item[id] = rows.size()
			rows.append({"id":id,"name":str(template.get("name",id)),"icon":EquipmentService.slot_icon(str(template.get("slot",""))),"count":1})
	return rows
