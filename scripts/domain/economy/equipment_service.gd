## EquipmentService — 装备系统（Alpha A0.5）。
##
## 职责（L3 Application 层）：
##   把「装备固定模板」变成「玩家背包里的装备实例」，并提供：
##     ① **权益兑现**：把 A0.4 登记的待领取权益（pending entitlement）兑现为真实装备实例；
##     ② 背包读写：实例的持有、装配、卸下；
##     ③ 强化：+0 → +10，成功率 100%，消耗装备零件 + 学园币；
##     ④ 重置强化：等级归零，返还累计实际投入的 80%（向下取整，不可超过累计投入）；
##     ⑤ 分解：销毁实例并回收模板规定的基础零件（不返还强化投入）。
##
## ── 为什么必须复用 A0.4 的待领取权益体系（不可另建）──
## 首通只有一次。A0.4 已把「首通应得的装备」登记为待领取权益（`SaveGame.entitlements`），
## 并在结算时与 firstClearClaimed 同事务写入——这正是为了防止「装备系统还没做，
## 玩家首通 1-9 后那件稀有饰品永久拿不到」这一**不可逆的奖励损失**。
##
## 因此 A0.5 **不重建** SaveService / 奖励结算 / 背包基础设施，而是：
##   消费 `StageRewardService.pending_entitlements()` → 用 `fulfill_entitlement()` 兑现，
##   并把「创建实例」与「权益兑现」放在**同一次 commit** 里，保证原子性。
##
## ── 规格纪律（V2.1.4）──
##   - L1597（LOCKED）：固定模板 + 固定词条数值，**不随机抽取、不随机浮动**。
##     本文件与 equipment.json / equipment_affixes.json 中**不存在任何随机数调用**。
##   - L1598：equipmentId = 模板 ID，instanceId = 背包内独立持有实例 ID；
##     同一模板可持有多件实例。
##   - L1611：每次处理按唯一 instanceId **原子提交**，重复点击/崩溃重试不重复发奖。
##
## 数值来源：**唯一来自** data/equipment.json、data/equipment_affixes.json、
## data/upgrade_costs.json。本文件不出现任何数值常量。
class_name EquipmentService
extends RefCounted

const TAG := "Equipment"

## 存档中承载背包的顶层键（SaveService.build_default_save() 已预留为 {}）。
const INVENTORY_KEY := "inventory"
## 背包内的装备实例列表键
const ITEMS_KEY := "equipmentInstances"
## 角色装配映射所在的位置：SaveGame.characters[charId].equipment
const CHARACTERS_KEY := "characters"
const EQUIP_SLOT_KEY := "equipment"

## 装备槽位（V2.1.4 表 63：每名角色三个槽位）
const SLOT_WEAPON := "WEAPON"
const SLOT_ACCESSORY := "ACCESSORY"
const SLOT_MEMENTO := "MEMENTO"
const VALID_SLOTS: Array[String] = [SLOT_WEAPON, SLOT_ACCESSORY, SLOT_MEMENTO]

## 品质（V2.1.4 表 64 四档）
const QUALITY_NAMES := {
	"COMMON": "普通",
	"FINE": "优秀",
	"RARE": "稀有",
	"EPIC": "史诗",
}


## 操作结果（统一的成功/失败 + 原因，供 UI 与测试断言）
class OpResult:
	extends RefCounted
	var ok: bool = false
	var reason: String = ""
	## 本次涉及的装备实例 ID
	var instance_id: String = ""
	## 本次实际消耗的资源 { currencyId: amount }
	var cost: Dictionary = {}
	## 本次实际返还的资源 { currencyId: amount }
	var refund: Dictionary = {}

	func _init(ok_value: bool = false, reason_value: String = "") -> void:
		ok = ok_value
		reason = reason_value


# ============================================================
#  模板查询（只读；数值全部来自数据文件）
# ============================================================

## 取一个装备模板；不存在返回空字典
static func template_of(equipment_id: String) -> Dictionary:
	if equipment_id.is_empty():
		return {}
	for t: Dictionary in DataRegistry.get_domain("equipment").get("equipment", []):
		if str(t.get("id", "")) == equipment_id:
			return t
	return {}


