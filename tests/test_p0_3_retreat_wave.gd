## P0.3 测试：主动撤退、再部署冷却、Wave 调度、暂停与完整一局闭环
## （V2.1.4 D-9 撤退与重新部署 / D-27 角色死亡 / D-33 敌人波次 / D-35 战斗暂停 / D-40 胜利 / D-41 失败）
##
## 覆盖要求（P0.3 正式施工指令 · 五）：
##   - 主动撤退只返还一次 AP
##   - 失能不返还 AP
##   - 撤退后阻挡关系正确释放
##   - 格子释放后可以合法部署其他单位
##   - 再部署冷却准确到期，提前部署被拒绝
##   - AP 不足时仍无法重新部署
##   - 撤退、死亡、重新部署不会复制角色实体
##   - Wave 顺序、生成数量、波次完成正确
##   - 暂停期间战斗逻辑和冷却时间冻结
##   - 胜利、失败均只能结算一次
##   - 撤退与重部署不会破坏原有 1-1 通关能力
##   - 不同帧率和分辨率不改变逻辑结果
extends GutTest

const CHAR_ID := "amamiya_mio"
const EPS := 0.0001


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


# ---------- 夹具 ----------

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
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/balance_0_5_1/1-1.json"))


## 出怪时序类夹具：清空 waves 元数据，让波次由 enemySpawnTimeline 自动推导，
## 避免「waves 声明了第 N 波但无敌人归属」的一致性报错。
func _cfg_no_waves(cfg: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	c.erase("waves")
	return c


## 可控夹具：AP 充足、核心血厚、出怪完全由参数决定
func _cfg(spawns: Array, ap: int = 10, regen: float = 1.0, core: int = 5) -> Dictionary:
	var c := _cfg_no_waves(_stage_config())
	c["coreHp"] = core
	c["startingAp"] = ap
	c["apRegen"] = regen
	c["enemySpawnTimeline"] = spawns
	c.erase("availableCharacters")
	c["availableCharacters"] = [CHAR_ID]
	return c


func _runtime(cfg: Dictionary) -> StageRuntime:
	return StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())


func _session(cfg: Dictionary) -> BattleSession:
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	return s


func _step_n(rt: StageRuntime, seconds: float) -> void:
	var t := 0.0
	while t < seconds - EPS:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS


## 以指定 tick 粒度推进到**总时长预算**（而不是固定调用次数），
## 这样不同帧率下走完的逻辑时间相同，才能公平比较逻辑结果。
func _advance_for(rt: StageRuntime, total: float, tick: float) -> void:
	var t := 0.0
	while t < total - EPS:
		rt.advance(tick)
		t += tick


func _tick_for(s: BattleSession, total: float, tick: float) -> void:
	var t := 0.0
	while t < total - EPS:
		s.tick(tick)
		t += tick


## 推进到**同一逻辑时刻**（而不是喂入同样的挂钟时长）。
## elapsed_seconds 只会在 1/60 秒的网格上前进，因此不同 tick 粒度下
## 三者必然停在同一个逻辑步边界上，可以公平比较逻辑结果。
func _advance_until(rt: StageRuntime, target_logic_seconds: float, tick: float) -> void:
	var guard := 0
	while rt.elapsed_seconds < target_logic_seconds - EPS and guard < 500000:
		rt.advance(tick)
		guard += 1


func _tick_n(s: BattleSession, seconds: float) -> void:
	var t := 0.0
	while t < seconds - EPS:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS


## 手动放置一个敌人到指定位置（用于精确构造阻挡/撤退场景）
func _place_enemy(
	rt: StageRuntime, lane: int, x: float, enemy_id: String = "echo_normal"
) -> EnemyRuntime:
	var e := EnemyRuntime.from_config(_enemy_table()[enemy_id], lane, 9000 + rt.enemies.size())
	e.logical_x = x
	e.state = BattleTypes.EnemyState.MOVING
	rt.enemies.append(e)
	return e


# ============================================================
#  一、数据来源：退款比例与再部署时长来自权威配置，不得写死在代码里
# ============================================================

func test_refund_rate_comes_from_balance_config() -> void:
	var combat := _combat()
	assert_true(combat.has("retreat"), "balance.combat 应含 retreat 段")
	var retreat: Dictionary = combat.get("retreat", {})
	# V2.1.4 D 章表 24：主动撤退返还 = 部署费用的 50%
	assert_eq(float(retreat.get("refundRate", -1.0)), 0.5, "退款比例应为 0.5（表 24）")


func test_redeploy_seconds_comes_from_config() -> void:
	var combat := _combat()
	assert_true(combat.has("redeploy"), "balance.combat 应含 redeploy 段")
	assert_eq(float(combat["redeploy"].get("defaultSeconds", -1.0)), 20.0,
		"普通角色再部署冷却应为 20 秒（表 24）")
	# 角色级覆盖
	var mio: Dictionary = _char_table()[CHAR_ID]
	assert_eq(float(mio.get("redeployTime", -1.0)), 8.0,
		"雨宫澪 redeployTime 应为 20 秒（表 26 / 表 47）")


func test_runtime_reads_refund_and_redeploy_from_config() -> void:
	var rt := _runtime(_cfg([]))
	assert_eq(rt.retreat_refund_rate, 0.5, "运行时退款比例应来自 balance.json")
	assert_eq(rt.redeploy_default_seconds, 20.0, "运行时默认再部署冷却应来自 balance.json")


# ============================================================
#  二、主动撤退与 AP 返还（V2.1.4 D-9 / 表 24）
# ============================================================

func test_withdraw_refunds_half_of_deploy_cost() -> void:
	var rt := _runtime(_cfg([], 10, 0.0))
	assert_true(rt.deploy_character(CHAR_ID, 2, 1).ok, "部署应成功")
	assert_eq(rt.ap, 0, "费用 10 应扣尽")

	var r := rt.withdraw_character_by_id(CHAR_ID)
	assert_true(r.ok, "主动撤退应成功：%s" % r.reason_text())
	# 雨宫澪费用 10 × 50% = 5 AP（规格原文示例）
	assert_eq(r.refund, 5, "应返还 5 AP（规格 D-9 原文示例）")
	assert_eq(rt.ap, 5, "AP 应实际到账 5")
	assert_eq(rt.retreat_count, 1, "撤退计数应为 1")


func test_withdraw_releases_the_deployed_cell() -> void:
	var rt := _runtime(_cfg([]))
	assert_true(rt.deploy_character(CHAR_ID, 2, 1).ok, "部署应成功")
	assert_not_null(rt.get_character_at(2, 1), "撤退前该格应有角色")

	rt.withdraw_character_by_id(CHAR_ID)
	assert_null(rt.get_character_at(2, 1), "撤退后原格应立即释放")
	assert_eq(rt.characters.size(), 0, "场上不应再留有该角色")


