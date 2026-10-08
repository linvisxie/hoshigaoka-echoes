## EnemyRuntime — 单个敌人的运行时状态（V2.1.4 F 章）。
##
## 纯数据 + 纯逻辑，不依赖场景节点。渲染表现由 battle_scene 读取本对象绘制。
class_name EnemyRuntime
extends RefCounted

## 唯一实例 id（同一关卡内递增，便于测试与调试追踪）
var instance_id: int = 0
## 敌人配置 id（对应 enemies.json 的 id）
var enemy_id: String = ""
## 显示名
var display_name: String = ""
## 所属路线（出生时确定，P0.1 不允许换线）
var lane: int = BattleTypes.Lane.MIDDLE
## 逻辑 x 坐标（无量纲 tile；x 越小越靠近核心）
var logical_x: float = BattleGrid.SPAWN_X
## 移动速度（tile/s，来自 EnemyConfig.moveSpeed）
var move_speed: float = 0.0
## 抵达核心造成的核心伤害（来自 EnemyConfig.coreDamage）
var core_damage: int = 1
## 当前状态（P0.1 只经历 SPAWNING -> MOVING -> REACHED_CORE）
var state: int = BattleTypes.EnemyState.SPAWNING
## 是否已结算过漏怪伤害（幂等保护：确保只扣一次）
var core_damage_applied: bool = false


## 从 EnemyConfig 字典与出生参数构建。
static func from_config(config: Dictionary, lane: int, instance_id: int) -> EnemyRuntime:
	var e := EnemyRuntime.new()
	e.instance_id = instance_id
	e.enemy_id = str(config.get("id", ""))
	e.display_name = str(config.get("name", e.enemy_id))
	e.lane = lane
	e.move_speed = float(config.get("moveSpeed", 0.0))
	e.core_damage = int(config.get("coreDamage", 0))
	e.logical_x = BattleGrid.SPAWN_X
	e.state = BattleTypes.EnemyState.MOVING
	return e


## 是否还需要在战场上被处理（核心结算/移除之后为 false）
func is_active() -> bool:
	return state == BattleTypes.EnemyState.SPAWNING \
		or state == BattleTypes.EnemyState.MOVING \
		or state == BattleTypes.EnemyState.BLOCKED \
		or state == BattleTypes.EnemyState.ATTACKING \
		or state == BattleTypes.EnemyState.CASTING


## 是否已抵达核心（x 达到或越过核心位置）
func has_reached_core() -> bool:
	return logical_x <= BattleGrid.CORE_X + BattleGrid.CORE_REACH_EPSILON


## 以固定逻辑时间步推进位置。
## delta_seconds 必须由调用方按固定逻辑步长传入（与渲染帧率解耦）。
func advance(delta_seconds: float) -> void:
	if state != BattleTypes.EnemyState.MOVING:
		return
	logical_x -= move_speed * delta_seconds
	# 不越过核心：允许略微小于 CORE_X 以便判定，但夹住防止数值漂移
	if logical_x < BattleGrid.CORE_X:
		logical_x = BattleGrid.CORE_X


func to_debug_dict() -> Dictionary:
	return {
		"instanceId": instance_id,
		"enemyId": enemy_id,
		"lane": lane,
		"logicalX": snappedf(logical_x, 0.0001),
		"speed": move_speed,
		"coreDamage": core_damage,
		"state": BattleTypes.enemy_state_name(state),
		"damageApplied": core_damage_applied,
	}
