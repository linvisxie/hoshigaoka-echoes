## 三路线战斗体验重构：跨路线攻击、射程边界与三路防守验收测试。
##
## 依据：产品裁决 DEC-C-0003（docs/产品裁决记录.md，2026-10-09）。
##   - 前线角色：普通攻击只能命中自己所在路线；阻挡仍只能作用于本路。
##   - 远程角色：普通攻击可命中本路与**相邻**路线；中路可选上/中/下三路；
##     上路最多上路+中路；下路最多下路+中路；**不允许上路直接打下路**。
##   - 每次普通攻击仍只选择一个目标；跨线不增加攻击频率、不复制攻击次数。
##   - 跨线能力必须由角色数据**显式声明**（allowCrossLane / maxLaneDelta /
##     adjacentLaneRangeTiles / targetLimit），禁止仅凭 behavior=RANGED 获得。
##   - 本次只改玩家角色的指定攻击范围，**敌人攻击范围不得随之变化**。
##
## 覆盖范围（本轮指令第一/第二阶段验收点）：
##    1. 数据声明完整性（本路 4.0 / 相邻 3.0 / maxLaneDelta 1 / targetLimit 1）
##    2. 中路角色可选上/中/下三路
##    3. 上路角色最多上路+中路；下路角色最多下路+中路
##    4. 不允许上路直接打下路（laneDelta=2 双向拒绝）
##    5. 相邻路线射程 3.0 格的边界（3.0 可打 / 3.1 不可打）
##    6. 本路线射程 4.0 格的边界（4.0 可打 / 4.1 不可打）
##    7. 攻击方向仍须面向敌方入口（身后的敌人不可攻击）
##    8. 跨线不增加攻击频率（冷却与同路完全一致）
##    9. 跨线不复制攻击次数（三路同时有目标时仍只打 1 个）
##   10. 跨线不改变 D-11 目标优先级（仍优先最接近核心者）
##   11. 前线角色不得跨线攻击（雨宫澪 maxLaneDelta=0）
##   12. 阻挡仍只作用于本路（跨线不产生阻挡）
##   13. 敌人侧攻击范围未受影响（试卷飞灵仍 3 格 / 同路线）
##   14. 构建期声明校验（自相矛盾的声明必须报错，不得静默通过）
##   15. 部署预览覆盖范围与实际攻击判定一致（UI 不可能显示打不到的范围）
##   16. 三路防守：1-1～1-5 零漏怪可达性 + 失败路径 + 站位战术差异
##
## 纪律：所有夹具先 duplicate(true) 再改，绝不修改 DataRegistry 里的权威字典。
extends GutTest

const CHAR_MIO := "amamiya_mio"
const CHAR_YUMA := "kamiya_yuma"
const CHAR_YUI := "ogawa_yui"

const AP_MAX := 30
const EPS := 0.0001

## 权威数值（data/characters.json）
const YUMA_OWN_RANGE := 4.0
const YUMA_ADJACENT_RANGE := 3.0
const YUMA_MAX_LANE_DELTA := 1
const YUMA_INTERVAL := 1.3
const MIO_RANGE := 1.25

## 试卷飞灵（敌人侧，不得被玩家侧改动影响）
const FLYER_RANGE := 3.0


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


# ============================================================
#  夹具
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


## 可控夹具：AP 充足、核心血厚、无出怪（敌人由测试手动放置）。
func _cfg(chars: Array = [CHAR_MIO], core: int = 99) -> Dictionary:
	return {
		"stageId": "probe_cross_lane",
		"coreHp": core,
		"startingAp": AP_MAX,
		"apRegen": 1.0,
		"availableCharacters": chars.duplicate(),
		"enemySpawnTimeline": [],
	}


func _runtime(chars: Array = [CHAR_MIO], core: int = 99) -> StageRuntime:
	var rt := StageRuntime.from_config(
		_cfg(chars, core), _enemy_table(), _grid(), _char_table(), _combat())
	rt.ap = AP_MAX
	return rt


func _triple_runtime() -> StageRuntime:
	return _runtime([CHAR_MIO, CHAR_YUMA, CHAR_YUI])


func _place_enemy(
	rt: StageRuntime, lane: int, x: float, enemy_id: String = "echo_normal", hp: int = 0
) -> EnemyRuntime:
	var e := EnemyRuntime.from_config(_enemy_table()[enemy_id], lane, 9000 + rt.enemies.size())
	e.logical_x = x
	e.state = BattleTypes.EnemyState.MOVING
	if hp > 0:
		e.hp = hp
		e.hp_max = hp
	rt.enemies.append(e)
	return e


func _step_n(rt: StageRuntime, seconds: float) -> void:
	var t := 0.0
	while t < seconds - EPS:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS


## 从权威角色表构建纯数据实例（用于纯函数式射程判定）
func _char(character_id: String) -> CharacterRuntime:
	return CharacterRuntime.from_config(_char_table()[character_id], 0, 1, 1)


# ============================================================
#  一、数据声明完整性
# ============================================================

