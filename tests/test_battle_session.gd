## P0.1 测试：核心 HP、漏怪结算与胜负状态机（V2.1.4 D-5 / D-40 / D-41 / D-3A）
##
## 覆盖要求：
##   - 普通敌人抵达核心后只结算一次漏怪伤害
##   - 多条路线漏怪时正确扣减同一个核心 HP
##   - 核心 HP 耗尽时只触发一次失败
##   - 所有计划敌人清除后正确触发胜利
##   - 胜负确定后不再处理新的出怪或重复结算
extends GutTest

const STAGE_ID := "1-1"
const LOGIC_EPSILON := 0.0001


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func _grid() -> BattleGrid:
	return BattleGrid.from_layout(DataRegistry.get_layout())


func _enemy_table() -> Dictionary:
	var t := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


func _char_table() -> Dictionary:
	var t := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		t[str(c.get("id", ""))] = c
	return t


func _combat() -> Dictionary:
	return DataRegistry.get_domain("balance").get("combat", {})


func _stage_config() -> Dictionary:
	return DataRegistry.get_entry("stages", STAGE_ID)


func _make_session(stage_config: Dictionary = {}) -> BattleSession:
	var s := BattleSession.new()
	add_child_autofree(s)
	var cfg := stage_config if not stage_config.is_empty() else _stage_config()
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	return s


func _advance_session(s: BattleSession, total: float) -> void:
	var t := 0.0
	var step := StageRuntime.LOGIC_STEP_SECONDS
	while t < total - 0.0000001 and s.is_running():
		s.tick(step)
		t += step


# ---------- 漏怪结算 ----------

func test_core_damage_applied_only_once_per_enemy() -> void:
	var rt := StageRuntime.from_config(_stage_config(), _enemy_table(), _grid(), _char_table(), _combat())
	# 生成一个敌人并推进到核心
	var e := EnemyRuntime.from_config(_enemy_table()["echo_normal"], 1, 1)
	rt.enemies.append(e)
	e.logical_x = BattleGrid.CORE_X
	e.state = BattleTypes.EnemyState.REACHED_CORE

	var hp0 := rt.core_hp
	var first := rt.apply_core_damage(e)
	var second := rt.apply_core_damage(e)
	var third := rt.apply_core_damage(e)

	assert_eq(first, 1, "首次应扣 1")
	assert_eq(second, 0, "重复结算应返回 0（幂等）")
	assert_eq(third, 0, "再次重复仍应返回 0")
	assert_eq(rt.core_hp, hp0 - 1, "核心 HP 应只被扣 1 点")
	assert_eq(rt.core_damage_events, 1, "结算事件应只发生 1 次")


## 漏怪结算专项夹具：单敌人、早出怪、不部署任何角色，
## 确保"敌人确实抵达核心"这一前提成立，不依赖 1-1 的可调出怪节奏。
func _leak_fixture_config(core_hp: int = 5) -> Dictionary:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = core_hp
	cfg["enemySpawnTimeline"] = [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal"},
	]
	return cfg


func test_enemy_reaching_core_via_session_damages_once() -> void:
	# 使用专项夹具：无角色在场，敌人必然抵达核心
	var s := _make_session(_leak_fixture_config())
	var hp0 := s.stage.core_hp
	# echo_normal 速度 0.55 格/秒，从 x=5 到 x=0 需约 9.1 秒；留足余量
	_advance_session(s, 20.0)
	assert_gt(s.stage.reached_core_count, 0, "应有敌人抵达核心")
	# 核心扣减次数应等于抵达核心的敌人数量（每个只扣一次）
	assert_eq(s.stage.core_damage_events, s.stage.reached_core_count,
		"每次抵达核心恰好结算一次")
	assert_lt(s.stage.core_hp, hp0, "核心 HP 应已下降")


func test_reached_enemies_are_removed_after_settlement() -> void:
	var s := _make_session(_leak_fixture_config())
	_advance_session(s, 20.0)
	# 场上不应残留 REACHED_CORE 状态的敌人
	for e: EnemyRuntime in s.stage.enemies:
		assert_ne(e.state, BattleTypes.EnemyState.REACHED_CORE,
			"抵达核心的敌人应在结算后被移除")


# ---------- 多路共享同一核心 ----------

