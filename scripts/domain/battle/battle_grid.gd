## BattleGrid — 3×6 战场逻辑坐标与渲染坐标换算（V2.1.4 D-3 / D-3A / LOCKED 度量规则）。
##
## 核心纪律（V2.1.4 明文）：
##   战斗逻辑始终以"格"(tile) 为无量纲单位；敌人 x 坐标、移动速度(tile/s)与横向射程均用 tile，
##   绝不直接用像素距离判定。像素仅在渲染层由 tile→px 换算得到。
##   tileSizePx / laneSpacingPx 是原型视觉可调参数，不作为技能平衡值。
##
## 纯逻辑类，不依赖场景节点。
class_name BattleGrid
extends RefCounted

## 参考画布与布局参数（从 balance.json 读取，禁止在代码里写死第二份）
var reference_canvas_width: int = 1920
var reference_canvas_height: int = 1080
var tile_size_px: float = 192.0
var lane_spacing_px: float = 192.0
var lanes: int = BattleTypes.LANE_COUNT
var columns: int = BattleTypes.COLUMN_COUNT

## 敌人逻辑 x 的取值范围：column 5 靠近敌人入口，column 0 靠近核心。
## 约定：逻辑 x 与 column 同向——x 越大越靠近敌人入口（右），x 越小越靠近核心（左）。
## 敌人在 x = SPAWN_X 生成，向 x = CORE_X 移动。
const CORE_X: float = 0.0
const SPAWN_X: float = 5.0

## 判定"已抵达核心"的阈值：x <= CORE_X（含浮点容差）
const CORE_REACH_EPSILON: float = 0.0001


## 从 DataRegistry 的 balance.json layout 段构建。
## 若数据缺失，返回带错误标记的实例（不静默使用默认值当成功）。
static func from_layout(layout: Dictionary) -> BattleGrid:
	var g := BattleGrid.new()
	var errors: Array[String] = []

	if layout.is_empty():
		errors.append("balance.json layout 段为空")
	else:
		if layout.has("tileSizePx"):
			g.tile_size_px = float(layout["tileSizePx"])
		else:
			errors.append("layout 缺少 tileSizePx")

		if layout.has("laneSpacingPx"):
			g.lane_spacing_px = float(layout["laneSpacingPx"])
		else:
			errors.append("layout 缺少 laneSpacingPx")

		if layout.has("lanes"):
			g.lanes = int(layout["lanes"])
		if layout.has("columns"):
			g.columns = int(layout["columns"])
		if layout.has("referenceCanvas"):
			var rc: Dictionary = layout["referenceCanvas"]
			g.reference_canvas_width = int(rc.get("width", g.reference_canvas_width))
			g.reference_canvas_height = int(rc.get("height", g.reference_canvas_height))

	if g.tile_size_px <= 0.0:
		errors.append("tileSizePx 必须为正数，实际 %s" % g.tile_size_px)
	if g.lane_spacing_px <= 0.0:
		errors.append("laneSpacingPx 必须为正数，实际 %s" % g.lane_spacing_px)
	if g.lanes != BattleTypes.LANE_COUNT:
		errors.append("lanes 必须为 %d，实际 %d" % [BattleTypes.LANE_COUNT, g.lanes])
	if g.columns != BattleTypes.COLUMN_COUNT:
		errors.append("columns 必须为 %d，实际 %d" % [BattleTypes.COLUMN_COUNT, g.columns])

	g._errors = errors
	return g


## 构建期的数据错误（空 = 无错）
var _errors: Array[String] = []


func get_errors() -> Array[String]:
	return _errors


func is_valid() -> bool:
	return _errors.is_empty()


## 部署格总数（V2.1.4 D-3：3×6 = 18 个标准部署格）
func cell_count() -> int:
	return lanes * columns


## 部署格中心的逻辑坐标：column 0 最靠近核心，column 5 最靠近敌人入口。
func cell_logical_x(column: int) -> float:
	return float(column)


## 判断 (column, lane) 是否为合法部署格。
func is_valid_cell(column: int, lane: int) -> bool:
	return BattleTypes.is_valid_column(column) and BattleTypes.is_valid_lane(lane)


## 枚举全部 18 个部署格，返回 [{column, lane}, ...]，按 lane 升序、column 升序。
## 顺序固定，保证测试可确定复现。
func all_cells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lane: int in range(lanes):
		for column: int in range(columns):
			out.append({"column": column, "lane": lane})
	return out


## 逻辑格坐标 -> 参考画布像素 x。
## V2.1.4 公式：xPx = boardOriginXPx + logicalX × tileSizePx
func logical_to_px_x(logical_x: float, board_origin_x: float) -> float:
	return board_origin_x + logical_x * tile_size_px


## 路线 -> 参考画布像素 y。
## V2.1.4 公式：yPx = boardOriginYPx + lane × laneSpacingPx
func lane_to_px_y(lane: int, board_origin_y: float) -> float:
	return board_origin_y + float(lane) * lane_spacing_px


## 6 格参考占宽（V2.1.4：6 格参考占宽 1152px = 192×6）
func board_reference_width_px() -> float:
	return tile_size_px * float(columns)


## 战场总高（3 条路线的参考高度）
func board_reference_height_px() -> float:
	return lane_spacing_px * float(lanes - 1 if lanes > 1 else 1)


## 在参考画布内居中计算 boardOrigin（V2.1.4：boardOrigin 根据可用战场区域居中计算）。
## 返回 {x, y}，用于渲染层；逻辑层不需要它。
##
## 注意：网格第一个格（column 0）中心即为 boardOrigin.x。
## 渲染时核心会被画在 column 0 左侧，因此调用方若要整体居中，
## 应使用 centered_board_origin_with_core() 以预留核心侧留白。
func centered_board_origin(viewport_w: float, viewport_h: float) -> Dictionary:
	var w := board_reference_width_px()
	var h := board_reference_height_px()
	return {
		"x": (viewport_w - w) * 0.5,
		"y": (viewport_h - h) * 0.5,
	}


## 连带核心侧留白一起居中的 boardOrigin。
## core_margin_px 为渲染层排在 column 0 左侧的像素宽度（纯视觉，不影响逻辑）。
func centered_board_origin_with_core(
	viewport_w: float,
	viewport_h: float,
	core_margin_px: float
) -> Dictionary:
	# 组装体总宽 = 核心留白 + (columns-1) 个格间距 + 半格两侧余量
	var grid_w := tile_size_px * float(columns - 1)
	var total_w := core_margin_px + grid_w + tile_size_px * 0.5
	var total_h := board_reference_height_px() + tile_size_px
	var left := (viewport_w - total_w) * 0.5
	var top := (viewport_h - total_h) * 0.5
	# column 0 的中心 = 组装体左缘 + 核心留白
	return {
		"x": left + core_margin_px,
		"y": top + tile_size_px * 0.5,
		"centered": true,
	}
