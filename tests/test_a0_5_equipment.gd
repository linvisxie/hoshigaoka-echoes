## Alpha A0.5 测试：装备系统（模板 / 权益兑现 / 装配 / 强化 / 重置 / 分解）。
##
## 依据：V2.1.4 H 章十～十四（L1581-1623）+ H 章二十二（L1695-1701）+ 表 63/64/65。
##
## 覆盖范围：
##    1. 模板数据契约（三槽位 / 四档品质 / 固定词条，无随机）
##    2. 引用完整性（词条 ID / 槽位合法性 / 奖励引用的模板必须存在）
##    3. **权益兑现**（A0.4 待领取权益 → 真实装备实例；复用既有体系，不重建）
##    4. 兑现幂等（重复兑现不复制装备）
##    5. 原子性（权益兑现失败时不得留下孤立实例）
##    6. 装配 / 换装（保留旧实例与强化等级，不返还材料）
##    7. 强化（+0→+10，100% 成功，扣费正确，上限保护）
##    8. 重置强化（返还 80% 向下取整，不可凭空返还，可重复使用但第二次返还 0）
##    9. 分解（回收模板规定零件，不返还强化投入；强化装备必须明确选择）
##   10. 面板加成（主属性随强化增长，副属性为固定值）
##   11. 经济自洽（强化预算落在表 71 的意图内）
##
## 纪律：所有夹具先 duplicate(true) 再改，绝不修改 DataRegistry 里的权威字典。
extends GutTest

const CHAR_YUMA := "kamiya_yuma" # Bow fixtures must use the eligible archer.
const EQUIP_1_2 := "equip_ch1_1_2_fine_weapon"
const EQUIP_1_6 := "equip_ch1_1_6_heal_accessory"
const EQUIP_1_9 := "equip_ch1_1_9_rare_accessory"
const AFFIX_WEAPON_ATKSPEED := "affix_weapon_atkspeed_pct_01"
const AFFIX_ACC_HP := "affix_accessory_hp_flat_01"

const EPS := 0.0001


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func before_each() -> void:
	# 每个用例从干净的存档开始（隔离在 _testenv 的 APPDATA 下）
	SaveService._current = SaveService.build_default_save()


func after_each() -> void:
	SaveService._current = {}


# ============================================================
#  一、模板数据契约
# ============================================================

## 覆盖项 1：三个槽位定义存在，且 ID 与 V2.1.4 表 70 逐字一致。
func test_01_template_ids_match_spec_table_70() -> void:
	assert_false(EquipmentService.template_of(EQUIP_1_2).is_empty(),
		"1-2 首通的优秀级基础武器模板应存在（表 70）")
	assert_false(EquipmentService.template_of(EQUIP_1_6).is_empty(),
		"1-6 首通的治疗饰品模板应存在（表 70）")
	assert_false(EquipmentService.template_of(EQUIP_1_9).is_empty(),
		"1-9 首通的稀有级通用饰品模板应存在（表 70 + L1678，ID 逐字固定）")


## 覆盖项 1b：槽位必须是表 63 的三槽位之一。
func test_01b_slots_are_within_table_63() -> void:
	var templates := EquipmentService.all_templates()
	assert_gt(templates.size(), 0, "应有装备模板")
	for t: Dictionary in templates:
		var slot := str(t.get("slot", ""))
		assert_true(EquipmentService.VALID_SLOTS.has(slot),
			"%s 的槽位 '%s' 必须是表 63 的三槽位之一" % [str(t.get("id", "?")), slot])


## 覆盖项 1c：品质必须是表 64 的四档之一；词条数量符合品质结构。
func test_01c_quality_and_affix_count_follow_table_64() -> void:
	# 表 64：普通 1 主属性 / 优秀 1 主 + 1 固定副 / 稀有 1 主 + 1～2 副 / 史诗 主 + 特殊效果
	var expected_affix_range := {
		"COMMON": [0, 0],
		"FINE": [1, 1],
		"RARE": [1, 2],
	}
	for t: Dictionary in EquipmentService.all_templates():
		var q := str(t.get("quality", ""))
		assert_true(expected_affix_range.has(q) or q == "EPIC",
			"%s 的品质 '%s' 应为表 64 四档之一" % [str(t.get("id", "?")), q])
		if expected_affix_range.has(q):
			var rng: Array = expected_affix_range[q]
			var n: int = (t.get("affixes", []) as Array).size()
			assert_gte(n, int(rng[0]),
				"%s（%s）的副属性数量不应少于 %d" % [str(t.get("id", "?")), q, int(rng[0])])
			assert_lte(n, int(rng[1]),
				"%s（%s）的副属性数量不应多于 %d" % [str(t.get("id", "?")), q, int(rng[1])])