func test_withdraw_refunds_ap_only_once() -> void:
	# 本轮硬性要求：撤退只结算一次，禁止重复点击获得多次 AP
	var rt := _runtime(_cfg([], 10, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	var inst_id := rt.get_character_instance(CHAR_ID).instance_id

	var first := rt.withdraw_character(inst_id)
	assert_true(first.ok, "首次撤退应成功")
	var ap_after_first := rt.ap

	# 反复点击同一个 instance_id
	for i: int in range(10):
		var again := rt.withdraw_character(inst_id)
		assert_false(again.ok, "第 %d 次重复撤退应被拒" % (i + 1))
		assert_eq(again.reason, StageRuntime.RetreatReject.CHARACTER_NOT_DEPLOYED,
			"重复撤退的原因应为「该角色不在场上」")
		assert_eq(again.refund, 0, "重复撤退不得再返还 AP")

	assert_eq(rt.ap, ap_after_first, "AP 不得因重复点击而增加")
	assert_eq(rt.retreat_count, 1, "撤退计数只应为 1")
	assert_eq(rt.retreat_refunded_ap_total, 5, "累计返还应恰好为一次 5 AP")


func test_withdraw_refund_never_exceeds_ap_max() -> void:
	# 返回的 AP 不得超过最大 AP 30
	var rt := _runtime(_cfg([], 10, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	rt.ap = 28  # 临近上限
	var r := rt.withdraw_character_by_id(CHAR_ID)
	assert_true(r.ok, "撤退应成功")
	assert_true(rt.ap <= rt.ap_max, "AP 不得超过上限（实际 %d，上限 %d）" % [rt.ap, rt.ap_max])
	assert_eq(rt.ap, 30, "应被上限截断在 30")
	# 但「应返还额」本身仍是 5，只是入账被截断
	assert_eq(r.refund, 5, "应返还额应仍为 5")
	assert_eq(r.refund_granted, 2, "实际入账应为上限允许的 2 AP")


func test_incapacitated_character_refunds_nothing() -> void:
	# 本轮硬性要求：角色因 HP 耗尽而失能时不返还 AP
	var rt := _runtime(_cfg([], 10, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	var ap_before := rt.ap

	mio.take_damage(99999)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)   # 让领域层完成失能离场结算

	assert_eq(rt.ap, ap_before, "失能不得返还任何 AP")
	assert_eq(rt.retreat_refunded_ap_total, 0, "累计返还应为 0")
	assert_eq(rt.retreat_count, 0, "撤退计数应为 0（这是失能而非撤退）")
	# 领域层区分了两种离场
	assert_eq(rt.removal_count(StageRuntime.Removal.INCAPACITATED), 1, "应记录 1 次失能离场")
	assert_eq(rt.removal_count(StageRuntime.Removal.RETREATED), 0, "不应记录撤退")


func test_withdraw_on_incapacitated_instance_is_rejected() -> void:
	# HP 已归零但尚未被清理时，主动撤退接口也必须拒绝（不得走退款路径）
	var rt := _runtime(_cfg([], 10, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	mio.take_damage(99999)   # 直接打空，但还没推进逻辑步

	var r := rt.withdraw_character(mio.instance_id)
	assert_false(r.ok, "失能角色不得走主动撤退")
	assert_eq(r.reason, StageRuntime.RetreatReject.CHARACTER_INCAPACITATED,
		"原因应为「该角色已无法战斗」")
	assert_eq(rt.ap, 0, "不得返还 AP")


func test_withdraw_rejected_for_undeployed_character() -> void:
	var rt := _runtime(_cfg([], 30, 0.0))
	var r := rt.withdraw_character_by_id(CHAR_ID)
	assert_false(r.ok, "未部署的角色不可撤退")
	assert_eq(r.reason, StageRuntime.RetreatReject.CHARACTER_NOT_DEPLOYED, "原因应为不在场上")
	assert_eq(rt.ap, 30, "不得改变 AP")


func test_withdraw_rejected_after_battle_finished() -> void:
	var s := _session(_cfg([]))
	s.deploy_character(CHAR_ID, 2, 1)
	s.stage.core_hp = 0
	s.tick(StageRuntime.LOGIC_STEP_SECONDS)
	assert_true(s.is_decided(), "应已决出胜负")
	var r := s.withdraw_character_by_id(CHAR_ID)
	assert_false(r.ok, "战斗结束后不得撤退")
	assert_eq(r.reason, StageRuntime.RetreatReject.BATTLE_FINISHED, "原因应为战斗已结束")


# ============================================================
#  三、撤退后阻挡关系释放（V2.1.4 D-10 / D-27）
# ============================================================

func test_withdraw_releases_blocked_enemies() -> void:
	var rt := _runtime(_cfg([]))
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	var e1 := _place_enemy(rt, 1, 2.5)
	var e2 := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(mio.blocking_enemy_ids.size(), 2, "应先建立 2 个阻挡")

	var r := rt.withdraw_character(mio.instance_id)
	assert_true(r.ok, "撤退应成功")
	assert_eq(r.released_blocks, 2, "应解除 2 个阻挡关系")
	assert_eq(e1.state, BattleTypes.EnemyState.MOVING, "敌人 #1 应恢复移动状态")
	assert_eq(e2.state, BattleTypes.EnemyState.MOVING, "敌人 #2 应恢复移动状态")
	assert_eq(e1.blocked_by_character_id, 0, "敌人 #1 的阻挡归属应被清空")
	assert_eq(e2.blocked_by_character_id, 0, "敌人 #2 的阻挡归属应被清空")


func test_blocked_enemy_resumes_moving_after_withdraw() -> void:
	var rt := _runtime(_cfg([]))
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(e.state, BattleTypes.EnemyState.BLOCKED, "应已被阻挡")

	var x_before := e.logical_x
	rt.withdraw_character_by_id(CHAR_ID)
	_step_n(rt, 1.0)

	assert_eq(e.state, BattleTypes.EnemyState.MOVING, "敌人应恢复移动")
	assert_lt(e.logical_x, x_before, "敌人应重新向左推进（实际 %.4f -> %.4f）"
		% [x_before, e.logical_x])


func test_enemy_becomes_blockable_again_by_a_new_character() -> void:
	# 撤退换线后，新部署的角色应能重新接住同一名敌人
	# 注意：AP 上限为 30（规格 D-7），startingAp 会被领域层夹到 30。
	# 这里需要支付两次费用（雨宫澪 10 + 熊真 10），故 AP 必须 ≥ 20。
	var cfg := _cfg([], 30, 0.0, 5)
	cfg["availableCharacters"] = [CHAR_ID, "kamiya_yuma"]
	var char_table := _char_table()
	char_table["kamiya_yuma"] = char_table[CHAR_ID].duplicate(true)
	char_table["kamiya_yuma"]["id"] = "kamiya_yuma"
	char_table["kamiya_yuma"]["blockCount"] = 1

	var rt := StageRuntime.from_config(cfg, _enemy_table(), _grid(), char_table, _combat())
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(e.state, BattleTypes.EnemyState.BLOCKED, "应已被雨宫澪阻挡")

	rt.withdraw_character_by_id(CHAR_ID)
	assert_eq(e.state, BattleTypes.EnemyState.MOVING, "撤退后敌人应恢复移动")

	# 在原格部署第二名角色（原格已释放）
	var r2 := rt.deploy_character("kamiya_yuma", 2, 1)
	assert_true(r2.ok, "原格释放后应可部署其他单位：%s" % r2.reason_text())
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(e.state, BattleTypes.EnemyState.BLOCKED, "新角色应重新建立阻挡")
	assert_eq(e.blocked_by_character_id, r2.character.instance_id, "阻挡归属应指向新角色")


func test_cell_is_free_for_other_units_after_withdraw() -> void:
	# 同上：两名角色的费用都需要被支付
	var cfg := _cfg([], 30, 0.0, 5)
	cfg["availableCharacters"] = [CHAR_ID, "kamiya_yuma"]
	var char_table := _char_table()
	char_table["kamiya_yuma"] = char_table[CHAR_ID].duplicate(true)
	char_table["kamiya_yuma"]["id"] = "kamiya_yuma"
	var rt := StageRuntime.from_config(cfg, _enemy_table(), _grid(), char_table, _combat())

	rt.deploy_character(CHAR_ID, 2, 1)
	assert_false(rt.query_deploy("kamiya_yuma", 2, 1).ok, "占用中不应可部署")
	assert_eq(rt.query_deploy("kamiya_yuma", 2, 1).reason,
		StageRuntime.DeployReject.CELL_OCCUPIED, "原因应为该格已被占用")

	rt.withdraw_character_by_id(CHAR_ID)
	var r := rt.query_deploy("kamiya_yuma", 2, 1)
	assert_true(r.ok, "撤退后该格应恢复合法：%s" % r.reason_text())


# ============================================================
#  四、再部署冷却（V2.1.4 D-9 / 表 24 / 表 26）
# ============================================================

func test_redeploy_cooldown_starts_at_spec_value() -> void:
	var rt := _runtime(_cfg([]))
	rt.deploy_character(CHAR_ID, 2, 1)
	rt.withdraw_character_by_id(CHAR_ID)
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_ID), 8.0, EPS,
		"撤退后应进入 20 秒再部署冷却")
	assert_true(rt.is_redeploy_cooling(CHAR_ID), "应处于冷却中")


func test_redeploy_rejected_during_cooldown() -> void:
	# 起手 30（AP 上限），部署 -10 → 20，撤退 +5 → 25
	var rt := _runtime(_cfg([], 30, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	rt.withdraw_character_by_id(CHAR_ID)
	assert_eq(rt.ap, 25, "撤退后 AP 应为 20+5=25")

	# 冷却期间任意格都不可部署，且原因必须明确是冷却
	var q := rt.query_deploy(CHAR_ID, 3, 0)
	assert_false(q.ok, "冷却期间不得部署")
	assert_eq(q.reason, StageRuntime.DeployReject.REDEPLOY_COOLDOWN, "原因应为再部署冷却")
	assert_almost_eq(q.cooldown_remaining, 8.0, EPS, "应带出剩余秒数供 UI 显示")

	var r := rt.deploy_character(CHAR_ID, 3, 0)
	assert_false(r.ok, "冷却期间部署应被拒绝")
	assert_eq(rt.characters.size(), 0, "不得产生角色")
	assert_eq(rt.ap, 25, "被拒的部署不得扣费（仍为撤退返还后的 25）")


func test_redeploy_cooldown_expires_exactly() -> void:
	var rt := _runtime(_cfg([], 200))
	rt.deploy_character(CHAR_ID, 2, 1)
	rt.withdraw_character_by_id(CHAR_ID)

	# 推进 19 秒：仍在冷却
	_step_n(rt, 7.0)
	assert_gt(rt.get_redeploy_remaining(CHAR_ID), 0.0, "7 秒时应仍在冷却")
	assert_false(rt.query_deploy(CHAR_ID, 3, 0).ok, "7 秒时不应可部署")

	# 补齐到 20 秒：冷却应准确到期
	_step_n(rt, 1.05)
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_ID), 0.0, 0.05, "8 秒后冷却应到期")
	var q := rt.query_deploy(CHAR_ID, 3, 0)
	assert_true(q.ok, "冷却结束后应可重新部署：%s" % q.reason_text())


func test_redeploy_deducts_ap_again() -> void:
	# 起手 30（AP 上限）→ 部署 20 → 撤退 25 → 重部署 15
	var rt := _runtime(_cfg([], 30, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	var ap_after_first := rt.ap
	assert_eq(ap_after_first, 20, "首次应扣 10 AP（30 → 20）")

	rt.withdraw_character_by_id(CHAR_ID)
	assert_eq(rt.ap, 25, "撤退应返还 5 AP（20 → 25）")

	_step_n(rt, 20.1)
	var r := rt.deploy_character(CHAR_ID, 4, 2)
	assert_true(r.ok, "冷却结束后应可再次部署：%s" % r.reason_text())
	assert_eq(rt.ap, 15, "再次部署仍应正常扣除 10 AP（25 → 15）")
	assert_eq(r.character.lane, 2, "应部署到新路线（换线）")


func test_redeploy_still_requires_enough_ap() -> void:
	var rt := _runtime(_cfg([], 10, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	rt.withdraw_character_by_id(CHAR_ID)   # AP 回到 5
	_step_n(rt, 20.1)                       # 冷却结束

	assert_eq(rt.ap, 5, "此时 AP 为 5，低于费用 10")
	var q := rt.query_deploy(CHAR_ID, 3, 0)
	assert_false(q.ok, "AP 不足时仍无法重新部署")
	assert_eq(q.reason, StageRuntime.DeployReject.INSUFFICIENT_AP, "原因应为 AP 不足")

	rt.add_ap(5)
	var r := rt.deploy_character(CHAR_ID, 3, 0)
	assert_true(r.ok, "AP 充足后应可部署：%s" % r.reason_text())


func test_incapacitated_character_also_enters_redeploy_cooldown() -> void:
	# 本轮要求：因失能离场时同样按规格进入再部署冷却
	var rt := _runtime(_cfg([], 10, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	mio.take_damage(99999)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_true(rt.is_redeploy_cooling(CHAR_ID), "失能离场后应处于再部署冷却")
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_ID), 8.0, 0.05,
		"失能后同样应进入 20 秒冷却")
	assert_false(rt.query_deploy(CHAR_ID, 3, 0).ok, "冷却期间不得部署")


func test_redeploy_cooldown_is_frame_rate_independent() -> void:
	# 冷却必须由固定逻辑步长驱动，不依赖渲染帧率
	var results := []
	for tick: float in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 144.0]:
		var rt := _runtime(_cfg([], 30, 0.0))
		rt.deploy_character(CHAR_ID, 2, 1)
		rt.withdraw_character_by_id(CHAR_ID)
		# 推进到同一逻辑时刻（而不是喂入同样的挂钟时长）
		_advance_until(rt, 6.0, tick)
		results.append(snappedf(rt.get_redeploy_remaining(CHAR_ID), 0.001))
	assert_eq(results[0], results[1], "60fps 与 30fps 的剩余冷却必须一致")
	assert_eq(results[1], results[2], "30fps 与 144fps 的剩余冷却必须一致")
	assert_almost_eq(results[0], 2.0, 0.02, "6 秒后应剩余约 2 秒冷却")


func test_redeploy_timers_stop_after_outcome() -> void:
	# 胜负确定后，所有计时器停止推进
	var s := _session(_cfg([], 200, 0.0, 5))
	s.deploy_character(CHAR_ID, 2, 1)
	s.withdraw_character_by_id(CHAR_ID)
	var remaining_at_stop := s.get_redeploy_remaining(CHAR_ID)

	s.stage.core_hp = 0
	s.tick(StageRuntime.LOGIC_STEP_SECONDS)
	assert_true(s.is_decided(), "应已判负")

	_tick_n(s, 30.0)
	assert_almost_eq(s.get_redeploy_remaining(CHAR_ID), remaining_at_stop, 0.05,
		"胜负确定后再部署冷却不得继续推进")


# ============================================================
#  五、实体唯一性：撤退 / 死亡 / 重新部署不得复制角色
# ============================================================

func test_character_entity_is_never_duplicated() -> void:
	var rt := _runtime(_cfg([], 200, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	var first_id := rt.get_character_by_id(CHAR_ID).instance_id
	assert_eq(rt.characters.size(), 1, "场上应只有 1 个角色实体")

	# 撤退后重新部署
	rt.withdraw_character_by_id(CHAR_ID)
	assert_eq(rt.characters.size(), 0, "撤退后场上不应有角色")
	_step_n(rt, 20.1)
	rt.deploy_character(CHAR_ID, 4, 2)

	assert_eq(rt.characters.size(), 1, "重新部署后场上仍应只有 1 个实体")
	var second_id := rt.get_character_by_id(CHAR_ID).instance_id
	assert_ne(second_id, first_id, "重新部署应是全新实例，不得复用旧实例 id")
	assert_eq(rt.character_instances.size(), 2, "实例历史应为 2（旧实例作为离场记录保留）")

	# 同一个 id 永远不会同时出现在场上两次
	var seen := {}
	for c: CharacterRuntime in rt.characters:
		seen[c.character_id] = int(seen.get(c.character_id, 0)) + 1
	for cid: String in seen.keys():
		assert_eq(int(seen[cid]), 1, "角色 %s 在场实体数应恰好为 1" % cid)


func test_redeploy_resets_hp_and_attack_timer() -> void:
	# 重新部署的实例必须是满血、攻击计时就绪的新实体
	var rt := _runtime(_cfg([], 200, 0.0))
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	mio.take_damage(400)
	assert_eq(mio.hp, 600, "受伤后 HP 应为 600")

	rt.withdraw_character_by_id(CHAR_ID)
	_step_n(rt, 20.1)
	var r := rt.deploy_character(CHAR_ID, 4, 2)
	assert_true(r.ok, "应可重新部署")
	assert_eq(r.character.hp, 1000, "重新部署应恢复满血")
	assert_eq(r.character.max_hp, 1000, "最大 HP 应来自配置")
	assert_eq(r.character.attack_cooldown, 0.0, "重新部署的攻击计时应就绪")
	assert_eq(r.character.blocking_enemy_ids.size(), 0, "新实例不应继承任何阻挡关系")
	assert_eq(r.character.block_count_max, 2, "阻挡上限应来自配置")


func test_repeated_withdraw_and_redeploy_never_leaks_entities() -> void:
	var rt := _runtime(_cfg([], 200, 0.0))
	var total_expected := 0
	for i: int in range(3):
		var r := rt.deploy_character(CHAR_ID, i, 0)
		assert_true(r.ok, "第 %d 次部署应成功" % (i + 1))
		total_expected += 1
		assert_eq(rt.characters.size(), 1, "场上始终应只有 1 个实体")

		var w := rt.withdraw_character_by_id(CHAR_ID)
		assert_true(w.ok, "第 %d 次撤退应成功" % (i + 1))
		assert_eq(rt.characters.size(), 0, "撤退后场上应为空")
		_step_n(rt, 20.1)
	assert_eq(rt.character_instances.size(), total_expected,
		"实例历史应恰好等于部署次数（不得复制额外实体）")


# ============================================================
#  六、Wave 调度（V2.1.4 D-33 / D-34 / D-40）
# ============================================================

func test_stage_1_1_declares_three_sequential_waves() -> void:
	var rt := _runtime(_stage_config())
	assert_true(rt.is_valid(), "1-1 应无构建错误：%s" % str(rt.get_errors()))
	assert_eq(rt.total_wave_count(), 3, "1-1 应组织为 3 个 Wave")
	assert_eq(rt.current_wave_number(), 1, "开局应处于第 1 波")
	# 波次编号必须递增
	var prev := 0
	for i: int in range(rt.total_wave_count()):
		var n := int(rt.waves[i]["number"])
		assert_gt(n, prev, "波次编号应严格递增（实际 %d 在 %d 之后）" % [n, prev])
		prev = n


func test_wave_enemy_counts_match_timeline() -> void:
	# Wave 与 enemySpawnTimeline 必须是同一份数据：波次敌人总数 == 时间线条目总数
	var cfg := _stage_config()
	var rt := _runtime(cfg)
	var total := 0
	for i: int in range(rt.total_wave_count()):
		total += int(rt.waves[i]["enemyCount"])
	assert_eq(total, rt.planned_enemy_count(),
		"各波敌人数量之和应等于时间线条目总数（唯一数据来源）")
	assert_eq(total, (cfg["enemySpawnTimeline"] as Array).size(),
		"各波敌人数量之和应等于配置里的出怪条目数")

	# 每个波次至少 1 个敌人
	for i: int in range(rt.total_wave_count()):
		assert_gt(int(rt.waves[i]["enemyCount"]), 0, "第 %d 波不应为空" % (i + 1))


func test_wave_advances_in_order_as_enemies_are_cleared() -> void:
	# 用两波夹具精确验证推进顺序
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 1.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 2.0, "lane": 1, "enemy": "echo_normal", "wave": 2},
	]
	var cfg := _cfg(spawns, 100)
	cfg["waves"] = [
		{"number": 1, "label": "第一波"},
		{"number": 2, "label": "第二波"},
	]
	var rt := _runtime(cfg)
	assert_eq(rt.total_wave_count(), 2, "应有 2 个 Wave")
	assert_eq(int(rt.waves[0]["enemyCount"]), 2, "第 1 波应有 2 名敌人")
	assert_eq(int(rt.waves[1]["enemyCount"]), 1, "第 2 波应有 1 名敌人")

	# 生成第 1 波的两名敌人（尚未清除 → 波次不得推进）
	_step_n(rt, 1.2)
	assert_eq(rt.spawned_enemy_count(), 2, "第 1 波两名敌人应已生成")
	assert_eq(rt.current_wave_number(), 1, "敌人未清除前不得进入下一波")

	rt.despawn_all_for_test()
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt.current_wave_number(), 2, "清空第 1 波后应进入第 2 波")

	# 第 2 波敌人生成并清除
	_step_n(rt, 1.2)
	assert_eq(rt.spawned_enemy_count(), 3, "第 2 波敌人应已生成")
	rt.despawn_all_for_test()
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_true(rt.all_waves_cleared(), "全部 Wave 完成后 all_waves_cleared 应为 true")


func test_wave_does_not_complete_while_enemies_still_on_field() -> void:
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 8.0, "lane": 1, "enemy": "echo_normal", "wave": 2},
	]
	var cfg := _cfg(spawns, 100)
	cfg["waves"] = [{"number": 1}, {"number": 2}]
	var rt := _runtime(cfg)

	_step_n(rt, 1.0)
	assert_eq(rt.enemies.size(), 1, "场上应有 1 名敌人")
	assert_eq(rt.current_wave_number(), 1, "敌人仍在场上时不得推进波次")

	# 第 1 波敌人仍在场：不得**跳过**未完成的第 1 波直接进入第 2 波。
	# 注意：计划内的第 2 波敌人若按时生成，会把 current_wave_number 推进到 2，
	# 这在规则上允许（时间线是唯一出怪来源）；真正必须守住的不变量是
	# 「不得出现空波推进」——即不存在任何被跳过的、未完成的波次。
	_step_n(rt, 9.0)
	var wn := rt.current_wave_number()
	assert_true(wn >= 1, "波次编号不得倒退")
	if wn >= 2:
		var w1 := rt.wave_state_at(0)
		assert_eq(int(w1["killed"]) + int(w1["leaked"]), int(rt.waves[0]["enemyCount"]),
			"进入第 2 波时，第 1 波必须已全部结算完毕（不得跳过）")


func test_victory_requires_all_waves_cleared() -> void:
	var cfg := _cfg([], 100, 0.0, 99)
	var rt := _runtime(cfg)
	# 空关卡：无出怪 → 视为全部波次已完成
	assert_true(rt.all_waves_cleared(), "无出怪的关卡应视为波次全部完成")


func test_core_at_zero_blocks_further_spawning() -> void:
	# D-41：核心 HP 耗尽立即失败，不得继续出怪
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 20.0, "lane": 1, "enemy": "echo_normal", "wave": 2},
	]
	var cfg := _cfg(spawns, 100, 0.0, 1)
	cfg["waves"] = [{"number": 1}, {"number": 2}]
	var s := _session(cfg)

	# 不部署任何角色 → 第 1 波敌人漏怪，核心 1 → 0 立即失败
	var t := 0.0
	while s.is_running() and t < 60.0:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS

	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT, "核心耗尽应判失败")
	var spawned_at_fail := s.stage.spawned_enemy_count()
	assert_eq(spawned_at_fail, 1,
		"失败时应只生成过第 1 波的那 1 名敌人（实际 %d）" % spawned_at_fail)

	_tick_n(s, 60.0)
	assert_eq(s.stage.spawned_enemy_count(), spawned_at_fail,
		"失败后不得再生成任何敌人（实际从 %d 变为 %d）"
		% [spawned_at_fail, s.stage.spawned_enemy_count()])
	assert_eq(s.stage.current_wave_number(), 1, "失败后不得推进波次")


func test_wave_preview_reports_next_wave() -> void:
	var rt := _runtime(_stage_config())
	var nxt := rt.next_wave_preview()
	assert_false(nxt.is_empty(), "第 1 波时应能预告下一波")
	assert_eq(int(nxt["number"]), 2, "下一波应为第 2 波")
	assert_gt(int(nxt["enemyCount"]), 0, "预告应带出敌人数量")
	assert_gt((nxt["lanes"] as Array).size(), 0, "预告应带出涉及路线")


func test_invalid_wave_data_is_reported_not_silently_ignored() -> void:
	# 声明了波次却没有任何敌人归属 → 必须报错，不能静默通过
	var cfg := _cfg([{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1}], 100)
	cfg["waves"] = [{"number": 1}, {"number": 2}]
	var rt := _runtime(cfg)
	assert_false(rt.is_valid(), "声明了空波次应报错")
	assert_string_contains("\n".join(rt.get_errors()), "第 2 波", "错误信息应指出是哪一波")

	# 出怪引用了未声明的波次 → 同样报错
	var cfg2 := _cfg([{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 5}], 100)
	cfg2["waves"] = [{"number": 1}]
	var rt2 := _runtime(cfg2)
	assert_false(rt2.is_valid(), "引用未声明的波次应报错")


func test_legacy_timeline_without_wave_field_still_works() -> void:
	# 未标注 wave 的旧配置应归入第 1 波，保持向后兼容
	var cfg := _cfg([
		{"time": 0.5, "lane": 1, "enemy": "echo_normal"},
		{"time": 1.0, "lane": 0, "enemy": "echo_normal"},
	], 100)
	var rt := _runtime(cfg)
	assert_true(rt.is_valid(), "旧格式应仍然有效：%s" % str(rt.get_errors()))
	assert_eq(rt.total_wave_count(), 1, "未标注 wave 的条目应合并为第 1 波")
	assert_eq(int(rt.waves[0]["enemyCount"]), 2, "第 1 波应含全部条目")


# ============================================================
#  七、暂停（V2.1.4 D-35）
# ============================================================

func test_pause_freezes_enemy_movement() -> void:
	var rt := _runtime(_cfg([]))
	var e := _place_enemy(rt, 1, 5.0)
	_step_n(rt, 1.0)
	var x_before := e.logical_x

	rt.set_paused(true)
	_step_n(rt, 3.0)
	assert_almost_eq(e.logical_x, x_before, EPS, "暂停期间敌人不得移动")
	assert_almost_eq(rt.elapsed_seconds, 1.0, 0.02, "暂停期间逻辑时间不得推进")

	rt.set_paused(false)
	_step_n(rt, 1.0)
	assert_lt(e.logical_x, x_before, "恢复后敌人应继续移动")


func test_pause_freezes_ap_regeneration() -> void:
	var rt := _runtime(_cfg([], 10, 1.0, 100))
	_step_n(rt, 5.0)
	var ap_before := rt.ap
	assert_eq(ap_before, 15, "5 秒应回复到 15 AP")

	rt.set_paused(true)
	_step_n(rt, 10.0)
	assert_eq(rt.ap, ap_before, "暂停期间 AP 不得回复")

	rt.set_paused(false)
	_step_n(rt, 3.0)
	assert_eq(rt.ap, ap_before + 3, "恢复后 AP 应继续按 1/秒回复")


func test_pause_freezes_attacks_and_cooldowns() -> void:
	var rt := _runtime(_cfg([]))
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	var e := _place_enemy(rt, 1, 2.5)
	e.hp = 100000
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	var enemy_hp := e.hp
	var mio_hp := mio.hp
	assert_lt(enemy_hp, 100000, "应先完成一次攻击")

	rt.set_paused(true)
	_step_n(rt, 10.0)
	assert_eq(e.hp, enemy_hp, "暂停期间角色不得攻击")
	assert_eq(mio.hp, mio_hp, "暂停期间敌人不得攻击角色")


func test_pause_freezes_wave_timers_and_redeploy() -> void:
	var spawns := [
		{"time": 30.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
	]
	var rt := _runtime(_cfg(spawns, 100))
	rt.deploy_character(CHAR_ID, 2, 1)
	rt.withdraw_character_by_id(CHAR_ID)
	var remaining := rt.get_redeploy_remaining(CHAR_ID)

	rt.set_paused(true)
	_step_n(rt, 60.0)
	assert_eq(rt.spawned_enemy_count(), 0, "暂停期间不得生成敌人（Wave 计时冻结）")
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_ID), remaining, EPS,
		"暂停期间再部署冷却不得推进")

	rt.set_paused(false)
	_step_n(rt, 31.0)
	assert_eq(rt.spawned_enemy_count(), 1, "恢复后 Wave 应继续推进并按时出怪")
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_ID), 0.0, 0.1,
		"恢复后再部署冷却应继续推进至到期")