## 取一个词条定义；不存在返回空字典
static func affix_of(affix_id: String) -> Dictionary:
	if affix_id.is_empty():
		return {}
	for a: Dictionary in DataRegistry.get_domain("equipment_affixes").get("affixes", []):
		if str(a.get("id", "")) == affix_id:
			return a
	return {}


## 模板的品质显示名
static func quality_name(quality: String) -> String:
	return str(QUALITY_NAMES.get(quality, quality))


## 全部装备模板（供图鉴/调试）
static func all_templates() -> Array:
	return DataRegistry.get_domain("equipment").get("equipment", [])


## 强化成本配置（来自 upgrade_costs.json 的 equipment 段）
static func enhancement_costs() -> Dictionary:
	return DataRegistry.get_domain("upgrade_costs").get("upgradeCosts", {})


## 从 fromLevel 强化到 fromLevel+1 的成本；不存在返回空字典
static func enhancement_cost_at(from_level: int) -> Dictionary:
	for row: Dictionary in enhancement_costs().get("equipment", []):
		if int(row.get("fromLevel", -1)) == from_level:
			return row
	return {}


## 强化等级上限（V2.1.4 L1604：+10）
static func enhancement_max_level() -> int:
	return int(enhancement_costs().get("equipmentMaxLevel", 0))


## 重置强化的返还比例（V2.1.4 L1610：80%，向下取整）
static func reset_refund_rate() -> float:
	return float(enhancement_costs().get("equipmentResetRefundRate", 0.0))


## 某模板能否强化（V2.1.4 L1604：只有武器与饰品可强化；纪念物不可）
static func can_enhance_template(equipment_id: String) -> bool:
	var t := template_of(equipment_id)
	if t.is_empty():
		return false
	return str(t.get("slot", "")) != SLOT_MEMENTO and int(t.get("enhanceMax", 0)) > 0


# ============================================================
#  实例化（固定模板 → 背包实例；无随机数）
# ============================================================

## 生成一个装备实例 ID。
##
## 纪律：必须**确定且唯一**，不得使用随机数（L1597 禁止随机；且实例 ID 需可复现以便测试）。
## 形如 `inst_<equipmentId>_<序号>`，序号在背包内递增，保证同一模板可持有多件实例。
static func next_instance_id(save: Dictionary, equipment_id: String) -> String:
	var n := 0
	for inst: Dictionary in _instances_of(save):
		if str(inst.get("equipmentId", "")) == equipment_id:
			n += 1
	return "inst_%s_%d" % [equipment_id, n + 1]


## 按模板创建一个装备实例（**纯函数式**：只返回字典，不写存档）。
##
## 实例字段：
##   instanceId / equipmentId / enhanceLevel / boundCharacterId（0 = 未装备）
## 纪律：不复制模板的数值——数值始终从模板读取，实例只记录「身份 + 强化等级」，
## 避免同一件装备在两处各存一份面板（B6 SSOT）。
static func build_instance(equipment_id: String, instance_id: String) -> Dictionary:
	if template_of(equipment_id).is_empty():
		return {}
	return {
		"instanceId": instance_id,
		"equipmentId": equipment_id,
		"enhanceLevel": 0,
		"boundCharacterId": "",
	}


# ============================================================
#  背包读取
# ============================================================

## 背包中的装备实例列表（读存档；无则空数组）
static func _instances_of(save: Dictionary) -> Array:
	var inv: Dictionary = save.get(INVENTORY_KEY, {})
	var arr: Variant = inv.get(ITEMS_KEY, [])
	if typeof(arr) != TYPE_ARRAY:
		return []
	return arr


## 背包中的全部装备实例（读当前存档）
static func all_instances() -> Array:
	var save := SaveService.get_current()
	if save.is_empty():
		return []
	return _instances_of(save).duplicate(true)


## 按实例 ID 取实例；不存在返回空字典
static func find_instance(save: Dictionary, instance_id: String) -> Dictionary:
	for inst: Dictionary in _instances_of(save):
		if str(inst.get("instanceId", "")) == instance_id:
			return inst
	return {}