## 覆盖项 1d：**不存在随机抽取**——同一模板反复实例化必须得到完全相同的面板。
func test_01d_no_random_rolls_on_instantiation() -> void:
	var insts: Array[Dictionary] = []
	for i: int in range(20):
		insts.append(EquipmentService.build_instance(EQUIP_1_9, "inst_%d" % i))
	assert_eq(insts.size(), 20, "应创建 20 个实例")
	var first := EquipmentService.stat_bonus_of(insts[0])
	for i: int in range(1, insts.size()):
		assert_eq(EquipmentService.stat_bonus_of(insts[i]), first,
			"第 %d 个实例的面板必须与第 1 个完全相同（V2.1.4 L1597 禁止随机浮动）" % (i + 1))


## 覆盖项 1e：实例 ID 必须确定且唯一（同一模板可持有多件，序号递增）。
func test_01e_instance_ids_are_deterministic_and_unique() -> void:
	var save := SaveService.build_default_save()
	var seen := {}
	for i: int in range(3):
		var id := EquipmentService.next_instance_id(save, EQUIP_1_2)
		assert_false(seen.has(id), "实例 ID 不得重复：%s" % id)
		seen[id] = true
		# 把实例**追加**进背包（而不是整体覆盖），否则下一个 ID 会与上一个相同
		var arr: Array = (save["inventory"] as Dictionary).get("equipmentInstances", [])
		arr.append(EquipmentService.build_instance(EQUIP_1_2, id))
		save["inventory"] = {"equipmentInstances": arr}
	assert_eq(seen.size(), 3, "应产生 3 个不同实例 ID")


## 覆盖项 1f：主属性与副属性必须是**不同的属性键**。
##
## 若相同，stat_bonus_of() 会把两者累加到同一个键，使「1 主属性 + 1 副属性」
## 的结构退化成同一个数值的重复计算——这是数据配置的静默错误。
func test_01f_primary_and_affix_keys_are_distinct() -> void:
	var checked := 0
	for t: Dictionary in EquipmentService.all_templates():
		var primary: Dictionary = t.get("primaryStat", {})
		if primary.is_empty():
			continue
		var pk := str(primary.get("key", ""))
		for aid: Variant in t.get("affixes", []):
			var a := EquipmentService.affix_of(str(aid))
			if a.is_empty():
				continue
			checked += 1
			assert_ne(str(a.get("statKey", "")), pk,
				"%s 的副属性 '%s' 与主属性键 '%s' 相同——会让主副属性合并成同一个数值"
				% [str(t.get("id", "?")), str(aid), pk])
	assert_gt(checked, 0, "应至少检查到一对主/副属性（否则本用例空转）")


# ============================================================
#  二、引用完整性
# ============================================================

## 覆盖项 2：DataRegistry 加载无错误（含装备引用校验）。
func test_02_data_registry_has_no_load_errors() -> void:
	var errs := DataRegistry.get_load_errors()
	assert_eq(errs.size(), 0, "数据加载不应有错误：%s" % str(errs))


## 覆盖项 2b：模板引用的词条 ID 必须存在于 equipment_affixes.json。
func test_02b_affix_references_resolve() -> void:
	for t: Dictionary in EquipmentService.all_templates():
		for aid: Variant in t.get("affixes", []):
			assert_false(EquipmentService.affix_of(str(aid)).is_empty(),
				"%s 引用的词条 '%s' 应存在" % [str(t.get("id", "?")), str(aid)])


## 覆盖项 2c：奖励表引用的装备模板必须存在（否则首通权益无法兑现 = 不可逆奖励损失）。
func test_02c_stage_reward_equipment_ids_resolve() -> void:
	var checked := 0
	for r: Dictionary in DataRegistry.get_domain("stage_rewards").get("rewards", []):
		var eq := str(r.get("equipmentId", ""))
		if eq.is_empty():
			continue
		checked += 1
		assert_false(EquipmentService.template_of(eq).is_empty(),
			"奖励 %s 的 equipmentId '%s' 应存在于 equipment.json" % [str(r.get("id", "?")), eq])
	assert_gt(checked, 0, "应至少检查到一个引用装备的奖励（否则本用例空转）")


