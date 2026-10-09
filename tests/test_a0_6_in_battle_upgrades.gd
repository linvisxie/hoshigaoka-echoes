## Alpha A0.6 局内强化（域层）回归。
##
## 存在的理由：局内强化直接改战斗数值，属于最容易破坏 LOCKED 规则的区域。
## 本文件钉死两件事：
##   A. **零影响不变量** —— 未开放强化系统时，倍率必须恒等于 1.0，
##      伤害/AP 回复/撤退返还与接入前逐位一致（既有 496 项测试全绿只是必要条件，
##      这里再加显式断言，防止未来有人把 null 分支写成"默认给个加成"）。
##   B. **规格纪律** —— 数值全部来自 upgrades.json（不写死）、
##      maxStacks 强制夹取（L2092 禁止无限叠层）、
##      候选完全无效项排除（L2052）、确定性抽取（战斗可复现 LOCKED）。
extends GutTest


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func _data() -> Dictionary:
	return DataRegistry.get_domain("upgrades")


func _ups() -> InBattleUpgrades:
	return InBattleUpgrades.from_data(_data())


# ============================================================ 数据契约

func test_upgrades_data_loads_without_errors() -> void:
	var u := _ups()
	assert_eq(u.get_errors().size(), 0, "upgrades.json 校验应无错误：%s" % str(u.get_errors()))
	assert_gte(u.all_ids().size(), 6, "A0.6 首批至少 6 项可生效强化")


func test_all_values_come_from_data_not_code() -> void:
	# L2036 配置化：抽一项强化，改数据里的 value，倍率必须跟着变。
	var raw := _data().duplicate(true)
	var items: Array = raw["upgrades"]
	var target_idx := -1
	for i: int in range(items.size()):
		if str(items[i].get("id", "")) == "upgrade_atk_all":
			target_idx = i
	assert_true(target_idx >= 0, "应存在 upgrade_atk_all")
	var original := float(items[target_idx]["effect"]["value"])
	items[target_idx]["effect"]["value"] = original + 0.33
	var u := InBattleUpgrades.from_data(raw)
	assert_true(u.apply("upgrade_atk_all"))
	# 若代码里写死了数值，这里就不会等于 1 + (original+0.33)
	assert_almost_eq(u.attack_multiplier("FRONTLINE"), 1.0 + original + 0.33, 0.0001)


func test_bad_definition_is_reported_not_silently_accepted() -> void:
	var raw := _data().duplicate(true)
	var items: Array = raw["upgrades"]
	items.append({
		"id": "broken_upgrade", "tier": "COMMON", "appliesTo": "WIZARD",
		"maxStacks": 1, "effect": {"type": "STAT_MOD", "stat": "ATTACK", "value": 0.1},
	})
	var u := InBattleUpgrades.from_data(raw)
	assert_gt(u.get_errors().size(), 0, "非法 appliesTo 必须被报告，不得静默收下")


# ============================================================ A. 零影响不变量

func test_no_selection_means_all_multipliers_are_exactly_one() -> void:
	var u := _ups()
	assert_eq(u.attack_multiplier("FRONTLINE"), 1.0)
	assert_eq(u.attack_multiplier("RANGED"), 1.0)
	assert_eq(u.attack_multiplier("HEALER"), 1.0)
	assert_eq(u.defense_multiplier("FRONTLINE"), 1.0)
	assert_eq(u.heal_multiplier("HEALER"), 1.0)
	assert_eq(u.ap_regen_multiplier(), 1.0)
	assert_eq(u.retreat_refund_bonus(), 0.0)


func test_retreat_refund_rate_equals_base_when_no_selection() -> void:
	var u := _ups()
	assert_eq(u.retreat_refund_rate(0.5), 0.5, "无强化时返还比例必须原样返回")


func test_stage_runtime_without_upgrades_is_deterministic_and_unchanged() -> void:
	# 1-1 完整跑一局，两次结果必须逐位一致（且 upgrades 恒为 null）
	var enemies := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		enemies[str(e["id"])] = e
	var chars := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		chars[str(c["id"])] = c
	var grid := BattleGrid.from_layout(DataRegistry.get_layout())
	# 显式标注 Dictionary：Dictionary.get() 返回 Variant，用 := 推导会触发
	# 「inferred from a Variant」警告，而本工程 GUT 把警告当错误会静默跳过整个文件。
	var combat: Dictionary = DataRegistry.get_domain("balance").get("combat", {})

	var snap_a := _run_1_1_snapshot(enemies, chars, grid, combat)
	var snap_b := _run_1_1_snapshot(enemies, chars, grid, combat)
	assert_null(snap_a["upgrades"], "1-1 不应启用强化系统（L2131 不开放）")
	assert_eq(snap_a["outcome"], snap_b["outcome"])
	assert_eq(snap_a["killed"], snap_b["killed"])
	assert_eq(snap_a["coreHp"], snap_b["coreHp"])
	assert_eq(snap_a["elapsed"], snap_b["elapsed"], "同输入必须同逻辑时长")