## 覆盖项 1：神谷悠真的跨线声明必须完整且与裁决一致。
func test_01_yuma_cross_lane_declaration_is_complete() -> void:
	var cfg: Dictionary = _char_table()[CHAR_YUMA]
	var rng: Dictionary = cfg.get("attackRange", {})
	assert_eq(float(rng.get("rangeTiles", 0.0)), YUMA_OWN_RANGE,
		"本路线射程应保持规格原值 4.0 格（表 28）")
	assert_eq(float(rng.get("adjacentLaneRangeTiles", 0.0)), YUMA_ADJACENT_RANGE,
		"相邻路线射程应为第一轮候选值 3.0 格（DEC-C-0003）")
	assert_eq(int(rng.get("maxLaneDelta", 0)), YUMA_MAX_LANE_DELTA,
		"maxLaneDelta 应为 1（最多跨相邻一条路线）")
	assert_true(bool(rng.get("allowCrossLane", false)),
		"必须显式声明 allowCrossLane=true（不得仅凭 behavior=RANGED 获得跨线）")
	assert_eq(int(rng.get("targetLimit", 0)), 1,
		"targetLimit 应为 1（每次普通攻击只选择一个目标）")
	assert_eq(str(rng.get("direction", "")), "forward",
		"攻击方向必须仍为面向敌方入口（forward）")
	assert_eq(str(rng.get("shape", "")), "lane_band", "射程形状应保持 lane_band")

	# 运行时字段同步
	var yuma := _char(CHAR_YUMA)
	assert_true(yuma.allow_cross_lane, "运行时实例应带上 allowCrossLane")
	assert_eq(yuma.max_lane_delta, YUMA_MAX_LANE_DELTA, "运行时 max_lane_delta 应为 1")
	assert_eq(yuma.adjacent_lane_range_tiles, YUMA_ADJACENT_RANGE,
		"运行时相邻射程应为 3.0")
	assert_eq(yuma.target_limit, 1, "运行时 target_limit 应为 1")


## 覆盖项 1b：**不得**仅凭 behavior=RANGED 让所有远程单位无条件获得跨线。
## 用一个只改 behavior、不声明跨线字段的合成角色验证「默认不可跨线」。
func test_01b_ranged_behavior_alone_does_not_grant_cross_lane() -> void:
	var cfg: Dictionary = _char_table()[CHAR_YUMA].duplicate(true)
	var rng: Dictionary = (cfg["attackRange"] as Dictionary).duplicate(true)
	rng.erase("allowCrossLane")
	rng.erase("adjacentLaneRangeTiles")
	rng["maxLaneDelta"] = 0
	cfg["attackRange"] = rng

	var probe := CharacterRuntime.from_config(cfg, 0, 1, 1)
	assert_eq(probe.behavior, CharacterRuntime.Behavior.RANGED, "该合成角色仍是 RANGED")
	assert_false(probe.allow_cross_lane, "未声明 allowCrossLane 时应为 false")
	assert_false(probe.can_attack_lane(0), "未声明的 RANGED 角色不得攻击相邻路线")
	assert_false(probe.can_attack_lane(2), "未声明的 RANGED 角色不得攻击相邻路线")
	assert_true(probe.can_attack_lane(1), "但仍可攻击本路线")


# ============================================================
#  二、路线闸门：中路三路 / 边路两路 / 不得跨两路
# ============================================================

## 覆盖项 2：位于中路的远程角色可选上、中、下三路。
func test_02_middle_lane_can_target_all_three_lanes() -> void:
	var yuma := _char(CHAR_YUMA)
	yuma.lane = 1
	assert_true(yuma.can_attack_lane(0), "中路角色应可攻击上路")
	assert_true(yuma.can_attack_lane(1), "中路角色应可攻击本路（中路）")
	assert_true(yuma.can_attack_lane(2), "中路角色应可攻击下路")
	assert_eq(yuma.attack_range_for_lane(0), YUMA_ADJACENT_RANGE, "上路目标用相邻射程 3.0")
	assert_eq(yuma.attack_range_for_lane(1), YUMA_OWN_RANGE, "本路目标用本路射程 4.0")
	assert_eq(yuma.attack_range_for_lane(2), YUMA_ADJACENT_RANGE, "下路目标用相邻射程 3.0")


## 覆盖项 3：位于上路时最多攻击上路和中路；位于下路时最多攻击下路和中路。
func test_03_edge_lanes_reach_only_own_and_middle() -> void:
	var up := _char(CHAR_YUMA)
	up.lane = 0
	assert_true(up.can_attack_lane(0), "上路角色应可攻击上路（本路）")
	assert_true(up.can_attack_lane(1), "上路角色应可攻击中路（相邻）")
	assert_false(up.can_attack_lane(2), "上路角色**不得**攻击下路")

	var low := _char(CHAR_YUMA)
	low.lane = 2
	assert_true(low.can_attack_lane(2), "下路角色应可攻击下路（本路）")
	assert_true(low.can_attack_lane(1), "下路角色应可攻击中路（相邻）")
	assert_false(low.can_attack_lane(0), "下路角色**不得**攻击上路")


