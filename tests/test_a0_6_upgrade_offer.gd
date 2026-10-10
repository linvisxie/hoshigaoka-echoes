## Alpha A0.6 局内强化的**三选一面板生命周期**回归（契约 docs/a0_6_ui_contract.md 第 1 节）。
##
## 与既有两个 A0.6 文件的分工：
##   test_a0_6_in_battle_upgrades.gd  数据契约 / 倍率数学 / 候选算法；
##   test_a0_6_upgrade_enablement.gd  关卡有没有启用 / 启用后是否真改战斗结果；
##   本文件                          **pending_offer 的建立与冻结、以及四个玩家入口的合法性**。
##
## 本文件存在的理由：面板一旦接错，最危险的失败模式不是"崩"而是**静默破坏 LOCKED**：
##   * 冻结不彻底 ⇒ 选择期间敌人继续走 / AP 继续回 / 技能 CD 继续走（违背 L1972）；
##   * 冻结用 paused 实现 ⇒ 玩家点「继续」会误跳到下一波（两套状态混用）；
##   * resolve 不校验候选归属 ⇒ 任何调用方都能凭 id 注入任意强化（UI 越权，绕过三选一规则）；
##   * skip 不计入开放次数 ⇒ 玩家靠"跳过→面板再来"无限刷候选，
##     等于取消 L2045「重掷不能反复刷到满意为止」的限制。
## 每一条都有对应用例钉死。
extends GutTest

## 两波出怪：第 1 波与第 2 波各 1 只普通残响体，**同一时刻生成**。
##
## 为什么这样构造：契约要求「波次清空时触发表板」，而 1-5 的 triggerWaves=[1]。
## 若只有一波，第 1 波清空 = 全部波次完成 = 战斗即将结束，面板不该弹
## （胜负已定后 resolve/reroll/skip 全返回 false，面板点了没用）。
## 两波且第 2 波敌人在场，才能构成"第 1 波清空但战斗仍在进行"的真实触发条件。
const SPAWNS := [
	{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
	{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 2},
]

const ICON_DIR := "res://assets/art/ui/icons"


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


# ============================================================ 夹具

func _data() -> Dictionary:
	return DataRegistry.get_domain("upgrades")


func _enemies() -> Dictionary:
	var t := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


func _chars() -> Dictionary:
	var t := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		t[str(c.get("id", ""))] = c
	return t


func _combat() -> Dictionary:
	return DataRegistry.get_domain("balance").get("combat", {})


func _grid() -> BattleGrid:
	return BattleGrid.from_layout(DataRegistry.get_layout())


## 构建关卡运行时。upgrades 恒注入（除非 data 参数显式给了别的域字典）。
func _rt(stage_id: String, data: Dictionary, spawns: Array) -> StageRuntime:
	var cfg: Dictionary = DataRegistry.get_entry("stages", stage_id).duplicate(true)
	cfg["enemySpawnTimeline"] = spawns
	cfg.erase("waves")
	return StageRuntime.from_config(cfg, _enemies(), _grid(), _chars(), _combat(), data)


## 推进到「第 1 波敌人已生成、但第 1 波尚未完成」的状态。
func _prep(stage_id: String = "1-5", data: Dictionary = {},
		spawns: Array = SPAWNS, tutorial: bool = true) -> StageRuntime:
	var domain: Dictionary = _data() if data.is_empty() else data
	var rt := _rt(stage_id, domain, spawns)
	if tutorial:
		rt.set_tutorial_offer_enabled(true)
	for i: int in range(60 * 3):
		rt.advance(1.0 / 60.0)
	return rt


## 清掉第 1 波的全部敌人 → 下一逻辑步应完成第 1 波并触发面板。
func _clear_wave1(rt: StageRuntime) -> bool:
	var victims: Array[int] = []
	for e: EnemyRuntime in rt.enemies:
		if e.wave_number == 1:
			victims.append(e.instance_id)
	for vid: int in victims:
		rt.despawn_for_test(vid)
	rt.advance(1.0 / 60.0)
	return rt.has_pending_offer()


func _first_enemy_of_wave(rt: StageRuntime, wave: int) -> EnemyRuntime:
	for e: EnemyRuntime in rt.enemies:
		if e.wave_number == wave:
			return e
	return null


# ============================================================ ① 触发时机（契约 1）

func test_wave1_completion_opens_offer_for_1_5() -> void:
	# L2132 + 契约「触发时机」：1-5 在第 1 波清空后弹出面板，候选 3 项。
	var rt := _prep()
	assert_eq(rt.get_errors().size(), 0, "构建应无错误：%s" % str(rt.get_errors()))
	assert_false(rt.has_pending_offer(), "前置：第 1 波未清空时不应有面板")
	assert_true(_clear_wave1(rt), "第 1 波清空后应建立待处理请求")
	assert_eq(int(rt.pending_offer.get("offerIndex", 0)), 1, "本次应是第 1 次开放")
	assert_true(bool(rt.pending_offer.get("isTutorial", false)), "1-5 首次应走固定教学三选一（L2132）")
	assert_eq(int(rt.pending_offer.get("rerollsRemaining", -1)), 1,
		"面板快照应携带剩余重掷（L2117 每场 1 次）")


func test_tutorial_offer_candidates_equal_fixed_choices() -> void:
	# 教学路径的候选必须**逐位等于**数据声明的固定三选一（不是随机抽取）。
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var expected: Array = _data()["tutorialFixedChoices_1_5"]["upgradeIds"]
	var got: Array = rt.pending_offer.get("candidates", [])
	assert_eq(got.size(), 3, "L2054 每次给 3 个选项")
	assert_eq(got.size(), expected.size())
	for i: int in range(expected.size()):
		assert_eq(str(expected[i]), str(got[i]), "教学候选顺序应与声明一致")


func test_offer_index_advances_with_opens() -> void:
	# 两次开放的 offerIndex 应递增（供 UI 显示「第 N 次强化」）。
	var plan := _data().duplicate(true)
	plan["openByStage"]["1-5"]["opens"] = 2
	plan["openByStage"]["1-5"]["triggerWaves"] = [1, 2]
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 2},
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 3},
	]
	var rt := _prep("1-5", plan, spawns)
	assert_true(_clear_wave1(rt), "第 1 次开放应建立")
	assert_eq(int(rt.pending_offer.get("offerIndex", 0)), 1)
	assert_true(rt.resolve_offer(str(rt.pending_offer["candidates"][0])))
	# 清掉第 2 波 → 第 2 次开放
	var victims: Array[int] = []
	for e: EnemyRuntime in rt.enemies:
		if e.wave_number == 2:
			victims.append(e.instance_id)
	for vid: int in victims:
		rt.despawn_for_test(vid)
	rt.advance(1.0 / 60.0)
	assert_true(rt.has_pending_offer(), "第 2 波清空后应建立第 2 次开放")
	assert_eq(int(rt.pending_offer.get("offerIndex", 0)), 2, "offerIndex 应为第 2 次")