## 某角色的三个槽位当前装配的实例 ID。
## 返回 { WEAPON: instanceId, ACCESSORY: instanceId, MEMENTO: instanceId }
static func equipped_of(save: Dictionary, character_id: String) -> Dictionary:
	var out := {}
	var chars: Dictionary = save.get(CHARACTERS_KEY, {})
	var c: Dictionary = chars.get(character_id, {})
	var eq: Variant = c.get(EQUIP_SLOT_KEY, {})
	if typeof(eq) == TYPE_DICTIONARY:
		for slot: String in VALID_SLOTS:
			var v := str((eq as Dictionary).get(slot, ""))
			if not v.is_empty():
				out[slot] = v
	return out


static func bonuses_for_character(save: Dictionary, character_id: String) -> Dictionary:
	var total := {}
	for instance_id: Variant in equipped_of(save, character_id).values():
		var bonus := stat_bonus_of(find_instance(save, str(instance_id)))
		for key: String in bonus:
			total[key] = float(total.get(key, 0.0)) + float(bonus[key])
	return total


## 实例的**最终面板加成**（主属性 + 副属性，含强化加成）。
##
## 返回 { statKey: value, ... }，其中 value 已按 isPercent 标记区分（百分数保持小数）。
## 纪律：数值一律从模板/词条读取后按强化等级缩放，**不在本类写死任何数值**。
static func stat_bonus_of(instance: Dictionary) -> Dictionary:
	var out := {}
	if instance.is_empty():
		return out
	var t := template_of(str(instance.get("equipmentId", "")))
	if t.is_empty():
		return out
	var level := int(instance.get("enhanceLevel", 0))

	# 主属性：每强化 1 级线性增加 base × 10%（第一轮候选口径，需试玩调表）。
	# 说明：规格未给「强化如何提升面板」，故此处为**候选口径**并集中在此一处，
	# 便于后续调表时只改这一个公式。
	var primary: Dictionary = t.get("primaryStat", {})
	if not primary.is_empty():
		var key := str(primary.get("key", ""))
		var base := float(primary.get("value", 0.0))
		if not key.is_empty():
			out[key] = _round_stat(base * (1.0 + 0.1 * float(level)))

	# 副属性：V2.1.4 L1602「词条数值在同品质内部保持窄区间」——固定值，不随强化变化。
	for affix_id: Variant in t.get("affixes", []):
		var a := affix_of(str(affix_id))
		if a.is_empty():
			continue
		var akey := str(a.get("statKey", ""))
		if akey.is_empty():
			continue
		var aval := float(a.get("value", 0.0))
		if bool(a.get("isPercent", false)):
			out[akey] = float(out.get(akey, 0.0)) + aval
		else:
			out[akey] = _round_stat(float(out.get(akey, 0.0)) + aval)
	return out


## 数值取整：非百分比属性取整（与 D-22 伤害公式的取整口径一致）；
## 百分比属性保持浮点。
static func _round_stat(v: float) -> float:
	return float(roundi(v))


# ============================================================
#  权益兑现（复用 A0.4 的待领取权益体系）
# ============================================================