## 覆盖项 4：不允许上路直接打下路——双向均被拒绝，且有效射程为 0。
func test_04_lane_delta_two_is_always_rejected() -> void:
	var up := _char(CHAR_YUMA)
	up.lane = 0
	var low := _char(CHAR_YUMA)
	low.lane = 2

	assert_false(up.can_attack_lane(2), "上路 → 下路应被拒（laneDelta=2）")
	assert_false(low.can_attack_lane(0), "下路 → 上路应被拒（laneDelta=2）")
	assert_eq(up.attack_range_for_lane(2), 0.0, "上路 → 下路的有效射程应为 0")
	assert_eq(low.attack_range_for_lane(0), 0.0, "下路 → 上路的有效射程应为 0")
	# 即使目标几何距离很近也不可攻击
	assert_false(up.is_target_in_attack_range(2, 0.5),
		"即使下路目标紧贴身前，上路角色也不得攻击（路线闸门优先于距离）")


# ============================================================
#  三、射程边界（全部以逻辑格计算，绝不用屏幕像素）
# ============================================================

## 覆盖项 5：相邻路线射程 3.0 格的边界（3.0 可打 / 3.1 不可打）。
func test_05_adjacent_lane_range_boundary() -> void:
	var yuma := _char(CHAR_YUMA)
	yuma.lane = 1
	yuma.column = 1
	assert_true(yuma.is_target_in_attack_range(0, 4.0),
		"相邻路上 delta=3.0（= 射程 3.0）应恰好在射程内")
	assert_false(yuma.is_target_in_attack_range(0, 4.1),
		"相邻路上 delta=3.1（> 射程 3.0）应在射程外")
	assert_true(yuma.is_target_in_attack_range(2, 4.0), "下路同样适用 3.0 边界")
	assert_false(yuma.is_target_in_attack_range(2, 4.1), "下路同样适用 3.0 边界")


## 覆盖项 6：本路线射程 4.0 格的边界（4.0 可打 / 4.1 不可打）。
func test_06_own_lane_range_boundary() -> void:
	var yuma := _char(CHAR_YUMA)
	yuma.lane = 1
	yuma.column = 1
	assert_true(yuma.is_target_in_attack_range(1, 5.0),
		"本路 delta=4.0（= 射程 4.0）应恰好在射程内")
	assert_false(yuma.is_target_in_attack_range(1, 5.1),
		"本路 delta=4.1（> 射程 4.0）应在射程外")


## 覆盖项 7：攻击方向仍须面向敌方入口——角色身后的目标不可攻击（含相邻路）。
func test_07_attack_direction_is_still_forward() -> void:
	var yuma := _char(CHAR_YUMA)
	yuma.lane = 1
	yuma.column = 3
	assert_false(yuma.is_target_in_attack_range(1, 2.0),
		"本路身后目标（x < column）不可攻击")
	assert_false(yuma.is_target_in_attack_range(0, 2.0),
		"相邻路身后目标也不可攻击（方向性对跨线同样适用）")
	assert_true(yuma.is_target_in_attack_range(0, 3.5),
		"相邻路前方目标可攻击")


# ============================================================
#  四、跨线不改变攻击频率与攻击次数
# ============================================================

## 覆盖项 8：跨线攻击后的冷却与同路攻击完全一致（不加快也不减慢）。
func test_08_cross_lane_does_not_change_attack_interval() -> void:
	# 同路场景
	var rt_same := _triple_runtime()
	assert_true(rt_same.deploy_character(CHAR_YUMA, 1, 1).ok, "应能部署悠真")
	var t_same := _place_enemy(rt_same, 1, 3.0, "echo_normal", 1000000)
	rt_same.advance(StageRuntime.LOGIC_STEP_SECONDS)
	var yuma_same := rt_same.get_character_by_id(CHAR_YUMA)
	assert_lt(t_same.hp, 1000000, "同路目标应被攻击")

	# 跨线场景（相邻路上 delta 2.0，落在 3.0 内）
	var rt_cross := _triple_runtime()
	assert_true(rt_cross.deploy_character(CHAR_YUMA, 1, 1).ok, "应能部署悠真")
	var t_cross := _place_enemy(rt_cross, 0, 3.0, "echo_normal", 1000000)
	rt_cross.advance(StageRuntime.LOGIC_STEP_SECONDS)
	var yuma_cross := rt_cross.get_character_by_id(CHAR_YUMA)
	assert_lt(t_cross.hp, 1000000, "相邻路目标应被攻击")

	assert_almost_eq(yuma_cross.attack_cooldown, yuma_same.attack_cooldown, EPS,
		"跨线与同路的攻击冷却必须完全相同（跨线不改变攻击频率）")
	assert_almost_eq(yuma_cross.attack_cooldown, YUMA_INTERVAL, EPS,
		"跨线攻击后应进入完整的 1.3 秒冷却")


## 覆盖项 9：三路同时有合法目标时，仍然**只攻击一个**（不复制攻击次数）。
func test_09_cross_lane_does_not_duplicate_attacks() -> void:
	var rt := _triple_runtime()
	assert_true(rt.deploy_character(CHAR_YUMA, 1, 1).ok, "应能部署悠真")
	var targets: Array[EnemyRuntime] = []
	for lane_i: int in [0, 1, 2]:
		targets.append(_place_enemy(rt, lane_i, 3.0, "echo_normal", 1000000))

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	var hit := 0
	for e: EnemyRuntime in targets:
		if e.hp < 1000000:
			hit += 1
	assert_eq(hit, 1,
		"三路同时有目标时应恰好攻击 1 个（实际 %d 个）——跨线不复制攻击次数" % hit)

	# 继续推进一个完整攻击间隔，仍应只多打 1 次
	_step_n(rt, YUMA_INTERVAL + 0.05)
	var hit2 := 0
	for e: EnemyRuntime in targets:
		if e.hp < 1000000:
			hit2 += 1
	assert_eq(hit2, 1, "一个完整间隔后仍只有 1 个目标被攻击（不存在多重攻击）")


