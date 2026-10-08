## P0.2 测试：AP 系统与角色部署（V2.1.4 D-6 / D-7 / E 章）
##
## 覆盖要求：
##   - AP 初始化、自然恢复、上限与费用扣除
##   - AP 不足、占用格、非法格、重复角色部署
##   - 多次连续部署操作不会重复扣 AP
extends GutTest

const STAGE_ID := "1-1"
const CHAR_ID := "amamiya_mio"


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


func _make_runtime(stage_config: Dictionary = {}) -> StageRuntime:
	var cfg := stage_config if not stage_config.is_empty() else _stage_config()
	return StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())


func _make_session(stage_config: Dictionary = {}) -> BattleSession:
	var s := BattleSession.new()
	add_child_autofree(s)
	var cfg := stage_config if not stage_config.is_empty() else _stage_config()
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	return s


func _advance(rt: StageRuntime, total: float) -> void:
	var t := 0.0
	while t < total - 0.0000001:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS


# ---------- 数据与初始化 ----------

func test_character_config_loaded_with_spec_values() -> void:
	var t := _char_table()
	assert_true(t.has(CHAR_ID), "应含雨宫澪")
	var mio: Dictionary = t[CHAR_ID]
	var st: Dictionary = mio.get("baseStats", {})
	# V2.1.4 D 章表 26 数值
	assert_eq(int(st.get("hp", 0)), 1000, "HP 应为 1000")
	assert_eq(int(st.get("attack", 0)), 120, "攻击应为 120")
	assert_eq(int(st.get("defense", 0)), 80, "防御应为 80")
	assert_eq(float(mio.get("attackInterval", 0.0)), 1.1, "攻击间隔应为 1.1 秒")
	assert_eq(int(mio.get("blockCount", 0)), 2, "阻挡数应为 2")
	assert_eq(int(mio.get("deployCost", 0)), 10, "部署费用应为 10 AP")


func test_ap_initialized_from_config() -> void:
	var rt := _make_runtime()
	assert_true(rt.is_valid(), "运行时应有效：%s" % str(rt.get_errors()))
	assert_eq(rt.ap, 10, "开局 AP 应为 10（规格 D-7）")
	assert_eq(rt.ap_max, 30, "AP 上限应为 30（规格 D-7）")
	assert_eq(rt.ap_regen_per_second, 1.0, "自然回复应为 1 AP/秒")


func test_ap_regenerates_over_logic_time() -> void:
	var rt := _make_runtime()
	var ap0 := rt.ap
	_advance(rt, 5.0)
	# 5 秒应回复约 5 AP（一个逻辑步长的容差）
	assert_almost_eq(float(rt.ap), float(ap0) + 5.0, 0.05,
		"5 秒应回复约 5 AP，实际 %d" % rt.ap)


func test_ap_never_exceeds_max() -> void:
	var rt := _make_runtime()
	_advance(rt, 120.0)
	assert_eq(rt.ap, rt.ap_max, "长时间后 AP 应停在上限")
	assert_true(rt.ap <= rt.ap_max, "AP 不得超过上限")


func test_ap_never_negative() -> void:
	var rt := _make_runtime()
	# 尝试花掉超过持有量的 AP
	var ok := rt.try_spend_ap(9999)
	assert_false(ok, "超出持有量应拒绝")
	assert_true(rt.ap >= 0, "AP 不得为负")
	assert_eq(rt.ap, 10, "被拒绝的扣费不应改变 AP")


func test_add_ap_is_capped() -> void:
	var rt := _make_runtime()
	var added := rt.add_ap(9999)
	assert_eq(rt.ap, rt.ap_max, "加 AP 应被上限截断")
	assert_eq(added, rt.ap_max - 10, "返回值应为实际增加量")


# ---------- 部署合法性 ----------

func test_available_characters_honored() -> void:
	var rt := _make_runtime()
	assert_true(rt.available_characters.has(CHAR_ID), "1-1 应允许雨宫澪")
	var r := rt.query_deploy("kamiya_yuma", 0, 1)
	assert_false(r.ok, "未在 availableCharacters 中的角色应不可部署")
	assert_eq(r.reason, StageRuntime.DeployReject.CHARACTER_NOT_AVAILABLE, "原因应为不可使用")


func test_deploy_success_deducts_exact_cost() -> void:
	var rt := _make_runtime()
	var ap0 := rt.ap
	var cost := int(_char_table()[CHAR_ID].get("deployCost", 0))
	var r := rt.deploy_character(CHAR_ID, 2, 1)
	assert_true(r.ok, "合法部署应成功：%s" % r.reason_text())
	assert_eq(rt.ap, ap0 - cost, "应准确扣除 %d AP" % cost)
	assert_eq(rt.characters.size(), 1, "场上应有 1 名角色")
	assert_not_null(r.character, "结果应带角色实例")
	assert_eq(r.character.hp, 1000, "角色初始 HP 应为配置值")
	assert_eq(r.character.block_count_max, 2, "角色阻挡上限应为 2")


func test_deploy_rejected_on_invalid_cell() -> void:
	var rt := _make_runtime()
	var ap0 := rt.ap
	for cell: Array in [[-1, 0], [6, 0], [0, -1], [0, 3], [99, 99]]:
		var r := rt.query_deploy(CHAR_ID, int(cell[0]), int(cell[1]))
		assert_false(r.ok, "非法格 (%d,%d) 应不可部署" % [cell[0], cell[1]])
		assert_eq(r.reason, StageRuntime.DeployReject.INVALID_CELL, "原因应为非法格")
	assert_eq(rt.ap, ap0, "失败的部署不得扣费")


