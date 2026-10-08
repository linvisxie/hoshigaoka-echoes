## 战斗领域公共类型与枚举（V2.1.4 D 章 / 3A 战场坐标硬规则）。
##
## 纯逻辑类型，不依赖任何 Control / 场景节点（L3 分层要求）。
class_name BattleTypes
extends RefCounted

## 路线（V2.1.4 D-3A：lane 0 = 上段，lane 1 = 中段，lane 2 = 下段）
enum Lane {
	UPPER = 0,
	MIDDLE = 1,
	LOWER = 2,
}

## 战斗总体结果（V2.1.4 D-40 胜利条件 / D-41 失败条件）
enum Outcome {
	RUNNING = 0,
	VICTORY = 1,
	DEFEAT = 2,
}

## 敌人状态机的 P0.1 子集（V2.1.4 F-四十五）
## P0.1 只实现 SPAWNING / MOVING / REACHED_CORE；BLOCKED / ATTACKING / CASTING / DEAD
## 属 P0.2（阻挡与攻击）范围，此处仅保留枚举值以免后续改结构。
enum EnemyState {
	SPAWNING = 0,
	MOVING = 1,
	BLOCKED = 2,
	ATTACKING = 3,
	CASTING = 4,
	DEAD = 5,
	REACHED_CORE = 6,
}

const LANE_COUNT := 3
const COLUMN_COUNT := 6

## 路线枚举 -> 显示名（上段/中段/下段）
static func lane_name(lane: int) -> String:
	match lane:
		Lane.UPPER:
			return "上段"
		Lane.MIDDLE:
			return "中段"
		Lane.LOWER:
			return "下段"
		_:
			return "未知路线(%d)" % lane


## lane 是否合法
static func is_valid_lane(lane: int) -> bool:
	return lane >= 0 and lane < LANE_COUNT


## column 是否合法
static func is_valid_column(column: int) -> bool:
	return column >= 0 and column < COLUMN_COUNT


## 结果枚举 -> 显示名
static func outcome_name(outcome: int) -> String:
	match outcome:
		Outcome.RUNNING:
			return "进行中"
		Outcome.VICTORY:
			return "胜利"
		Outcome.DEFEAT:
			return "失败"
		_:
			return "未知(%d)" % outcome


## 敌人状态 -> 显示名
static func enemy_state_name(state: int) -> String:
	match state:
		EnemyState.SPAWNING:
			return "SPAWNING"
		EnemyState.MOVING:
			return "MOVING"
		EnemyState.BLOCKED:
			return "BLOCKED"
		EnemyState.ATTACKING:
			return "ATTACKING"
		EnemyState.CASTING:
			return "CASTING"
		EnemyState.DEAD:
			return "DEAD"
		EnemyState.REACHED_CORE:
			return "REACHED_CORE"
		_:
			return "UNKNOWN"