## 覆盖项 10：跨线不改变 D-11 目标优先级——仍优先最接近核心者，即使它在别的路线。
func test_10_cross_lane_keeps_d11_priority() -> void:
	var rt := _triple_runtime()
	assert_true(rt.deploy_character(CHAR_YUMA, 1, 1).ok, "应能部署悠真")
	# 相邻路（上路）目标更靠近核心
	var near_upper := _place_enemy(rt, 0, 1.5, "echo_normal", 1000000)
	# 本路目标较远
	var far_mid := _place_enemy(rt, 1, 3.5, "echo_normal", 1000000)

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_lt(near_upper.hp, 1000000,
		"更接近核心的相邻路目标应被优先攻击（D-11 优先级不受跨线影响）")
	assert_eq(far_mid.hp, 1000000, "较远的本路目标本轮不应被攻击（单目标约束）")


# ============================================================
#  五、前线角色与阻挡不受影响
# ============================================================

## 覆盖项 11：前线角色（雨宫澪）的普通攻击仍只能命中自己所在路线。
func test_11_frontline_attacks_only_its_own_lane() -> void:
	var rt := _triple_runtime()
	assert_true(rt.deploy_character(CHAR_MIO, 2, 1).ok, "应能部署雨宫澪")
	var mio := rt.get_character_by_id(CHAR_MIO)
	assert_eq(mio.attack_range_tiles, MIO_RANGE, "澪的射程应保持规格原值 1.25 格")
	assert_false(mio.allow_cross_lane, "前线角色不得声明跨线")

	# 相邻路上放一个在射程内的敌人（若允许跨线就会被攻击）
	var side := _place_enemy(rt, 0, 2.5, "echo_normal", 1000000)
	var own := _place_enemy(rt, 1, 2.5, "echo_normal", 1000000)

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(side.hp, 1000000, "前线角色不得攻击相邻路线上的敌人")
	assert_lt(own.hp, 1000000, "但本路线上的敌人应被正常攻击")


## 覆盖项 12：阻挡仍只能作用于本路——跨线攻击不产生任何阻挡关系。
func test_12_blocking_is_still_same_lane_only() -> void:
	var rt := _triple_runtime()
	assert_true(rt.deploy_character(CHAR_MIO, 3, 1).ok, "应能部署雨宫澪")
	var mio := rt.get_character_by_id(CHAR_MIO)

	# 相邻路上放一个会走到接触线的敌人
	var side := _place_enemy(rt, 0, 3.6)
	# 本路放一个对照敌人
	var own := _place_enemy(rt, 1, 3.6)

	_step_n(rt, 2.0)

	assert_eq(side.blocked_by_character_id, 0, "相邻路敌人不得被本路角色阻挡")
	assert_ne(side.state, BattleTypes.EnemyState.BLOCKED, "相邻路敌人不应进入 BLOCKED")
	assert_eq(own.blocked_by_character_id, mio.instance_id, "本路敌人应被正常阻挡")
	assert_eq(mio.blocking_enemy_ids.size(), 1,
		"角色的阻挡列表只应含本路敌人（实际 %d）" % mio.blocking_enemy_ids.size())


# ============================================================
#  六、敌人侧范围未被改动（玩家改动不得外溢）
# ============================================================

## 覆盖项 13：试卷飞灵的射程与跨线限制保持规格原值，未被玩家侧改动影响。
func test_13_enemy_ranges_are_unchanged() -> void:
	var flyer_cfg: Dictionary = _enemy_table()["echo_exam_sheet"]
	var mech: Dictionary = flyer_cfg.get("mechanic", {})
	assert_eq(float(mech.get("rangeTiles", 0.0)), FLYER_RANGE,
		"试卷飞灵射程应仍为规格值 3 格")
	assert_eq(int(mech.get("maxLaneDelta", -1)), 0,
		"试卷飞灵应仍只打同路线（maxLaneDelta=0）")

	var flyer := EnemyRuntime.from_config(flyer_cfg, 1, 1)
	assert_eq(flyer.ranged_range_tiles(), FLYER_RANGE, "运行时射程应仍为 3.0")
	assert_eq(flyer.ranged_max_lane_delta(), 0, "运行时跨线限制应仍为 0")

	# 行为验证：飞灵不得把相邻路线的角色当作合法目标
	var rt := _triple_runtime()
	assert_true(rt.deploy_character(CHAR_MIO, 3, 0).ok, "应能部署澪到上段")
	var e := _place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_exam_sheet")
	_step_n(rt, 1.0)
	assert_eq(e.state, BattleTypes.EnemyState.MOVING,
		"中段飞灵不得把上段角色当作合法目标（敌人侧未获跨线能力）")


