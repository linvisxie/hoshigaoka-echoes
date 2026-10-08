## P0.4 测试：神谷悠真 + 小川结衣 + 三职业基础战斗
## （V2.1.4 表 25 / 表 28 / 表 30 / 表 47 与 D-3A 跨线规则 / D-11 目标优先级 / D-13 射程 /
##   D-22 伤害公式 / D-9 撤退与再部署 / D-27 失能 / D-35 暂停）
##
## 覆盖范围（本轮指令 一 · 16 项 + 裁决 A/B 回归）：
##    1. 三名角色使用统一部署框架（同一套 deploy_character 路径即可放下三人）
##    2. AP 不足时部署失败（三种角色各验证一次）
##    3. 三名角色各自消耗正确 AP（10 / 12 / 14）
##    4. 场上角色不能重复部署
##    5. 悠真射程内攻击、射程外停火（4.0 格边界：3.9 内可打、4.1 外不打；跨线不打）
##    6. 悠真不能阻挡敌人（敌人从其格上穿过继续前进；blockCount=0；can_block_more()=false）
##    7. 结衣能够治疗受伤的雨宫澪
##    8. 结衣不治疗满血目标（不产生 heal_events，且不进入治疗冷却）
##    9. 结衣不治疗超出范围的目标（曼哈顿 > 3 格时无治疗）
##   10. 上路结衣不能直接治疗下路角色（laneDelta=2 > maxLaneDelta=1，独立于几何距离）
##   11. 治疗后 HP 不超过最大 HP（治疗量大于缺口时只补到满）
##   12. 多个受伤友军时按**生命百分比**（而不是绝对 HP）选择目标
##   13. 主动撤退、失能、再部署对三名角色均正确生效
##   14. 再部署后满血，且不存在重复返还 AP 的漏洞
##   15. 攻击、治疗、AP、Wave 与暂停均遵守固定逻辑步长
##   16. 不同分辨率与渲染帧率不改变战斗结果（推进到同一逻辑时刻比较）
##
## 裁决 A/B 回归：三人再部署满血、三人不重复返还 AP、再部署仍支付正常费用、
##   正式 1-1 的 availableCharacters 不被开发入口污染、apply_triple 不修改传入原字典、
##   三职业开发编队可全部部署（合计费用 36 > 开局 AP 上限 30 这一事实被如实处理）。
##
## 纪律：
##   - 所有夹具先 duplicate(true) 再改，绝不修改 DataRegistry 里的权威字典；
##   - 整体替换 enemySpawnTimeline 时必须同时 erase("waves")（见 _cfg_no_waves）；
##   - 三职业的差别只来自数据（behavior / blockCount / rangeTiles / maxLaneDelta / healPower），
##     测试不假设任何按角色名分支的实现。
extends GutTest

const CHAR_MIO := "amamiya_mio"
const CHAR_YUMA := "kamiya_yuma"
const CHAR_YUI := "ogawa_yui"

## 三职业 Prototype 编队（与 PrototypeRoster.TRIPLE_ROSTER 一致）
const TRIPLE: Array[String] = [CHAR_MIO, CHAR_YUMA, CHAR_YUI]

## 权威数值（data/characters.json，表 26 / 表 28 / 表 30 / 表 47）
const COST := {CHAR_MIO: 10, CHAR_YUMA: 12, CHAR_YUI: 14}
const MAX_HP := {CHAR_MIO: 1000, CHAR_YUMA: 620, CHAR_YUI: 720}
## 撤退返还 = 费用 × 50%，向下取整（表 24）
const REFUND := {CHAR_MIO: 5, CHAR_YUMA: 6, CHAR_YUI: 7}

const HEAL_POWER := 110
const HEAL_INTERVAL := 1.5
const AP_MAX := 30
const REDEPLOY_SECONDS := 20.0
const EPS := 0.0001


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


# ============================================================
#  夹具（与 tests/test_p0_3_retreat_wave.gd 同一套写法）
# ============================================================

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
	return DataRegistry.get_entry("stages", "1-1")


## 出怪时序类夹具：清空 waves 元数据，让波次由 enemySpawnTimeline 自动推导，
## 避免「waves 声明了第 N 波但无敌人归属」的一致性报错。
func _cfg_no_waves(cfg: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	c.erase("waves")
	return c


## 可控夹具：AP 充足、核心血厚、出怪完全由参数决定。
## 默认只解锁雨宫澪；需要三职业时由调用方覆盖 availableCharacters。
func _cfg(spawns: Array, ap: int = 10, regen: float = 1.0, core: int = 5) -> Dictionary:
	var c := _cfg_no_waves(_stage_config())
	c["coreHp"] = core
	c["startingAp"] = ap
	c["apRegen"] = regen
	c["enemySpawnTimeline"] = spawns
	c.erase("availableCharacters")
	c["availableCharacters"] = [CHAR_MIO]
	return c


## 三职业可用且 AP 顶到上限 30 的夹具（合计费用 36 > 30，见三职业编队用例）
func _cfg_triple(spawns: Array, regen: float = 1.0, core: int = 99) -> Dictionary:
	var c := _cfg(spawns, AP_MAX, regen, core)
	c["availableCharacters"] = TRIPLE.duplicate()
	return c


func _runtime(cfg: Dictionary) -> StageRuntime:
	return StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())


func _session(cfg: Dictionary) -> BattleSession:
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	return s


## 从权威角色表构建一个纯数据运行时实例（用于校验配置数值与纯函数）
func _char(table: Dictionary, character_id: String) -> CharacterRuntime:
	var cfg: Dictionary = table[character_id]
	return CharacterRuntime.from_config(cfg, 0, 1, 1)


## 从权威角色表读取部署费用（DataRegistry.get_entry 只为 stages/story 建立 ID 索引，
## 角色域必须经 get_domain 读取，不能依赖 get_entry）。
func _cost_of(character_id: String) -> int:
	return int((_char_table()[character_id] as Dictionary).get("deployCost", 0))


func _step_n(rt: StageRuntime, seconds: float) -> void:
	var t := 0.0
	while t < seconds - EPS:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS


## 推进到**同一逻辑时刻**（而不是喂入同样的挂钟时长）。
## elapsed_seconds 只会在 1/60 秒的网格上前进，因此不同 tick 粒度下
## 必然停在同一个逻辑步边界上，可以公平比较逻辑结果。
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


## 手动放置一个敌人到指定位置（用于精确构造射程 / 阻挡 / 治疗场景）
func _place_enemy(
	rt: StageRuntime, lane: int, x: float, enemy_id: String = "echo_normal"
) -> EnemyRuntime:
	var e := EnemyRuntime.from_config(_enemy_table()[enemy_id], lane, 9000 + rt.enemies.size())
	e.logical_x = x
	e.state = BattleTypes.EnemyState.MOVING
	rt.enemies.append(e)
	return e


## 取指定路线上的第一名敌人（避免依赖 enemies 数组的插入顺序）
func _enemy_in_lane(rt: StageRuntime, lane: int) -> EnemyRuntime:
	for e: EnemyRuntime in rt.enemies:
		if e.lane == lane:
			return e
	return null


## 依次把三人放在同一路线的三个不同格上（统一部署路径）。
## 注意：一个部署格只能容纳一名角色（格占用是规格要求），因此三人必须分格部署。
## 三人合计费用 10+12+14 = 36 大于开局 AP 上限 30，因此与真实玩家一致地
## 等待自然回复补足后再放下——这本身就是「36 > 30」这一配置事实的体现。
func _deploy_triple(rt: StageRuntime, lane: int) -> Array[CharacterRuntime]:
	var out: Array[CharacterRuntime] = []
	var columns: Array[int] = [1, 2, 3]
	for i: int in range(TRIPLE.size()):
		var cid: String = TRIPLE[i]
		_wait_ap_for(rt, cid)
		var r := rt.deploy_character(cid, columns[i], lane)
		assert_true(r.ok, "统一部署路径应能放下 %s：%s" % [cid, r.reason_text()])
		if r.character != null:
			out.append(r.character)
	return out


## 推进逻辑步直到 AP 足以支付指定角色（用于「三人合计 36 > 开局上限 30」的场景）
func _wait_ap_for(rt: StageRuntime, character_id: String) -> void:
	var guard := 0
	var need := _cost_of(character_id)
	while rt.ap < need and guard < 20000:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1
	assert_true(rt.ap >= need, "自然回复应补足 %s 的费用 %d（实际 AP %d）" % [character_id, need, rt.ap])


# ============================================================
#  一、三职业统一部署框架（覆盖项 1 / 2 / 3 / 4）
# ============================================================

