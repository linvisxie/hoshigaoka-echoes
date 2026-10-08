## P0.1 测试：敌人生成与移动（V2.1.4 D-24 / D-34 / F 章）
##
## 覆盖要求：
##   - 敌人从指定入口和路线生成，不意外换线
##   - 移动速度按"格/秒"逻辑计算
##   - 不同帧率/渲染分辨率不改变逻辑移动速度、到达顺序
extends GutTest

const STAGE_ID := "1-1"

## 逻辑比较容差（浮点步长累积误差）
const LOGIC_EPSILON := 0.0001


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func _grid() -> BattleGrid:
	return BattleGrid.from_layout(DataRegistry.get_layout())


func _char_table() -> Dictionary:
	var t := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		t[str(c.get("id", ""))] = c
	return t


func _combat() -> Dictionary:
	return DataRegistry.get_domain("balance").get("combat", {})

func _enemy_table() -> Dictionary:
	var t := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


func _stage_config() -> Dictionary:
	return DataRegistry.get_entry("stages", STAGE_ID)


## 生成时序测试专用夹具：不依赖 1-1 的可调平衡值，
## 用固定时间/路线验证"按配置出怪"这一行为本身。
## （1-1 的精确出怪秒数属规格 G-十一 列为候选的可配置平衡参数，会随试玩调整。）
func _fixture_config() -> Dictionary:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 5
	cfg["startingAp"] = 10
	cfg["apRegen"] = 1
	cfg["enemySpawnTimeline"] = [
		{"time": 2.0, "lane": 1, "enemy": "echo_normal"},
		{"time": 6.0, "lane": 0, "enemy": "echo_normal"},
		{"time": 10.0, "lane": 2, "enemy": "echo_normal"},
	]
	return cfg


func _make_fixture_runtime() -> StageRuntime:
	return StageRuntime.from_config(
		_fixture_config(), _enemy_table(), _grid(), _char_table(), _combat()
	)


func _make_runtime() -> StageRuntime:
	return StageRuntime.from_config(_stage_config(), _enemy_table(), _grid(), _char_table(), _combat())