func test_blocked_final_wave_does_not_open_offer() -> void:
	# 只有一波且被清空 = 全部波次完成 + 场上无敌人 ⇒ 战斗即将判胜，
	# 此时**不得**弹面板（契约「战斗未结束才触发」）。
	var rt := _prep("1-5", {}, [{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1}])
	assert_true(_clear_wave1(rt) == false || not rt.has_pending_offer(),
		"最终波清空后战斗已实质结束，不得建立面板（否则是点不动的死面板）")


func test_unopened_stage_never_produces_pending_offer() -> void:
	# L2131：1-1～1-4 不开放。整局跑完都不得出现面板。
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(DataRegistry.get_entry("stages", "1-1"), _enemies(), _grid(),
		_chars(), _combat(), _data())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	assert_null(s.stage.upgrades, "1-1 不得启用强化系统（L2131）")
	s.deploy_character("amamiya_mio", 2, 1)
	var saw_offer := false
	for i: int in range(60 * 90):
		s.tick(1.0 / 60.0)
		if s.stage.has_pending_offer():
			saw_offer = true
		if s.is_decided():
			break
	assert_false(saw_offer, "1-1 整局过程中不得出现强化面板")
	assert_false(s.stage.has_pending_offer(), "1-1 结束时不得残留面板")


func test_paused_battle_does_not_open_offer() -> void:
	# 契约：paused==true 时不得建立 pending（玩家暂停与强化冻结是两套状态）。
	# 说明：正常流程下 paused 会先冻住 advance，本用例直接调用**触发点**以验证守卫本身。
	var rt := _prep()
	rt.paused = true
	rt._complete_current_wave()
	assert_false(rt.has_pending_offer(), "暂停中不得建立强化面板")
	rt.paused = false
	assert_false(rt.has_pending_offer(), "恢复后不得补建（本波已完成，不再触发）")


# ============================================================ ② 冻结纪律（L1972）