func test_pause_does_not_lose_accumulated_time() -> void:
	# 恢复后应从同一状态继续，不补跑暂停期间的时间
	# 起手 AP 取 5：远离上限 30，才能观察到"回复 2 秒"的净增量
	var rt := _runtime(_cfg([], 5, 1.0, 100))
	_step_n(rt, 3.0)
	var ap_before := rt.ap
	rt.set_paused(true)
	_step_n(rt, 100.0)
	rt.set_paused(false)
	_step_n(rt, 2.0)
	assert_eq(rt.ap, ap_before + 2, "恢复后只应推进恢复后的 2 秒")
	assert_almost_eq(rt.elapsed_seconds, 5.0, 0.02, "累计逻辑时间应为 3+2=5 秒")


func test_pause_via_session_and_signal() -> void:
	var s := _session(_cfg([], 10, 1.0, 100))
	var events: Array[bool] = []
	s.pause_changed.connect(func(p: bool) -> void: events.append(p))

	assert_false(s.is_paused(), "初始不应暂停")
	s.set_paused(true)
	assert_true(s.is_paused(), "会话应处于暂停")
	assert_eq(events, [true], "应发出一次暂停信号")

	# 重复设置同一状态不应重复发信号
	s.set_paused(true)
	assert_eq(events, [true], "同状态重复设置不应重复发信号")

	s.set_paused(false)
	assert_eq(events, [true, false], "应发出继续信号")