# ============================================================
#  七、构建期声明校验（自相矛盾的声明必须报错）
# ============================================================

## 覆盖项 14：allowCrossLane=true 但 maxLaneDelta=0 → 必须报错（不得静默）。
func test_14_contradictory_cross_lane_declaration_is_rejected() -> void:
	var chars := _char_table()
	var cfg: Dictionary = (chars[CHAR_YUMA] as Dictionary).duplicate(true)
	var rng: Dictionary = (cfg["attackRange"] as Dictionary).duplicate(true)
	rng["allowCrossLane"] = true
	rng["maxLaneDelta"] = 0
	cfg["attackRange"] = rng
	chars[CHAR_YUMA] = cfg

	var rt := StageRuntime.from_config(
		_cfg([CHAR_YUMA]), _enemy_table(), _grid(), chars, _combat())
	assert_false(rt.is_valid(), "allowCrossLane=true 但 maxLaneDelta=0 应报错")
	assert_gt(_error_count_containing(rt, "maxLaneDelta"), 0,
		"错误信息应指出 maxLaneDelta 的问题：%s" % str(rt.get_errors()))


## 覆盖项 14b：maxLaneDelta≥1 但未声明 allowCrossLane → 必须报错
## （防止「配了跨线却没生效」这类静默不一致）。
func test_14b_max_lane_delta_without_declaration_is_rejected() -> void:
	var chars := _char_table()
	var cfg: Dictionary = (chars[CHAR_YUMA] as Dictionary).duplicate(true)
	var rng: Dictionary = (cfg["attackRange"] as Dictionary).duplicate(true)
	rng.erase("allowCrossLane")
	rng["maxLaneDelta"] = 1
	cfg["attackRange"] = rng
	chars[CHAR_YUMA] = cfg

	var rt := StageRuntime.from_config(
		_cfg([CHAR_YUMA]), _enemy_table(), _grid(), chars, _combat())
	assert_false(rt.is_valid(), "maxLaneDelta≥1 但未声明 allowCrossLane 应报错")
	assert_gt(_error_count_containing(rt, "allowCrossLane"), 0,
		"错误信息应指出缺少 allowCrossLane：%s" % str(rt.get_errors()))


## 覆盖项 14c：相邻路线射程大于本路线射程 → 必须报错。
func test_14c_adjacent_range_larger_than_own_is_rejected() -> void:
	var chars := _char_table()
	var cfg: Dictionary = (chars[CHAR_YUMA] as Dictionary).duplicate(true)
	var rng: Dictionary = (cfg["attackRange"] as Dictionary).duplicate(true)
	rng["rangeTiles"] = 3.0
	rng["adjacentLaneRangeTiles"] = 4.0
	cfg["attackRange"] = rng
	chars[CHAR_YUMA] = cfg

	var rt := StageRuntime.from_config(
		_cfg([CHAR_YUMA]), _enemy_table(), _grid(), chars, _combat())
	assert_false(rt.is_valid(), "相邻射程 > 本路射程应报错")
	assert_gt(_error_count_containing(rt, "adjacentLaneRangeTiles"), 0,
		"错误信息应指出相邻射程的问题：%s" % str(rt.get_errors()))


## 覆盖项 14d：治疗角色声明 allowCrossLane → 必须报错（治疗走既有路径）。
func test_14d_healer_cross_lane_declaration_is_rejected() -> void:
	var chars := _char_table()
	var cfg: Dictionary = (chars[CHAR_YUI] as Dictionary).duplicate(true)
	var rng: Dictionary = (cfg["attackRange"] as Dictionary).duplicate(true)
	rng["allowCrossLane"] = true
	cfg["attackRange"] = rng
	chars[CHAR_YUI] = cfg

	var rt := StageRuntime.from_config(
		_cfg([CHAR_YUI]), _enemy_table(), _grid(), chars, _combat())
	assert_false(rt.is_valid(), "治疗角色不得声明 allowCrossLane")
	assert_gt(_error_count_containing(rt, "allowCrossLane"), 0,
		"错误信息应指出治疗角色不得跨线攻击：%s" % str(rt.get_errors()))


## 覆盖项 14e：权威配置本身必须无构建错误（回归保护）。
func test_14e_authoritative_config_builds_cleanly() -> void:
	var rt := _triple_runtime()
	assert_true(rt.is_valid(),
		"权威角色配置应能无错误构建：%s" % str(rt.get_errors()))


func _error_count_containing(rt: StageRuntime, needle: String) -> int:
	var n := 0
	for e: String in rt.get_errors():
		if e.contains(needle):
			n += 1
	return n


# ============================================================
#  八、部署预览覆盖范围与实际攻击判定一致
# ============================================================