## 把一条待领取权益兑现为真实装备实例。
##
## **原子性纪律**（V2.1.4 L1611 + A0.4 加固）：
##   「创建实例」与「权益移入 fulfilled」必须在**同一次 commit** 内完成，
##   否则会出现「实例已创建但权益仍 pending」→ 下次兑现再发一件（复制装备）。
##   实现方式：先在内存里同时改背包与权益，再 commit 一次；
##   commit 失败则由 SaveService 回滚内存（A0.4 已保证）。
##
## 幂等：权益不在 pending 中（已兑现或从未登记）时直接返回失败，不做任何改动。
static func fulfill(entitlement_id_value: String, commit_now: bool = true) -> OpResult:
	if entitlement_id_value.is_empty():
		return OpResult.new(false, "权益 ID 为空")
	var ent := StageRewardService.find_pending(entitlement_id_value)
	if ent.is_empty():
		return OpResult.new(false, "权益不在待领取列表中（可能已兑现）")

	var kind := str(ent.get("kind", ""))
	if kind != "EQUIPMENT":
		return OpResult.new(false, "该权益类型（%s）不由装备系统兑现" % kind)

	var equipment_id := str(ent.get("itemId", ""))
	if template_of(equipment_id).is_empty():
		return OpResult.new(false, "装备模板不存在：%s" % equipment_id)

	if not SaveService.ensure_loaded():
		return OpResult.new(false, "存档不可用")
	var save := SaveService.get_current()
	if save.is_empty():
		return OpResult.new(false, "存档为空")

	# ① 创建实例（写入内存）
	var instance_id := next_instance_id(save, equipment_id)
	var inst := build_instance(equipment_id, instance_id)
	if inst.is_empty():
		return OpResult.new(false, "实例创建失败")
	_ensure_inventory(save)
	(_instances_of(save) as Array).append(inst)

	# ② 兑现权益（同一内存事务内；commit_now=false 避免二次落盘）
	if not StageRewardService.fulfill_entitlement(entitlement_id_value, instance_id, false):
		# 权益兑现失败 → 回滚刚写入的实例，避免「实例存在但权益未消费」
		_remove_instance_in_memory(save, instance_id)
		return OpResult.new(false, "权益兑现失败（已回滚实例）")

	var r := OpResult.new(true, "已兑现")
	r.instance_id = instance_id
	if commit_now:
		if not SaveService.commit(save):
			return OpResult.new(false, "落盘失败（内存已回滚）")
	GameLog.info(TAG, "权益 %s 已兑现为装备实例 %s（模板 %s）"
		% [entitlement_id_value, instance_id, equipment_id])
	return r


## 一键兑现全部**装备类**待领取权益（供装备界面「领取全部」使用）。
##
## 返回 { fulfilled: Array[String]（instanceId）, skipped: Array[String]（原因）, ok: bool }
static func fulfill_all_equipment(commit_now: bool = true) -> Dictionary:
	var out := {"fulfilled": [], "skipped": [], "ok": true}
	var pendings := StageRewardService.pending_entitlements()
	for ent: Dictionary in pendings:
		if str(ent.get("kind", "")) != "EQUIPMENT":
			continue
		var eid := str(ent.get("entitlementId", ""))
		var r := fulfill(eid, false)   # 逐个改内存，最后一次落盘
		if r.ok:
			out["fulfilled"].append(r.instance_id)
		else:
			out["skipped"].append("%s：%s" % [eid, r.reason])
	if commit_now and not (out["fulfilled"] as Array).is_empty():
		var save := SaveService.get_current()
		if not SaveService.commit(save):
			out["ok"] = false
	return out


# ============================================================
#  装配 / 卸下
# ============================================================

## 把实例装配到角色槽位。槽位由模板的 slot 决定。
##
## 纪律：
##   - 实例必须存在于背包；
##   - 该实例若已绑给别的角色，先解绑（一件实例只能被一个角色持有）；
##   - 目标槽位已有装备时，**卸下旧装备但保留其实例与强化等级**（V2.1.4 L1610：
##     「普通换装只卸下装备并保留当前强化等级，不自动返还材料」）。
static func equip(character_id: String, instance_id: String) -> OpResult:
	if character_id.is_empty() or instance_id.is_empty():
		return OpResult.new(false, "参数为空")
	if not SaveService.ensure_loaded():
		return OpResult.new(false, "存档不可用")
	var save := SaveService.get_current()
	if save.is_empty():
		return OpResult.new(false, "存档为空")

	var inst := find_instance(save, instance_id)
	if inst.is_empty():
		return OpResult.new(false, "装备实例不存在")
	var slot := str(template_of(str(inst.get("equipmentId", ""))).get("slot", ""))
	if not VALID_SLOTS.has(slot):
		return OpResult.new(false, "模板槽位非法：%s" % slot)

	# 解绑该实例原来的持有者（若绑了别人）
	var prev := str(inst.get("boundCharacterId", ""))
	if not prev.is_empty() and prev != character_id:
		_clear_slot_of(save, prev, slot)

	# 目标槽位已有装备 → 卸下旧装备并**解绑**（V2.1.4 L1610：
	# 「普通换装只卸下装备并保留当前强化等级，不自动返还材料」）。
	# 必须解绑，否则旧实例会残留指向本角色的 boundCharacterId，
	# 导致「实例仍显示为已装备」而槽位其实已换人。
	var existing := str(equipped_of(save, character_id).get(slot, ""))
	if not existing.is_empty() and existing != instance_id:
		var old_inst := find_instance(save, existing)
		if not old_inst.is_empty():
			old_inst["boundCharacterId"] = ""

	_ensure_character(save, character_id)
	var chars: Dictionary = save[CHARACTERS_KEY]
	var c: Dictionary = chars[character_id]
	if not c.has(EQUIP_SLOT_KEY):
		c[EQUIP_SLOT_KEY] = {}
	inst["boundCharacterId"] = character_id
	(c[EQUIP_SLOT_KEY] as Dictionary)[slot] = instance_id

	var r := OpResult.new(true, "已装备")
	r.instance_id = instance_id
	if not SaveService.commit(save):
		return OpResult.new(false, "落盘失败（内存已回滚）")
	GameLog.info(TAG, "%s 装备 %s（槽位 %s）" % [character_id, instance_id, slot])
	return r


