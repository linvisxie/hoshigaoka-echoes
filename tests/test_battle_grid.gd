## P0.1 测试：战场坐标与网格（V2.1.4 D-2 / D-3 / D-3A）
##
## 覆盖要求：
##   - 三条路线及 18 个部署格坐标正确
##   - lane/column 语义与规格一致（column 0 靠核心，column 5 靠入口）
##   - 逻辑单位与像素单位分离
extends GutTest

const GRID_SCRIPT := "res://scripts/domain/battle/battle_grid.gd"

## 与 balance.json 一致（V2.1.4 LOCKED 首轮参数）
const EXPECTED_TILE_PX := 192.0
const EXPECTED_LANE_SPACING_PX := 192.0
const EXPECTED_LANES := 3
const EXPECTED_COLUMNS := 6


func _make_grid_from_data() -> BattleGrid:
	return BattleGrid.from_layout(DataRegistry.get_layout())


func before_all() -> void:
	# 确保 DataRegistry 已加载（Autoload 在 _ready 已加载，这里兜底）
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func test_grid_reads_locked_layout_from_balance() -> void:
	var g := _make_grid_from_data()
	assert_true(g.is_valid(), "从 balance.json 构建的网格应有效：%s" % str(g.get_errors()))
	assert_eq(g.tile_size_px, EXPECTED_TILE_PX, "tileSizePx 应读自 balance.json")
	assert_eq(g.lane_spacing_px, EXPECTED_LANE_SPACING_PX, "laneSpacingPx 应读自 balance.json")
	assert_eq(g.lanes, EXPECTED_LANES, "应为 3 条路线")
	assert_eq(g.columns, EXPECTED_COLUMNS, "每路应为 6 格")


func test_grid_has_exactly_eighteen_cells() -> void:
	var g := _make_grid_from_data()
	assert_eq(g.cell_count(), 18, "3×6 共 18 个标准部署格")


func test_all_cells_enumerate_3_lanes_x_6_columns() -> void:
	var g := _make_grid_from_data()
	var cells := g.all_cells()
	assert_eq(cells.size(), 18, "应枚举出 18 个格")

	# 逐 lane / column 校验存在性
	for lane: int in range(3):
		for column: int in range(6):
			var found := false
			for c: Dictionary in cells:
				if int(c["lane"]) == lane and int(c["column"]) == column:
					found = true
					break
			assert_true(found, "应存在格 (column=%d, lane=%d)" % [column, lane])


func test_cell_logical_x_matches_column_index() -> void:
	var g := _make_grid_from_data()
	# V2.1.4 3A：column 0 最靠近核心，column 5 最靠近敌人入口
	for column: int in range(6):
		assert_eq(g.cell_logical_x(column), float(column),
			"column %d 的逻辑 x 应等于其列号" % column)
	# 单调性：column 越大越靠右（越靠敌人入口）
	assert_true(g.cell_logical_x(5) > g.cell_logical_x(0),
		"column 5 应比 column 0 更靠近敌人入口（逻辑 x 更大）")


func test_is_valid_cell_rejects_out_of_range() -> void:
	var g := _make_grid_from_data()
	assert_true(g.is_valid_cell(0, 0), "(0,0) 应合法")
	assert_true(g.is_valid_cell(5, 2), "(5,2) 应合法")
	assert_false(g.is_valid_cell(6, 0), "column 6 越界")
	assert_false(g.is_valid_cell(-1, 0), "column -1 越界")
	assert_false(g.is_valid_cell(0, 3), "lane 3 越界")
	assert_false(g.is_valid_cell(0, -1), "lane -1 越界")


func test_lane_names_match_spec() -> void:
	assert_eq(BattleTypes.lane_name(0), "上段", "lane 0 = 上段")
	assert_eq(BattleTypes.lane_name(1), "中段", "lane 1 = 中段")
	assert_eq(BattleTypes.lane_name(2), "下段", "lane 2 = 下段")


func test_core_and_spawn_x_follow_coordinate_rule() -> void:
	# 规格：column 0 靠核心、column 5 靠入口；敌人从入口生成、向核心移动
	assert_eq(BattleGrid.CORE_X, 0.0, "核心逻辑 x 应为 0")
	assert_eq(BattleGrid.SPAWN_X, 5.0, "生成逻辑 x 应为 5（= column 5）")
	assert_true(BattleGrid.SPAWN_X > BattleGrid.CORE_X, "生成点应在核心右侧")


func test_pixel_conversion_is_separate_from_logic() -> void:
	var g := _make_grid_from_data()
	var origin_x := 100.0
	var origin_y := 50.0
	# V2.1.4 公式：xPx = boardOriginXPx + logicalX × tileSizePx
	assert_eq(g.logical_to_px_x(0.0, origin_x), origin_x, "x=0 应映射到原点")
	assert_eq(g.logical_to_px_x(1.0, origin_x), origin_x + EXPECTED_TILE_PX,
		"x=1 应映射到原点 + 1 格")
	# yPx = boardOriginYPx + lane × laneSpacingPx
	assert_eq(g.lane_to_px_y(0, origin_y), origin_y, "lane 0 应为原点的 y")
	assert_eq(g.lane_to_px_y(2, origin_y), origin_y + 2.0 * EXPECTED_LANE_SPACING_PX,
		"lane 2 应偏移 2 个路间距")


func test_board_reference_width_is_1152() -> void:
	var g := _make_grid_from_data()
	assert_eq(g.board_reference_width_px(), 1152.0,
		"6 格参考占宽应为 1152px（192×6，V2.1.4 LOCKED）")


func test_invalid_layout_produces_errors_not_silent_success() -> void:
	# 空 layout
	var g1 := BattleGrid.from_layout({})
	assert_false(g1.is_valid(), "空 layout 应报错而非静默通过")
	assert_gt(g1.get_errors().size(), 0, "应记录错误原因")

	# 非法 tileSizePx
	var g2 := BattleGrid.from_layout({
		"tileSizePx": -1,
		"laneSpacingPx": 192,
		"lanes": 3,
		"columns": 6,
	})
	assert_false(g2.is_valid(), "负 tileSizePx 应报错")

	# lane 数不符
	var g3 := BattleGrid.from_layout({
		"tileSizePx": 192,
		"laneSpacingPx": 192,
		"lanes": 4,
		"columns": 6,
	})
	assert_false(g3.is_valid(), "lanes=4 应报错（规格锁定 3 条）")