## 覆盖项 1：三名角色共用同一条 deploy_character 路径，不因 behavior 而需要第二套入口。
func test_unified_deploy_path_accepts_all_three_classes() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_eq(rt.available_characters.size(), 3, "夹具应解锁三名角色")
	assert_eq(rt.deploy_success_count, 0, "开局不应有部署记录")

	var deployed := _deploy_triple(rt, 1)
	assert_eq(deployed.size(), 3, "同一路线的三个格上应能依次放下三人（统一部署路径）")
	assert_eq(rt.get_character_at(1, 1).character_id, CHAR_MIO, "第一人应落在 col1")
	assert_eq(rt.get_character_at(2, 1).character_id, CHAR_YUMA, "第二人应落在 col2")
	assert_eq(rt.get_character_at(3, 1).character_id, CHAR_YUI, "第三人应落在 col3")
	assert_eq(rt.characters.size(), 3, "场上应恰好有三名角色")
	assert_eq(rt.deploy_success_count, 3, "三次部署都应走同一条成功路径")

	# 三人的行为分类来自数据，而不是按角色名写死的分支
	assert_eq(rt.get_character_by_id(CHAR_MIO).behavior, CharacterRuntime.Behavior.FRONTLINE,
		"雨宫澪的行为应为 FRONTLINE")
	assert_eq(rt.get_character_by_id(CHAR_YUMA).behavior, CharacterRuntime.Behavior.RANGED,
		"神谷悠真的行为应为 RANGED")
	assert_eq(rt.get_character_by_id(CHAR_YUI).behavior, CharacterRuntime.Behavior.HEALER,
		"小川结衣的行为应为 HEALER")

	# 行为只决定走哪条结算路径，数值全部来自配置
	assert_true(rt.get_character_by_id(CHAR_MIO).is_attacker(), "前线应走攻击结算路径")
	assert_true(rt.get_character_by_id(CHAR_YUMA).is_attacker(), "远程应与前线共用攻击结算路径")
	assert_false(rt.get_character_by_id(CHAR_YUMA).is_healer(), "远程不是治疗型")
	assert_true(rt.get_character_by_id(CHAR_YUI).is_healer(), "治疗型应走治疗结算路径")
	assert_false(rt.get_character_by_id(CHAR_YUI).is_attacker(), "治疗型不应走攻击结算路径")


## 覆盖项 2：AP 不足时三名角色各自都部署失败，且失败不得扣费、不得产生实体。
func test_deploy_rejected_when_ap_insufficient_for_each_class() -> void:
	for cid: String in TRIPLE:
		var cost := _cost_of(cid)
		# 起手 AP = 费用 - 1，恰好差 1 点
		var rt := _runtime(_cfg_triple([], 0.0, 99))
		rt.ap = cost - 1
		rt._ap_accumulator = 0.0

		var q := rt.query_deploy(cid, 2, 1)
		assert_false(q.ok, "%s（费用 %d）在 AP %d 时应不可部署" % [cid, cost, cost - 1])
		assert_eq(q.reason, StageRuntime.DeployReject.INSUFFICIENT_AP,
			"%s 的拒绝原因应为 AP 不足" % cid)

		var r := rt.deploy_character(cid, 2, 1)
		assert_false(r.ok, "%s 的部署应被拒绝" % cid)
		assert_eq(r.reason, StageRuntime.DeployReject.INSUFFICIENT_AP, "%s 原因应为 AP 不足" % cid)
		assert_eq(rt.ap, cost - 1, "%s 部署失败不得扣除任何 AP" % cid)
		assert_eq(rt.characters.size(), 0, "%s 部署失败不得产生角色实体" % cid)
		assert_eq(rt.character_instances.size(), 0, "%s 部署失败不得留下实例历史" % cid)
		assert_eq(rt.deploy_success_count, 0, "%s 不应计入成功部署" % cid)
		assert_eq(rt.deploy_reject_count, 1, "%s 应计入 1 次拒绝" % cid)

		# 补足 1 点后立即可部署 → 证明失败的唯一原因是 AP
		rt.add_ap(1)
		var ok := rt.deploy_character(cid, 2, 1)
		assert_true(ok.ok, "%s 在 AP 补足后应可部署：%s" % [cid, ok.reason_text()])
		assert_eq(rt.ap, 0, "%s 部署后 AP 应恰好扣尽" % cid)


## 覆盖项 3：三名角色各自消耗正确 AP（10 / 12 / 14，来自 characters.json 的 deployCost）。
func test_each_class_spends_exact_deploy_cost() -> void:
	for cid: String in TRIPLE:
		var cost := int(COST[cid])
		assert_eq(_cost_of(cid), cost, "%s 的 deployCost 应为 %d（权威数值）" % [cid, cost])

		var rt := _runtime(_cfg_triple([], 0.0, 99))
		assert_eq(rt.ap, AP_MAX, "开局 AP 应为上限 %d" % AP_MAX)
		var r := rt.deploy_character(cid, 2, 1)
		assert_true(r.ok, "%s 应能部署：%s" % [cid, r.reason_text()])
		assert_eq(r.cost, cost, "%s 的部署结果应报告费用 %d" % [cid, cost])
		assert_eq(rt.ap, AP_MAX - cost, "%s 应恰好扣除 %d AP" % [cid, cost])
		assert_eq(rt.ap_max, AP_MAX, "AP 上限应来自 balance.combat.maxAp")


## 覆盖项 4：同一角色在场时不得重复部署（三职业各验一次），且失败不得扣费。
func test_deployed_character_cannot_be_deployed_twice() -> void:
	for cid: String in TRIPLE:
		var cost := int(COST[cid])
		var rt := _runtime(_cfg_triple([], 0.0, 99))
		var first := rt.deploy_character(cid, 2, 1)
		assert_true(first.ok, "%s 首次部署应成功" % cid)
		var ap_after_first := rt.ap

		# 换一个空格的重复部署同样必须被拒
		var q := rt.query_deploy(cid, 4, 2)
		assert_false(q.ok, "%s 已在场时不得再次部署" % cid)
		assert_eq(q.reason, StageRuntime.DeployReject.CHARACTER_ALREADY_DEPLOYED,
			"%s 的拒绝原因应为「该角色已在场」" % cid)

		var second := rt.deploy_character(cid, 4, 2)
		assert_false(second.ok, "%s 重复部署应被拒绝" % cid)
		assert_eq(rt.ap, ap_after_first, "%s 被拒的重复部署不得扣费" % cid)
		assert_eq(rt.characters.size(), 1, "%s 场上应始终只有 1 个实体" % cid)
		assert_eq(rt.character_instances.size(), 1, "%s 不得产生第二个实例" % cid)
		assert_null(rt.get_character_at(4, 2), "%s 不得出现在第二个格上" % cid)
		assert_eq(rt.ap, AP_MAX - cost, "%s 的净消耗应仍是一次部署费用" % cid)


# ============================================================
#  二、神谷悠真：远程射程与不阻挡（覆盖项 5 / 6）
# ============================================================

## 覆盖项 5a：射程内攻击（4.0 格边界内侧 3.9 可打）。
func test_ranged_attacks_target_inside_range() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_YUMA, 0, 1).ok, "应能部署神谷悠真")
	var yuma := rt.get_character_by_id(CHAR_YUMA)
	assert_eq(yuma.attack_range_tiles, 4.0, "悠真射程应来自配置的 4.0 格（表 28）")
	assert_eq(yuma.block_count_max, 0, "悠真阻挡数应来自配置的 0（表 28）")
	assert_eq(yuma.attack_interval, 1.3, "悠真攻击间隔应来自配置的 1.3 秒")

	var e := _place_enemy(rt, 1, 3.9)
	assert_eq(e.hp, e.hp_max, "敌人初始应为满血")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_lt(e.hp, e.hp_max, "3.9 格（≤ 射程 4.0）应在射程内被攻击")
	# 伤害来自统一公式：150 × 100 / (100 + 20) = 125
	assert_eq(e.hp_max - e.hp, 125, "伤害应按 D-22 公式计算（150 × 100 / 120 = 125）")
	assert_almost_eq(yuma.attack_cooldown, 1.3, EPS,
		"攻击后应进入完整的 1.3 秒攻击冷却（冷却从出手时刻起算）")


## 覆盖项 5b：射程外停火（4.1 格不打），且敌人走进 4.0 格后才开火；跨线不打。
func test_ranged_holds_fire_outside_range_and_across_lanes() -> void:
	# ① 4.1 格：射程外，一个逻辑步内不得攻击、不得进入冷却
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_YUMA, 0, 1).ok, "应能部署神悠真")
	var yuma := rt.get_character_by_id(CHAR_YUMA)
	var outside := _place_enemy(rt, 1, 4.1)
	var hp_before := outside.hp
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(outside.hp, hp_before, "4.1 格（> 射程 4.0）应在射程外，不得攻击")
	assert_eq(yuma.attack_cooldown, 0.0, "射程外不得进入攻击冷却（避免空转掉一次攻击）")

	# ② 同一名敌人继续走向核心，越过 4.0 格边界后才被攻击
	var guard := 0
	while outside.logical_x > 4.0 - EPS and guard < 600:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1
	assert_lt(outside.logical_x, 4.0, "敌人应已走进 4.0 格以内")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_lt(outside.hp, hp_before, "走进射程后应开始被攻击")

	# ③ 跨线不打：同为 3.0 格（射程内），但路线不同
	var rt2 := _runtime(_cfg_triple([]))
	assert_true(rt2.deploy_character(CHAR_YUMA, 0, 1).ok, "应能部署神谷悠真")
	var cross := _place_enemy(rt2, 2, 3.0)
	_step_n(rt2, 1.0)
	assert_eq(cross.hp, cross.hp_max,
		"跨线（lane 1 → lane 2）即使几何距离在射程内也不得攻击（表 28：不跨线）")