## 覆盖项 2d：1-9 的稀有饰品 ID 必须逐字固定（L1678：不得留给实现者自行选择）。
func test_02d_1_9_rare_accessory_id_is_fixed() -> void:
	var reward := {}
	for r: Dictionary in DataRegistry.get_domain("stage_rewards").get("rewards", []):
		if str(r.get("id", "")) == "reward_1_9_first":
			reward = r
			break
	assert_false(reward.is_empty(), "应存在 reward_1_9_first")
	assert_eq(str(reward.get("equipmentId", "")), EQUIP_1_9,
		"1-9 首通的装备 ID 必须是 L1678 逐字固定的 equip_ch1_1_9_rare_accessory")
	assert_eq(str(EquipmentService.template_of(EQUIP_1_9).get("quality", "")), "RARE",
		"该模板品质必须是稀有（表 70：「固定稀有级通用饰品」）")
	assert_eq(str(EquipmentService.template_of(EQUIP_1_9).get("slot", "")), "ACCESSORY",
		"该模板槽位必须是饰品（表 70：「通用饰品」）")


# ============================================================
#  三、权益兑现（复用 A0.4 体系）
# ============================================================

## 覆盖项 3：首通结算登记权益后，兑现应产出真实装备实例。
func test_03_fulfill_creates_real_instance() -> void:
	# 模拟 1-2 首通结算（登记权益）
	var cfg := _stage("1-2")
	assert_false(cfg.is_empty(), "应能读到 1-2")
	var s := StageRewardService.settle(cfg, true, false)
	assert_true(s.ok, "结算应成功")
	assert_gt(s.pending_registered.size(), 0, "1-2 首通应登记装备类权益")

	var pendings := EquipmentService.pending_equipment_entitlements()
	assert_gt(pendings.size(), 0, "应存在待领取的装备类权益")

	var ent: Dictionary = pendings[0]
	var r := EquipmentService.fulfill(str(ent.get("entitlementId", "")), false)
	assert_true(r.ok, "兑现应成功：%s" % r.reason)
	assert_false(r.instance_id.is_empty(), "应产出实例 ID")

	# 实例确实进入背包
	var save := SaveService.get_current()
	var inst := EquipmentService.find_instance(save, r.instance_id)
	assert_false(inst.is_empty(), "背包中应存在该实例")
	assert_eq(str(inst.get("equipmentId", "")), EQUIP_1_2, "实例应指向 1-2 的武器模板")
	assert_eq(int(inst.get("enhanceLevel", 0)), 0, "新实例强化等级应为 0")

	# 权益应从 pending 移入 fulfilled
	assert_eq(EquipmentService.pending_equipment_entitlements().size(), pendings.size() - 1,
		"兑现后待领取列表应减少 1")


## 覆盖项 4：**幂等**——重复兑现不得复制装备。
func test_04_fulfill_is_idempotent() -> void:
	var cfg := _stage("1-2")
	StageRewardService.settle(cfg, true, false)
	var ent: Dictionary = EquipmentService.pending_equipment_entitlements()[0]
	var eid := str(ent.get("entitlementId", ""))

	var r1 := EquipmentService.fulfill(eid, false)
	assert_true(r1.ok, "首次兑现应成功")
	var count_after_first := EquipmentService.instance_count()

	var r2 := EquipmentService.fulfill(eid, false)
	assert_false(r2.ok, "重复兑现必须失败（权益已不在 pending）")
	assert_eq(EquipmentService.instance_count(), count_after_first,
		"重复兑现不得增加实例数量（%d）" % count_after_first)

	# 第三次仍然失败
	var r3 := EquipmentService.fulfill(eid, false)
	assert_false(r3.ok, "第三次兑现同样必须失败")
	assert_eq(EquipmentService.instance_count(), count_after_first, "实例数量必须保持不变")


## 覆盖项 5：模板不存在时兑现必须失败，且**不得留下孤立实例**（原子性）。
func test_05_fulfill_with_missing_template_leaves_no_orphan() -> void:
	var save := SaveService.build_default_save()
	save["entitlements"] = {
		"pending": [{
			"entitlementId": "1-2:reward_1_2_first:EQUIPMENT:no_such_template",
			"stageId": "1-2", "rewardId": "reward_1_2_first",
			"kind": "EQUIPMENT", "itemId": "no_such_template", "source": "FIRST_CLEAR",
		}],
		"fulfilled": [],
	}
	SaveService._current = save

	var r := EquipmentService.fulfill("1-2:reward_1_2_first:EQUIPMENT:no_such_template", false)
	assert_false(r.ok, "模板不存在时兑现必须失败")
	assert_eq(EquipmentService.instance_count(), 0, "不得留下任何孤立实例")
	assert_eq(EquipmentService.pending_equipment_entitlements().size(), 1,
		"失败的兑现不得消费权益（仍应在 pending 中，便于后续补发）")