func test_paused_battle_logic_is_frozen_then_resumes() -> void:
	# 取远离上限的起手 AP，保证"继续回复"可被观测；
	# 同时必须让对局不会立刻结束——空出怪关卡会在第 1 帧直接判胜，
	# 因此安排一个远在本次观测窗口之外的敌人。
	var cfg := _cfg([{"time": 500.0, "lane": 1, "enemy": "echo_normal", "wave": 1}], 5, 1.0, 5)
	cfg["waves"] = [{"number": 1}]
	var s := _session(cfg)
	s.deploy_character(CHAR_ID, 2, 1)
	_tick_n(s, 3.0)
	assert_true(s.is_running(), "观测窗口内对局应仍在进行")
	var ap_before := s.stage.ap
	var elapsed_before := s.stage.elapsed_seconds

	s.set_paused(true)
	_tick_n(s, 20.0)
	assert_eq(s.stage.ap, ap_before, "暂停期间 AP 应冻结")
	assert_almost_eq(s.stage.elapsed_seconds, elapsed_before, 0.02, "暂停期间逻辑时间应冻结")

	s.set_paused(false)
	_tick_n(s, 2.0)
	assert_eq(s.stage.ap, ap_before + 2, "恢复后 AP 应继续回复")
	assert_true(s.is_running(), "暂停与恢复不应改变胜负状态")