func _run_1_1_snapshot(enemies: Dictionary, chars: Dictionary,
		grid: BattleGrid, combat: Dictionary) -> Dictionary:
	# 走 BattleSession（outcome 归会话所有，StageRuntime 只暴露 running/核心/统计）
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(DataRegistry.get_entry("stages", "1-1"), enemies, grid, chars, combat)
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	s.deploy_character("amamiya_mio", 2, 1)
	for i: int in range(60 * 90):
		s.tick(1.0 / 60.0)
		if s.is_decided():
			break
	return {"outcome": s.outcome, "killed": s.stage.enemies_killed,
		"coreHp": s.stage.core_hp, "elapsed": snappedf(s.stage.elapsed_seconds, 0.001),
		"upgrades": s.stage.upgrades}


# ============================================================ 叠加与夹取

func test_max_stacks_is_enforced() -> void:
	var u := _ups()
	var cfg := u.definition("upgrade_atk_all")
	var limit := int(cfg.get("maxStacks", 0))
	assert_gte(limit, 1)
	for i: int in range(limit):
		assert_true(u.apply("upgrade_atk_all"), "第 %d 次应可选" % (i + 1))
	assert_false(u.apply("upgrade_atk_all"), "达到 maxStacks 后必须拒绝（L2092 禁止无限叠层）")
	assert_eq(u.stacks_of("upgrade_atk_all"), limit)


func test_stacks_multiply_linearly() -> void:
	var u := _ups()
	var per := float(u.definition("upgrade_atk_all")["effect"]["value"])
	u.apply("upgrade_atk_all")
	assert_almost_eq(u.attack_multiplier("RANGED"), 1.0 + per, 0.0001)
	u.apply("upgrade_atk_all")
	assert_almost_eq(u.attack_multiplier("RANGED"), 1.0 + per * 2.0, 0.0001)


func test_unknown_upgrade_cannot_be_applied() -> void:
	var u := _ups()
	assert_false(u.apply("not_a_real_upgrade"))
	assert_eq(u.total_selections(), 0)


func test_class_specific_bonus_does_not_leak_to_other_behaviors() -> void:
	# 「远程攻击 +15%」不得同时加成给前线，否则职业专属强化失去意义
	var u := _ups()
	assert_true(u.apply("upgrade_ranged_atk"))
	assert_almost_eq(u.attack_multiplier("RANGED"), 1.15, 0.0001)
	assert_eq(u.attack_multiplier("FRONTLINE"), 1.0, "远程强化不得泄漏给前线")
	assert_eq(u.attack_multiplier("HEALER"), 1.0, "远程强化不得泄漏给治疗")


func test_retreat_refund_rate_is_clamped_to_one() -> void:
	# 返还比例不可能超过原费用（L2040 语义）
	var u := _ups()
	u.apply("upgrade_fast_retreat")
	var rate := u.retreat_refund_rate(0.95)
	assert_lte(rate, 1.0, "返还比例必须夹在 1.0 以内，实际 %s" % rate)
	assert_gt(rate, 0.95)


func test_ap_regen_bonus_respects_spec_soft_ceiling() -> void:
	# L2032：AP 自然回复增益不超过 +50%。由数据侧 maxStacks 保证，
	# 本断言把这条约束变成可执行守卫（有人调大 maxStacks 就会红）。
	var u := _ups()
	var cfg := u.definition("upgrade_ap_regen")
	var per := float(cfg["effect"]["value"])
	var limit := int(cfg.get("maxStacks", 0))
	assert_lte(float(per * limit), 0.50 + 0.0001,
		"AP 回复强化满叠不得超过 L2032 的 +50% 软上限")


# ============================================================ 候选算法

func test_roller_returns_three_distinct_candidates() -> void:
	var u := _ups()
	var got := UpgradeCandidateRoller.roll(u, ["FRONTLINE", "RANGED"],
		["FRONTLINE", "SINGLE"], 12345)
	assert_eq(got.size(), 3, "L2054 每次给 3 个选项")
	var seen := {}
	for id: String in got:
		assert_false(seen.has(id), "候选不得重复：%s" % id)
		seen[id] = true
		assert_true(u.has_definition(id), "候选必须是已定义强化：%s" % id)