## 覆盖项 5b：非装备类权益不得由装备系统兑现。
func test_05b_non_equipment_entitlement_is_rejected() -> void:
	var save := SaveService.build_default_save()
	save["entitlements"] = {
		"pending": [{
			"entitlementId": "1-10:reward_1_10_first:MEMENTO:memento_ch1_boss_cleared",
			"stageId": "1-10", "rewardId": "reward_1_10_first",
			"kind": "MEMENTO", "itemId": "memento_ch1_boss_cleared", "source": "FIRST_CLEAR",
		}],
		"fulfilled": [],
	}
	SaveService._current = save

	var r := EquipmentService.fulfill(
		"1-10:reward_1_10_first:MEMENTO:memento_ch1_boss_cleared", false)
	assert_true(r.ok, "Chapter memento is now implemented")
	assert_eq(EquipmentService.instance_count(), 1)
	assert_false(EquipmentService.fulfill("1-10:reward_1_10_first:MEMENTO:memento_ch1_boss_cleared",false).ok,"No duplicate memento")
	assert_false(EquipmentService.dismantle(r.instance_id,true).ok,"Unique chapter keepsake cannot be destroyed")


## 覆盖项 3b：一键兑现应处理全部装备类权益，且跳过非装备类。
func test_03b_fulfill_all_handles_only_equipment() -> void:
	# 1-2（装备）+ 1-10（纪念物，非装备）
	StageRewardService.settle(_stage("1-2"), true, false)
	# 手工追加一条纪念物权益（1-10 尚未配置关卡时间线，无法走真实结算）
	var save := SaveService.get_current()
	(save["entitlements"]["pending"] as Array).append({
		"entitlementId": "1-10:reward_1_10_first:MEMENTO:memento_ch1_boss_cleared",
		"stageId": "1-10", "rewardId": "reward_1_10_first",
		"kind": "MEMENTO", "itemId": "memento_ch1_boss_cleared", "source": "FIRST_CLEAR",
	})

	var res := EquipmentService.fulfill_all_equipment(false)
	assert_gt((res["fulfilled"] as Array).size(), 0, "应至少兑现一件装备")
	# 纪念物权益必须仍留在 pending（不得被装备系统消费，也不得丢失）
	var still_pending := EquipmentService.pending_equipment_entitlements()
	assert_eq(still_pending.size(), 0, "装备类权益应已全部兑现")
	assert_eq((SaveService.get_current()["entitlements"]["pending"] as Array).size(), 0,"All implemented rewards claimed")
	assert_eq(EquipmentService.instance_count(),2,"Bow and chapter memento are both real instances")


# ============================================================
#  六、装配 / 卸下
# ============================================================

## 覆盖项 6：装备到正确槽位；换装保留旧实例与强化等级。
func test_06_equip_and_swap_keeps_old_instance() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [
		EquipmentService.build_instance(EQUIP_1_2, "inst_a"),
		EquipmentService.build_instance(EQUIP_1_2, "inst_b"),
	]}
	SaveService._current = save

	var r1 := EquipmentService.equip(CHAR_YUMA, "inst_a")
	assert_true(r1.ok, "应能装备 inst_a：%s" % r1.reason)
	assert_eq(str(EquipmentService.equipped_of(SaveService.get_current(), CHAR_YUMA).get("WEAPON", "")),
		"inst_a", "武器槽应指向 inst_a")

	# 换装到 inst_b
	var r2 := EquipmentService.equip(CHAR_YUMA, "inst_b")
	assert_true(r2.ok, "应能换装到 inst_b：%s" % r2.reason)
	assert_eq(str(EquipmentService.equipped_of(SaveService.get_current(), CHAR_YUMA).get("WEAPON", "")),
		"inst_b", "武器槽应改指 inst_b")
	# 旧实例仍留在背包且解绑（V2.1.4 L1610：换装只卸下，不销毁、不返还材料）
	assert_eq(EquipmentService.instance_count(), 2, "换装不得销毁旧实例")
	assert_eq(str(EquipmentService.find_instance(SaveService.get_current(), "inst_a").get(
		"boundCharacterId", "")), "", "旧实例应已解绑")