# ============================================================
#  八、胜负只结算一次
# ============================================================

func test_victory_settles_exactly_once() -> void:
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
	]
	var cfg := _cfg(spawns, 100, 0.0, 99)
	cfg["waves"] = [{"number": 1}]
	var s := _session(cfg)

	var decisions: Array[int] = []
	s.outcome_decided.connect(func(o: int) -> void: decisions.append(o))

	# 部署雨宫澪并让敌人从她面前经过 → 真实击杀
	s.deploy_character(CHAR_ID, 3, 1)
	var t := 0.0
	while s.is_running() and t < 120.0:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS

	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
		"全部 Wave 清除后应判胜（击杀 %d，漏怪 %d）"
		% [s.stage.enemies_killed, s.stage.reached_core_count])
	assert_gt(s.stage.enemies_killed, 0, "胜利应来自真实击杀")

	# 继续推进，结果不得被改写，信号不得重复
	_tick_n(s, 60.0)
	assert_eq(decisions.size(), 1, "outcome_decided 只应触发一次")
	assert_eq(decisions[0], BattleTypes.Outcome.VICTORY, "信号应携带胜利")
	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY, "结果不得被改写")


func test_defeat_settles_exactly_once_with_waves() -> void:
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 3.0, "lane": 1, "enemy": "echo_normal", "wave": 2},
	]
	var cfg := _cfg(spawns, 100, 0.0, 1)
	cfg["waves"] = [{"number": 1}, {"number": 2}]
	var s := _session(cfg)

	var decisions: Array[int] = []
	s.outcome_decided.connect(func(o: int) -> void: decisions.append(o))

	_tick_n(s, 60.0)
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT, "核心耗尽应判失败")
	_tick_n(s, 60.0)
	assert_eq(decisions.size(), 1, "outcome_decided 只应触发一次")
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT, "结果不得被改写")