func test_advance_is_frozen_while_offer_pending() -> void:
	# 契约「冻结战斗」：pending 非空期间不推进任何计时器，返回空数组，
	# 且**不得**把 paused 置为 true。
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var enemy := _first_enemy_of_wave(rt, 2)
	assert_not_null(enemy, "前置：第 2 波敌人应在场（否则本用例测不到移动冻结）")
	var x_before := enemy.logical_x
	var elapsed_before := rt.elapsed_seconds
	rt.ap = 0        # 若 AP 未被冻结，5 秒后会回 5 点
	var returned := rt.advance(5.0)
	assert_eq(returned.size(), 0, "冻结期间 advance 必须返回空数组")
	assert_eq(rt.elapsed_seconds, elapsed_before, "冻结期间逻辑时刻不得推进")
	assert_eq(rt.ap, 0, "冻结期间 AP 自然回复必须停止")
	assert_eq(enemy.logical_x, x_before, "冻结期间敌人不得移动")
	assert_false(rt.paused, "冻结**不得**通过 paused 实现（两套状态不可混用）")


func test_freeze_discards_elapsed_time_and_never_catches_up() -> void:
	# 不补跑 + 不丢逻辑步：pending 期间用**不等长**的 delta 反复 advance，
	# 解冻后的逻辑时刻必须与"从未被阻塞"的对照局**逐位一致**。
	var blocked := _prep()
	var control := _prep()
	assert_true(_clear_wave1(blocked), "前置：blocked 局应建立请求")
	assert_true(_clear_wave1(control), "前置：control 局应建立请求")
	var elapsed_at_freeze := blocked.elapsed_seconds
	assert_eq(blocked.elapsed_seconds, control.elapsed_seconds, "前置：两局进度应一致")
	# blocked 局在选择界面停留 0.7 + 1.3 + 2.5 秒（总 4.5 秒）
	blocked.advance(0.7)
	blocked.advance(1.3)
	blocked.advance(2.5)
	assert_eq(blocked.elapsed_seconds, elapsed_at_freeze, "选择期间逻辑时刻必须一动不动")
	# 两局以同一方式结束选择
	assert_true(blocked.skip_offer())
	assert_true(control.skip_offer())
	# 解冻后推进同样时长
	blocked.advance(2.0)
	control.advance(2.0)
	assert_eq(blocked.elapsed_seconds, control.elapsed_seconds,
		"解冻后不得补跑选择期间的时间（也不得丢逻辑步）")
	assert_almost_eq(blocked.elapsed_seconds, elapsed_at_freeze + 2.0, 0.0001,
		"解冻后应恰好推进 2.0 秒")


# ============================================================ ③ resolve_offer

func test_resolve_offer_applies_and_resumes_battle() -> void:
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var pick := str(rt.pending_offer["candidates"][0])
	assert_true(rt.resolve_offer(pick), "选择候选内的强化应成功")
	assert_eq(rt.upgrades.selections_used, 1, "成功选择应计入已用开放次数")
	assert_false(rt.has_pending_offer(), "成功后必须清空 pending")
	assert_eq(rt.upgrades.stacks_of(pick), 1, "效果应真的应用（层数 1）")
	# 恢复推进：逻辑时刻重新走动
	var before := rt.elapsed_seconds
	rt.advance(1.0)
	assert_gt(rt.elapsed_seconds, before, "选择完成后战斗必须恢复推进")
	assert_false(rt.paused, "恢复推进不得依赖 paused 状态")


func test_resolve_offer_changes_damage_end_to_end() -> void:
	# 端到端：选「会心准备（远程攻击 +15%）」后，**首条伤害事件**必须比对照局高。
	# 取首条而不是累计：累计会被敌人 HP 截断（两边都停在 420），测不出倍率是否生效。
	var plain := _first_hit_damage_after_offer(false)
	var boosted := _first_hit_damage_after_offer(true)
	assert_gt(plain, 0, "前置：对照组必须真的打出伤害，否则本用例没有意义")
	assert_gt(boosted, plain,
		"选择攻击强化后伤害必须变高（plain=%d boosted=%d）" % [plain, boosted])


## 建立面板 → （选择远程攻击强化 / 跳过）→ 部署神谷悠真（RANGED）→ 返回首条对敌伤害。
func _first_hit_damage_after_offer(use_upgrade: bool) -> int:
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var candidates: Array = rt.pending_offer.get("candidates", [])
	assert_true(candidates.has("upgrade_ranged_atk"), "前置：1-5 教学候选应含远程攻击强化")
	if use_upgrade:
		assert_true(rt.resolve_offer("upgrade_ranged_atk"), "选择应成功")
	else:
		assert_true(rt.skip_offer(), "对照组跳过应成功")
	rt.add_ap(99)
	var res := rt.deploy_character("kamiya_yuma", 2, 1)
	assert_true(res.ok, "部署应成功，实际：%s" % res.reason_text())
	for i: int in range(60 * 25):
		rt.advance(1.0 / 60.0)
		if not rt.damage_events.is_empty():
			break
	for ev: Dictionary in rt.damage_events:
		if str(ev.get("targetKind", "")) == "enemy":
			return int(ev.get("amount", 0))
	return 0