func test_deploy_rejected_on_occupied_cell() -> void:
	var rt := _make_runtime()
	assert_true(rt.deploy_character(CHAR_ID, 3, 1).ok, "首次部署应成功")
	# 同一格再部署（用另一个角色 id 绕过"角色唯一性"，验证占用判定）
	var cfg := _stage_config().duplicate(true)
	cfg["availableCharacters"] = [CHAR_ID, "kamiya_yuma"]
	var rt2 := _make_runtime(cfg)
	var char_table := _char_table()
	char_table["kamiya_yuma"] = char_table[CHAR_ID].duplicate(true)
	char_table["kamiya_yuma"]["id"] = "kamiya_yuma"
	rt2._character_configs = char_table
	assert_true(rt2.deploy_character(CHAR_ID, 3, 1).ok, "首次部署应成功")
	var r := rt2.query_deploy("kamiya_yuma", 3, 1)
	assert_false(r.ok, "已占用格应不可部署")
	assert_eq(r.reason, StageRuntime.DeployReject.CELL_OCCUPIED, "原因应为占用")


func test_deploy_rejected_when_ap_insufficient() -> void:
	var rt := _make_runtime()
	rt.ap = 3  # 低于费用 10
	var r := rt.deploy_character(CHAR_ID, 2, 1)
	assert_false(r.ok, "AP 不足应拒绝")
	assert_eq(r.reason, StageRuntime.DeployReject.INSUFFICIENT_AP, "原因应为 AP 不足")
	assert_eq(rt.ap, 3, "失败部署不得扣费")
	assert_eq(rt.characters.size(), 0, "失败部署不得产生角色")


func test_same_character_cannot_be_deployed_twice() -> void:
	var rt := _make_runtime()
	assert_true(rt.deploy_character(CHAR_ID, 1, 1).ok, "首次部署应成功")
	rt.add_ap(30)  # 保证 AP 充足，确保拒绝原因是唯一性而非费用
	var r := rt.deploy_character(CHAR_ID, 4, 1)
	assert_false(r.ok, "同一角色不可重复部署")
	assert_eq(r.reason, StageRuntime.DeployReject.CHARACTER_ALREADY_DEPLOYED, "原因应为已在场")
	assert_eq(rt.characters.size(), 1, "场上仍应只有 1 名该角色")


func test_repeated_deploy_attempts_do_not_double_charge() -> void:
	# 覆盖要求 11：多次连续部署操作不会重复扣 AP
	var rt := _make_runtime()
	rt.ap = 30
	var cost := int(_char_table()[CHAR_ID].get("deployCost", 0))
	assert_true(rt.deploy_character(CHAR_ID, 2, 1).ok, "首次应成功")
	var ap_after_first := rt.ap
	assert_eq(ap_after_first, 30 - cost, "首次应扣一次费用")

	# 连续 10 次重复部署尝试（同一角色 / 同一格 / 其他格）
	for i: int in range(10):
		var r := rt.deploy_character(CHAR_ID, i % 6, 1)
		assert_false(r.ok, "第 %d 次重复部署应被拒" % (i + 1))
	assert_eq(rt.ap, ap_after_first, "重复尝试不得再次扣费")
	assert_eq(rt.characters.size(), 1, "不得产生额外角色")


func test_query_deploy_has_no_side_effects() -> void:
	var rt := _make_runtime()
	var ap0 := rt.ap
	for i: int in range(20):
		var _r := rt.query_deploy(CHAR_ID, 2, 1)
	assert_eq(rt.ap, ap0, "查询不应改变 AP")
	assert_eq(rt.characters.size(), 0, "查询不应产生角色")
	assert_eq(rt.deploy_success_count, 0, "查询不计为成功部署")


func test_deploy_rejected_after_battle_finished() -> void:
	var s := _make_session()
	# 强制判负
	s.stage.core_hp = 0
	s.tick(StageRuntime.LOGIC_STEP_SECONDS)
	assert_true(s.is_decided(), "应已决出胜负")
	var r := s.deploy_character(CHAR_ID, 2, 1)
	assert_false(r.ok, "战斗结束后不得部署")
	assert_eq(r.reason, StageRuntime.DeployReject.BATTLE_FINISHED, "原因应为战斗已结束")


func test_deploy_result_reason_text_is_meaningful() -> void:
	var rt := _make_runtime()
	rt.ap = 0
	var r := rt.query_deploy(CHAR_ID, 2, 1)
	assert_false(r.ok, "应被拒")
	assert_ne(r.reason_text(), "", "应提供可读原因")
	assert_string_contains(r.reason_text(), "AP", "AP 不足的原因文案应提到 AP")


func test_ap_carried_by_stage_config_not_balance_default() -> void:
	# 关卡配置覆盖开局 AP 时，应使用关卡值
	var cfg := _stage_config().duplicate(true)
	cfg["startingAp"] = 25
	var rt := _make_runtime(cfg)
	assert_eq(rt.ap, 25, "应使用关卡配置的 startingAp")
	assert_eq(rt.ap_max, 30, "上限仍来自 balance.json")
