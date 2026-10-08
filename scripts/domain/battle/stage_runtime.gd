## StageRuntime — 单场战斗的关卡运行时（V2.1.4 L4：场景实例化，不进全局单例）。
##
## 职责（P0.1 范围）：
##   - 按 StageConfig.enemySpawnTimeline 在正确时间/路线生成敌人
##   - 以固定逻辑步长推进敌人移动（与渲染帧率严格解耦）
##   - 核心 HP 与"抵达核心"的漏怪结算（同一敌人只结算一次）
##
## 不含任何渲染、输入或 UI；不含攻击/阻挡/技能（属 P0.2+）。
class_name StageRuntime
extends RefCounted

## 固定逻辑步长（秒）。敌人移动只在此步长上推进，
## 因此渲染帧率、分辨率、是否掉帧都不会改变逻辑结果（V2.1.4 L11 / 本次验收要求）。
const LOGIC_STEP_SECONDS: float = 1.0 / 60.0

## 单帧最多追赶的逻辑步数，防止长时间卡顿后一次性跑完整关
const MAX_STEPS_PER_ADVANCE: int = 240

var grid: BattleGrid

var stage_id: String = ""
var core_hp_max: int = 0
var core_hp: int = 0

## 当前场上存活的敌人
var enemies: Array[EnemyRuntime] = []

## 计划中的出怪条目（来自 StageConfig，禁止写死在代码）
var _spawn_plan: Array[Dictionary] = []

## 已生成出怪条目的数量（游标）
var _spawn_cursor: int = 0

## 累计逻辑时间（秒）
var elapsed_seconds: float = 0.0

## 剩余未消耗的逻辑时间（用于固定步长累积）
var _accumulator: float = 0.0

## 下一个敌人实例 id
var _next_instance_id: int = 1

## 构建或运行期的错误（空 = 无错）
var _errors: Array[String] = []

## 核心被扣减的总次数（用于幂等断言与调试）
var core_damage_events: int = 0

## 累计抵达核心的敌人数量
var reached_core_count: int = 0


## 从 StageConfig 与敌人配置表构建 StageRuntime。
## enemy_table: { enemyId -> EnemyConfig字典 }
static func from_config(
	stage_config: Dictionary,
	enemy_table: Dictionary,
	grid: BattleGrid
) -> StageRuntime:
	var rt := StageRuntime.new()
	rt.grid = grid
	# 必须先设置敌人配置表，_validate_spawn_timeline 依赖它校验 enemy ID 引用
	rt._enemy_configs = enemy_table

	if grid == null or not grid.is_valid():
		rt._errors.append("BattleGrid 无效，无法构建 StageRuntime")

	var sid := str(stage_config.get("stageId", ""))
	if sid.is_empty():
		rt._errors.append("StageConfig 缺少 stageId")
	rt.stage_id = sid

	var core_hp_raw: Variant = stage_config.get("coreHp", null)
	if core_hp_raw == null:
		rt._errors.append("StageConfig 缺少 coreHp")
	elif int(core_hp_raw) <= 0:
		rt._errors.append("StageConfig.coreHp 必须为正整数，实际 %s" % core_hp_raw)
	else:
		rt.core_hp_max = int(core_hp_raw)
		rt.core_hp = int(core_hp_raw)

	rt._spawn_plan = rt._validate_spawn_timeline(stage_config, enemy_table)
	return rt


## 校验并规范化出怪时间线，返回按时间升序的条目数组。
## 非法条目一律记错误（不静默跳过导致"看起来正常但少了怪"）。
func _validate_spawn_timeline(
	stage_config: Dictionary,
	enemy_table: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if not stage_config.has("enemySpawnTimeline"):
		_errors.append("StageConfig 缺少 enemySpawnTimeline")
		return out

	var raw: Variant = stage_config["enemySpawnTimeline"]
	if typeof(raw) != TYPE_ARRAY:
		_errors.append("enemySpawnTimeline 必须是数组")
		return out

	var timeline: Array = raw
	for i: int in range(timeline.size()):
		var entry: Variant = timeline[i]
		if typeof(entry) != TYPE_DICTIONARY:
			_errors.append("enemySpawnTimeline[%d] 必须是对象" % i)
			continue
		var e: Dictionary = entry

		if not e.has("time"):
			_errors.append("enemySpawnTimeline[%d] 缺少 time" % i)
			continue
		var t := float(e["time"])
		if t < 0.0:
			_errors.append("enemySpawnTimeline[%d].time 不能为负（%s）" % [i, t])
			continue

		if not e.has("lane"):
			_errors.append("enemySpawnTimeline[%d] 缺少 lane" % i)
			continue
		var lane := int(e["lane"])
		if not BattleTypes.is_valid_lane(lane):
			_errors.append(
				"enemySpawnTimeline[%d].lane 非法（%d），必须为 0～%d"
				% [i, lane, BattleTypes.LANE_COUNT - 1]
			)
			continue

		if not e.has("enemy"):
			_errors.append("enemySpawnTimeline[%d] 缺少 enemy" % i)
			continue
		var enemy_id := str(e["enemy"])
		if enemy_id.is_empty():
			_errors.append("enemySpawnTimeline[%d].enemy 为空" % i)
			continue
		if not enemy_table.has(enemy_id):
			_errors.append(
				"enemySpawnTimeline[%d].enemy 引用了不存在的敌人 ID：'%s'"
				% [i, enemy_id]
			)
			continue

		out.append({"time": t, "lane": lane, "enemy": enemy_id, "index": i})

	# 按时间升序稳定排序（同时间保持原索引顺序），确保确定性
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["time"]), float(b["time"])):
			return float(a["time"]) < float(b["time"])
		return int(a["index"]) < int(b["index"])
	)
	return out