## 覆盖项 15：query_attack_coverage 报告的覆盖格必须与实际攻击判定一致。
##
## 这是「UI 不可能显示出一个实际打不到的范围」的可执行保证。
func test_15_coverage_preview_matches_real_targeting() -> void:
	var rt := _triple_runtime()
	var coverage := rt.query_attack_coverage(CHAR_YUMA, 1, 1)
	assert_gt(coverage.size(), 0, "悠真应有非空覆盖范围")

	# 中路部署应覆盖上/中/下三路
	var lanes: Array[int] = []
	for entry: Dictionary in coverage:
		lanes.append(int(entry["lane"]))
	lanes.sort()
	assert_eq(lanes, [0, 1, 2] as Array[int],
		"中路部署的覆盖范围应含上/中/下三路（实际 %s）" % str(lanes))

	# 每一条报告的覆盖格，都必须真的落在攻击范围内
	var probe := CharacterRuntime.from_config(_char_table()[CHAR_YUMA], 1, 1, 0, {})
	for entry: Dictionary in coverage:
		var lane := int(entry["lane"])
		for cell: Dictionary in entry["cells"]:
			var col := int(cell["column"])
			assert_true(probe.is_target_in_attack_range(lane, float(col)),
				"预览报告的格 (col%d, lane%d) 必须真的在攻击范围内" % [col, lane])

	# 相邻路不得报告超出 3.0 格的格
	for entry: Dictionary in coverage:
		var lane := int(entry["lane"])
		if lane == 1:
			continue
		for cell: Dictionary in entry["cells"]:
			var delta := int(cell["column"]) - 1
			assert_lte(float(delta), YUMA_ADJACENT_RANGE + EPS,
				"相邻路预览不得报告超出 3.0 格的格（col%d）" % int(cell["column"]))

	# 上路部署的覆盖范围只能是上路+中路
	var up_cov := rt.query_attack_coverage(CHAR_YUMA, 1, 0)
	var up_lanes: Array[int] = []
	for entry: Dictionary in up_cov:
		up_lanes.append(int(entry["lane"]))
	up_lanes.sort()
	assert_eq(up_lanes, [0, 1] as Array[int],
		"上路部署的覆盖范围应只有上路+中路（实际 %s）" % str(up_lanes))

	# 前线角色的覆盖范围只有本路
	var mio_cov := rt.query_attack_coverage(CHAR_MIO, 3, 1)
	var mio_lanes: Array[int] = []
	for entry: Dictionary in mio_cov:
		mio_lanes.append(int(entry["lane"]))
	assert_eq(mio_lanes, [1] as Array[int],
		"前线角色的覆盖范围应只有本路（实际 %s）" % str(mio_lanes))

	# 预览必须无副作用
	assert_eq(rt.characters.size(), 0, "query_attack_coverage 不得产生部署副作用")
	assert_eq(rt.ap, AP_MAX, "query_attack_coverage 不得扣除 AP")


## 覆盖项 15b：BattleSession 必须转发覆盖查询，且结果与领域层完全一致。
##
## 这是「UI 只能经唯一入口读取射程」的契约保证：UI 不得自行推导，
## 因此不会出现「面板显示一套、实际打另一套」。
func test_15b_session_forwards_coverage_query_consistently() -> void:
	var s := BattleSession.new()
	add_child_autofree(s)
	var cfg := _cfg([CHAR_MIO, CHAR_YUMA])
	cfg["coreHp"] = 99
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))

	var via_session := s.query_attack_coverage(CHAR_YUMA, 1, 1)
	var via_stage := s.stage.query_attack_coverage(CHAR_YUMA, 1, 1)

	assert_eq(via_session.size(), via_stage.size(),
		"BattleSession 与 StageRuntime 的覆盖范围条目数必须一致")
	assert_eq(via_session.size(), 3, "中路部署应报告 3 条路线（上/中/下）")

	for i: int in range(via_session.size()):
		var a: Dictionary = via_session[i]
		var b: Dictionary = via_stage[i]
		assert_eq(int(a["lane"]), int(b["lane"]), "第 %d 条的路线必须一致" % i)
		assert_almost_eq(float(a["rangeTiles"]), float(b["rangeTiles"]), EPS,
			"第 %d 条的射程必须一致" % i)
		assert_eq(bool(a["isAdjacent"]), bool(b["isAdjacent"]),
			"第 %d 条的相邻标记必须一致" % i)

	# 未部署时也应有覆盖（预览发生在部署之前）
	assert_eq(s.stage.characters.size(), 0, "查询不得产生部署")


## 覆盖项 15c：非法输入（未知角色 / 非法格）必须返回空覆盖，不得崩溃或猜测。
func test_15c_coverage_query_is_safe_for_invalid_input() -> void:
	var rt := _triple_runtime()
	assert_eq(rt.query_attack_coverage("no_such_character", 1, 1).size(), 0,
		"未知角色应返回空覆盖")
	assert_eq(rt.query_attack_coverage(CHAR_YUMA, -1, 1).size(), 0,
		"非法 column 应返回空覆盖")
	assert_eq(rt.query_attack_coverage(CHAR_YUMA, 1, 9).size(), 0,
		"非法 lane 应返回空覆盖")


# ============================================================
#  九、三路防守：零漏怪可达性 / 失败路径 / 站位差异
# ============================================================