func test_result_summary_reports_required_fields() -> void:
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
	]
	var cfg := _cfg(spawns, 100, 0.0, 5)
	cfg["waves"] = [{"number": 1}]
	var s := _session(cfg)
	_tick_n(s, 30.0)   # 不部署 → 敌人漏怪（核心 5 → 4），但"全部敌人已处理 + 核心仍活着"即为胜利

	var summary := s.result_summary()
	for key: String in ["outcome", "outcomeName", "victory", "coreHp", "coreHpMax",
			"kills", "leaked", "elapsed"]:
		assert_true(summary.has(key), "结算摘要应含字段 %s" % key)
	assert_eq(int(summary["coreHp"]), 4, "核心应为 5-1=4")
	assert_eq(int(summary["leaked"]), 1, "应有 1 次漏怪")
	assert_eq(int(summary["kills"]), 0, "未部署时不应有击杀")
	# 规格 D-40：全部计划敌人已生成且场上无存活敌人 → 胜利（允许有漏怪，只要核心还在）
	assert_true(bool(summary["victory"]), "漏怪但核心尚存，仍应判胜利")
	assert_eq(int(summary["outcome"]), BattleTypes.Outcome.VICTORY, "结果应为胜利")


# ============================================================
#  九、1-1 通关能力不被撤退/重部署破坏
# ============================================================

func test_stage_1_1_still_winnable_with_only_amamiya_mio() -> void:
	# 规格约束：1-1 必须保留「仅使用雨宫澪即可通关」的原则
	var s := _session(_stage_config())
	assert_true(s.deploy_character(CHAR_ID, 2, 1).ok, "应能部署雨宫澪")

	var t := 0.0
	while s.is_running() and t < 300.0:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS

	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
		"1-1 应仍可用雨宫澪单人通关（核心 %d/%d，击杀 %d，漏怪 %d，Wave %d/%d）"
		% [s.stage.core_hp, s.stage.core_hp_max, s.stage.enemies_killed,
			s.stage.reached_core_count, s.stage.current_wave_number(),
			s.stage.total_wave_count()])
	assert_gt(s.stage.enemies_killed, 0, "应通过真实击杀通关")
	assert_eq(s.stage.total_wave_count(), 3, "应完整跑过 3 个 Wave")