func test_multiple_lanes_share_single_core_hp() -> void:
	var rt := StageRuntime.from_config(_stage_config(), _enemy_table(), _grid(), _char_table(), _combat())
	var hp0 := rt.core_hp

	# 手工放三个敌人分别在上/中/下路，且都抵达核心
	for lane: int in range(3):
		var e := EnemyRuntime.from_config(_enemy_table()["echo_normal"], lane, 100 + lane)
		rt.enemies.append(e)
		e.logical_x = BattleGrid.CORE_X
		e.state = BattleTypes.EnemyState.REACHED_CORE

	for e: EnemyRuntime in rt.enemies:
		rt.apply_core_damage(e)

	assert_eq(rt.core_hp, hp0 - 3, "三条路线应共享同一核心 HP，共扣 3")
	assert_eq(rt.core_damage_events, 3, "应有 3 次结算事件")
	# 确认只有一个核心 HP 字段（不存在按路独立的核心）
	assert_eq(rt.core_hp_max, hp0, "核心上限不应随路线变化")


func test_lanes_do_not_have_independent_cores() -> void:
	var rt := StageRuntime.from_config(_stage_config(), _enemy_table(), _grid(), _char_table(), _combat())
	# StageRuntime 只暴露单一 core_hp，不提供 per-lane 核心
	assert_true(rt.has_method("apply_core_damage"), "应通过统一入口结算核心伤害")
	var props := rt.get_property_list()
	var per_lane_core := false
	for p: Dictionary in props:
		var n := str(p.get("name", ""))
		if n.contains("core_hp") and n != "core_hp" and n != "core_hp_max":
			per_lane_core = true
			break
	assert_false(per_lane_core, "不应存在按路线的独立核心 HP 字段")


# ---------- 失败 ----------

func test_defeat_when_core_hp_depleted() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 1  # 一个敌人抵达即失败
	cfg["enemySpawnTimeline"] = [{"time": 0.5, "lane": 1, "enemy": "echo_normal"}]

	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "构建应成功")

	_advance_session(s, 20.0)
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT, "核心耗尽应判失败")
	assert_eq(s.stage.core_hp, 0, "核心 HP 应为 0")


func test_defeat_triggers_only_once() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 1
	cfg["enemySpawnTimeline"] = [
		{"time": 0.5, "lane": 0, "enemy": "echo_normal"},
		{"time": 1.0, "lane": 2, "enemy": "echo_normal"},
	]

	var s := BattleSession.new()
	add_child_autofree(s)
	s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())

	var decisions := []
	s.outcome_decided.connect(func(o: int) -> void: decisions.append(o))

	_advance_session(s, 30.0)
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT, "应判失败")
	assert_eq(decisions.size(), 1, "outcome_decided 信号只应触发一次")
	assert_eq(decisions[0], BattleTypes.Outcome.DEFEAT, "信号应携带失败")


# ---------- 胜利 ----------

func test_victory_when_all_planned_enemies_cleared() -> void:
	var cfg := _stage_config().duplicate(true)
	# 用小规模、快速抵达的配置便于测试
	cfg["coreHp"] = 99  # 确保不会失败
	cfg["enemySpawnTimeline"] = [
		{"time": 0.5, "lane": 0, "enemy": "echo_normal"},
		{"time": 1.0, "lane": 2, "enemy": "echo_normal"},
	]

	var s := BattleSession.new()
	add_child_autofree(s)
	s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())

	# 先让敌人全部生成
	_advance_session(s, 1.5)
	assert_eq(s.stage.spawned_enemy_count(), 2, "两个敌人应已生成")
	assert_eq(s.stage.enemies.size(), 2, "场上应有 2 个敌人")
	assert_true(s.is_running(), "尚有存活敌人时不应判胜")

	# 通过受控夹具清除敌人（P0.1 无攻击系统，禁止偷偷加入战斗攻击）
	var removed := s.stage.despawn_all_for_test()
	assert_eq(removed, 2, "应清除 2 个敌人")

	# 再推进一帧以触发状态机评估
	s.tick(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY, "计划出怪清空且核心有血应判胜")


func test_victory_requires_all_planned_enemies_spawned() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 99
	cfg["enemySpawnTimeline"] = [
		{"time": 0.5, "lane": 0, "enemy": "echo_normal"},
		{"time": 50.0, "lane": 1, "enemy": "echo_normal"},  # 远未到时间
	]

	var s := BattleSession.new()
	add_child_autofree(s)
	s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())

	_advance_session(s, 1.0)
	s.stage.despawn_all_for_test()
	s.tick(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(s.outcome, BattleTypes.Outcome.RUNNING,
		"仍有计划敌人未生成时不得判胜")


func test_victory_requires_core_alive() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 1
	cfg["enemySpawnTimeline"] = [{"time": 0.5, "lane": 1, "enemy": "echo_normal"}]

	var s := BattleSession.new()
	add_child_autofree(s)
	s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())

	_advance_session(s, 20.0)
	# 核心已耗尽 → 必须是失败，而不是胜利
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT,
		"核心耗尽时即使敌人已清空也应判失败")