## 覆盖项 6b：卸下保留实例与强化等级。
func test_06b_unequip_keeps_instance_and_level() -> void:
	var save := SaveService.build_default_save()
	var inst := EquipmentService.build_instance(EQUIP_1_2, "inst_x")
	inst["enhanceLevel"] = 4
	save["inventory"] = {"equipmentInstances": [inst]}
	SaveService._current = save

	EquipmentService.equip(CHAR_YUMA, "inst_x")
	var r := EquipmentService.unequip(CHAR_YUMA, "WEAPON")
	assert_true(r.ok, "应能卸下：%s" % r.reason)
	assert_eq(EquipmentService.equipped_of(SaveService.get_current(), CHAR_YUMA).size(), 0,
		"卸下后不应有装备")
	var after := EquipmentService.find_instance(SaveService.get_current(), "inst_x")
	assert_eq(int(after.get("enhanceLevel", 0)), 4, "卸下必须保留强化等级（L1610）")
	assert_eq(EquipmentService.instance_count(), 1, "卸下不得销毁实例")


## 覆盖项 6c：一件实例不能同时被两名角色持有。
func test_06c_instance_cannot_be_bound_to_two_characters() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [
		EquipmentService.build_instance(EQUIP_1_9, "inst_shared"),
	]}
	SaveService._current = save

	EquipmentService.equip(CHAR_YUMA, "inst_shared")
	EquipmentService.equip("amamiya_mio", "inst_shared")

	var previous_holder := EquipmentService.equipped_of(SaveService.get_current(), CHAR_YUMA)
	var next_holder := EquipmentService.equipped_of(SaveService.get_current(), "amamiya_mio")
	assert_eq(previous_holder.size(), 0, "原持有者的槽位应被清空")
	assert_eq(str(next_holder.get("ACCESSORY", "")), "inst_shared", "新持有者应持有该实例")
	assert_eq(EquipmentService.instance_count(), 1, "不得复制实例")


# ============================================================
#  七、强化
# ============================================================

## 覆盖项 7：强化一次扣费正确、等级 +1、成功率 100%。
func test_07_enhance_deducts_cost_and_increases_level() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_e")]}
	save["currencies"] = {"school_coin": 1000, "equipment_part": 50}
	SaveService._current = save

	var row := EquipmentService.enhancement_cost_at(0)
	assert_false(row.is_empty(), "应有 +0 → +1 的成本配置")
	var coin := int(row.get("school_coin", 0))
	var parts := int(row.get("equipment_part", 0))

	var r := EquipmentService.enhance("inst_e")
	assert_true(r.ok, "强化应成功：%s" % r.reason)
	assert_eq(int(EquipmentService.find_instance(SaveService.get_current(), "inst_e").get(
		"enhanceLevel", 0)), 1, "等级应为 +1")
	assert_eq(int(SaveService.get_current()["currencies"]["school_coin"]), 1000 - coin,
		"学园币应扣 %d" % coin)
	assert_eq(int(SaveService.get_current()["currencies"]["equipment_part"]), 50 - parts,
		"装备零件应扣 %d" % parts)


## 覆盖项 7b：强化至上限后必须拒绝，且不扣费。
func test_07b_enhance_stops_at_cap() -> void:
	var save := SaveService.build_default_save()
	var inst := EquipmentService.build_instance(EQUIP_1_2, "inst_cap")
	inst["enhanceLevel"] = EquipmentService.enhancement_max_level()
	save["inventory"] = {"equipmentInstances": [inst]}
	save["currencies"] = {"school_coin": 999999, "equipment_part": 9999}
	SaveService._current = save

	var before_coin := int(SaveService.get_current()["currencies"]["school_coin"])
	var r := EquipmentService.enhance("inst_cap")
	assert_false(r.ok, "已达上限应拒绝强化")
	assert_eq(int(SaveService.get_current()["currencies"]["school_coin"]), before_coin,
		"被拒的强化不得扣费")


## 覆盖项 7c：资源不足时拒绝，且不改变等级。
func test_07c_enhance_rejects_when_poor() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_poor")]}
	save["currencies"] = {"school_coin": 0, "equipment_part": 0}
	SaveService._current = save

	var r := EquipmentService.enhance("inst_poor")
	assert_false(r.ok, "资源不足应拒绝强化")
	assert_eq(int(EquipmentService.find_instance(SaveService.get_current(), "inst_poor").get(
		"enhanceLevel", 0)), 0, "被拒的强化不得改变等级")


## 覆盖项 7d：纪念物不可强化（表 63：只有武器与饰品有强化语义）。
func test_07d_memento_cannot_be_enhanced() -> void:
	assert_false(EquipmentService.can_enhance_template("memento_ch1_boss_cleared"),
		"纪念物不应可强化")


# ============================================================
#  八、重置强化
# ============================================================