## 覆盖项 6：悠真不能阻挡敌人——敌人从其所在格上穿过继续前进。
func test_ranged_cannot_block_enemies() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_YUMA, 2, 1).ok, "应能部署神谷悠真")
	var yuma := rt.get_character_by_id(CHAR_YUMA)
	assert_eq(yuma.block_count_max, 0, "blockCount 应来自配置的 0")
	assert_false(yuma.can_block_at_all(), "blockCount=0 的角色天然不能建立阻挡")
	assert_false(yuma.can_block_more(), "悠真不得建立任何阻挡")
	assert_eq(yuma.block_slots_remaining(), 0, "悠真的剩余阻挡名额应为 0")
	assert_false(yuma.add_blocking(1), "即使直接调用也不得建立阻挡关系")

	# 敌人从 x=2.6 走到悠真所在格（col2）左侧
	var e := _place_enemy(rt, 1, 2.6)
	_step_n(rt, 2.0)
	assert_eq(e.blocked_by_character_id, 0, "悠真不得成为敌人的阻挡者")
	assert_ne(e.state, BattleTypes.EnemyState.BLOCKED, "敌人不应被悠真阻挡")
	assert_lt(e.logical_x, 2.0, "敌人应已越过悠真所在格（col2）继续前进")
	assert_true(yuma.blocking_enemy_ids.is_empty(), "悠真的阻挡列表应始终为空")
	# 同一场景下前线角色会建立阻挡，作为对照
	var rt2 := _runtime(_cfg_triple([]))
	assert_true(rt2.deploy_character(CHAR_MIO, 2, 1).ok, "对照组应能部署雨宫澪")
	var e2 := _place_enemy(rt2, 1, 2.6)
	_step_n(rt2, 2.0)
	assert_eq(e2.state, BattleTypes.EnemyState.BLOCKED, "对照：前线角色应阻挡住同一名敌人")


# ============================================================
#  三、小川结衣：治疗范围、优先级与治疗上限（覆盖项 7 / 8 / 9 / 10 / 11 / 12）
# ============================================================

## 覆盖项 7 前置：结衣的治疗参数全部来自权威配置，且不引入隐藏倍率。
func test_healer_values_come_from_authoritative_config() -> void:
	var yui := _char(_char_table(), CHAR_YUI)
	assert_eq(yui.heal_power, HEAL_POWER, "治疗力应来自配置的 110（表 30）")
	assert_eq(yui.heal_interval, HEAL_INTERVAL, "治疗间隔应来自配置的 1.5 秒（表 30）")
	assert_eq(yui.attack_range_tiles, 3.0, "治疗范围应来自配置的曼哈顿 ≤ 3 格（表 30）")
	assert_true(yui.heal_uses_manhattan, "治疗范围应使用曼哈顿距离（shape=manhattan）")
	assert_eq(yui.max_lane_delta, 1, "最多跨相邻 1 条路线（maxLaneDelta=1）")
	assert_eq(yui.block_count_max, 0, "结衣阻挡数应来自配置的 0（表 30）")
	assert_eq(yui.compute_heal_amount(), HEAL_POWER, "基础治疗量应等于治疗力（倍率固定 1.0）")
	assert_eq(yui.compute_heal_amount(0.0), 0, "倍率为 0 时治疗量应为 0")
	assert_eq(yui.hp_ratio(), 1.0, "新建实例应为满血（生命百分比 1.0）")
	assert_false(yui.is_wounded(), "满血不应算作受伤")


## 覆盖项 7：结衣能够治疗受伤的雨宫澪。
func test_healer_heals_wounded_ally() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_MIO, 1, 1).ok, "应能部署雨宫澪")
	assert_true(rt.deploy_character(CHAR_YUI, 2, 1).ok, "应能部署小川结衣")
	var mio := rt.get_character_by_id(CHAR_MIO)
	var yui := rt.get_character_by_id(CHAR_YUI)

	mio.take_damage(300)
	assert_eq(mio.hp, 700, "雨宫澪应先受伤到 700 HP")
	assert_true(mio.is_wounded(), "受伤后应进入「受伤但仍在场」状态")
	assert_eq(rt.heal_events.size(), 0, "治疗前不应有治疗事件")

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(rt.heal_events.size(), 1, "应恰好产生 1 次治疗事件")
	var ev: Dictionary = rt.heal_events[0]
	assert_eq(int(ev["healerId"]), yui.instance_id, "治疗者应为小川结衣")
	assert_eq(int(ev["targetId"]), mio.instance_id, "治疗目标应为雨宫澪")
	assert_eq(int(ev["amount"]), HEAL_POWER, "实际治疗量应为 110")
	assert_eq(mio.hp, 810, "雨宫澪应回复到 810 HP")
	assert_eq(yui.total_healing_done, HEAL_POWER, "结衣的累计治疗量应为 110")
	assert_eq(rt.total_healing_done, HEAL_POWER, "全队累计治疗量应为 110")
	assert_almost_eq(yui.last_heal_at, StageRuntime.LOGIC_STEP_SECONDS, EPS,
		"应记录最近一次治疗的逻辑时刻")
	assert_almost_eq(yui.attack_cooldown, HEAL_INTERVAL, EPS, "治疗后应进入 1.5 秒治疗间隔")

	# 治疗事件同样通过 BattleSession 转发
	var s := _session(_cfg_triple([]))
	s.deploy_character(CHAR_MIO, 1, 1)
	s.deploy_character(CHAR_YUI, 2, 1)
	var healed: Array[int] = []
	s.character_healed.connect(func(_h: CharacterRuntime, _t: CharacterRuntime, amount: int) -> void:
		healed.append(amount))
	s.stage.get_character_by_id(CHAR_MIO).take_damage(300)
	s.tick(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(healed, [HEAL_POWER], "BattleSession 应转发一次 110 点治疗")
	assert_eq(int(s.result_summary()["heals"]), 1, "结算摘要应报告 1 次治疗")
	assert_eq(int(s.result_summary()["healedTotal"]), HEAL_POWER, "结算摘要应报告累计治疗量")


## 覆盖项 8：结衣不治疗满血目标——不产生 heal_events，且**不进入治疗冷却**。
func test_healer_skips_full_hp_targets_without_consuming_cooldown() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_MIO, 1, 1).ok, "应能部署雨宫澪")
	assert_true(rt.deploy_character(CHAR_YUI, 2, 1).ok, "应能部署小川结衣")
	var yui := rt.get_character_by_id(CHAR_YUI)
	assert_eq(yui.attack_cooldown, 0.0, "开局治疗计时应就绪")

	# 曼哈顿距离 1、路线相同，但目标满血 → 不得治疗
	_step_n(rt, 5.0)
	assert_eq(rt.heal_events.size(), 0, "全部满血时不得产生任何治疗事件")
	assert_eq(rt.total_healing_done, 0, "累计治疗量应为 0")
	assert_eq(yui.total_healing_done, 0, "结衣的累计治疗量应为 0")
	assert_eq(yui.attack_cooldown, 0.0,
		"无可治疗目标时不得进入治疗冷却（否则会空转掉一次治疗）")
	assert_almost_eq(yui.last_heal_at, -1.0, EPS, "从未治疗时应保持 last_heal_at = -1")

	# 目标受伤后立刻（同一逻辑步内）就能治疗，证明冷却确实没有被空转消耗
	rt.get_character_by_id(CHAR_MIO).take_damage(100)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt.heal_events.size(), 1, "目标受伤后应能立即治疗（冷却未被空转消耗）")


## 覆盖项 9：结衣不治疗超出范围的目标（曼哈顿距离 > 3 格）。
func test_healer_ignores_targets_beyond_manhattan_range() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_MIO, 4, 1).ok, "应能部署雨宫澪（同路远格）")
	assert_true(rt.deploy_character(CHAR_YUI, 0, 1).ok, "应能部署小川结衣")
	var mio := rt.get_character_by_id(CHAR_MIO)
	assert_eq(absi(4 - 0), 4, "构造的曼哈顿距离应为 4（> 3）")
	mio.take_damage(400)

	_step_n(rt, 5.0)
	assert_eq(rt.heal_events.size(), 0, "曼哈顿距离 4 > 3 时不得治疗")
	assert_eq(mio.hp, 600, "超范围目标不得被治疗")
	assert_eq(rt.get_character_by_id(CHAR_YUI).attack_cooldown, 0.0,
		"超范围时不得进入治疗冷却")

	# 边界对照：曼哈顿恰好 3 格（同路 col0 ↔ col3）应可治疗
	var rt2 := _runtime(_cfg_triple([]))
	assert_true(rt2.deploy_character(CHAR_MIO, 3, 1).ok, "边界用例应能部署雨宫澪")
	assert_true(rt2.deploy_character(CHAR_YUI, 0, 1).ok, "边界用例应能部署小川结衣")
	var mio2 := rt2.get_character_by_id(CHAR_MIO)
	mio2.take_damage(400)
	rt2.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt2.heal_events.size(), 1, "曼哈顿恰好 3 格（≤ 3）应可治疗")
	assert_eq(mio2.hp, 710, "边界内目标应被治疗 110 点（600 → 710）")


