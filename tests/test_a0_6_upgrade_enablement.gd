## Alpha A0.6 局内强化的**启用与端到端生效**回归。
##
## 与 tests/test_a0_6_in_battle_upgrades.gd 的分工：
##   那个文件管数据契约、倍率数学、候选算法；
##   本文件管「关卡到底有没有启用」「启用后到底改不改战斗结果」「有没有破坏 LOCKED」。
##
## 本文件最重要的三条：
##   ① 未声明开放的关卡必须 upgrades == null（不静默开启）；
##   ② 启用后强化必须**真的**改变伤害/AP 回复（否则是假接线）；
##   ③ 候选种子**不得依赖逻辑时刻**，否则不同帧率会摇出不同候选，
##      破坏「不同分辨率与渲染帧率不改变战斗结果」这条 LOCKED 保证。
extends GutTest


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


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


## 构建一个关卡运行时。pass_upgrades 控制是否注入强化数据；
## spawns 走 enemySpawnTimeline（工程无直接出怪 API，既有测试同一套路）。
func _rt(stage_id: String, with_upgrades: bool, spawns: Array = []) -> StageRuntime:
	var cfg: Dictionary = DataRegistry.get_entry("stages", stage_id).duplicate(true)
	cfg["enemySpawnTimeline"] = spawns
	cfg.erase("waves")
	return StageRuntime.from_config(cfg, _enemies(), _grid(), _chars(), _combat(),
		_data() if with_upgrades else {})


# ============================================================ ① 开放节奏

func test_stage_1_1_does_not_enable_upgrades() -> void:
	# L2131：1-1～1-4 不开放。未启用时 upgrades 必须为 null，倍率恒 1.0。
	var rt := _rt("1-1", true)
	assert_eq(rt.get_errors().size(), 0, "构建应无错误：%s" % str(rt.get_errors()))
	assert_null(rt.upgrades, "1-1 不得启用局内强化（L2131）")


func test_stage_1_5_enables_upgrades_when_data_injected() -> void:
	# L2132：1-5 首次开放 1 次教学三选一
	var rt := _rt("1-5", true)
	assert_eq(rt.get_errors().size(), 0, "构建应无错误：%s" % str(rt.get_errors()))
	assert_not_null(rt.upgrades, "1-5 应启用局内强化")
	assert_eq(rt.upgrades.total_opens, 1, "1-5 开放 1 次（L2132）")
	assert_eq(rt.upgrades.rerolls_remaining, 1, "每场默认 1 次免费重掷（L2117）")


func test_stage_1_5_stays_disabled_without_injection() -> void:
	# 不注入数据（如 tools/ 模拟器）时，1-5 也必须不启用 —— 证明"注入式"没有后门
	var rt := _rt("1-5", false)
	assert_null(rt.upgrades, "未注入 upgrades 数据时不得启用强化系统")


func test_unknown_stage_never_enables() -> void:
	# 未在 openByStage 显式列出的关卡一律不启用（不拿 default 当开放依据）
	var rt := _rt("1-11", true)
	assert_null(rt.upgrades, "Unknown stages must not enable upgrades")


func test_bad_upgrade_data_disables_and_reports() -> void:
	# 数据坏掉时：不启用 + 报错，而不是带着坏数据继续跑
	var bad := _data().duplicate(true)
	var items: Array = bad["upgrades"]
	items.append({"id": "x_broken", "tier": "NOPE", "appliesTo": "STAGE",
		"maxStacks": 1, "effect": {"type": "STAT_MOD", "stat": "ATTACK", "value": 0.1}})
	var cfg: Dictionary = DataRegistry.get_entry("stages", "1-5").duplicate(true)
	cfg["enemySpawnTimeline"] = []
	cfg.erase("waves")
	var rt := StageRuntime.from_config(cfg, _enemies(), _grid(), _chars(), _combat(), bad)
	assert_null(rt.upgrades, "数据有错时不得启用强化")
	assert_gt(rt.get_errors().size(), 0, "数据错误必须并入关卡错误上报")


# ============================================================ ② 真的生效