func _make_session() -> BattleSession:
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(_stage_config(), _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	return s


# ---------- 数据有效性 ----------

func test_stage_1_1_loads_with_expected_values() -> void:
	var cfg := _stage_config()
	assert_false(cfg.is_empty(), "应能取到 1-1 配置")
	assert_eq(int(cfg.get("coreHp", 0)), 5, "1-1 核心生命应为 5（规格 G-五）")
	assert_gt((cfg.get("enemySpawnTimeline", []) as Array).size(), 0, "应有出怪计划")


func test_enemy_table_contains_spec_enemies() -> void:
	var t := _enemy_table()
	assert_true(t.has("echo_normal"), "应含普通残响体")
	assert_true(t.has("echo_runner"), "应含疾走残响体")
	# 数值取自规格 F 章
	assert_eq(float(t["echo_normal"]["moveSpeed"]), 0.55, "普通残响体速度 0.55 格/秒")
	assert_eq(int(t["echo_normal"]["coreDamage"]), 1, "普通残响体核心伤害 1")
	assert_eq(float(t["echo_runner"]["moveSpeed"]), 1.0, "疾走残响体速度 1.0 格/秒")


func test_runtime_builds_without_errors() -> void:
	var rt := _make_runtime()
	assert_true(rt.is_valid(), "运行时应无构建错误：%s" % str(rt.get_errors()))
	assert_eq(rt.planned_enemy_count(), 6, "1-1 计划出怪 6 个")
	assert_eq(rt.core_hp, 5, "初始核心 HP 应为 5")


# ---------- 生成 ----------

func test_enemies_spawn_at_scheduled_time_and_lane() -> void:
	var rt := _make_fixture_runtime()
	assert_eq(rt.spawned_enemy_count(), 0, "t=0 时不应有敌人已生成")

	# 推进到 2.0s：第一条计划（lane 1）应生成
	_advance(rt, 2.05)
	assert_eq(rt.spawned_enemy_count(), 1, "t≈2.0s 应生成第 1 个敌人")
	assert_eq(rt.enemies[0].lane, 1, "第 1 个敌人应在 lane 1（中段）")
	assert_eq(rt.enemies[0].enemy_id, "echo_normal", "第 1 个敌人应为 echo_normal")

	# 推进到 6.0s：第二条（lane 0）
	_advance(rt, 4.0)
	assert_eq(rt.spawned_enemy_count(), 2, "t≈6.0s 应生成第 2 个敌人")
	assert_eq(rt.enemies[1].lane, 0, "第 2 个敌人应在 lane 0（上段）")


func test_enemies_spawn_at_entry_position() -> void:
	var rt := _make_fixture_runtime()
	_advance(rt, 2.01)
	assert_gt(rt.enemies.size(), 0, "应已生成敌人")
	# 生成瞬间应在入口侧（x = SPAWN_X = 5.0）
	assert_almost_eq(rt.enemies[0].logical_x, BattleGrid.SPAWN_X, 0.02,
		"敌人应在入口侧生成")


func test_enemies_never_change_lane() -> void:
	# 使用专项夹具（多个敌人分布在不同路线），确保场上确实有敌人可供检查，
	# 不依赖 1-1 的可调出怪节奏（1-1 中段敌人会被玩家单位阻挡/击杀）。
	var cfg := _fixture_config().duplicate(true)
	cfg["enemySpawnTimeline"] = [
		{"time": 1.0, "lane": 0, "enemy": "echo_normal"},
		{"time": 1.0, "lane": 1, "enemy": "echo_normal"},
		{"time": 1.0, "lane": 2, "enemy": "echo_normal"},
	]
	var rt := StageRuntime.from_config(
		cfg, _enemy_table(), _grid(), _char_table(), _combat()
	)
	# 推进到三个敌人都已生成
	_advance(rt, 1.05)
	assert_eq(rt.enemies.size(), 3, "应生成 3 个敌人（三种路线各一）")

	# 记录当前路线
	var lanes_before := {}
	for e: EnemyRuntime in rt.enemies:
		lanes_before[e.instance_id] = e.lane
	assert_eq(lanes_before.size(), 3, "应记录到 3 个敌人的初始路线")

	# 再推进一段（敌人会持续移动）
	_advance(rt, 3.0)
	var checked := 0
	for e: EnemyRuntime in rt.enemies:
		if lanes_before.has(e.instance_id):
			assert_eq(e.lane, lanes_before[e.instance_id],
				"敌人 #%d 不得换线（规格 D-4）" % e.instance_id)
			checked += 1
	assert_gt(checked, 0, "应至少检查到一个仍在场的敌人（保证本测试确实断言）")


# ---------- 移动 ----------

func test_enemy_moves_left_at_configured_speed() -> void:
	var rt := _make_fixture_runtime()
	_advance(rt, 2.05)
	if rt.enemies.is_empty():
		fail_test("未生成敌人")
		return
	var e: EnemyRuntime = rt.enemies[0]
	var x0 := e.logical_x
	var speed := e.move_speed  # echo_normal = 0.55 tile/s

	# 推进正好 1 秒（按固定步长累加）
	_advance(rt, 1.0)
	# 预期移动 speed × 1s（允许一个逻辑步长的误差）
	var moved := x0 - e.logical_x
	assert_almost_eq(moved, speed, speed * 0.05 + 0.02,
		"1 秒应移动约 %.3f 格，实际 %.4f" % [speed, moved])


func test_enemy_does_not_cross_core() -> void:
	var rt := _make_fixture_runtime()
	_advance(rt, 2.05)
	if rt.enemies.is_empty():
		fail_test("未生成敌人")
		return
	var e: EnemyRuntime = rt.enemies[0]
	# 推进远超所需的时间
	_advance(rt, 60.0)
	assert_true(e.logical_x >= BattleGrid.CORE_X,
		"敌人逻辑 x 不应越过核心位置（实际 %.4f）" % e.logical_x)


# ---------- 帧率无关性（本次验收硬要求）----------

func test_movement_is_frame_rate_independent() -> void:
	# 同样总时长，用两种不同的 tick 粒度驱动，最终位置应一致
	var rt_a := _make_runtime()
	var rt_b := _make_runtime()

	_advance_granular(rt_a, 10.0, 1.0 / 60.0)   # 60 FPS
	_advance_granular(rt_b, 10.0, 1.0 / 30.0)   # 30 FPS（同一固定步长内部累积）

	# 两者的 elapsed_seconds 与生成数量应一致
	assert_almost_eq(rt_a.elapsed_seconds, rt_b.elapsed_seconds,
		LOGIC_EPSILON, "不同 tick 粒度下累计逻辑时间应一致")
	assert_eq(rt_a.spawned_enemy_count(), rt_b.spawned_enemy_count(),
		"不同 tick 粒度下生成数量应一致")

	# 逐敌人比较位置
	assert_eq(rt_a.enemies.size(), rt_b.enemies.size(), "敌人总数应一致")
	for i: int in range(mini(rt_a.enemies.size(), rt_b.enemies.size())):
		assert_almost_eq(rt_a.enemies[i].logical_x, rt_b.enemies[i].logical_x,
			LOGIC_EPSILON,
			"敌人 #%d 位置应与帧率无关" % rt_a.enemies[i].instance_id)


func test_movement_is_resolution_independent() -> void:
	# 渲染分辨率只影响像素换算，不影响逻辑。这里用不同 viewport 尺寸构建网格，
	# 逻辑推进结果必须完全一致。
	var layout := DataRegistry.get_layout()
	var g1 := BattleGrid.from_layout(layout)
	var g2 := BattleGrid.from_layout(layout)
	# 仅改变"参考画布"（模拟不同分辨率下的渲染换算），逻辑参数不变
	g2.reference_canvas_width = 3840
	g2.reference_canvas_height = 2160

	var rt1 := StageRuntime.from_config(_stage_config(), _enemy_table(), g1, _char_table(), _combat())
	var rt2 := StageRuntime.from_config(_stage_config(), _enemy_table(), g2, _char_table(), _combat())
	_advance_granular(rt1, 8.0, 1.0 / 60.0)
	_advance_granular(rt2, 8.0, 1.0 / 60.0)

	assert_eq(rt1.spawned_enemy_count(), rt2.spawned_enemy_count(), "生成数量应与分辨率无关")
	assert_eq(rt1.core_hp, rt2.core_hp, "核心 HP 应与分辨率无关")
	assert_eq(rt1.enemies.size(), rt2.enemies.size(), "敌人数量应与分辨率无关")
	for i: int in range(mini(rt1.enemies.size(), rt2.enemies.size())):
		assert_almost_eq(rt1.enemies[i].logical_x, rt2.enemies[i].logical_x,
			LOGIC_EPSILON, "位置应与渲染分辨率无关")

	# 像素换算确实随画布变化（证明两者确实分离）
	var o1 := g1.centered_board_origin(1920, 1080)
	var o2 := g2.centered_board_origin(3840, 2160)
	assert_ne(o1["x"], o2["x"], "像素原点应随画布变化（逻辑/渲染确已分离）")


# ---------- 非法数据 ----------

func test_invalid_enemy_id_is_reported() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["enemySpawnTimeline"] = [{"time": 1.0, "lane": 0, "enemy": "echo_does_not_exist"}]
	var rt := StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_false(rt.is_valid(), "引用不存在的敌人应报错")
	var joined := "\n".join(rt.get_errors())
	assert_string_contains(joined, "echo_does_not_exist", "错误信息应包含非法 ID")


func test_invalid_lane_is_reported() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["enemySpawnTimeline"] = [{"time": 1.0, "lane": 7, "enemy": "echo_normal"}]
	var rt := StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_false(rt.is_valid(), "非法 lane 应报错")


func test_missing_core_hp_is_reported() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg.erase("coreHp")
	var rt := StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_false(rt.is_valid(), "缺少 coreHp 应报错")


func test_zero_or_negative_core_hp_is_reported() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["coreHp"] = 0
	var rt := StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_false(rt.is_valid(), "coreHp=0 应报错")

	var cfg2 := _stage_config().duplicate(true)
	cfg2["coreHp"] = -3
	var rt2 := StageRuntime.from_config(cfg2, _enemy_table(), _grid(), _char_table(), _combat())
	assert_false(rt2.is_valid(), "coreHp 为负应报错")


func test_missing_spawn_fields_are_reported() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["enemySpawnTimeline"] = [{"lane": 0, "enemy": "echo_normal"}]  # 缺 time
	var rt := StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_false(rt.is_valid(), "缺少 time 应报错")

	var cfg2 := _stage_config().duplicate(true)
	cfg2["enemySpawnTimeline"] = [{"time": 1.0, "enemy": "echo_normal"}]  # 缺 lane
	var rt2 := StageRuntime.from_config(cfg2, _enemy_table(), _grid(), _char_table(), _combat())
	assert_false(rt2.is_valid(), "缺少 lane 应报错")


func test_negative_spawn_time_is_reported() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["enemySpawnTimeline"] = [{"time": -1.0, "lane": 0, "enemy": "echo_normal"}]
	var rt := StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_false(rt.is_valid(), "负 time 应报错")


func test_invalid_session_setup_returns_errors() -> void:
	var cfg := _stage_config().duplicate(true)
	cfg["enemySpawnTimeline"] = [{"time": 1.0, "lane": 99, "enemy": "echo_normal"}]
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_gt(errs.size(), 0, "非法配置应使 setup 返回错误")


# ---------- 辅助 ----------

## 以固定逻辑步长推进 total 秒（模拟某一帧率下的多次 _process）
func _advance(rt: StageRuntime, total: float) -> void:
	_advance_granular(rt, total, StageRuntime.LOGIC_STEP_SECONDS)


func _advance_granular(rt: StageRuntime, total: float, tick: float) -> void:
	var t := 0.0
	while t < total - 0.0000001:
		rt.advance(tick)
		t += tick