## 覆盖项 10：上路结衣不能直接治疗下路角色——laneDelta 是独立于几何距离的规则。
func test_healer_cannot_cross_two_lanes_even_when_in_range() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_MIO, 1, 2).ok, "应能把雨宫澪部署到下路")
	assert_true(rt.deploy_character(CHAR_YUI, 1, 0).ok, "应能把小川结衣部署到上路")
	var yui := rt.get_character_by_id(CHAR_YUI)
	var mio := rt.get_character_by_id(CHAR_MIO)
	# 几何上完全够得着：曼哈顿 = |1-1| + |0-2| = 2 ≤ 3
	assert_eq(absi(yui.column - mio.column) + absi(yui.lane - mio.lane), 2,
		"构造的曼哈顿距离应为 2（在 3 格范围内）")
	assert_eq(absi(yui.lane - mio.lane), 2, "构造的跨线数应为 2（> maxLaneDelta=1）")
	mio.take_damage(500)

	_step_n(rt, 5.0)
	assert_eq(rt.heal_events.size(), 0,
		"上路 → 下路（laneDelta=2 > maxLaneDelta=1）即使曼哈顿 ≤ 3 也必须拒绝治疗")
	assert_eq(mio.hp, 500, "下路角色不得被上路结衣治疗")

	# 对照：结衣换到中路（laneDelta=1）后，同一名受伤友军应立刻被治疗
	var rt2 := _runtime(_cfg_triple([]))
	assert_true(rt2.deploy_character(CHAR_MIO, 1, 2).ok, "对照应能部署雨宫澪到下路")
	assert_true(rt2.deploy_character(CHAR_YUI, 1, 1).ok, "对照应能把结衣部署到中路")
	var mio2 := rt2.get_character_by_id(CHAR_MIO)
	mio2.take_damage(500)
	rt2.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt2.heal_events.size(), 1, "跨 1 条路线（laneDelta=1）应可治疗")
	assert_eq(mio2.hp, 610, "对照目标应被治疗 110 点")


## 覆盖项 11：治疗后 HP 不超过最大 HP——治疗量大于缺口时只补到满。
func test_healing_never_exceeds_target_max_hp() -> void:
	# ① 纯函数层：receive_healing 自行夹取，且满血时返回 0
	var mio_pure := _char(_char_table(), CHAR_MIO)
	assert_eq(mio_pure.max_hp, int(MAX_HP[CHAR_MIO]), "雨宫澪最大 HP 应来自配置的 1000")
	mio_pure.take_damage(50)
	assert_eq(mio_pure.hp, 950, "应先造出小于治疗力的缺口（50 < 110）")
	assert_eq(mio_pure.receive_healing(HEAL_POWER), 50, "治疗量大于缺口时应只回复缺口部分")
	assert_eq(mio_pure.hp, mio_pure.max_hp, "接受治疗后应恰好等于最大 HP，不得溢出")
	assert_eq(mio_pure.receive_healing(HEAL_POWER), 0, "已满血时不得再回复")

	# ② 集成层：结衣治疗只差 50 点血的雨宫澪
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_MIO, 1, 1).ok, "应能部署雨宫澪")
	assert_true(rt.deploy_character(CHAR_YUI, 2, 1).ok, "应能部署小川结衣")
	var mio := rt.get_character_by_id(CHAR_MIO)
	mio.take_damage(50)
	assert_eq(mio.hp, 950, "雨宫澪应先受伤到 950 HP")

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(mio.hp, mio.max_hp, "治疗量 110 > 缺口 50 时应只补到满血")
	assert_eq(mio.hp, int(MAX_HP[CHAR_MIO]), "满血应为配置值 1000")
	assert_eq(rt.heal_events.size(), 1, "应恰好产生 1 次治疗事件")
	assert_eq(int(rt.heal_events[0]["amount"]), 50, "事件记录的应是实际回复量 50，而不是治疗力 110")
	assert_eq(rt.total_healing_done, 50, "全队累计治疗量应只计实际回复量")
	assert_almost_eq(rt.get_character_by_id(CHAR_YUI).attack_cooldown, HEAL_INTERVAL, EPS,
		"即使只补到满血，结衣仍应进入治疗间隔（治疗确实发生了）")


## 覆盖项 12：多个受伤友军时按**生命百分比**选择目标，而不是绝对 HP。
## 对照组：悠真的绝对 HP 更低（200 < 300），但生命百分比更高（0.3226 > 0.30），
## 因此结衣必须选择雨宫澪——若实现改用绝对 HP，本用例会失败。
func test_healer_targets_lowest_hp_ratio_not_lowest_absolute_hp() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_MIO, 1, 1).ok, "应能部署雨宫澪")
	assert_true(rt.deploy_character(CHAR_YUMA, 0, 1).ok, "应能部署神谷悠真")
	# 前两人已花掉 22 AP，第三人需等待自然回复（36 > 30 的配置事实）
	_wait_ap_for(rt, CHAR_YUI)
	assert_true(rt.deploy_character(CHAR_YUI, 3, 1).ok, "应能部署小川结衣")
	var mio := rt.get_character_by_id(CHAR_MIO)
	var yuma := rt.get_character_by_id(CHAR_YUMA)
	var yui := rt.get_character_by_id(CHAR_YUI)

	# 曼哈顿距离：结衣(col3) → 澪(col1) = 2；结衣(col3) → 悠真(col0) = 3，两人都在 3 格范围内
	mio.take_damage(700)      # 1000 → 300，百分比 0.30
	yuma.take_damage(420)     # 620 → 200，百分比 0.3226
	assert_eq(mio.hp, 300, "雨宫澪应受伤到 300 HP")
	assert_eq(yuma.hp, 200, "神谷悠真应受伤到 200 HP")
	assert_lt(yuma.hp, mio.hp, "对照条件：悠真的**绝对 HP 更低**")
	assert_lt(mio.hp_ratio(), yuma.hp_ratio(), "对照条件：雨宫澪的**生命百分比更低**")
	assert_almost_eq(mio.hp_ratio(), 0.30, 0.0001, "雨宫澪生命百分比应为 0.30")
	assert_almost_eq(yuma.hp_ratio(), 0.322580, 0.0001, "悠真生命百分比应约为 0.3226")

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(rt.heal_events.size(), 1, "应恰好产生 1 次治疗事件")
	assert_eq(int(rt.heal_events[0]["targetId"]), mio.instance_id,
		"应按生命百分比选择雨宫澪，而不是绝对 HP 更低的神谷悠真")
	assert_eq(int(rt.heal_events[0]["healerId"]), yui.instance_id, "治疗者应为小川结衣")
	assert_eq(mio.hp, 410, "雨宫澪应被治疗 110 点（300 → 410）")
	assert_eq(yuma.hp, 200, "神谷悠真本次不得被治疗")

	# 下一次治疗：澪的百分比（0.41）已高于悠真（0.3226）→ 应转向悠真
	_step_n(rt, HEAL_INTERVAL + 0.05)
	assert_eq(rt.heal_events.size(), 2, "治疗间隔到期后应产生第 2 次治疗")
	assert_eq(int(rt.heal_events[1]["targetId"]), yuma.instance_id,
		"澪的百分比反超后应转向百分比更低的悠真")
	assert_eq(yuma.hp, 310, "悠真应被治疗 110 点（200 → 310）")


# ============================================================
#  四、撤退 / 失能 / 再部署对三职业均生效（覆盖项 13 / 14 与裁决 A）
# ============================================================