func test_enabling_attack_upgrade_increases_damage() -> void:
	# 端到端：让角色真的打一个敌人，比较累计伤害。
	# 若接线是假的（倍率算了但没人用），两边伤害会相等，这条就红。
	var dmg_plain := _first_hit_damage(false)
	var dmg_boost := _first_hit_damage(true)
	assert_gt(dmg_plain, 0, "前置：对照组必须真的打出伤害，否则本用例没有意义")
	assert_gt(dmg_boost, dmg_plain,
		"攻击强化必须提高实际造成的伤害（plain=%d boosted=%d）" % [dmg_plain, dmg_boost])


## 部署雨宫澪 + 按 timeline 生成一个普通敌人，推进固定步数，
## 返回**第一次出手**的伤害数值。
##
## 为什么取首条伤害事件而不是累计伤害：累计值会被敌人血量截断
## （echo_normal HP=420，两次 210 就打死了），那样两边都停在 420，
## 测不出倍率是否生效 —— 这正是本用例第一次跑失败的原因。
## 首条事件不受击杀影响，且直接来自领域层结算，是有效测量。
func _first_hit_damage(with_upgrades: bool) -> int:
	var spawns := [{"time": 0.5, "lane": 1, "enemy": "echo_normal"}]
	var rt := _rt("1-5", with_upgrades, spawns)
	if with_upgrades:
		assert_true(rt.choose_upgrade("upgrade_atk_all"), "应能选择全队攻击强化")
	rt.add_ap(99)
	var res := rt.deploy_character("amamiya_mio", 2, 1)
	assert_true(res.ok, "部署应成功，实际：%s" % res.reason_text())
	for i: int in range(60 * 20):
		rt.advance(1.0 / 60.0)
		if not rt.damage_events.is_empty():
			break
	for ev: Dictionary in rt.damage_events:
		if str(ev.get("targetKind", "")) == "enemy":
			return int(ev.get("amount", 0))
	return 0


func test_ap_regen_upgrade_speeds_up_regeneration() -> void:
	# 用固定步数推进，比较 AP 增量：强化局必须比对照局回得多
	var plain := _rt("1-5", false)
	var boosted := _rt("1-5", true)
	assert_true(boosted.choose_upgrade("upgrade_ap_regen"))
	# 清空到同一个起点，避免部署费用差异干扰
	for rt: StageRuntime in [plain, boosted]:
		rt.ap = 0
	for i: int in range(60 * 20):
		plain.advance(1.0 / 60.0)
		boosted.advance(1.0 / 60.0)
	assert_gt(boosted.ap, plain.ap,
		"AP 回复强化必须让同长度对局回更多 AP（plain=%d boosted=%d）" % [plain.ap, boosted.ap])
	assert_eq(plain.ap, 20, "对照组应恰好回 20 AP（1/秒 × 20 秒）")


func test_defense_upgrade_reduces_damage_taken() -> void:
	# 前线防御 +20% 必须降低角色受到的伤害（消费点在敌人攻击的防御端）。
	# 注意 _defense_of_target() 返回的**已经是有效防御值**（内含 defense），
	# 不可再乘一次 defense —— 那会得到 defense² 的无意义数值。
	var plain := _rt("1-5", false)
	var boosted := _rt("1-5", true)
	var p := plain.deploy_character("amamiya_mio", 2, 1)
	var b := boosted.deploy_character("amamiya_mio", 2, 1)
	assert_true(p.ok and b.ok, "部署应成功")
	assert_almost_eq(plain._defense_of_target(p.character), float(p.character.defense), 0.001,
		"未启用强化时有效防御必须等于基础防御")
	assert_true(boosted.choose_upgrade("upgrade_def_front"))
	var def_plain := plain._defense_of_target(p.character)
	var def_boost := boosted._defense_of_target(b.character)
	assert_gt(def_boost, def_plain, "防御强化必须抬高有效防御")
	var dmg_plain := plain.combat_math.compute_damage(100.0, def_plain)
	var dmg_boost := boosted.combat_math.compute_damage(100.0, def_boost)
	assert_lt(dmg_boost, dmg_plain,
		"防御强化必须降低受伤（plain=%d boost=%d）" % [dmg_plain, dmg_boost])


func test_retreat_refund_upgrade_increases_refund() -> void:
	var plain := _rt("1-5", false)
	var boosted := _rt("1-5", true)
	var rp := plain.deploy_character("amamiya_mio", 2, 1)
	var rb := boosted.deploy_character("amamiya_mio", 2, 1)
	assert_true(boosted.choose_upgrade("upgrade_fast_retreat"))
	var refund_plain := plain.compute_retreat_refund(10)
	var refund_boost := boosted.compute_retreat_refund(10)
	assert_eq(refund_plain, 5, "基础返还 50% → 10 费返 5")
	assert_gt(refund_boost, refund_plain, "「快速换防」必须提高返还")