func get_errors() -> Array[String]:
	return _errors


func is_valid() -> bool:
	return _errors.is_empty()


## 计划生成的总敌人数
func planned_enemy_count() -> int:
	return _spawn_plan.size()


## 已生成敌人数
func spawned_enemy_count() -> int:
	return _spawn_cursor


## 是否所有计划敌人都已生成
func all_planned_spawned() -> bool:
	return _spawn_cursor >= _spawn_plan.size()


## 场上是否还有存活敌人
func has_living_enemies() -> bool:
	for e: EnemyRuntime in enemies:
		if e.is_active():
			return true
	return false


## 按固定逻辑步长推进战斗。
## 返回本次推进中抵达核心的敌人列表（便于上层播放反馈 / 断言）。
func advance(delta_seconds: float) -> Array[EnemyRuntime]:
	var reached: Array[EnemyRuntime] = []
	if delta_seconds <= 0.0 or not is_valid():
		return reached

	_accumulator += delta_seconds
	var steps := 0
	while _accumulator >= LOGIC_STEP_SECONDS and steps < MAX_STEPS_PER_ADVANCE:
		_accumulator -= LOGIC_STEP_SECONDS
		steps += 1
		elapsed_seconds += LOGIC_STEP_SECONDS
		_spawn_due()
		var step_reached := _advance_enemies(LOGIC_STEP_SECONDS)
		reached.append_array(step_reached)
	return reached


## 生成所有到达时间的敌人。
func _spawn_due() -> void:
	while _spawn_cursor < _spawn_plan.size():
		var entry: Dictionary = _spawn_plan[_spawn_cursor]
		if float(entry["time"]) > elapsed_seconds:
			break
		var enemy_id: String = str(entry["enemy"])
		var lane: int = int(entry["lane"])
		var cfg: Dictionary = _enemy_configs[enemy_id]
		var inst := EnemyRuntime.from_config(cfg, lane, _next_instance_id)
		_next_instance_id += 1
		enemies.append(inst)
		_spawn_cursor += 1
		GameLog.debug("StageRuntime", "生成敌人 %s（lane=%d, t=%.2fs）"
			% [enemy_id, lane, elapsed_seconds])


## 敌人配置表副本（由 from_config 填入，供生成时取用）
var _enemy_configs: Dictionary = {}


## 推进所有敌人一步，返回抵达核心者。
func _advance_enemies(step: float) -> Array[EnemyRuntime]:
	var reached: Array[EnemyRuntime] = []
	for e: EnemyRuntime in enemies:
		if not e.is_active():
			continue
		e.advance(step)
		if e.has_reached_core():
			e.state = BattleTypes.EnemyState.REACHED_CORE
			reached_core_count += 1
			reached.append(e)
	return reached


## 对指定敌人结算核心伤害（幂等：同一敌人只结算一次）。
## 返回实际扣减的核心 HP 数（已结算过则返回 0）。
func apply_core_damage(enemy: EnemyRuntime) -> int:
	if enemy == null:
		return 0
	if enemy.core_damage_applied:
		return 0
	enemy.core_damage_applied = true
	var dmg := maxi(0, enemy.core_damage)
	core_hp = maxi(0, core_hp - dmg)
	core_damage_events += 1
	GameLog.info("StageRuntime", "敌人 %s 抵达核心，核心 HP -%d -> %d"
		% [enemy.enemy_id, dmg, core_hp])
	return dmg


## 清除全部已抵达核心的敌人（结算后从场上移除）。
func remove_reached_core() -> void:
	var kept: Array[EnemyRuntime] = []
	for e: EnemyRuntime in enemies:
		if e.state != BattleTypes.EnemyState.REACHED_CORE:
			kept.append(e)
	enemies = kept


## 供测试使用的受控夹具：按 instance_id 移除一个敌人（模拟"被清除"）。
## P0.1 没有攻击系统，胜负测试必须通过本夹具触发"场上无存活敌人"，
## 而不是偷偷加入正式战斗攻击。
func despawn_for_test(instance_id: int) -> bool:
	for i: int in range(enemies.size()):
		if enemies[i].instance_id == instance_id:
			enemies[i].state = BattleTypes.EnemyState.DEAD
			enemies.remove_at(i)
			return true
	return false


## 供测试使用：清除场上全部敌人。
func despawn_all_for_test() -> int:
	var n := enemies.size()
	for e: EnemyRuntime in enemies:
		e.state = BattleTypes.EnemyState.DEAD
	enemies.clear()
	return n


func to_debug_dict() -> Dictionary:
	var list: Array[Dictionary] = []
	for e: EnemyRuntime in enemies:
		list.append(e.to_debug_dict())
	return {
		"stageId": stage_id,
		"elapsed": snappedf(elapsed_seconds, 0.001),
		"coreHp": core_hp,
		"coreHpMax": core_hp_max,
		"spawned": _spawn_cursor,
		"planned": _spawn_plan.size(),
		"living": enemies.size(),
		"reachedCore": reached_core_count,
		"enemies": list,
	}