## 覆盖项 13：主动撤退、失能离场、再部署对三名角色都正确生效。
func test_retreat_incapacitation_and_redeploy_work_for_all_three_classes() -> void:
	for cid: String in TRIPLE:
		var cost := int(COST[cid])
		var refund := int(REFUND[cid])

		# ① 主动撤退：离场、返还 50% 费用、进入 20 秒再部署冷却
		var rt := _runtime(_cfg_triple([], 0.0))
		var dep := rt.deploy_character(cid, 2, 1)
		assert_true(dep.ok, "%s 应能部署：%s" % [cid, dep.reason_text()])
		var inst_id := dep.character.instance_id

		var w := rt.withdraw_character(inst_id)
		assert_true(w.ok, "%s 应能主动撤退：%s" % [cid, w.reason_text()])
		assert_eq(w.refund, refund, "%s 应返还 %d AP（费用 %d × 50%%）" % [cid, refund, cost])
		assert_eq(w.refund_granted, refund, "%s 的返还应全额入账（未触及 AP 上限）" % cid)
		assert_eq(rt.ap, AP_MAX - cost + refund, "%s 撤退后 AP 应为 %d" % [cid, AP_MAX - cost + refund])
		assert_eq(rt.characters.size(), 0, "%s 撤退后应离场" % cid)
		assert_null(rt.get_character_at(2, 1), "%s 撤退后原格应立即释放" % cid)
		assert_eq(rt.retreat_count, 1, "%s 应记录 1 次撤退" % cid)
		assert_eq(rt.removal_count(StageRuntime.Removal.RETREATED), 1, "%s 应记录 1 次撤退离场" % cid)
		assert_almost_eq(rt.get_redeploy_remaining(cid), REDEPLOY_SECONDS, EPS,
			"%s 撤退后应进入 %.0f 秒再部署冷却" % [cid, REDEPLOY_SECONDS])
		assert_false(rt.query_deploy(cid, 4, 2).ok, "%s 冷却期间不得部署" % cid)

		# ② 再部署：全新满血实例，位置生效
		_step_n(rt, REDEPLOY_SECONDS + 0.1)
		assert_almost_eq(rt.get_redeploy_remaining(cid), 0.0, 0.05, "%s 的冷却应准确到期" % cid)
		var again := rt.deploy_character(cid, 4, 2)
		assert_true(again.ok, "%s 冷却结束后应能再部署：%s" % [cid, again.reason_text()])
		assert_eq(again.character.column, 4, "%s 应部署到新格" % cid)
		assert_eq(again.character.lane, 2, "%s 应部署到新路线" % cid)
		assert_ne(again.character.instance_id, inst_id, "%s 再部署应是全新实例" % cid)
		assert_eq(rt.character_instances.size(), 2, "%s 的实例历史应为 2" % cid)

		# ③ 失能离场：不返还 AP、进入冷却、记录 INCAPACITATED
		var rt2 := _runtime(_cfg_triple([], 0.0))
		var dep2 := rt2.deploy_character(cid, 2, 1)
		assert_true(dep2.ok, "%s（失能用例）应能部署" % cid)
		var ap_before := rt2.ap
		dep2.character.take_damage(999999)
		rt2.advance(StageRuntime.LOGIC_STEP_SECONDS)

		assert_eq(rt2.characters.size(), 0, "%s 失能后应离场" % cid)
		assert_eq(rt2.characters_lost, 1, "%s 应计入 1 次失能" % cid)
		assert_eq(rt2.removal_count(StageRuntime.Removal.INCAPACITATED), 1,
			"%s 应记录 1 次失能离场" % cid)
		assert_eq(rt2.removal_count(StageRuntime.Removal.RETREATED), 0,
			"%s 失能不得被记为撤退" % cid)
		assert_eq(rt2.ap, ap_before, "%s 失能不得返还任何 AP（表 24：死亡返还 0 AP）" % cid)
		assert_eq(rt2.retreat_refunded_ap_total, 0, "%s 失能不得累计任何返还" % cid)
		assert_true(rt2.is_redeploy_cooling(cid), "%s 失能后应进入再部署冷却" % cid)


## 覆盖项 14 + 裁决 A：三人受伤后撤退再重部署都必须满血，且冷却期间不得提前部署。
func test_redeploy_full_hp_for_all_three_classes() -> void:
	for cid: String in TRIPLE:
		var max_hp := int(MAX_HP[cid])
		var rt := _runtime(_cfg_triple([], 0.0))
		var dep := rt.deploy_character(cid, 2, 1)
		assert_true(dep.ok, "%s 应能部署" % cid)
		assert_eq(dep.character.max_hp, max_hp, "%s 的最大 HP 应来自配置的 %d" % [cid, max_hp])
		assert_eq(dep.character.hp, max_hp, "%s 首次部署应为满血" % cid)

		var inst_id := dep.character.instance_id
		dep.character.take_damage(max_hp - 1)   # 打成 1 HP
		assert_eq(dep.character.hp, 1, "%s 应先被打到 1 HP" % cid)

		var w := rt.withdraw_character(inst_id)
		assert_true(w.ok, "%s 应能撤退" % cid)

		# 冷却未到期时不得提前部署（也不得因此刷出满血新实例）
		assert_false(rt.deploy_character(cid, 4, 2).ok, "%s 冷却期间不得提前再部署" % cid)
		assert_eq(rt.characters.size(), 0, "%s 冷却期间场上应为空" % cid)

		_step_n(rt, REDEPLOY_SECONDS + 0.1)
		var again := rt.deploy_character(cid, 4, 2)
		assert_true(again.ok, "%s 冷却结束后应能再部署：%s" % [cid, again.reason_text()])
		assert_eq(again.character.hp, max_hp, "%s 再部署后必须满血（裁决 A）" % cid)
		assert_eq(again.character.hp, again.character.max_hp, "%s 再部署后应处于满血上限" % cid)
		assert_eq(again.character.attack_cooldown, 0.0, "%s 再部署后攻击/治疗计时应就绪" % cid)
		assert_true(again.character.blocking_enemy_ids.is_empty(), "%s 新实例不得继承阻挡关系" % cid)
		assert_eq(again.character.total_damage_taken, 0, "%s 新实例不得继承受伤统计" % cid)
		assert_eq(rt.characters.size(), 1, "%s 场上应恰好 1 个实体" % cid)


## 覆盖项 14 + 裁决 A：三人各自撤退只返还一次 50%，重复调用不得叠加。
func test_no_double_refund_across_classes() -> void:
	for cid: String in TRIPLE:
		var refund := int(REFUND[cid])
		var rt := _runtime(_cfg_triple([], 0.0))
		var dep := rt.deploy_character(cid, 2, 1)
		assert_true(dep.ok, "%s 应能部署" % cid)
		var inst_id := dep.character.instance_id

		var first := rt.withdraw_character(inst_id)
		assert_true(first.ok, "%s 首次撤退应成功" % cid)
		assert_eq(first.refund, refund, "%s 应返还 %d AP" % [cid, refund])
		var ap_after := rt.ap
		var total_after := rt.retreat_refunded_ap_total

		# 反复点击同一个 instance_id
		for i: int in range(10):
			var again := rt.withdraw_character(inst_id)
			assert_false(again.ok, "%s 第 %d 次重复撤退应被拒" % [cid, i + 1])
			assert_eq(again.reason, StageRuntime.RetreatReject.CHARACTER_NOT_DEPLOYED,
				"%s 重复撤退的原因应为「该角色不在场上」" % cid)
			assert_eq(again.refund, 0, "%s 重复撤退不得再返还 AP" % cid)
			assert_eq(again.refund_granted, 0, "%s 重复撤退不得入账 AP" % cid)

		assert_eq(rt.ap, ap_after, "%s 的 AP 不得因重复点击而增加" % cid)
		assert_eq(rt.retreat_refunded_ap_total, total_after, "%s 的累计返还应只计一次" % cid)
		assert_eq(rt.retreat_count, 1, "%s 的撤退计数应仍为 1" % cid)

		# 冷却结束、再部署之后再撤退一次 → 应当且只应当再返还一次
		_step_n(rt, REDEPLOY_SECONDS + 0.1)
		var redeploy := rt.deploy_character(cid, 4, 2)
		assert_true(redeploy.ok, "%s 应能再部署" % cid)
		var second := rt.withdraw_character(redeploy.character.instance_id)
		assert_true(second.ok, "%s 第二次撤退应成功" % cid)
		assert_eq(second.refund, refund, "%s 第二次撤退应同样返还 %d AP" % [cid, refund])
		assert_eq(rt.retreat_refunded_ap_total, total_after + refund,
			"%s 的累计返还应为两次之和，不得因重复调用而多计" % cid)
		assert_eq(rt.retreat_count, 2, "%s 的撤退计数应为 2" % cid)


## 裁决 A：再部署仍支付正常费用，不存在隐藏折扣或隐藏加成。
func test_decision_a_redeploy_charges_normal_cost() -> void:
	for cid: String in TRIPLE:
		var cost := int(COST[cid])
		var refund := int(REFUND[cid])
		var rt := _runtime(_cfg_triple([], 0.0))

		var first := rt.deploy_character(cid, 2, 1)
		assert_true(first.ok, "%s 首次部署应成功" % cid)
		assert_eq(first.cost, cost, "%s 首次部署费用应为 %d" % [cid, cost])
		assert_eq(rt.ap, AP_MAX - cost, "%s 首次部署后 AP 应为 %d" % [cid, AP_MAX - cost])

		var w := rt.withdraw_character(first.character.instance_id)
		assert_true(w.ok, "%s 应能撤退" % cid)
		var ap_after_retreat := rt.ap
		assert_eq(ap_after_retreat, AP_MAX - cost + refund,
			"%s 撤退后 AP 应为 %d（返还 %d）" % [cid, AP_MAX - cost + refund, refund])

		_step_n(rt, REDEPLOY_SECONDS + 0.1)
		var again := rt.deploy_character(cid, 4, 2)
		assert_true(again.ok, "%s 再部署应成功：%s" % [cid, again.reason_text()])
		assert_eq(again.cost, cost, "%s 再部署的费用必须与首次完全一致（无隐藏折扣）" % cid)
		assert_eq(rt.ap, ap_after_retreat - cost,
			"%s 再部署应恰好扣除 %d AP，不得有隐藏减免" % [cid, cost])
		assert_eq(rt.deploy_success_count, 2, "%s 应记录 2 次成功部署" % cid)


# ============================================================
#  五、固定逻辑步长与暂停（覆盖项 15）
# ============================================================