func test_resolve_offer_twice_is_rejected_and_does_not_stack() -> void:
	# 重复提交同一 id：第二次必须失败，且**不得重复应用**（层数不能翻倍）。
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var pick := str(rt.pending_offer["candidates"][0])
	assert_true(rt.resolve_offer(pick))
	assert_false(rt.resolve_offer(pick), "第二次提交必须失败（pending 已清空 + 次数已用尽）")
	assert_eq(rt.upgrades.stacks_of(pick), 1, "层数不得因重复提交而翻倍")
	assert_eq(rt.upgrades.selections_used, 1, "已用开放次数不得翻倍")


func test_resolve_offer_rejects_non_candidate_id() -> void:
	# 越权防护：id 必须属于**当前候选**，不能凭 id 任意注入强化。
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var candidates: Array = rt.pending_offer.get("candidates", [])
	var outsider := ""
	for id: String in rt.upgrades.all_ids():
		if not candidates.has(id):
			outsider = id
			break
	assert_false(outsider.is_empty(), "前置：应存在一个不在候选内的合法强化 id")
	assert_false(rt.resolve_offer(outsider),
		"候选外的 id 必须被拒（%s 不在 %s 中）" % [outsider, str(candidates)])
	assert_true(rt.has_pending_offer(), "拒绝时**不得**清空 pending（玩家可改选）")
	assert_eq(rt.upgrades.selections_used, 0, "被拒的选择不得计入开放次数")
	assert_eq(rt.upgrades.stacks_of(outsider), 0, "被拒的强化不得生效")


func test_resolve_offer_rejects_unknown_id() -> void:
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	assert_false(rt.resolve_offer("not_a_real_upgrade"))
	assert_true(rt.has_pending_offer(), "未知 id 被拒后 pending 应保留")


func test_resolve_offer_without_pending_is_rejected() -> void:
	var rt := _prep()
	assert_false(rt.has_pending_offer(), "前置：本局不应有面板")
	assert_false(rt.resolve_offer("upgrade_atk_all"), "无 pending 时必须返回 false")
	assert_eq(rt.upgrades.selections_used, 0)


# ============================================================ ④ reroll_offer

func test_reroll_offer_is_single_use() -> void:
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	assert_true(rt.reroll_offer(), "首次重掷应可用（L2117）")
	assert_eq(rt.upgrades.rerolls_remaining, 0, "重掷后剩余次数应为 0")
	assert_eq(rt.upgrades.reroll_count, 1, "重掷计数应 +1（参与候选种子）")
	assert_true(rt.has_pending_offer(), "重掷后仍应保持 pending")
	assert_false(rt.reroll_offer(), "重掷只有 1 次，第二次必须失败")


func test_tutorial_reroll_keeps_fixed_candidates_and_consumes_reroll() -> void:
	# 教学态取舍（L2132）：重掷后候选仍是固定教学三项，但**照常消耗**那 1 次重掷。
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var before: Array = rt.pending_offer.get("candidates", []).duplicate()
	var expected: Array = _data()["tutorialFixedChoices_1_5"]["upgradeIds"]
	assert_eq(rt.upgrades.rerolls_remaining, 1)
	assert_true(rt.reroll_offer(), "教学态重掷应成功（消耗次数）")
	assert_eq(rt.upgrades.rerolls_remaining, 0, "教学态重掷同样消耗次数")
	var after: Array = rt.pending_offer.get("candidates", [])
	assert_eq(after.size(), expected.size())
	for i: int in range(expected.size()):
		assert_eq(str(after[i]), str(expected[i]), "教学态重掷后候选应保持固定（L2132）")
	assert_eq(before, after, "教学态重掷前后候选应完全一致")


func test_reroll_rebuilds_deterministically() -> void:
	# 契约「重掷确定性」：两个独立运行时在同一状态下重掷，必须得到同一候选集。
	# 这条同时钉死「重掷次数参与种子」与「种子不含 elapsed_seconds」。
	var a := _prep("1-5", {}, SPAWNS, false)
	var b := _prep("1-5", {}, SPAWNS, false)
	assert_true(_clear_wave1(a) and _clear_wave1(b), "前置：两局都应建立请求")
	assert_eq(a.pending_offer.get("candidates"), b.pending_offer.get("candidates"),
		"重掷前候选应一致")
	assert_true(a.reroll_offer() and b.reroll_offer(), "两局重掷都应成功")
	assert_eq(a.pending_offer.get("candidates"), b.pending_offer.get("candidates"),
		"重掷后候选必须仍然由稳定种子决定（同状态同结果）")