func test_selection_cap_is_enforced() -> void:
	# L2116：1-5 只开放 1 次；选完第二次必须被拒
	var rt := _rt("1-5", true)
	assert_true(rt.choose_upgrade("upgrade_atk_all"))
	assert_false(rt.choose_upgrade("upgrade_def_front"), "超出 total_opens 必须被拒")
	assert_eq(rt.upgrades.selections_used, 1)


func test_reroll_is_single_use() -> void:
	var rt := _rt("1-5", true)
	assert_true(rt.reroll_upgrades(), "首次重掷应可用（L2117）")
	assert_false(rt.reroll_upgrades(), "重掷只有 1 次，第二次必须失败")


# ============================================================ ③ LOCKED 保证

func test_choices_are_deterministic_across_runtime_instances() -> void:
	# 同一关卡、同一选择进度，两个独立运行时必须摇出同一候选集
	var a := _rt("1-5", true)
	var b := _rt("1-5", true)
	assert_eq(a.upgrade_choices(), b.upgrade_choices(),
		"候选必须由稳定种子决定，不得依赖实例状态或全局随机")
	assert_eq(a.upgrade_choices().size(), 3, "L2054 每次 3 个选项")


func test_choices_do_not_depend_on_elapsed_time() -> void:
	# 关键 LOCKED：不同帧率/不同推进时机不得改变候选。
	# 若种子混入了 elapsed_seconds，这条会红。
	var a := _rt("1-5", true)
	var b := _rt("1-5", true)
	for i: int in range(60 * 13):
		b.advance(1.0 / 60.0)     # b 多推进 13 秒
	# 前置：确认两局的逻辑时刻确实不同，否则这条断言是空转
	assert_gt(b.elapsed_seconds, 12.0, "前置失败：b 未真正推进时间")
	assert_lt(a.elapsed_seconds, 0.001, "前置失败：a 不应已推进")
	assert_eq(a.upgrade_choices(), b.upgrade_choices(),
		"候选不得随逻辑时刻变化（否则破坏帧率无关性）")


func test_choices_change_after_a_selection() -> void:
	# 选过一次之后，池与叠层状态变了，候选应当重新计算（不重复推同一份）
	var rt := _rt("1-5", true)
	var before := rt.upgrade_choices()
	assert_true(before.size() == 3)
	rt.choose_upgrade(before[0])
	# 1-5 只开放 1 次，因此选完后不得再给候选（避免"还能继续选"的错觉）
	assert_eq(rt.upgrade_choices().size(), 0,
		"选择次数用尽后不应再提供候选")


func test_tutorial_fixed_choices_for_1_5() -> void:
	# L2132：1-5 首次是固定教学三选一，不走随机
	var rt := _rt("1-5", true)
	var fixed := rt.tutorial_upgrade_choices(_data())
	assert_eq(fixed.size(), 3, "教学固定三选一应有 3 项")
	var expected: Array = _data()["tutorialFixedChoices_1_5"]["upgradeIds"]
	for i: int in range(expected.size()):
		assert_eq(str(expected[i]), fixed[i], "教学选项顺序应与声明一致")


func test_tutorial_choices_fall_back_when_one_is_unusable() -> void:
	# 有一项不可用就整体回落（不硬凑缺一个的教学）。
	# 注意必须把该项**叠层打满**才算不可用：upgrade_def_front 的 maxStacks=3，
	# 只 apply 一次它仍然可选 —— 第一版测试就是误在这里。
	var rt := _rt("1-5", true)
	var expected: Array = _data()["tutorialFixedChoices_1_5"]["upgradeIds"]
	var victim := str(expected[1])
	var limit := int(rt.upgrades.definition(victim).get("maxStacks", 1))
	for i: int in range(limit):
		assert_true(rt.upgrades.apply(victim), "夹具应能把 %s 叠到上限" % victim)
	assert_false(rt.upgrades.can_select(victim), "前置：该项必须已不可选")
	assert_eq(rt.tutorial_upgrade_choices(_data()).size(), 0,
		"教学项有不可用者应返回空，由调用方回落随机")