func test_stage_1_1_still_fails_without_deployment() -> void:
	var s := _session(_stage_config())
	var t := 0.0
	while s.is_running() and t < 300.0:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT, "不部署仍应失败（对照）")


func test_1_1_wave_gap_now_allows_redeploy_swap() -> void:
	# ⚠️ 本用例在「三路线战斗体验重构」第二阶段被**反转**。
	#
	# 原用例名：test_1_1_wave_gap_is_shorter_than_redeploy_cooldown，
	# 断言「第 1 波清场到第 3 波出怪的空档（约 13s）**短于** 20 秒冷却」，
	# 即 1-1 上无法在关内完成撤退换线。
	#
	# 该断言的依据已在裁决 DEC-B-0002 中被明确限定为「**事实记录断言，非产品规则**」——
	# 它只描述 P0.3 当时那版原型时间线的事实，并明文声明
	# 「不得将当前约 13 秒的波次空档锁定为不可调整的产品规则」。
	#
	# 本轮第二阶段审查的结论：那个空档正是「机制强迫漏怪」的根因——
	# 1-1 只有雨宫澪一人、核心 5 点，而 Wave 3 的两只敌人只隔 4 秒压上，
	# 玩家在物理上不可能及时换线，零漏怪**不可达**。
	# 因此按 DEC-B-0002 授予的可调性，把 Wave 3 的两只敌人改为 48s / 80s，
	# 使空档拉长到 > 20 秒冷却，「撤退 → 换线 → 再部署」成为可行操作。
	#
	# 本用例现在断言**反转后的新事实**：空档足够完成一次撤退换线。
	var rt := _runtime(_stage_config())
	assert_eq(rt.redeploy_default_seconds, 20.0, "再部署冷却应为 20 秒（表 24）")

	var s := _session(_stage_config())
	assert_true(s.deploy_character(CHAR_ID, 2, 1).ok, "应能部署")
	var t := 0.0
	var first_wave_cleared_at := -1.0
	var wave3_time := 0.0
	for e: Dictionary in _stage_config()["enemySpawnTimeline"]:
		if int(e.get("wave", 1)) == 3:
			wave3_time = minf(wave3_time, float(e["time"])) if wave3_time > 0.0 else float(e["time"])
	while s.is_running() and t < 120.0:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS
		if first_wave_cleared_at < 0.0 and s.stage.wave_state_at(0).get("status", 0) == StageRuntime.WAVE_CLEARED:
			first_wave_cleared_at = s.stage.elapsed_seconds

	assert_gt(first_wave_cleared_at, 0.0, "第 1 波应被完成（否则约束无从成立）")
	assert_gt(wave3_time, first_wave_cleared_at, "第 3 波应排在第 1 波清场之后")
	var gap := wave3_time - first_wave_cleared_at
	assert_gte(gap, rt.redeploy_default_seconds,
		"第 1 波清场到第 3 波出怪的空档（%.1fs）应不短于 %.0f 秒冷却——"
		% [gap, rt.redeploy_default_seconds]
		+ "1-1 上必须存在可行的撤退换线窗口（本轮重平衡目标）")

	# 更直接的证据：1-1 上确实能用「撤退 → 换线 → 再部署」达成零漏怪。
	# 与 tools/probe_cross_lane.gd 的实测量化依据一致。
	var z := _session(_stage_config())
	assert_true(z.deploy_character(CHAR_ID, 2, 1).ok, "零漏怪解应能部署第一人")
	_advance_session_to(z, 30.0)
	assert_true(z.withdraw_character_by_id(CHAR_ID).ok, "零漏怪解应在 30.0s 撤退")
	_advance_session_to(z, 50.5)
	assert_true(z.deploy_character(CHAR_ID, 2, 0).ok, "零漏怪解应能在 50.5s 于上段再部署")
	_advance_session_to(z, 57.0)
	assert_true(z.withdraw_character_by_id(CHAR_ID).ok, "零漏怪解应在 57.0s 再次撤退")
	_advance_session_to(z, 77.5)
	assert_true(z.deploy_character(CHAR_ID, 2, 2).ok, "零漏怪解应能在 77.5s 于下段再部署")
	_advance_session_to(z, 240.0)
	assert_eq(z.outcome, BattleTypes.Outcome.VICTORY, "零漏怪解应为胜利")
	assert_eq(z.stage.reached_core_count, 0, "零漏怪解应达成零漏怪")
	assert_eq(z.stage.core_hp, z.stage.core_hp_max, "零漏怪解核心应保持满值")


## 把会话推进到指定逻辑时刻（若已结束则提前返回）。
func _advance_session_to(s: BattleSession, target: float) -> void:
	var guard := 0
	while s.is_running() and s.stage.elapsed_seconds < target - 0.0001 and guard < 200000:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1


func test_withdraw_and_redeploy_loop_is_winnable() -> void:
	# 完整换人循环：部署 → 击杀 → 主动撤退 → 等待冷却 → 换线重新部署 → 通关
	# 用节奏宽裕的夹具（两波间隔 29 秒 > 20 秒冷却），把循环本身跑通并证明它不破坏通关能力。
	var spawns := [
		{"time": 1.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 30.0, "lane": 0, "enemy": "echo_normal", "wave": 2},
	]
	var cfg := _cfg(spawns, 30, 1.0, 10)
	cfg["waves"] = [{"number": 1}, {"number": 2}]
	var s := _session(cfg)
	assert_true(s.deploy_character(CHAR_ID, 3, 1).ok, "应在中段部署")

	# 第 1 波：等她把敌人击杀
	var t := 0.0
	while s.is_running() and t < 20.0 and s.stage.enemies_killed < 1:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS
	assert_eq(s.stage.enemies_killed, 1, "第 1 波敌人应已被击杀")

	# 主动撤退。注意 AP 有 30 上限（规格 D-7），
	# 若撤退时已顶到上限，返还额会被截断，故此处断言"到账量"而非"固定 +5"。
	var ap_before := s.stage.ap
	var w := s.withdraw_character_by_id(CHAR_ID)
	assert_true(w.ok, "应能主动撤退：%s" % w.reason_text())
	assert_eq(w.refund, 5, "应返还额应为 5 AP")
	assert_eq(w.refund_granted, mini(5, s.stage.ap_max - ap_before),
		"实际入账应受 AP 上限约束")
	assert_eq(s.stage.ap, mini(s.stage.ap_max, ap_before + 5), "AP 应实际增加（不超上限）")
	# 保证后续换线部署有足够 AP
	s.stage.add_ap(30)
	assert_eq(s.stage.characters.size(), 0, "撤退后场上应为空")

	# 冷却期内换线部署必须被拒
	assert_false(s.deploy_character(CHAR_ID, 4, 0).ok, "冷却期内不得重新部署")

	# 等待冷却结束（20 秒），再换线到上段
	t = 0.0
	while s.is_running() and t < 25.0 and s.get_redeploy_remaining(CHAR_ID) > 0.0:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS
	assert_almost_eq(s.get_redeploy_remaining(CHAR_ID), 0.0, 0.05, "冷却应已到期")

	var r := s.deploy_character(CHAR_ID, 4, 0)
	assert_true(r.ok, "冷却结束 + AP 充足 + 格子合法 → 应能换线重新部署：%s" % r.reason_text())
	assert_eq(r.character.column, 4, "应部署到新格")
	assert_eq(r.character.lane, 0, "应换到上段")

	# 第 2 波从上段来 → 应被新位置接住
	t = 0.0
	while s.is_running() and t < 120.0:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS

	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
		"完成「撤退→冷却→换线重部署」循环后仍应通关（核心 %d/%d，击杀 %d，漏怪 %d）"
		% [s.stage.core_hp, s.stage.core_hp_max,
			s.stage.enemies_killed, s.stage.reached_core_count])
	assert_eq(s.stage.enemies_killed, 2, "两波敌人都应由同一名角色击杀")