func test_reroll_without_pending_is_rejected() -> void:
	var rt := _prep()
	assert_false(rt.reroll_offer(), "无 pending 时重掷必须返回 false")
	assert_eq(rt.upgrades.rerolls_remaining, 1, "失败的调用不得消耗重掷次数")


# ============================================================ ⑤ skip_offer

func test_skip_offer_consumes_open_and_leaves_no_gained_upgrade() -> void:
	# L2051 允许跳过；但跳过必须**计入开放次数**，否则等于无限刷候选。
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	assert_true(rt.skip_offer(), "跳过应成功")
	assert_false(rt.has_pending_offer(), "跳过后应清空 pending")
	assert_eq(rt.upgrades.selections_used, 1, "跳过必须计入已用开放次数（防无限刷）")
	assert_eq(rt.upgrades.total_selections(), 0, "跳过不得应用任何效果")
	assert_eq(rt.upgrade_summary().size(), 0, "跳过的强化不得出现在「本局已获得」（跳过 ≠ 获得）")
	# 次数用尽后不得再开
	assert_false(rt.upgrade_choices().size() == 3, "开放次数用尽后不应再提供候选")


func test_skip_without_pending_is_rejected() -> void:
	var rt := _prep()
	assert_false(rt.skip_offer(), "无 pending 时跳过必须返回 false")
	assert_eq(rt.upgrades.selections_used, 0)


# ============================================================ ⑥ 池耗尽

func test_exhausted_pool_does_not_open_offer_and_keeps_opens() -> void:
	# 池耗尽（全部 maxStacks 打满）⇒ **不建立** pending、**不消耗**开放次数、记日志。
	var rt := _prep()
	for id: String in rt.upgrades.all_ids():
		var limit := int(rt.upgrades.definition(id).get("maxStacks", 1))
		for i: int in range(limit):
			rt.upgrades.apply(id)
	assert_true(rt.upgrade_summary().size() > 0, "前置：夹具应已把池打满")
	assert_false(_clear_wave1(rt), "候选为空时不得建立 pending")
	assert_false(rt.has_pending_offer())
	assert_eq(rt.upgrades.selections_used, 0, "候选为空不得消耗开放次数（否则白白吃掉一次开放）")


func test_tutorial_falls_back_to_random_when_fixed_choice_maxed() -> void:
	# 教学项有一项已满叠 ⇒ 整体回落随机候选，且 isTutorial 必须为 false
	# （不给"缺一个"的教学，也不谎称这是教学面板）。
	var rt := _prep()
	var victim := str(_data()["tutorialFixedChoices_1_5"]["upgradeIds"][1])
	var limit := int(rt.upgrades.definition(victim).get("maxStacks", 1))
	for i: int in range(limit):
		rt.upgrades.apply(victim)
	assert_eq(rt.tutorial_upgrade_choices(_data()).size(), 0, "前置：教学项应已回落为空")
	assert_true(_clear_wave1(rt), "回落随机后仍应能建立面板（池未耗尽）")
	assert_false(bool(rt.pending_offer.get("isTutorial", true)),
		"教学不可用时应标记为非教学")
	var candidates: Array = rt.pending_offer.get("candidates", [])
	assert_false(candidates.has(victim), "已满叠的条目不得进入候选（L2056 第 5 步）")


# ============================================================ ⑦ 战斗结束

func test_finished_battle_rejects_all_offer_actions() -> void:
	# 契约：战斗已结束 ⇒ resolve / reroll / skip 一律返回 false。
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	rt.running = false          # 模拟上层停表（BattleSession 在胜负确定时设置）
	var pick := str(rt.pending_offer["candidates"][0])
	assert_false(rt.resolve_offer(pick), "战斗结束后不得再选择")
	assert_false(rt.reroll_offer(), "战斗结束后不得再重掷")
	assert_false(rt.skip_offer(), "战斗结束后不得再跳过")
	assert_eq(rt.upgrades.selections_used, 0, "失败的调用不得消耗开放次数")


func test_finished_battle_does_not_open_new_offer() -> void:
	var rt := _prep()
	rt.running = false
	assert_false(_clear_wave1(rt), "战斗结束后不得建立新的强化面板")
	assert_false(rt.has_pending_offer())


func test_core_destroyed_does_not_open_offer() -> void:
	# D-41 立即失败：核心归零后不得弹出要求玩家操作的强化面板。
	var rt := _prep()
	rt.core_hp = 0
	assert_false(_clear_wave1(rt), "核心归零后不得建立强化面板")


# ============================================================ ⑧ upgrade_summary 与探针