func test_roller_is_deterministic_for_same_seed() -> void:
	# 战斗可复现 LOCKED：同一种子必须给出同一候选集
	var u := _ups()
	var a := UpgradeCandidateRoller.roll(u, ["FRONTLINE", "HEALER"], ["FRONTLINE"], 777)
	var b := UpgradeCandidateRoller.roll(u, ["FRONTLINE", "HEALER"], ["FRONTLINE"], 777)
	assert_eq(a, b, "同种子必须同结果（不得使用全局随机）")
	assert_eq(a.size(), 3)


func test_roller_excludes_useless_upgrades() -> void:
	# L2052 第 2 步：队伍没有治疗时，不得提供治疗专属强化
	var u := _ups()
	for s: int in range(60):
		var got := UpgradeCandidateRoller.roll(u, ["FRONTLINE", "RANGED"],
			["FRONTLINE", "SINGLE"], 1000 + s)
		for id: String in got:
			var cfg := u.definition(id)
			var applies := str(cfg.get("appliesTo", ""))
			if applies == InBattleUpgrades.APPLIES_HEALER:
				fail_test("无治疗队伍却收到治疗强化 %s（seed=%d）" % [id, 1000 + s])
				return
	pass_test("60 个种子下均未向无治疗队伍提供治疗专属强化")


func test_roller_drops_option_once_max_stacks_reached() -> void:
	# L2056 第 5 步：检查叠加上限 —— 满叠的条目不得再进候选
	var u := _ups()
	var cfg := u.definition("upgrade_fast_retreat")
	var limit := int(cfg.get("maxStacks", 1))
	for i: int in range(limit):
		u.apply("upgrade_fast_retreat")
	for s: int in range(40):
		var got := UpgradeCandidateRoller.roll(u, ["FRONTLINE", "RANGED", "HEALER"],
			["FRONTLINE", "SINGLE", "HEAL", "SUPPORT"], 2000 + s)
		assert_false(got.has("upgrade_fast_retreat"),
			"已达叠加上限的强化不得再出现在候选（seed=%d）" % (2000 + s))


func test_roller_prefers_distinct_categories() -> void:
	# L2054 第 4 步：3 个选项尽量来自不同类别
	var u := _ups()
	var distinct_count := 0
	for s: int in range(40):
		var got := UpgradeCandidateRoller.roll(u, ["FRONTLINE", "RANGED", "HEALER"],
			["FRONTLINE", "SINGLE", "HEAL", "SUPPORT", "AP", "ECONOMY"], 3000 + s)
		var cats := {}
		for id: String in got:
			var t: Array = u.definition(id).get("tags", [])
			if not t.is_empty():
				cats[str(t[0])] = true
		if cats.size() >= 2:
			distinct_count += 1
	assert_gte(distinct_count, 36,
		"40 个种子中至少 90%% 应给出 2 个以上不同类别（实际 %d）" % distinct_count)


func test_roller_empty_pool_returns_empty_not_crash() -> void:
	var u := _ups()
	# 全部强化打满后池为空
	for id: String in u.all_ids():
		var limit := int(u.definition(id).get("maxStacks", 1))
		for i: int in range(limit):
			u.apply(id)
	var got := UpgradeCandidateRoller.roll(u, ["FRONTLINE"], ["FRONTLINE"], 4242)
	assert_eq(got.size(), 0, "池耗尽应返回空，不得崩溃或返回无效项")


# ============================================================ 开放节奏

func test_open_by_stage_matches_spec_rhythm() -> void:
	# L2131：1-1～1-4 不开放；L2132：1-5 首次固定三选一教学
	var plan: Dictionary = _data().get("openByStage", {})
	for sid: String in ["1-1", "1-2", "1-3", "1-4"]:
		assert_true(plan.has(sid), "开放表应显式列出 %s，不得靠默认值猜" % sid)
		assert_eq(int(plan[sid]["opens"]), 0, "%s 不应开放局内强化（L2131）" % sid)
	assert_eq(int(plan["1-5"]["opens"]), 1, "1-5 应开放 1 次教学三选一")


func test_tutorial_fixed_choices_exist_in_pool() -> void:
	# L2132 的 1-5 固定三选项必须是真实存在的强化 id
	var u := _ups()
	var fixed: Dictionary = _data().get("tutorialFixedChoices_1_5", {})
	var ids: Array = fixed.get("upgradeIds", [])
	assert_eq(ids.size(), 3, "教学固定三选一应有 3 项")
	for id: Variant in ids:
		assert_true(u.has_definition(str(id)), "教学强化 %s 必须已定义" % str(id))