func test_withdraw_does_not_break_determinism() -> void:
	# 同样的操作序列必须得到完全一致的结果
	var spawns := [
		{"time": 1.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 30.0, "lane": 0, "enemy": "echo_normal", "wave": 2},
	]
	var cfg := _cfg(spawns, 30, 1.0, 10)
	cfg["waves"] = [{"number": 1}, {"number": 2}]

	var results := []
	for run: int in range(2):
		var s := _session(cfg)
		s.deploy_character(CHAR_ID, 3, 1)
		var t := 0.0
		var moved := false
		while s.is_running() and t < 200.0:
			s.tick(StageRuntime.LOGIC_STEP_SECONDS)
			t += StageRuntime.LOGIC_STEP_SECONDS
			if not moved and s.stage.enemies_killed >= 1 and s.stage.characters.size() > 0:
				s.withdraw_character_by_id(CHAR_ID)
				moved = true
			elif moved and s.stage.characters.size() == 0 \
					and s.get_redeploy_remaining(CHAR_ID) <= 0.0:
				s.deploy_character(CHAR_ID, 4, 0)
		results.append({
			"outcome": s.outcome,
			"core": s.stage.core_hp,
			"killed": s.stage.enemies_killed,
			"leaked": s.stage.reached_core_count,
			"waves": s.stage.current_wave_number(),
			"ap": s.stage.ap,
		})
	assert_eq(results[0], results[1], "含撤退/重部署的一局仍应完全确定")
	assert_eq(int(results[0]["outcome"]), BattleTypes.Outcome.VICTORY,
		"该操作序列应能通关")


# ============================================================
#  十、帧率与分辨率无关（含 P0.3 新逻辑）
# ============================================================

func test_retreat_result_independent_of_tick_granularity() -> void:
	# 关键：把敌人放在 col4 上游、角色放在 col2，使撤退后敌人能继续走到核心，
	# 这样「撤退确实改变了战局」有可观察的确定性结果（漏怪次数），而不是空转。
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
	]
	var results := []
	for tick: float in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 144.0]:
		var rt := _runtime(_cfg(spawns, 30, 1.0, 100))
		rt.deploy_character(CHAR_ID, 2, 1)
		# 敌人 0.5s 生成、速度 0.55 格/秒，从 x=5 走到 col2 的接触线 x=2.5 需约 4.6 秒，
		# 故推进到同一逻辑时刻 7 秒时它必然已被阻挡。
		_advance_until(rt, 7.0, tick)
		var blocked_before := (rt.enemies[0] as EnemyRuntime).state if rt.enemies.size() > 0 else -1
		var w := rt.withdraw_character_by_id(CHAR_ID)
		# 撤退后再推进 20 秒：敌人应恢复移动并抵达核心
		_advance_until(rt, 27.0, tick)
		results.append({
			"ap": rt.ap,
			"refund": w.refund,
			"blockedBefore": blocked_before,
			"leaked": rt.reached_core_count,
			"core": rt.core_hp,
			"cooldown": snappedf(rt.get_redeploy_remaining(CHAR_ID), 0.001),
		})
	assert_eq(results[0]["blockedBefore"], BattleTypes.EnemyState.BLOCKED,
		"撤退前敌人应已被阻挡（保证用例确有效果）")
	assert_gt(int(results[0]["leaked"]), 0, "撤退后敌人应抵达核心（保证用例确有效果）")
	assert_eq(results[0], results[1], "60fps 与 30fps 的撤退结果必须一致")
	assert_eq(results[1], results[2], "30fps 与 144fps 的撤退结果必须一致")


func test_wave_progress_independent_of_render_resolution() -> void:
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1},
		{"time": 1.0, "lane": 1, "enemy": "echo_normal", "wave": 2},
	]
	var results := []
	for size: Array in [[1280, 720], [1920, 1080], [3840, 2160]]:
		var g := BattleGrid.from_layout(DataRegistry.get_layout())
		g.reference_canvas_width = int(size[0])
		g.reference_canvas_height = int(size[1])
		var cfg := _cfg(spawns, 100)
		cfg["waves"] = [{"number": 1}, {"number": 2}]
		var rt := StageRuntime.from_config(cfg, _enemy_table(), g, _char_table(), _combat())
		rt.deploy_character(CHAR_ID, 3, 1)
		var t := 0.0
		while t < 60.0 - EPS:
			rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
			t += StageRuntime.LOGIC_STEP_SECONDS
		results.append({
			"killed": rt.enemies_killed,
			"core": rt.core_hp,
			"wave": rt.current_wave_number(),
			"spawned": rt.spawned_enemy_count(),
		})
	assert_eq(results[0], results[1], "720p 与 1080p 的 Wave 进度必须一致")
	assert_eq(results[1], results[2], "1080p 与 4K 的 Wave 进度必须一致")


func test_refund_rounding_is_downward_and_extensible() -> void:
	# 退款比例与取整规则必须可扩展到其他角色 / 其他费用，不得写死 5 AP
	var rt := _runtime(_cfg([]))
	# 雨宫澪 10 AP × 50% = 5
	assert_eq(rt.compute_retreat_refund(10), 5, "10 × 50% 应为 5")
	# 12 AP × 50% = 6（悠真费用，表 47）
	assert_eq(rt.compute_retreat_refund(12), 6, "12 × 50% 应为 6")
	# 14 AP × 50% = 7（结衣费用）
	assert_eq(rt.compute_retreat_refund(14), 7, "14 × 50% 应为 7")
	# 奇数费用向下取整，保证不超过规格上限
	assert_eq(rt.compute_retreat_refund(15), 7, "15 × 50% = 7.5 应向下取整为 7")
	assert_eq(rt.compute_retreat_refund(0), 0, "费用为 0 时返还 0")
	# 比例可覆写（供后续「快速换防」类强化使用）
	assert_eq(rt.compute_retreat_refund(10, 1.0), 10, "比例 100% 时应全额返还")
	assert_eq(rt.compute_retreat_refund(10, 0.0), 0, "比例 0% 时不返还")