func test_upgrade_summary_order_and_data_source() -> void:
	# 顺序 + 层数 + 数据一致性：name/category/icon 必须与 upgrades.json 一致。
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var pick := str(rt.pending_offer["candidates"][0])
	assert_true(rt.resolve_offer(pick))
	var summary := rt.upgrade_summary()
	assert_eq(summary.size(), 1, "选 1 项应只产出 1 条")
	var cfg: Dictionary = rt.upgrades.definition(pick)
	var row: Dictionary = summary[0]
	assert_eq(str(row.get("id", "")), pick)
	assert_eq(str(row.get("name", "")), str(cfg.get("name", "")), "名称必须来自数据（不得写死在代码里）")
	assert_eq(str(row.get("description", "")), str(cfg.get("description", "")))
	assert_eq(str(row.get("category", "")), str(cfg.get("category", "")))
	assert_eq(str(row.get("icon", "")), str(cfg.get("icon", "")))
	assert_eq(str(row.get("tier", "")), str(cfg.get("tier", "")))
	assert_eq(int(row.get("maxStacks", 0)), int(cfg.get("maxStacks", 0)))
	assert_eq(int(row.get("stacks", 0)), 1)


func test_upgrade_summary_is_empty_before_any_selection() -> void:
	var rt := _prep()
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	assert_eq(rt.upgrade_summary().size(), 0, "未选择时「本局已获得」必须为空")


func test_upgrade_summary_follows_gain_order() -> void:
	# 按**获得顺序**返回（契约）：先选的必须排在前面。
	var plan := _data().duplicate(true)
	plan["openByStage"]["1-5"]["opens"] = 2
	plan["openByStage"]["1-5"]["triggerWaves"] = [1, 2]
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 2},
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 3},
	]
	var rt := _prep("1-5", plan, spawns)
	assert_true(_clear_wave1(rt), "第 1 次开放应建立")
	var first := str(rt.pending_offer["candidates"][0])
	assert_true(rt.resolve_offer(first))
	var victims: Array[int] = []
	for e: EnemyRuntime in rt.enemies:
		if e.wave_number == 2:
			victims.append(e.instance_id)
	for vid: int in victims:
		rt.despawn_for_test(vid)
	rt.advance(1.0 / 60.0)
	assert_true(rt.has_pending_offer(), "前置：第 2 次开放应建立")
	var second := ""
	for cand: Variant in rt.pending_offer["candidates"]:
		if str(cand) != first:
			second = str(cand)
			break
	assert_false(second.is_empty(), "前置：第 2 次应与第 1 次不同项可选")
	assert_true(rt.resolve_offer(second))
	var summary := rt.upgrade_summary()
	assert_eq(summary.size(), 2, "两次选择应产出 2 条")
	assert_eq(str(summary[0].get("id", "")), first, "获得顺序应从最先选的开始")
	assert_eq(str(summary[1].get("id", "")), second)


func test_offer_debug_dict_exposes_pending_state() -> void:
	var rt := _prep()
	assert_eq(bool(rt.offer_debug_dict().get("active", true)), false, "无面板时 active 应为 false")
	assert_true(_clear_wave1(rt), "前置：应建立待处理请求")
	var dbg := rt.offer_debug_dict()
	assert_eq(bool(dbg.get("active", false)), true)
	assert_eq(int(dbg.get("ids", []).size()), 3, "ids 应列出全部候选")
	assert_eq(int(dbg.get("offerIndex", 0)), 1)
	assert_eq(int(dbg.get("rerollsRemaining", -1)), 1)
	assert_true(bool(dbg.get("isTutorial", false)))
	# to_debug_dict 也应暴露（探针/测试读取）
	var full := rt.to_debug_dict()
	assert_true(full.has("upgradeOffer"), "to_debug_dict 应含 upgradeOffer 键")
	assert_true(full.has("gainedUpgrades"), "to_debug_dict 应含 gainedUpgrades 键")


# ============================================================ ⑨ 数据层：category / icon

func test_icon_whitelist_entries_exist_on_disk() -> void:
	# 白名单是**代码里的静态表**（不读磁盘），但每一项必须真实存在，
	# 否则实机画不出图标。本用例把「代码白名单 ↔ 美术资产」的漂移变成可执行守卫。
	assert_gt(InBattleUpgrades.ICON_WHITELIST.size(), 0, "白名单不得为空")
	for icon: String in InBattleUpgrades.ICON_WHITELIST:
		var path := "%s/%s_64.png" % [ICON_DIR, icon]
		assert_true(FileAccess.file_exists(path),
			"白名单图标必须真实存在：%s（实际查找 %s）" % [icon, path])