## 卸下角色某槽位的装备（保留实例与强化等级，不返还材料）。
static func unequip(character_id: String, slot: String) -> OpResult:
	if character_id.is_empty() or not VALID_SLOTS.has(slot):
		return OpResult.new(false, "参数非法")
	if not SaveService.ensure_loaded():
		return OpResult.new(false, "存档不可用")
	var save := SaveService.get_current()
	var inst_id := str(equipped_of(save, character_id).get(slot, ""))
	if inst_id.is_empty():
		return OpResult.new(false, "该槽位没有装备")
	var inst := find_instance(save, inst_id)
	if not inst.is_empty():
		inst["boundCharacterId"] = ""
	_clear_slot_of(save, character_id, slot)
	var r := OpResult.new(true, "已卸下")
	r.instance_id = inst_id
	if not SaveService.commit(save):
		return OpResult.new(false, "落盘失败（内存已回滚）")
	return r


static func _clear_slot_of(save: Dictionary, character_id: String, slot: String) -> void:
	var chars: Dictionary = save.get(CHARACTERS_KEY, {})
	if not chars.has(character_id):
		return
	var c: Dictionary = chars[character_id]
	if not c.has(EQUIP_SLOT_KEY):
		return
	(c[EQUIP_SLOT_KEY] as Dictionary).erase(slot)


# ============================================================
#  强化 / 重置 / 分解
# ============================================================

## 强化一次（+N → +N+1）。
##
## 规格（V2.1.4 L1604）：「强化使用『装备零件 + 学园币』，成功率固定为 100%，
## 不设计失败、降级、爆装。」
## 原子性（L1611）：扣费与升级在**同一次 commit**；失败则内存回滚。
static func enhance(instance_id: String) -> OpResult:
	if instance_id.is_empty():
		return OpResult.new(false, "实例 ID 为空")
	if not SaveService.ensure_loaded():
		return OpResult.new(false, "存档不可用")
	var save := SaveService.get_current()
	var inst := find_instance(save, instance_id)
	if inst.is_empty():
		return OpResult.new(false, "装备实例不存在")

	var equipment_id := str(inst.get("equipmentId", ""))
	if not can_enhance_template(equipment_id):
		return OpResult.new(false, "该装备不可强化（纪念物或未配置强化上限）")

	var level := int(inst.get("enhanceLevel", 0))
	var cap := int(template_of(equipment_id).get("enhanceMax", enhancement_max_level()))
	if level >= cap:
		return OpResult.new(false, "已达强化上限 +%d" % cap)

	var row := enhancement_cost_at(level)
	if row.is_empty():
		return OpResult.new(false, "缺少 +%d → +%d 的强化成本配置" % [level, level + 1])

	var coin := int(row.get("school_coin", 0))
	var parts := int(row.get("equipment_part", 0))
	if not _can_afford(save, "school_coin", coin):
		return OpResult.new(false, "学园币不足（需 %d）" % coin)
	if not _can_afford(save, "equipment_part", parts):
		return OpResult.new(false, "装备零件不足（需 %d）" % parts)

	# 扣费 + 升级（同一次内存事务）
	_spend(save, "school_coin", coin)
	_spend(save, "equipment_part", parts)
	inst["enhanceLevel"] = level + 1
	# 记录**累计实际投入**（重置强化按它返还 80%，V2.1.4 L1610）
	var invested: Dictionary = inst.get("invested", {"school_coin": 0, "equipment_part": 0})
	invested["school_coin"] = int(invested.get("school_coin", 0)) + coin
	invested["equipment_part"] = int(invested.get("equipment_part", 0)) + parts
	inst["invested"] = invested

	var r := OpResult.new(true, "强化成功 → +%d" % (level + 1))
	r.instance_id = instance_id
	r.cost = {"school_coin": coin, "equipment_part": parts}
	if not SaveService.commit(save):
		return OpResult.new(false, "落盘失败（内存已回滚）")
	GameLog.info(TAG, "%s 强化至 +%d（消耗 学园币 %d / 零件 %d）"
		% [instance_id, level + 1, coin, parts])
	return r