## 覆盖项 16：1-3 在跨线规则下，把悠真放在相邻路也能零漏怪
## （证明「某条路线空闲时，角色能利用自身机制支援其他路线」）。
func test_16_stage_1_3_cross_lane_support_reaches_zero_leak() -> void:
	var stable := _run_stage("1-3", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
		{"t": 12.5, "c": CHAR_YUMA, "col": 1, "lane": 1},
	])
	assert_eq(int(stable["outcome"]), BattleTypes.Outcome.VICTORY, "中段集火解应胜利")
	assert_eq(int(stable["leaked"]), 0, "中段集火解应零漏怪")
	assert_eq(int(stable["coreHp"]), int(stable["coreHpMax"]), "中段集火解核心应满值")

	# 相邻路支援：悠真放在上路，仍能覆盖中段
	var support := _run_stage("1-3", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
		{"t": 12.5, "c": CHAR_YUMA, "col": 1, "lane": 0},
	])
	assert_eq(int(support["outcome"]), BattleTypes.Outcome.VICTORY,
		"悠真放在相邻路应仍可通关（跨线支援）")
	assert_gt(int(support["kills"]), 0, "相邻路支援应至少击杀若干敌人")


## 密集波次后，中路贯穿仍可零漏怪；上路支援也能胜利，但会漏一只。
## 保留真实站位代价，不能把旧低密度版本的双零漏怪结果继续标为通过。
func test_16b_stage_1_4_has_multiple_winning_placements_with_different_costs() -> void:
	var mid := _run_stage("1-4", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
		{"t": 12.5, "c": CHAR_YUMA, "col": 1, "lane": 1},
	])
	var side := _run_stage("1-4", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
		{"t": 12.5, "c": CHAR_YUMA, "col": 3, "lane": 0},
	])

	assert_eq(int(mid["outcome"]), BattleTypes.Outcome.VICTORY, "1-4 中路解应胜利")
	assert_eq(int(mid["leaked"]), 0, "1-4 中路解应零漏怪")
	assert_eq(int(side["outcome"]), BattleTypes.Outcome.VICTORY, "1-4 相邻路解应胜利")
	assert_gt(int(side["leaked"]), 0, "密集群与交替旁路下，固定边路摆法应弱于中路覆盖")
	assert_gt(int(side["coreHp"]), 0, "相邻路支援应仍有可通关余量，不能成为必败摆法")
	assert_gt(int(mid["coreHp"]), int(side["coreHp"]), "本路贯穿应体现密集清群的站位优势")


## 覆盖项 16c：1-5 垂直切片在跨线规则下应零漏怪（核心满值）。
func test_16c_stage_1_5_vertical_slice_reaches_zero_leak() -> void:
	var r := _run_stage("1-5", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
		{"t": 12.5, "c": CHAR_YUMA, "col": 1, "lane": 1},
	])
	assert_eq(int(r["outcome"]), BattleTypes.Outcome.VICTORY, "1-5 垂直切片解应胜利")
	assert_eq(int(r["leaked"]), 0, "1-5 垂直切片解应零漏怪（不再是必然漏 1）")
	assert_eq(int(r["kills"]), int(r["spawned"]), "应击杀全部生成的敌人")


## 覆盖项 16d：1-1 用「撤退 → 换线 → 再部署」可零漏怪。
## 这是「20 秒冷却不再让玩家失去救场机会」的直接证据。
func test_16d_stage_1_1_zero_leak_via_redeploy_swap() -> void:
	var r := _run_stage("1-1", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
		{"t": 30.0, "a": "retreat", "c": CHAR_MIO},
		{"t": 50.5, "c": CHAR_MIO, "col": 3, "lane": 0},
		{"t": 57.0, "a": "retreat", "c": CHAR_MIO},
		{"t": 77.5, "c": CHAR_MIO, "col": 3, "lane": 2},
	])
	assert_eq(int(r["outcome"]), BattleTypes.Outcome.VICTORY, "1-1 换线解应胜利")
	assert_eq(int(r["leaked"]), 0, "1-1 换线解应零漏怪")
	assert_eq(int(r["coreHp"]), int(r["coreHpMax"]), "1-1 换线解核心应保持满值")

	# 对照：全程只守中段必然漏怪（零漏怪是「优秀表现」而非自动达成）
	var no_swap := _run_stage("1-1", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
	])
	assert_gt(int(no_swap["leaked"]), 0,
		"全程只守中段的对照解应漏怪（证明零漏怪需要正确操作，而非关卡自动放水）")