func test_every_upgrade_declares_legal_category_and_icon() -> void:
	var u := InBattleUpgrades.from_data(_data())
	assert_eq(u.get_errors().size(), 0, "upgrades.json 校验应无错误：%s" % str(u.get_errors()))
	for id: String in u.all_ids():
		var cfg := u.definition(id)
		var category := str(cfg.get("category", ""))
		var icon := str(cfg.get("icon", ""))
		assert_true(InBattleUpgrades.is_category_allowed(category),
			"强化 %s 的 category 必须属于 L1979 表 79：%s" % [id, category])
		assert_true(InBattleUpgrades.is_icon_allowed(icon),
			"强化 %s 的 icon 必须在白名单内：%s" % [id, icon])
		assert_true(FileAccess.file_exists("%s/%s_64.png" % [ICON_DIR, icon]),
			"强化 %s 的图标资产必须存在：%s" % [id, icon])


func test_missing_category_is_reported() -> void:
	var raw := _data().duplicate(true)
	var items: Array = raw["upgrades"]
	items.append({
		"id": "no_category", "tier": "COMMON", "appliesTo": "ALL", "maxStacks": 1,
		"icon": "icon_attack_up",
		"effect": {"type": "STAT_MOD", "stat": "ATTACK", "value": 0.1},
	})
	var u := InBattleUpgrades.from_data(raw)
	assert_gt(u.get_errors().size(), 0, "缺少 category 必须被报告，不得静默收下")
	assert_false(u.has_definition("no_category"), "非法条目不得进入定义表")


func test_illegal_category_is_reported() -> void:
	var raw := _data().duplicate(true)
	var items: Array = raw["upgrades"]
	items.append({
		"id": "bad_category", "tier": "COMMON", "appliesTo": "ALL", "maxStacks": 1,
		"category": "不存在的类别", "icon": "icon_attack_up",
		"effect": {"type": "STAT_MOD", "stat": "ATTACK", "value": 0.1},
	})
	var u := InBattleUpgrades.from_data(raw)
	assert_gt(u.get_errors().size(), 0, "非法 category 必须被报告")
	assert_false(u.has_definition("bad_category"))


func test_icon_outside_whitelist_is_reported() -> void:
	var raw := _data().duplicate(true)
	var items: Array = raw["upgrades"]
	items.append({
		"id": "bad_icon", "tier": "COMMON", "appliesTo": "ALL", "maxStacks": 1,
		"category": "攻击型", "icon": "icon_totally_missing",
		"effect": {"type": "STAT_MOD", "stat": "ATTACK", "value": 0.1},
	})
	var u := InBattleUpgrades.from_data(raw)
	assert_gt(u.get_errors().size(), 0, "白名单外的 icon 必须被报告")
	assert_false(u.has_definition("bad_icon"))
	# 对照：缺少 icon 字段同样必须被拒
	var raw2 := _data().duplicate(true)
	(raw2["upgrades"] as Array).append({
		"id": "no_icon", "tier": "COMMON", "appliesTo": "ALL", "maxStacks": 1,
		"category": "攻击型",
		"effect": {"type": "STAT_MOD", "stat": "ATTACK", "value": 0.1},
	})
	var u2 := InBattleUpgrades.from_data(raw2)
	assert_gt(u2.get_errors().size(), 0, "缺少 icon 必须被报告")


func test_trigger_waves_declared_for_open_stages_only() -> void:
	var plan: Dictionary = _data().get("openByStage", {})
	for sid: String in ["1-1", "1-2", "1-3", "1-4"]:
		assert_true(plan.has(sid), "开放表应显式列出 %s" % sid)
		assert_eq(_trigger_waves_of(plan[sid]), [],
			"%s 不开放，triggerWaves 必须为空数组（不得缺省猜）" % sid)
	# 注意：JSON 把所有数字解析为 float，声明里的 [1] 读出来是 [1.0]，
	# 因此必须按 int 比较，不能用 assert_eq(..., [1]) 直接比（会假红）。
	assert_eq(_trigger_waves_of(plan["1-5"]), [1],
		"1-5 应在第 1 波清空后触发（契约）")


## 把原始 JSON 的 triggerWaves 规范化为 Array[String] 便于比较（JSON 数字为 float）。
func _trigger_waves_of(entry: Variant) -> Array:
	var out: Array = []
	if typeof(entry) != TYPE_DICTIONARY:
		return out
	var raw: Variant = (entry as Dictionary).get("triggerWaves", null)
	if typeof(raw) != TYPE_ARRAY:
		return out
	for v: Variant in (raw as Array):
		out.append(int(v))
	return out


func test_missing_trigger_waves_disables_upgrades() -> void:
	# 契约纪律：triggerWaves 缺失 ⇒ 不启用 + 报错，**不得**兜底成"每波都能触发"。
	var bad := _data().duplicate(true)
	bad["openByStage"]["1-5"].erase("triggerWaves")
	var rt := _rt("1-5", bad, SPAWNS)
	assert_null(rt.upgrades, "缺少 triggerWaves 时不得启用强化系统")
	assert_gt(rt.get_errors().size(), 0, "缺少 triggerWaves 必须上报错误")