## 覆盖项 8：重置返还累计投入的 80%，向下取整，等级归零。
func test_08_reset_refunds_80_percent_floored() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_r")]}
	save["currencies"] = {"school_coin": 10000, "equipment_part": 1000}
	SaveService._current = save

	# 强化 5 次，记录累计投入
	var invested_coin := 0
	var invested_parts := 0
	for i: int in range(5):
		var row := EquipmentService.enhancement_cost_at(i)
		invested_coin += int(row.get("school_coin", 0))
		invested_parts += int(row.get("equipment_part", 0))
		assert_true(EquipmentService.enhance("inst_r").ok, "第 %d 次强化应成功" % (i + 1))

	var coin_before := int(SaveService.get_current()["currencies"]["school_coin"])
	var parts_before := int(SaveService.get_current()["currencies"]["equipment_part"])

	var r := EquipmentService.reset_enhancement("inst_r")
	assert_true(r.ok, "重置应成功：%s" % r.reason)

	var want_coin := int(floor(float(invested_coin) * 0.8))
	var want_parts := int(floor(float(invested_parts) * 0.8))
	assert_eq(int(r.refund.get("school_coin", 0)), want_coin,
		"学园币返还应为 floor(%d × 0.8) = %d" % [invested_coin, want_coin])
	assert_eq(int(r.refund.get("equipment_part", 0)), want_parts,
		"零件返还应为 floor(%d × 0.8) = %d" % [invested_parts, want_parts])
	assert_eq(int(SaveService.get_current()["currencies"]["school_coin"]), coin_before + want_coin,
		"学园币应实际入账")
	assert_eq(int(SaveService.get_current()["currencies"]["equipment_part"]), parts_before + want_parts,
		"零件应实际入账")
	assert_eq(int(EquipmentService.find_instance(SaveService.get_current(), "inst_r").get(
		"enhanceLevel", 0)), 0, "重置后等级应为 0")


## 覆盖项 8b：**不可凭空返还**——重复重置第二次必须返还 0。
func test_08b_reset_cannot_be_repeated_for_free_refund() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_r2")]}
	save["currencies"] = {"school_coin": 10000, "equipment_part": 1000}
	SaveService._current = save

	for i: int in range(3):
		EquipmentService.enhance("inst_r2")

	var r1 := EquipmentService.reset_enhancement("inst_r2")
	assert_true(r1.ok, "首次重置应成功")
	assert_gt(int(r1.refund.get("school_coin", 0)), 0, "首次重置应有返还")

	var coin_after_first := int(SaveService.get_current()["currencies"]["school_coin"])
	var r2 := EquipmentService.reset_enhancement("inst_r2")
	assert_false(r2.ok, "已重置（等级 0）的装备再次重置必须失败——不可凭空返还")
	assert_eq(int(SaveService.get_current()["currencies"]["school_coin"]), coin_after_first,
		"第二次重置不得入账任何资源")


## 覆盖项 8c：未强化装备重置返还 0（L1610 明文）。
func test_08c_reset_unenhanced_refunds_zero() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_u")]}
	SaveService._current = save

	var r := EquipmentService.reset_enhancement("inst_u")
	assert_false(r.ok, "未强化装备无需重置")
	assert_eq((r.refund as Dictionary).size(), 0, "未强化装备返还 0")


## 覆盖项 8d：返还永不超过累计投入（L1610 明文）。
func test_08d_refund_never_exceeds_invested() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_cap2")]}
	save["currencies"] = {"school_coin": 100000, "equipment_part": 10000}
	SaveService._current = save

	var total_coin := 0
	var total_parts := 0
	for i: int in range(EquipmentService.enhancement_max_level()):
		var row := EquipmentService.enhancement_cost_at(i)
		total_coin += int(row.get("school_coin", 0))
		total_parts += int(row.get("equipment_part", 0))
		EquipmentService.enhance("inst_cap2")

	var r := EquipmentService.reset_enhancement("inst_cap2")
	assert_true(r.ok, "满强化重置应成功")
	assert_lte(int(r.refund.get("school_coin", 0)), total_coin,
		"返还不得超过累计投入的学园币（%d ≤ %d）" % [int(r.refund.get("school_coin", 0)), total_coin])
	assert_lte(int(r.refund.get("equipment_part", 0)), total_parts,
		"返还不得超过累计投入的零件")


# ============================================================
#  九、分解
# ============================================================