## 覆盖项 15a：攻击、治疗、AP 回复只在固定逻辑步内结算；不足一步时全部不动。
func test_all_timers_advance_only_on_fixed_logic_steps() -> void:
	var step := StageRuntime.LOGIC_STEP_SECONDS
	var rt := _runtime(_cfg_triple([], 1.0, 99))
	assert_true(rt.deploy_character(CHAR_MIO, 2, 1).ok, "应能部署雨宫澪")
	assert_true(rt.deploy_character(CHAR_YUI, 1, 1).ok, "应能部署小川结衣")
	var mio := rt.get_character_by_id(CHAR_MIO)
	var yui := rt.get_character_by_id(CHAR_YUI)
	assert_eq(rt.ap, AP_MAX - int(COST[CHAR_MIO]) - int(COST[CHAR_YUI]),
		"两次部署后 AP 应为 30-10-14=6")

	var e := _place_enemy(rt, 1, 3.0)
	e.hp = 100000

	# ① 不足一个逻辑步：任何计时器都不得前进
	rt.advance(step * 0.5)
	assert_eq(rt.elapsed_seconds, 0.0, "不足一个逻辑步时逻辑时间不得推进")
	assert_eq(rt.ap, 6, "不足一个逻辑步时 AP 不得回复")
	assert_eq(e.logical_x, 3.0, "不足一个逻辑步时敌人不得移动")
	assert_eq(e.hp, 100000, "不足一个逻辑步时不得结算攻击")
	assert_eq(yui.attack_cooldown, 0.0, "不足一个逻辑步时治疗计时不得推进")

	# ② 恰好一个逻辑步：移动与攻击各发生一次
	rt.advance(step)
	assert_almost_eq(rt.elapsed_seconds, step, EPS, "恰好一个逻辑步时逻辑时间应前进一个步长")
	assert_lt(e.hp, 100000, "一个逻辑步内应完成一次攻击")
	assert_eq(100000 - e.hp, 100, "雨宫澪的单次伤害应为 120 × 100 / 120 = 100")
	assert_lt(e.logical_x, 3.0, "一个逻辑步内敌人应前进一个步长的距离")

	# ③ 治疗同样只在逻辑步内结算
	mio.hp = 500
	rt.advance(step)
	assert_eq(mio.hp, 610, "结衣应治疗 110 HP（治疗在逻辑步内结算）")
	assert_eq(rt.heal_events.size(), 1, "应恰好产生 1 次治疗事件")
	assert_almost_eq(yui.attack_cooldown, HEAL_INTERVAL, EPS, "治疗后应进入 1.5 秒治疗冷却")

	# ④ 治疗冷却按逻辑步递减：不足一步不动，恰好一步递减一个步长。
	# 先清零内部累积器，把「步长边界」这一条单独隔离出来观察
	# （否则上一步留下的半个步长残量会立刻凑成完整一步）。
	rt._accumulator = 0.0
	var cd := yui.attack_cooldown
	rt.advance(step * 0.5)
	assert_almost_eq(yui.attack_cooldown, cd, EPS, "不足一个逻辑步时治疗冷却不得推进")
	rt.advance(step)
	assert_almost_eq(yui.attack_cooldown, cd - step, EPS,
		"治疗冷却应恰好按一个逻辑步递减")

	# ⑤ 攻击冷却同理
	rt._accumulator = 0.0
	var mio_cd := mio.attack_cooldown
	rt.advance(step * 0.5)
	assert_almost_eq(mio.attack_cooldown, mio_cd, EPS, "不足一个逻辑步时攻击冷却不得推进")
	rt.advance(step)
	assert_almost_eq(mio.attack_cooldown, mio_cd - step, EPS,
		"攻击冷却应恰好按一个逻辑步递减")


## 覆盖项 15b：暂停期间敌人不动、AP 不回、不出怪、不攻击、不治疗、不推进再部署冷却。
func test_pause_freezes_every_timer_for_three_classes() -> void:
	var spawns := [{"time": 1.0, "lane": 1, "enemy": "echo_normal", "wave": 1}]
	var rt := _runtime(_cfg_triple(spawns, 1.0, 99))
	assert_true(rt.deploy_character(CHAR_MIO, 2, 1).ok, "应能部署雨宫澪")
	assert_true(rt.deploy_character(CHAR_YUI, 1, 1).ok, "应能部署小川结衣")

	# 推进到敌人已被阻挡、双方已交火、结衣已开始治疗的状态
	_step_n(rt, 7.0)
	assert_eq(rt.spawned_enemy_count(), 1, "1.0 秒应生成敌人（Wave 计时在逻辑步内生效）")
	var e := _enemy_in_lane(rt, 1)
	assert_not_null(e, "中段应有敌人")
	assert_eq(e.state, BattleTypes.EnemyState.BLOCKED, "敌人应已被雨宫澪阻挡")
	assert_lt(e.hp, e.hp_max, "雨宫澪应已造成伤害（攻击在逻辑步内发生）")
	var mio := rt.get_character_by_id(CHAR_MIO)
	assert_lt(mio.hp, mio.max_hp, "雨宫澪应已被反击受伤")
	assert_gt(rt.heal_events.size(), 0, "结衣应已治疗受伤的雨宫澪（治疗在逻辑步内发生）")

	# 移动见证者：上路的自由敌人（BLOCKED 的敌人本来就不动，无法证明「暂停使敌人不动」）
	var witness := _place_enemy(rt, 0, 4.0)
	_step_n(rt, 0.5)
	assert_lt(witness.logical_x, 4.0, "见证敌人应已在移动（保证用例确有效果）")

	var snap := {
		"ap": rt.ap,
		"elapsed": rt.elapsed_seconds,
		"spawned": rt.spawned_enemy_count(),
		"enemyHp": e.hp,
		"enemyX": e.logical_x,
		"mioHp": mio.hp,
		"heals": rt.heal_events.size(),
		"witnessX": witness.logical_x,
	}

	rt.set_paused(true)
	_step_n(rt, 30.0)

	assert_almost_eq(rt.elapsed_seconds, float(snap["elapsed"]), EPS, "暂停期间逻辑时间不得推进")
	assert_eq(rt.ap, int(snap["ap"]), "暂停期间 AP 不得回复")
	assert_eq(rt.spawned_enemy_count(), int(snap["spawned"]), "暂停期间不得出怪（Wave 计时冻结）")
	assert_eq(e.hp, int(snap["enemyHp"]), "暂停期间角色不得攻击")
	assert_eq(mio.hp, int(snap["mioHp"]), "暂停期间敌人不得攻击角色")
	assert_eq(rt.heal_events.size(), int(snap["heals"]), "暂停期间不得产生新的治疗")
	assert_almost_eq(e.logical_x, float(snap["enemyX"]), EPS, "暂停期间被阻挡的敌人不得移动")
	assert_almost_eq(witness.logical_x, float(snap["witnessX"]), EPS, "暂停期间自由敌人不得移动")

	# 恢复后从同一状态继续（不补跑暂停期间的时间）
	rt.set_paused(false)
	_step_n(rt, 2.0)
	assert_gt(rt.elapsed_seconds, float(snap["elapsed"]) + 1.9, "恢复后逻辑时间应继续推进")
	assert_gt(rt.ap, int(snap["ap"]), "恢复后 AP 应继续按 1/秒回复")
	assert_lt(witness.logical_x, float(snap["witnessX"]), "恢复后自由敌人应继续移动")


## 覆盖项 15c：暂停期间三职业的再部署冷却一律冻结，恢复后继续推进至到期。
func test_pause_freezes_redeploy_cooldown_for_all_three_classes() -> void:
	for cid: String in TRIPLE:
		var rt := _runtime(_cfg_triple([], 0.0))
		assert_true(rt.deploy_character(cid, 2, 1).ok, "%s 应能部署" % cid)
		assert_true(rt.withdraw_character_by_id(cid).ok, "%s 应能撤退" % cid)
		var remaining := rt.get_redeploy_remaining(cid)
		assert_almost_eq(remaining, REDEPLOY_SECONDS, EPS,
			"%s 撤退后应处于 %.0f 秒冷却" % [cid, REDEPLOY_SECONDS])

		rt.set_paused(true)
		_step_n(rt, 30.0)
		assert_almost_eq(rt.get_redeploy_remaining(cid), remaining, EPS,
			"暂停期间 %s 的再部署冷却不得推进" % cid)
		assert_false(rt.query_deploy(cid, 3, 0).ok, "暂停期间 %s 仍应处于冷却" % cid)

		rt.set_paused(false)
		_step_n(rt, REDEPLOY_SECONDS + 0.1)
		assert_almost_eq(rt.get_redeploy_remaining(cid), 0.0, 0.05,
			"恢复后 %s 的再部署冷却应继续推进至到期" % cid)
		assert_true(rt.query_deploy(cid, 3, 0).ok, "冷却到期后 %s 应可部署" % cid)


# ============================================================
#  六、帧率与分辨率无关（覆盖项 16）
# ============================================================