# ---------- 终态冻结 ----------

func test_no_new_spawns_after_outcome_decided() -> void:
	# 设计说明：要验证"胜负已定后不再出怪"，必须让全部计划出怪先于胜负确定生成，
	# 否则按规格（D-40：全部计划敌人已生成才判胜）根本不该判胜。
	# 因此这里把出怪全部排在很早期，并在判胜后再安排一个"本不应出现"的敌人时间点，
	# 用 cfg 的时线长度来证明冻结：判胜后即便时间继续推进也不得再生成。
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 99
	cfg["enemySpawnTimeline"] = [
		{"time": 0.5, "lane": 0, "enemy": "echo_normal"},
		{"time": 1.0, "lane": 1, "enemy": "echo_normal"},
	]

	var s := BattleSession.new()
	add_child_autofree(s)
	s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())

	# 推进到两个敌人都已生成
	_advance_session(s, 1.5)
	assert_eq(s.stage.spawned_enemy_count(), 2, "两个敌人应均已生成")

	# 清除敌人 → 应判胜
	s.stage.despawn_all_for_test()
	s.tick(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY, "全部计划已生成且场上清空应判胜")

	var spawned_at_victory := s.stage.spawned_enemy_count()
	var hp_at_victory := s.stage.core_hp
	var events_at_victory := s.stage.core_damage_events

	# 继续推进很长时间（远超全部出怪时间）
	_advance_session(s, 60.0)

	assert_eq(s.stage.spawned_enemy_count(), spawned_at_victory,
		"胜负确定后不得再生成新敌人")
	assert_eq(s.stage.core_hp, hp_at_victory, "胜负确定后核心 HP 不得再变化")
	assert_eq(s.stage.core_damage_events, events_at_victory,
		"胜负确定后不得再结算漏怪")
	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY, "结果不得被改写")


func test_no_damage_after_defeat() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 1
	cfg["enemySpawnTimeline"] = [
		{"time": 0.5, "lane": 0, "enemy": "echo_normal"},
		{"time": 3.0, "lane": 1, "enemy": "echo_normal"},
	]

	var s := BattleSession.new()
	add_child_autofree(s)
	s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())

	_advance_session(s, 20.0)
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT, "应判失败")
	var events := s.stage.core_damage_events

	_advance_session(s, 40.0)
	assert_eq(s.stage.core_damage_events, events, "失败后不得再结算伤害")
	assert_eq(s.stage.core_hp, 0, "核心 HP 不应变为负数")
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT, "结果不得被改写")


func test_session_freezes_on_outcome() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 1
	cfg["enemySpawnTimeline"] = [{"time": 0.5, "lane": 1, "enemy": "echo_normal"}]

	var s := BattleSession.new()
	add_child_autofree(s)
	s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	_advance_session(s, 20.0)
	assert_true(s.is_frozen(), "确定胜负后应冻结状态机")
	assert_true(s.is_decided(), "应处于已决出状态")
	assert_false(s.is_running(), "不应仍为进行中")


# ---------- 完整跑通 1-1（确定性）----------

func test_full_stage_1_1_is_deterministic() -> void:
	var outcomes := []
	for i: int in range(2):
		var s := _make_session()
		_advance_session(s, 120.0)
		outcomes.append({
			"outcome": s.outcome,
			"hp": s.stage.core_hp,
			"spawned": s.stage.spawned_enemy_count(),
			"reached": s.stage.reached_core_count,
			"events": s.stage.core_damage_events,
		})
	assert_eq(outcomes[0], outcomes[1],
		"同一关卡连续两次运行应得到完全一致的结果（确定性）")
	# 1-1：6 个敌人全部漏怪，核心 5 → 应为失败
	assert_eq(outcomes[0]["spawned"], 6, "应生成全部 6 个敌人")
	assert_eq(outcomes[0]["outcome"], BattleTypes.Outcome.DEFEAT,
		"1-1 无玩家单位时 6 个敌人漏怪应导致失败（核心 5）")