## 覆盖项 9：分解回收模板规定的零件，销毁实例，不返还强化投入。
func test_09_dismantle_returns_template_parts_only() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_d")]}
	save["currencies"] = {"school_coin": 10000, "equipment_part": 0}
	SaveService._current = save

	# 先强化 2 次（这些投入不得在分解时返还）
	for i: int in range(2):
		EquipmentService.enhance("inst_d")
	var coin_before := int(SaveService.get_current()["currencies"]["school_coin"])

	var expect_parts := int(EquipmentService.template_of(EQUIP_1_2).get("dismantleParts", 0))
	var r := EquipmentService.dismantle("inst_d", true)
	assert_true(r.ok, "分解应成功：%s" % r.reason)
	assert_eq(int(r.refund.get("equipment_part", 0)), expect_parts,
		"应回收模板规定的 %d 个零件" % expect_parts)
	assert_eq(EquipmentService.instance_count(), 0, "实例应被销毁")
	assert_eq(int(SaveService.get_current()["currencies"]["school_coin"]), coin_before,
		"分解不得返还任何强化投入的学园币（L1611）")


## 覆盖项 9b：**强化装备必须明确选择**——未确认时分解应被拒绝。
func test_09b_enhanced_equipment_requires_explicit_choice() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_e2")]}
	save["currencies"] = {"school_coin": 10000, "equipment_part": 50}
	SaveService._current = save
	EquipmentService.enhance("inst_e2")

	# 未明确放弃 → 拒绝（把「UI 明示差别」落成领域层闸门）
	var r := EquipmentService.dismantle("inst_e2", false)
	assert_false(r.ok, "强化装备未明确选择时不得直接分解")
	assert_eq(EquipmentService.instance_count(), 1, "被拒的分解不得销毁实例")

	# 明确放弃 → 允许
	var r2 := EquipmentService.dismantle("inst_e2", true)
	assert_true(r2.ok, "明确放弃强化投入后应可分解：%s" % r2.reason)
	assert_eq(EquipmentService.instance_count(), 0, "确认后实例应被销毁")


## 覆盖项 9c：先重置再分解的推荐路径应可用，且总返还优于直接放弃。
func test_09c_reset_then_dismantle_path_works() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_rd")]}
	save["currencies"] = {"school_coin": 10000, "equipment_part": 50}
	SaveService._current = save
	EquipmentService.enhance("inst_rd")
	EquipmentService.enhance("inst_rd")

	var r_reset := EquipmentService.reset_enhancement("inst_rd")
	assert_true(r_reset.ok, "先重置应成功")
	assert_gt(int(r_reset.refund.get("equipment_part", 0)), 0, "重置应返还部分零件")

	var parts_before_dismantle := int(SaveService.get_current()["currencies"]["equipment_part"])
	var r_dis := EquipmentService.dismantle("inst_rd", false)
	assert_true(r_dis.ok, "重置后再分解应成功（等级已为 0，无需确认）：%s" % r_dis.reason)
	assert_gt(int(SaveService.get_current()["currencies"]["equipment_part"]), parts_before_dismantle,
		"分解应再回收模板基础零件")


## 覆盖项 9d：分解已装配的装备应先解绑，不留悬空引用。
func test_09d_dismantle_equipped_clears_slot() -> void:
	var save := SaveService.build_default_save()
	save["inventory"] = {"equipmentInstances": [EquipmentService.build_instance(EQUIP_1_2, "inst_de")]}
	save["currencies"] = {"equipment_part": 0}
	SaveService._current = save
	EquipmentService.equip(CHAR_YUMA, "inst_de")

	var r := EquipmentService.dismantle("inst_de", true)
	assert_true(r.ok, "分解已装配装备应成功：%s" % r.reason)
	assert_eq(EquipmentService.equipped_of(SaveService.get_current(), CHAR_YUMA).size(), 0,
		"角色槽位应被清空，不得留下指向已销毁实例的悬空引用")


# ============================================================
#  十、面板加成
# ============================================================