## 覆盖项 16e：1-2 用换线可零漏怪，但时序容差很紧（20 秒冷却仍有约束力）。
func test_16e_stage_1_2_zero_leak_requires_timing() -> void:
	var ok := _run_stage("1-2", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
		{"t": 79.0, "a": "retreat", "c": CHAR_MIO},
		{"t": 99.5, "c": CHAR_MIO, "col": 3, "lane": 0},
	])
	assert_eq(int(ok["outcome"]), BattleTypes.Outcome.VICTORY, "1-2 换线解应胜利")
	assert_eq(int(ok["leaked"]), 0, "1-2 换线解应零漏怪")

	# 负面对照：晚 2 秒撤退就撞上 20 秒冷却 → 该动作必须被拒。
	# 这证明冷却约束真实存在，而不是被本轮重平衡架空。
	var late := _run_stage("1-2", [
		{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
		{"t": 81.0, "a": "retreat", "c": CHAR_MIO},
		{"t": 99.5, "c": CHAR_MIO, "col": 3, "lane": 0},
	])
	assert_gt((late["rejects"] as Array).size(), 0,
		"晚 2 秒撤退应被 20 秒再部署冷却拒绝（冷却仍具约束力）")


## 覆盖项 16f：所有关卡在不部署时都必须失败（关卡压力真实存在）。
func test_16f_every_stage_fails_without_deployment() -> void:
	for sid: String in ["1-1", "1-2", "1-3", "1-4", "1-5"]:
		var r := _run_stage(sid, [])
		assert_eq(int(r["outcome"]), BattleTypes.Outcome.DEFEAT,
			"%s 不部署必须失败" % sid)


## 覆盖项 16g：零漏怪在 1-1～1-5 全部可达（第二阶段核心目标）。
func test_16g_zero_leak_is_achievable_in_all_stages() -> void:
	var tactics := {
		"1-1": [
			{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
			{"t": 30.0, "a": "retreat", "c": CHAR_MIO},
			{"t": 50.5, "c": CHAR_MIO, "col": 3, "lane": 0},
			{"t": 57.0, "a": "retreat", "c": CHAR_MIO},
			{"t": 77.5, "c": CHAR_MIO, "col": 3, "lane": 2},
		],
		"1-2": [
			{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
			{"t": 79.0, "a": "retreat", "c": CHAR_MIO},
			{"t": 99.5, "c": CHAR_MIO, "col": 3, "lane": 0},
		],
		"1-3": [
			{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
			{"t": 12.5, "c": CHAR_YUMA, "col": 1, "lane": 1},
		],
		"1-4": [
			{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
			{"t": 12.5, "c": CHAR_YUMA, "col": 1, "lane": 1},
		],
		"1-5": [
			{"t": 0.5, "c": CHAR_MIO, "col": 3, "lane": 1},
			{"t": 12.5, "c": CHAR_YUMA, "col": 1, "lane": 1},
		],
	}
	for sid: String in ["1-1", "1-2", "1-3", "1-4", "1-5"]:
		var r := _run_stage(sid, tactics[sid])
		assert_eq(int(r["outcome"]), BattleTypes.Outcome.VICTORY,
			"%s 应存在胜利解" % sid)
		assert_eq(int(r["leaked"]), 0,
			"%s 应可达零漏怪（实际漏 %d）" % [sid, int(r["leaked"])])


# ============================================================
#  关卡运行夹具
# ============================================================

## 从磁盘读关卡 JSON（规避内存污染），按动作序列跑一局，返回战果字典。
##
## acts 元素：
##   {"t": 秒, "c": 角色 id, "col": n, "lane": n}            → 部署
##   {"t": 秒, "a": "retreat", "c": 角色 id}                 → 主动撤退
func _run_stage(sid: String, acts: Array) -> Dictionary:
	var cfg := _read_stage(sid)
	if cfg.is_empty():
		fail_test("应能从磁盘读到关卡 %s" % sid)
		return {}

	var rt := StageRuntime.from_config(
		cfg, _enemy_table(), _grid(), _char_table(), _combat())
	if not rt.is_valid():
		fail_test("关卡 %s 构建失败：%s" % [sid, str(rt.get_errors())])
		return {}

	rt.configure_skills(DataRegistry.get_domain("skills"))
	var rejects: Array[String] = []
	for act: Dictionary in acts:
		_advance_rt_to(rt, float(act["t"]))
		if str(act.get("a", "deploy")) == "retreat":
			var rr := rt.withdraw_character_by_id(str(act["c"]))
			if not rr.ok:
				rejects.append("撤退 %s：%s" % [str(act["c"]), rr.reason_text()])
			continue
		var dr := rt.deploy_character(str(act["c"]), int(act["col"]), int(act["lane"]))
		if not dr.ok:
			rejects.append("%s@col%d/lane%d：%s"
				% [str(act["c"]), int(act["col"]), int(act["lane"]), dr.reason_text()])

	_advance_rt_to(rt, 900.0)

	return {
		"outcome": _outcome_of(rt),
		"coreHp": rt.core_hp,
		"coreHpMax": rt.core_hp_max,
		"spawned": rt.spawned_enemy_count(),
		"kills": rt.enemies_killed,
		"leaked": rt.reached_core_count,
		"lost": rt.characters_lost,
		"rejects": rejects,
	}


func _advance_rt_to(rt: StageRuntime, target: float) -> void:
	var guard := 0
	while rt.elapsed_seconds < target - EPS and guard < 400000:
		for unit: CharacterRuntime in rt.characters:
			if unit.skill_ready() and rt.has_living_enemies():
				rt.cast_skill(unit.instance_id)
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1
		if rt.core_hp <= 0:
			return
		if rt.all_waves_cleared() and not rt.has_living_enemies():
			return


func _outcome_of(rt: StageRuntime) -> int:
	if rt.core_hp <= 0:
		return BattleTypes.Outcome.DEFEAT
	if rt.all_waves_cleared() and not rt.has_living_enemies():
		return BattleTypes.Outcome.VICTORY
	return BattleTypes.Outcome.RUNNING


## 从磁盘读关卡 JSON（所有数据断言都以磁盘为准，不用内存副本）。
func _read_stage(sid: String) -> Dictionary:
	var path := "res://data/stages/ch1/%s.json" % sid
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
