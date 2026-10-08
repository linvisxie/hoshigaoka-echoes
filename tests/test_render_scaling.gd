## P0.1 测试：渲染缩放与逻辑分离（V2.1.4 度量 LOCKED 规则）
##
## 覆盖要求：
##   - 不同渲染分辨率不改变逻辑移动速度、到达顺序或胜负判定
##   - tileSizePx / laneSpacingPx 只是原型视觉参数，不作为平衡值
##   - 逻辑换算与像素换算严格分离
extends GutTest

const LOGIC_EPSILON := 0.0001


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func _layout() -> Dictionary:
	return DataRegistry.get_layout()


func _stage_config() -> Dictionary:
	return DataRegistry.get_entry("stages", "1-1")


func _enemy_table() -> Dictionary:
	var t := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


# ---------- 参考画布换算公式 ----------

func test_logical_to_pixel_uses_locked_formula() -> void:
	var g := BattleGrid.from_layout(_layout())
	# V2.1.4 公式：xPx = boardOriginXPx + logicalX × tileSizePx
	var origin := 300.0
	assert_eq(g.logical_to_px_x(0.0, origin), 300.0, "x=0 → 原点")
	assert_eq(g.logical_to_px_x(2.0, origin), 300.0 + 2.0 * 192.0, "x=2 → 原点+2格")
	assert_eq(g.logical_to_px_x(5.0, origin), 300.0 + 5.0 * 192.0, "x=5 → 原点+5格")

	# V2.1.4 公式：yPx = boardOriginYPx + lane × laneSpacingPx
	var origin_y := 120.0
	assert_eq(g.lane_to_px_y(0, origin_y), 120.0, "lane 0 → 原点")
	assert_eq(g.lane_to_px_y(1, origin_y), 120.0 + 192.0, "lane 1 → 原点+1路间距")
	assert_eq(g.lane_to_px_y(2, origin_y), 120.0 + 2.0 * 192.0, "lane 2 → 原点+2路间距")


func test_tile_and_lane_spacing_are_independent_visual_params() -> void:
	# 把 tileSizePx 改成别的值，逻辑坐标换算（格）不受影响，
	# 只有像素映射变化 —— 证明视觉参数不参与平衡。
	var base := BattleGrid.from_layout(_layout())
	var scaled := BattleGrid.from_layout({
		"tileSizePx": 96,
		"laneSpacingPx": 96,
		"lanes": 3,
		"columns": 6,
		"referenceCanvas": {"width": 1920, "height": 1080},
	})

	# 逻辑层面完全一致
	assert_eq(base.cell_count(), scaled.cell_count(), "部署格数不受视觉参数影响")
	assert_eq(base.cell_logical_x(3), scaled.cell_logical_x(3), "逻辑 x 不受视觉参数影响")
	assert_eq(base.all_cells(), scaled.all_cells(), "18 格坐标不受视觉参数影响")

	# 渲染层面确实不同
	assert_ne(
		base.logical_to_px_x(1.0, 0.0),
		scaled.logical_to_px_x(1.0, 0.0),
		"像素换算应随视觉参数变化"
	)


func test_board_reference_width_scales_with_tile_size() -> void:
	var g192 := BattleGrid.from_layout(_layout())
	assert_eq(g192.board_reference_width_px(), 1152.0, "192×6 = 1152")

	var g96 := BattleGrid.from_layout({
		"tileSizePx": 96, "laneSpacingPx": 96, "lanes": 3, "columns": 6,
	})
	assert_eq(g96.board_reference_width_px(), 576.0, "96×6 = 576")


func test_centered_origin_differs_across_viewports() -> void:
	var g := BattleGrid.from_layout(_layout())
	var o720 := g.centered_board_origin(1280, 720)
	var o1080 := g.centered_board_origin(1920, 1080)
	var o4k := g.centered_board_origin(3840, 2160)

	# 画布越大，居中偏移越大（证明像素原点随分辨率变化）
	assert_gt(float(o1080["x"]), float(o720["x"]), "1080p 的原点 x 应大于 720p")
	assert_gt(float(o4k["x"]), float(o1080["x"]), "4K 的原点 x 应大于 1080p")


func test_centered_origin_with_core_reserves_left_margin() -> void:
	var g := BattleGrid.from_layout(_layout())
	var margin := g.tile_size_px * 1.15
	var with_core := g.centered_board_origin_with_core(1920, 1080, margin)
	# column 0 的中心应在核心留白右侧
	assert_gt(float(with_core["x"]), margin, "column 0 应排在核心留白右侧")
	assert_true(bool(with_core.get("centered", false)), "应标记为已居中")


# ---------- 分辨率不改变逻辑（核心验收要求）----------

func test_resolution_does_not_change_logic_outcome() -> void:
	var results := []
	# 用三种不同渲染分辨率构建网格，逻辑推进必须完全一致
	for size: Array in [[1280, 720], [1920, 1080], [3840, 2160]]:
		var g := BattleGrid.from_layout(_layout())
		g.reference_canvas_width = int(size[0])
		g.reference_canvas_height = int(size[1])
		# 仅计算渲染原点（模拟不同分辨率下的渲染布局），不影响逻辑
		var _origin := g.centered_board_origin(size[0], size[1])

		var rt := StageRuntime.from_config(_stage_config(), _enemy_table(), g)
		# 统一用固定逻辑步长推进相同总时长
		var t := 0.0
		while t < 60.0 - LOGIC_EPSILON:
			rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
			t += StageRuntime.LOGIC_STEP_SECONDS

		results.append({
			"hp": rt.core_hp,
			"spawned": rt.spawned_enemy_count(),
			"reached": rt.reached_core_count,
			"events": rt.core_damage_events,
			"elapsed": snappedf(rt.elapsed_seconds, 0.0001),
		})

	assert_eq(results[0], results[1], "720p 与 1080p 的逻辑结果必须一致")
	assert_eq(results[1], results[2], "1080p 与 4K 的逻辑结果必须一致")


func test_resolution_does_not_change_enemy_arrival_order() -> void:
	var orders := []
	for width: int in [1280, 3840]:
		var g := BattleGrid.from_layout(_layout())
		g.reference_canvas_width = width
		var rt := StageRuntime.from_config(_stage_config(), _enemy_table(), g)

		# 记录敌人抵达核心的先后顺序（按 instance_id）
		var order: Array[int] = []
		var t := 0.0
		while t < 80.0 - LOGIC_EPSILON:
			var reached := rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
			for e: EnemyRuntime in reached:
				order.append(e.instance_id)
			t += StageRuntime.LOGIC_STEP_SECONDS
		orders.append(order)

	assert_eq(orders[0], orders[1], "不同渲染分辨率下敌人到达顺序必须一致")


func test_lane_order_preserved_across_resolutions() -> void:
	# 同一时间生成的多个敌人，跨分辨率应保持相同的相对位置关系
	var positions := []
	for width: int in [1280, 3840]:
		var g := BattleGrid.from_layout(_layout())
		g.reference_canvas_width = width
		var rt := StageRuntime.from_config(_stage_config(), _enemy_table(), g)
		var t := 0.0
		while t < 20.0 - LOGIC_EPSILON:
			rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
			t += StageRuntime.LOGIC_STEP_SECONDS

		var snap := []
		for e: EnemyRuntime in rt.enemies:
			snap.append([e.instance_id, e.lane, snappedf(e.logical_x, 0.0001)])
		positions.append(snap)

	assert_eq(positions[0], positions[1], "跨分辨率的敌人位置快照必须一致")