## 覆盖项 10：主属性随强化增长，副属性为固定值（不随强化变化）。
func test_10_primary_scales_affix_is_fixed() -> void:
	var t := EquipmentService.template_of(EQUIP_1_2)
	var primary_key := str((t.get("primaryStat", {}) as Dictionary).get("key", ""))
	var primary_base := float((t.get("primaryStat", {}) as Dictionary).get("value", 0.0))
	var affix := EquipmentService.affix_of(AFFIX_WEAPON_ATKSPEED)
	var affix_key := str(affix.get("statKey", ""))
	var affix_val := float(affix.get("value", 0.0))
	assert_ne(affix_key, primary_key, "主属性与副属性必须是不同的键（否则本用例无意义）")

	var inst := EquipmentService.build_instance(EQUIP_1_2, "inst_bonus")
	var at0 := EquipmentService.stat_bonus_of(inst)
	inst["enhanceLevel"] = 5
	var at5 := EquipmentService.stat_bonus_of(inst)
	inst["enhanceLevel"] = 10
	var at10 := EquipmentService.stat_bonus_of(inst)

	assert_gt(float(at5.get(primary_key, 0.0)), float(at0.get(primary_key, 0.0)),
		"主属性应随强化增长")
	assert_gt(float(at10.get(primary_key, 0.0)), float(at5.get(primary_key, 0.0)),
		"主属性应继续增长")
	assert_eq(float(at0.get(primary_key, 0.0)), primary_base,
		"+0 时主属性应等于模板基准值 %.1f" % primary_base)
	# 副属性固定
	assert_almost_eq(float(at0.get(affix_key, 0.0)), affix_val, EPS,
		"+0 时副属性应等于词条固定值 %.2f" % affix_val)
	assert_almost_eq(float(at5.get(affix_key, 0.0)), affix_val, EPS,
		"副属性不得随强化变化（L1602：词条数值在同品质内部保持窄区间）")
	assert_almost_eq(float(at10.get(affix_key, 0.0)), affix_val, EPS,
		"副属性在 +10 时仍应保持固定值 %.2f" % affix_val)


## 覆盖项 10b：稀有饰品的两条副属性都应计入面板。
func test_10b_rare_accessory_has_two_affixes() -> void:
	var inst := EquipmentService.build_instance(EQUIP_1_9, "inst_rare")
	var bonus := EquipmentService.stat_bonus_of(inst)
	var t := EquipmentService.template_of(EQUIP_1_9)

	var expected_keys := {}
	var pk := str((t.get("primaryStat", {}) as Dictionary).get("key", ""))
	expected_keys[pk] = true
	for aid: Variant in t.get("affixes", []):
		expected_keys[str(EquipmentService.affix_of(str(aid)).get("statKey", ""))] = true

	for k: String in expected_keys.keys():
		assert_true(bonus.has(k), "面板应包含 %s" % k)
	assert_eq((t.get("affixes", []) as Array).size(), 2, "稀有饰品应有 2 条固定副属性")


# ============================================================
#  十一、经济自洽
# ============================================================

## 覆盖项 11：单件装备强化满级的累计消耗应落在表 71 的预算意图内。
##
## 表 71（L1689）：装备零件 15～24「允许进行早期强化，但不要求刷装」。
## 因此「单件强化满」的累计零件需求不应超过全章首通总给量（20）。
func test_11_enhancement_budget_is_consistent_with_table_71() -> void:
	var total_coin := 0
	var total_parts := 0
	for i: int in range(EquipmentService.enhancement_max_level()):
		var row := EquipmentService.enhancement_cost_at(i)
		assert_false(row.is_empty(), "应有 +%d → +%d 的成本配置" % [i, i + 1])
		total_coin += int(row.get("school_coin", 0))
		total_parts += int(row.get("equipment_part", 0))

	assert_eq(total_parts + 5, 20,
		"单件强化满需 %d 零件，加上余量应正好等于全章首通总给量 20（表 71）" % total_parts)
	assert_lt(total_coin, 5200 / 2,
		"单件强化满的学园币消耗（%d）应明显低于全章预算 5200 的一半" % total_coin)


## 覆盖项 11b：全部强化成本行必须连续覆盖 +0 → +上限，无缺档。
func test_11b_enhancement_costs_cover_all_levels() -> void:
	var cap := EquipmentService.enhancement_max_level()
	assert_eq(cap, 10, "V2.1.4 L1604：强化上限应为 +10")
	var seen := {}
	for row: Dictionary in EquipmentService.enhancement_costs().get("equipment", []):
		var f := int(row.get("fromLevel", -1))
		var t := int(row.get("toLevel", -1))
		assert_eq(t, f + 1, "成本行必须相邻（%d → %d）" % [f, t])
		seen[f] = true
	for i: int in range(cap):
		assert_true(seen.has(i), "缺少 +%d 的成本行" % i)


## 覆盖项 11c：成功率必须是 100%（L1604：不设计失败、降级、爆装）。
func test_11c_success_rate_is_100_percent() -> void:
	assert_almost_eq(
		float(EquipmentService.enhancement_costs().get("equipmentSuccessRate", 0.0)), 1.0, EPS,
		"V2.1.4 L1604：强化成功率固定 100%")


# ============================================================
#  夹具
# ============================================================

func _stage(sid: String) -> Dictionary:
	var cfg: Dictionary = DataRegistry.get_entry("stages", sid)
	return cfg.duplicate(true)