## 覆盖项 16a：三职业同场时，不同渲染帧率不改变战斗结果（推进到同一逻辑时刻比较）。
func test_three_class_result_independent_of_tick_granularity() -> void:
	var spawns := [{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1}]
	var results := []
	for tick: float in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 144.0]:
		var rt := _runtime(_cfg_triple(spawns, 1.0, 99))
		assert_true(rt.deploy_character(CHAR_MIO, 2, 1).ok, "应能部署雨宫澪")
		assert_true(rt.deploy_character(CHAR_YUI, 1, 1).ok, "应能部署小川结衣")

		_advance_until(rt, 10.0, tick)
		var mid := {
			"elapsed": snappedf(rt.elapsed_seconds, 0.001),
			"ap": rt.ap,
			"kills": rt.enemies_killed,
			"core": rt.core_hp,
			"spawned": rt.spawned_enemy_count(),
			"heals": rt.heal_events.size(),
			"healedTotal": rt.total_healing_done,
			"mioHp": rt.get_character_by_id(CHAR_MIO).hp,
		}
		_advance_until(rt, 30.0, tick)
		var late := {
			"elapsed": snappedf(rt.elapsed_seconds, 0.001),
			"ap": rt.ap,
			"kills": rt.enemies_killed,
			"core": rt.core_hp,
			"spawned": rt.spawned_enemy_count(),
			"heals": rt.heal_events.size(),
			"healedTotal": rt.total_healing_done,
			"yuiCooldown": snappedf(rt.get_character_by_id(CHAR_YUI).attack_cooldown, 0.001),
		}
		results.append({"mid": mid, "late": late})

	assert_eq(results[0]["mid"], results[1]["mid"], "60fps 与 30fps 的中场结果必须一致")
	assert_eq(results[1]["mid"], results[2]["mid"], "30fps 与 144fps 的中场结果必须一致")
	assert_eq(results[0]["late"], results[1]["late"], "60fps 与 30fps 的终场结果必须一致")
	assert_eq(results[1]["late"], results[2]["late"], "30fps 与 144fps 的终场结果必须一致")
	# 保证用例确实产生了可观察的战斗结果，而不是空转
	var mid0: Dictionary = results[0]["mid"]
	assert_gt(int(mid0["kills"]), 0, "10 秒内应已有击杀（保证用例确有效果）")
	assert_gt(int(mid0["heals"]), 0, "10 秒内应已有治疗（保证用例确有效果）")


## 覆盖项 16b：不同参考分辨率不改变三职业战斗结果。
func test_three_class_result_independent_of_render_resolution() -> void:
	var spawns := [{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1}]
	var results := []
	for size: Array in [[1280, 720], [1920, 1080], [3840, 2160]]:
		var g := BattleGrid.from_layout(DataRegistry.get_layout())
		g.reference_canvas_width = int(size[0])
		g.reference_canvas_height = int(size[1])
		var rt := StageRuntime.from_config(
			_cfg_triple(spawns, 1.0, 99), _enemy_table(), g, _char_table(), _combat()
		)
		assert_true(rt.is_valid(), "%s 分辨率下应无构建错误：%s" % [str(size), str(rt.get_errors())])
		assert_true(rt.deploy_character(CHAR_MIO, 2, 1).ok, "应能部署雨宫澪")
		assert_true(rt.deploy_character(CHAR_YUI, 1, 1).ok, "应能部署小川结衣")
		_step_n(rt, 30.0)
		results.append({
			"kills": rt.enemies_killed,
			"leaked": rt.reached_core_count,
			"core": rt.core_hp,
			"spawned": rt.spawned_enemy_count(),
			"ap": rt.ap,
			"heals": rt.heal_events.size(),
			"healedTotal": rt.total_healing_done,
			"mioHp": rt.get_character_by_id(CHAR_MIO).hp,
		})

	assert_eq(results[0], results[1], "720p 与 1080p 的三职业战斗结果必须一致")
	assert_eq(results[1], results[2], "1080p 与 4K 的三职业战斗结果必须一致")
	assert_gt(int(results[0]["kills"]), 0, "应通过真实击杀产生可比较的结果")


# ============================================================
#  七、裁决 B：正式 1-1 配置不被开发入口污染
# ============================================================

## 裁决 B：正式 1-1 的 availableCharacters 仍然只有雨宫澪，开发入口只在显式调用时生效。
func test_decision_b_1_1_roster_unchanged() -> void:
	var cfg := _stage_config()
	assert_eq(cfg["availableCharacters"], [CHAR_MIO],
		"正式 1-1 配置的 availableCharacters 应仍然只有 amamiya_mio")

	var rt := _runtime(cfg)
	assert_true(rt.is_valid(), "正式 1-1 应无构建错误：%s" % str(rt.get_errors()))
	assert_eq(rt.available_characters.size(), 1, "正式 1-1 应只有 1 名可部署角色")
	assert_eq(rt.available_characters[0], CHAR_MIO, "正式 1-1 唯一可部署角色应为雨宫澪")
	assert_false(rt.available_characters.has(CHAR_YUMA), "正式 1-1 不得解锁神谷悠真")
	assert_false(rt.available_characters.has(CHAR_YUI), "正式 1-1 不得解锁小川结衣")

	# 开发入口即使被调用，也不得回写 DataRegistry，也不得污染已构建的运行时
	var dev := PrototypeRoster.apply_triple(cfg)
	assert_eq(rt.available_characters.size(), 1, "apply_triple 不得污染已构建的运行时")
	assert_false(rt.available_characters.has(CHAR_YUMA), "运行时仍不得解锁神谷悠真")
	assert_eq(_stage_config()["availableCharacters"], [CHAR_MIO],
		"DataRegistry 中的权威配置不得被改动")
	assert_eq(dev["availableCharacters"], PrototypeRoster.TRIPLE_ROSTER,
		"开发副本应含三职业编队（只作用于副本）")

	# 章节解锁顺序（1-1 澪 / 1-3 悠真 / 1-6 结衣）不得为测试方便而改动
	assert_eq(str(_char_table()[CHAR_MIO].get("unlockStage", "")), "1-1", "雨宫澪应在 1-1 解锁")
	assert_eq(str(_char_table()[CHAR_YUMA].get("unlockStage", "")), "1-3", "神谷悠真应在 1-3 解锁")
	assert_eq(str(_char_table()[CHAR_YUI].get("unlockStage", "")), "1-6", "小川结衣应在 1-6 解锁")

	# 正式路径下悠真 / 结衣的部署必须被明确拒绝（不是静默失败）
	assert_eq(rt.query_deploy(CHAR_YUMA, 2, 1).reason,
		StageRuntime.DeployReject.CHARACTER_NOT_AVAILABLE, "正式 1-1 不得部署神谷悠真")
	assert_eq(rt.query_deploy(CHAR_YUI, 2, 1).reason,
		StageRuntime.DeployReject.CHARACTER_NOT_AVAILABLE, "正式 1-1 不得部署小川结衣")


## 裁决 B：PrototypeRoster.apply_triple 只改内存副本，传入的原字典不被修改。
func test_decision_b_dev_roster_does_not_mutate_source_config() -> void:
	var source := _stage_config()
	var before_chars: Array = (source["availableCharacters"] as Array).duplicate()
	var before_ap := int(source["startingAp"])
	var before_timeline: Array = (source["enemySpawnTimeline"] as Array).duplicate(true)

	var dev := PrototypeRoster.apply_triple(source)

	assert_eq(source["availableCharacters"], before_chars, "传入的原字典不得被修改")
	assert_eq(int(source["startingAp"]), before_ap, "原字典的 startingAp 不得被修改")
	assert_eq(source["enemySpawnTimeline"], before_timeline, "原字典的出怪时间线不得被修改")
	assert_false(source.has("_devRoster"), "原字典不得被写入开发标记")
	assert_true(dev.has("_devRoster"), "开发副本应带开发标记（与原配置可区分）")

	assert_eq(dev["availableCharacters"], PrototypeRoster.TRIPLE_ROSTER, "副本应含三职业编队")
	assert_eq(int(dev["startingAp"]), PrototypeRoster.TRIPLE_STARTING_AP,
		"副本应使用开发用开局 AP %d" % PrototypeRoster.TRIPLE_STARTING_AP)
	assert_eq(str(dev.get("_devRoster", "")), "triple", "副本应带开发标记，便于识别")

	# 复制必须独立：改副本不得影响原字典
	dev["availableCharacters"].append("__probe__")
	assert_eq(source["availableCharacters"], before_chars,
		"开发副本与原字典必须是深拷贝关系（改副本不得影响原字典）")