func test_illegal_trigger_waves_disables_upgrades() -> void:
	var bad := _data().duplicate(true)
	bad["openByStage"]["1-5"]["triggerWaves"] = [0]
	var rt := _rt("1-5", bad, SPAWNS)
	assert_null(rt.upgrades, "非法波号时不得启用强化系统")
	assert_gt(rt.get_errors().size(), 0, "非法波号必须上报错误")
	var bad2 := _data().duplicate(true)
	bad2["openByStage"]["1-5"]["triggerWaves"] = "1"
	var rt2 := _rt("1-5", bad2, SPAWNS)
	assert_null(rt2.upgrades, "triggerWaves 非数组时不得启用")
	assert_gt(rt2.get_errors().size(), 0)


# ============================================================ ⑩ 零影响不变量（1-1）

func test_stage_1_1_battle_is_bit_identical_to_reference() -> void:
	# 未开放强化的关卡整局跑完必须与接入前逐位一致，且全程无面板。
	var a := _run_1_1()
	var b := _run_1_1()
	assert_null(a["upgrades"], "1-1 不应启用强化系统")
	assert_eq(a["outcome"], b["outcome"], "同输入必须同胜负")
	assert_eq(a["killed"], b["killed"])
	assert_eq(a["coreHp"], b["coreHp"])
	assert_eq(a["elapsed"], b["elapsed"], "同输入必须同逻辑时长")
	assert_false(a["sawOffer"], "1-1 全程不得出现强化面板")


func _run_1_1() -> Dictionary:
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(DataRegistry.get_entry("stages", "1-1"), _enemies(), _grid(),
		_chars(), _combat(), _data())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	s.deploy_character("amamiya_mio", 2, 1)
	var saw := false
	for i: int in range(60 * 90):
		s.tick(1.0 / 60.0)
		if s.stage.has_pending_offer():
			saw = true
		if s.is_decided():
			break
	return {
		"outcome": s.outcome,
		"killed": s.stage.enemies_killed,
		"coreHp": s.stage.core_hp,
		"elapsed": snappedf(s.stage.elapsed_seconds, 0.001),
		"upgrades": s.stage.upgrades,
		"sawOffer": saw,
	}


# ============================================================ ⑪ 整局不卡死（端到端）

func test_full_1_5_run_resolves_offer_and_finishes() -> void:
	# 端到端：1-5 整局跑完。**若冻结/解冻接错，这条会超时或永远不判胜负**
	# （面板不放行 ⇒ 战斗停在 Wave 1；或时间补跑 ⇒ 波次统计错位）。
	# 本用例用真实 1-5 关卡数据（含 5 波、2 只监考者），走 BattleSession 全路径。
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(DataRegistry.get_entry("stages", "1-5"), _enemies(), _grid(),
		_chars(), _combat(), _data())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	s.stage.set_tutorial_offer_enabled(true)
	s.deploy_character("amamiya_mio", 2, 1)
	var offers := 0
	var frozen_checks := 0
	for i: int in range(60 * 400):
		s.tick(1.0 / 60.0)
		if s.stage.has_pending_offer():
			offers += 1
			# 面板出现后，再 tick 若干次：逻辑时刻必须一动不动（L1972）。
			# 注意必须在**本步之后**取样——建立 pending 的那一步本身已经推进了一个逻辑步，
			# 若在 tick 之前取样就会把"刚推进的那一步"误判成"没冻结"。
			var frozen_at := s.stage.elapsed_seconds
			s.tick(1.0 / 60.0)
			s.tick(0.5)
			if s.stage.elapsed_seconds == frozen_at and not s.stage.paused:
				frozen_checks += 1
			assert_true(s.stage.resolve_offer(str(s.stage.pending_offer["candidates"][0])),
				"自动解算面板应成功（模拟 autoplay 走同一域层入口）")
		if s.is_decided():
			break
	assert_true(s.is_decided(), "1-5 整局必须在时间上限内分出胜负（不得被面板卡死）")
	assert_gte(offers, 1, "1-5 整局至少应弹出过 1 次强化面板（L2132）")
	assert_false(s.stage.has_pending_offer(), "结束时不得残留未处理的面板")
	assert_eq(s.stage.upgrades.selections_used, offers, "每次面板都应恰好消耗一次开放")
	assert_eq(s.stage.upgrade_summary().size(), offers,
		"每次都选了一项 ⇒ 「本局已获得」应与之对应（1-5 只开放 1 次）")
	assert_eq(frozen_checks, offers, "每次面板期间都应观察到时间冻结")