## 重置强化：等级归零，返还累计实际投入的 80%（两种资源各自向下取整，不可超过累计投入）。
##
## 规格（V2.1.4 L1610）：「将该装备的强化等级归零，以累计实际投入的学园币与装备零件
## 分别**向下取整返还 80%**（不可超过累计投入），并记录重置事务；未强化装备返还 0。
## 重置回收可重复使用，但每次仅针对重置前仍存储的强化投入，**不可凭空返还**。」
##
## 「不可凭空返还」的实现要点：重置后**清零 invested**。因此重复重置第二次返还 0，
## 不可能凭同一笔投入反复领取返还。
static func reset_enhancement(instance_id: String) -> OpResult:
	if instance_id.is_empty():
		return OpResult.new(false, "实例 ID 为空")
	if not SaveService.ensure_loaded():
		return OpResult.new(false, "存档不可用")
	var save := SaveService.get_current()
	var inst := find_instance(save, instance_id)
	if inst.is_empty():
		return OpResult.new(false, "装备实例不存在")

	var level := int(inst.get("enhanceLevel", 0))
	var invested: Dictionary = inst.get("invested", {})
	var inv_coin := int(invested.get("school_coin", 0))
	var inv_parts := int(invested.get("equipment_part", 0))

	if level <= 0:
		return OpResult.new(false, "未强化的装备无需重置（返还 0）")

	var rate := reset_refund_rate()
	# 分别向下取整，且夹取不超过累计投入（V2.1.4 L1610 的两条明文）
	var back_coin := clampi(int(floor(float(inv_coin) * rate + 0.000001)), 0, inv_coin)
	var back_parts := clampi(int(floor(float(inv_parts) * rate + 0.000001)), 0, inv_parts)

	# 等级归零 + 清零投入记录（保证「不可凭空返还」）
	inst["enhanceLevel"] = 0
	inst["invested"] = {"school_coin": 0, "equipment_part": 0}
	inst["lastResetAt"] = Time.get_datetime_string_from_system(true)

	_gain(save, "school_coin", back_coin)
	_gain(save, "equipment_part", back_parts)

	var r := OpResult.new(true, "已重置强化（+%d → +0）" % level)
	r.instance_id = instance_id
	r.refund = {"school_coin": back_coin, "equipment_part": back_parts}
	if not SaveService.commit(save):
		return OpResult.new(false, "落盘失败（内存已回滚）")
	GameLog.info(TAG, "%s 重置强化：+%d → +0，返还 学园币 %d / 零件 %d（投入 学园币 %d / 零件 %d 的 %.0f%%）"
		% [instance_id, level, back_coin, back_parts, inv_coin, inv_parts, rate * 100.0])
	return r