## 裁决 B：三职业开发编队三人都能部署，且「合计费用 36 > 开局 AP 上限 30」被如实处理。
func test_three_class_roster_can_all_be_deployed() -> void:
	var cfg := PrototypeRoster.apply_triple(_cfg_no_waves(_stage_config()))
	cfg["enemySpawnTimeline"] = []
	cfg["coreHp"] = 99
	cfg["apRegen"] = 1.0
	var rt := _runtime(cfg)

	assert_true(rt.is_valid(), "三职业开发场景应无构建错误：%s" % str(rt.get_errors()))
	assert_eq(rt.available_characters.size(), 3, "开发场景应有 3 名可部署角色")
	assert_eq(rt.ap, PrototypeRoster.TRIPLE_STARTING_AP,
		"开发场景开局 AP 应为 %d" % PrototypeRoster.TRIPLE_STARTING_AP)
	assert_eq(rt.ap_max, AP_MAX, "开局 AP 仍受 balance.combat.maxAp 上限 %d 约束" % AP_MAX)

	var total_cost := 0
	for cid: String in TRIPLE:
		total_cost += int(COST[cid])
	assert_eq(total_cost, 36, "三职业合计费用应为 10 + 12 + 14 = 36")
	assert_gt(total_cost, rt.ap_max,
		"事实：三人合计费用 %d 大于开局 AP 上限 %d（本用例不掩盖这一事实）" % [total_cost, rt.ap_max])

	# 前两人可在开局 AP 内放下（一个格只能站一人，故分格部署）
	assert_true(rt.deploy_character(CHAR_MIO, 2, 1).ok, "第一人应能部署")
	assert_true(rt.deploy_character(CHAR_YUMA, 3, 1).ok, "第二人应能部署")
	assert_eq(rt.ap, AP_MAX - int(COST[CHAR_MIO]) - int(COST[CHAR_YUMA]),
		"放下前两人后 AP 应为 30-10-12=8")

	# 第三人此刻必然 AP 不足——36 > 30 是配置事实，不是缺陷
	var early := rt.query_deploy(CHAR_YUI, 4, 1)
	assert_false(early.ok, "开局 AP 不足以立刻放下第三人（36 > 30）")
	assert_eq(early.reason, StageRuntime.DeployReject.INSUFFICIENT_AP,
		"第三人被拒的原因应为 AP 不足（而不是角色不可用或格子被占用）")

	# 等待自然回复补足第三人的费用
	_wait_ap_for(rt, CHAR_YUI)
	var third := rt.deploy_character(CHAR_YUI, 4, 1)
	assert_true(third.ok, "自然回复补足费用后第三人应能部署：%s" % third.reason_text())
	assert_eq(rt.characters.size(), 3, "三人应全部在场上（统一部署框架）")
	assert_true(rt.ap <= rt.ap_max, "AP 在任何时刻都不得超过上限")
	assert_eq(rt.ap, 0, "三人合计 36 AP 应被扣尽")

	# 三人的战斗行为分类确实来自数据
	assert_eq(rt.get_character_by_id(CHAR_MIO).behavior, CharacterRuntime.Behavior.FRONTLINE,
		"雨宫澪应为 FRONTLINE")
	assert_eq(rt.get_character_by_id(CHAR_YUMA).behavior, CharacterRuntime.Behavior.RANGED,
		"神谷悠真应为 RANGED")
	assert_eq(rt.get_character_by_id(CHAR_YUI).behavior, CharacterRuntime.Behavior.HEALER,
		"小川结衣应为 HEALER")
	assert_eq(rt.living_character_count(), 3, "三名角色应全部可作战")


# ============================================================
#  八、三职业框架的数据校验（behavior 必须显式声明，不得按职业名猜）
# ============================================================

## 三职业的行为分类必须来自数据；非法或缺失的行为应在构建期报错而不是静默兜底。
func test_behavior_must_be_declared_explicitly() -> void:
	# 缺 behavior → 构建期报错
	var t1 := _char_table()
	var mio_cfg: Dictionary = (t1[CHAR_MIO] as Dictionary).duplicate(true)
	mio_cfg.erase("behavior")
	t1[CHAR_MIO] = mio_cfg
	var rt1 := StageRuntime.from_config(_cfg_triple([]), _enemy_table(), _grid(), t1, _combat())
	assert_false(rt1.is_valid(), "缺少 behavior 应在构建期报错")
	assert_string_contains("\n".join(rt1.get_errors()), "behavior", "错误信息应指出缺少 behavior")

	# 非法 behavior → 构建期报错
	var t2 := _char_table()
	var yuma_cfg: Dictionary = (t2[CHAR_YUMA] as Dictionary).duplicate(true)
	yuma_cfg["behavior"] = "ARCHER"
	t2[CHAR_YUMA] = yuma_cfg
	var rt2 := StageRuntime.from_config(_cfg_triple([]), _enemy_table(), _grid(), t2, _combat())
	assert_false(rt2.is_valid(), "非法 behavior 应在构建期报错")
	assert_string_contains("\n".join(rt2.get_errors()), "ARCHER", "错误信息应带出非法值原文")

	# 非前线角色声明 blockCount > 0 → 与规格冲突，必须报错
	var t3 := _char_table()
	var yui_cfg: Dictionary = (t3[CHAR_YUI] as Dictionary).duplicate(true)
	yui_cfg["blockCount"] = 1
	t3[CHAR_YUI] = yui_cfg
	var rt3 := StageRuntime.from_config(_cfg_triple([]), _enemy_table(), _grid(), t3, _combat())
	assert_false(rt3.is_valid(), "治疗角色 blockCount > 0 应在构建期报错")
	assert_string_contains("\n".join(rt3.get_errors()), CHAR_YUI, "错误信息应指出是哪个角色")

	# 治疗角色缺少 manhattan 形状 → 报错（治疗范围必须由数据声明）
	var t4 := _char_table()
	var yui_cfg2: Dictionary = (t4[CHAR_YUI] as Dictionary).duplicate(true)
	var range_cfg: Dictionary = (yui_cfg2["attackRange"] as Dictionary).duplicate(true)
	range_cfg["shape"] = "lane_band"
	yui_cfg2["attackRange"] = range_cfg
	t4[CHAR_YUI] = yui_cfg2
	var rt4 := StageRuntime.from_config(_cfg_triple([]), _enemy_table(), _grid(), t4, _combat())
	assert_false(rt4.is_valid(), "治疗角色的 attackRange.shape 非 manhattan 应报错")

	# 权威数据本身必须完全合法（上述错误都来自被篡改的副本）
	var rt5 := _runtime(_cfg_triple([]))
	assert_true(rt5.is_valid(), "权威数据应无构建错误：%s" % str(rt5.get_errors()))


## 非治疗角色不得携带治疗力（避免出现第二套治疗来源）。
func test_only_healer_declares_heal_power() -> void:
	var table := _char_table()
	var mio := _char(table, CHAR_MIO)
	var yuma := _char(table, CHAR_YUMA)
	var yui := _char(table, CHAR_YUI)
	assert_eq(mio.heal_power, 0, "雨宫澪不应有治疗力")
	assert_eq(yuma.heal_power, 0, "神谷悠真不应有治疗力")
	assert_eq(mio.compute_heal_amount(), 0, "非治疗角色不得产生治疗量")
	assert_eq(yuma.compute_heal_amount(), 0, "非治疗角色不得产生治疗量")
	assert_gt(yui.heal_power, 0, "治疗角色应有正的治疗力")

	# 携带 healPower 的输出角色应在构建期报错
	var t := _char_table()
	var yuma_cfg: Dictionary = (t[CHAR_YUMA] as Dictionary).duplicate(true)
	yuma_cfg["healPower"] = 50
	t[CHAR_YUMA] = yuma_cfg
	var rt := StageRuntime.from_config(_cfg_triple([]), _enemy_table(), _grid(), t, _combat())
	assert_false(rt.is_valid(), "输出角色声明 healPower 应在构建期报错")
	assert_string_contains("\n".join(rt.get_errors()), "healPower", "错误信息应指出 healPower")


## 非治疗角色不得走治疗结算路径：悠真在场时不会产生任何治疗事件。
func test_non_healer_never_produces_heal_events() -> void:
	var rt := _runtime(_cfg_triple([]))
	assert_true(rt.deploy_character(CHAR_MIO, 1, 1).ok, "应能部署雨宫澪")
	assert_true(rt.deploy_character(CHAR_YUMA, 2, 1).ok, "应能部署神谷悠真")
	rt.get_character_by_id(CHAR_MIO).take_damage(500)
	_step_n(rt, 5.0)
	assert_eq(rt.heal_events.size(), 0, "场上没有治疗角色时不得产生治疗事件")
	assert_eq(rt.get_character_by_id(CHAR_MIO).hp, 500, "受伤角色不得被非治疗角色治疗")

	# 治疗角色登场后才开始治疗（统一分派：只有 HEALER 走治疗路径）
	_wait_ap_for(rt, CHAR_YUI)
	assert_true(rt.deploy_character(CHAR_YUI, 0, 1).ok, "应能部署小川结衣")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt.heal_events.size(), 1, "治疗角色登场后应开始治疗")


# ============================================================
#  九、三职业同场的一局仍可正常推进与结算
# ============================================================

## 三职业同场时，BattleSession 的胜负判定与结算摘要仍正常（治疗不改变胜负规则）。
func test_three_class_battle_session_reaches_outcome() -> void:
	var spawns := [{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1}]
	var cfg := _cfg_triple(spawns, 1.0, 5)
	cfg["waves"] = [{"number": 1}]
	var s := _session(cfg)
	assert_true(s.deploy_character(CHAR_MIO, 2, 1).ok, "应能部署雨宫澪")
	assert_true(s.deploy_character(CHAR_YUI, 1, 1).ok, "应能部署小川结衣")

	var t := 0.0
	while s.is_running() and t < 120.0:
		_tick_n(s, 1.0)
		t += 1.0

	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
		"全部 Wave 清除后应判胜（击杀 %d，漏怪 %d）"
		% [s.stage.enemies_killed, s.stage.reached_core_count])
	assert_gt(s.stage.enemies_killed, 0, "胜利应来自真实击杀")
	var summary := s.result_summary()
	assert_true(summary.has("heals"), "结算摘要应含治疗次数")
	assert_true(summary.has("healedTotal"), "结算摘要应含累计治疗量")
	assert_eq(int(summary["kills"]), 1, "应恰好击杀 1 名敌人")