## 分解装备：销毁实例，回收**模板规定的基础零件**（不返还强化投入）。
##
## 规格（V2.1.4 L1611）：「分解 = 销毁装备实例并回收该模板规定的基础零件，
## **不再次返还其强化投入**。若分解强化装备，必须先选择『重置强化后分解』或
## 『直接分解且放弃强化投入』，UI 明示差别。」
##
## 因此本函数**拒绝**直接分解强化等级 > 0 的装备，强制调用方明确选择：
##   ① 先 reset_enhancement() 再 dismantle()；或
##   ② 传 acknowledge_forfeit = true 明确表示放弃强化投入。
## 这是把「UI 明示差别」落成**领域层可验证的闸门**，而不是只靠 UI 自觉。
static func dismantle(instance_id: String, acknowledge_forfeit: bool = false) -> OpResult:
	if instance_id.is_empty():
		return OpResult.new(false, "实例 ID 为空")
	if not SaveService.ensure_loaded():
		return OpResult.new(false, "存档不可用")
	var save := SaveService.get_current()
	var inst := find_instance(save, instance_id)
	if inst.is_empty():
		return OpResult.new(false, "装备实例不存在")

	var level := int(inst.get("enhanceLevel", 0))
	if level > 0 and not acknowledge_forfeit:
		return OpResult.new(false,
			"该装备已强化至 +%d：请先重置强化（返还 80%%）再分解，或明确选择「直接分解且放弃强化投入」" % level)

	var equipment_id := str(inst.get("equipmentId", ""))
	var parts := int(template_of(equipment_id).get("dismantleParts", 0))

	# 若已装配，先解绑
	var holder := str(inst.get("boundCharacterId", ""))
	if not holder.is_empty():
		var slot := str(template_of(equipment_id).get("slot", ""))
		_clear_slot_of(save, holder, slot)

	_remove_instance_in_memory(save, instance_id)
	_gain(save, "equipment_part", parts)

	var r := OpResult.new(true, "已分解（回收零件 %d）" % parts)
	r.instance_id = instance_id
	r.refund = {"equipment_part": parts}
	if not SaveService.commit(save):
		return OpResult.new(false, "落盘失败（内存已回滚）")
	GameLog.info(TAG, "%s 已分解（模板 %s，回收零件 %d，强化等级 %d 的投入不予返还）"
		% [instance_id, equipment_id, parts, level])
	return r


# ============================================================
#  存档读写辅助（只改内存；调用方负责 commit）
# ============================================================

static func _ensure_inventory(save: Dictionary) -> void:
	if not save.has(INVENTORY_KEY):
		save[INVENTORY_KEY] = {}
	var inv: Dictionary = save[INVENTORY_KEY]
	if not inv.has(ITEMS_KEY) or typeof(inv[ITEMS_KEY]) != TYPE_ARRAY:
		inv[ITEMS_KEY] = []


static func _ensure_character(save: Dictionary, character_id: String) -> void:
	if not save.has(CHARACTERS_KEY):
		save[CHARACTERS_KEY] = {}
	var chars: Dictionary = save[CHARACTERS_KEY]
	if not chars.has(character_id):
		chars[character_id] = {}
	var c: Dictionary = chars[character_id]
	if not c.has(EQUIP_SLOT_KEY):
		c[EQUIP_SLOT_KEY] = {}


static func _remove_instance_in_memory(save: Dictionary, instance_id: String) -> bool:
	_ensure_inventory(save)
	var arr: Array = _instances_of(save)
	for i: int in range(arr.size()):
		if str((arr[i] as Dictionary).get("instanceId", "")) == instance_id:
			arr.remove_at(i)
			return true
	return false


## 资源是否足够（读存档 currencies）
static func _can_afford(save: Dictionary, currency_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var cur: Dictionary = save.get("currencies", {})
	return int(cur.get(currency_id, 0)) >= amount


static func _spend(save: Dictionary, currency_id: String, amount: int) -> void:
	if amount <= 0:
		return
	if not save.has("currencies"):
		save["currencies"] = {}
	var cur: Dictionary = save["currencies"]
	cur[currency_id] = maxi(0, int(cur.get(currency_id, 0)) - amount)


static func _gain(save: Dictionary, currency_id: String, amount: int) -> void:
	if amount <= 0:
		return
	if not save.has("currencies"):
		save["currencies"] = {}
	var cur: Dictionary = save["currencies"]
	cur[currency_id] = int(cur.get(currency_id, 0)) + amount


# ============================================================
#  查询（供 UI / 测试）
# ============================================================

## 玩家当前持有的装备实例数量
static func instance_count() -> int:
	return all_instances().size()


## 待领取的**装备类**权益（供装备界面的「可领取」列表）
static func pending_equipment_entitlements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ent: Dictionary in StageRewardService.pending_entitlements():
		if str(ent.get("kind", "")) == "EQUIPMENT":
			out.append(ent)
	return out
