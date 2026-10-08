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
## 生命值（P0.2 引入，来自 EnemyConfig.hp）
var hp: int = 0
var hp_max: int = 0
## 抵达核心造成的核心伤害（来自 EnemyConfig.coreDamage）
var core_damage: int = 1
## 当前状态（P0.1 只经历 SPAWNING -> MOVING -> REACHED_CORE）
var state: int = BattleTypes.EnemyState.SPAWNING
## 是否已结算过漏怪伤害（幂等保护：确保只扣一次）
var core_damage_applied: bool = false

## 当前阻挡自己的角色 instance_id（0 = 未被阻挡，P0.2 引入）
var blocked_by_character_id: int = 0

## 攻击冷却计时（秒；P0.2 引入）
var attack_cooldown: float = 0.0

## 攻击力 / 防御（P0.2 引入，来自 EnemyConfig）
var attack: int = 0
var defense: int = 0
var attack_interval: float = 1.0
var damage_type: int = CombatMath.DamageType.PHYSICAL

## 累计受到/造成的伤害（调试与测试用）
var total_damage_taken: int = 0
var total_damage_dealt: int = 0


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
	# P0.2：战斗数值
	e.hp_max = int(config.get("hp", 0))
	e.hp = e.hp_max
	e.attack = int(config.get("attack", 0))
	e.defense = int(config.get("defense", 0))
	e.attack_interval = float(config.get("attackInterval", 1.0))
	var dtype := str(config.get("damageType", "PHYSICAL"))
	if dtype == "SPECIAL":
		e.damage_type = CombatMath.DamageType.SPECIAL
	return e


## 受到伤害。返回实际扣减的 HP。
## 注意：本方法**只扣 HP，不改变 state**。死亡状态由 StageRuntime._cleanup_dead()
## 统一设置并计数，避免"先被标记死亡导致清理阶段判定失效、击杀数不增加"。
func take_damage(amount: int) -> int:
	if amount <= 0 or hp <= 0:
		return 0
	var applied := mini(amount, hp)
	hp -= applied
	total_damage_taken += applied
	return applied


## HP 是否已耗尽（死亡判定的唯一依据）
func is_dead() -> bool:
	return hp <= 0


## 是否还需要在战场上被处理（核心结算/移除之后为 false）。
## HP 耗尽即视为不活跃——即使 state 尚未更新为 DEAD（状态由 StageRuntime
## 的清理阶段统一设置），这样可避免"已死敌人仍占用阻挡名额/被选为攻击目标"。
func is_active() -> bool:
	if hp <= 0:
		return false
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
		"hp": hp,
		"hpMax": hp_max,
		"attack": attack,
		"coreDamage": core_damage,
		"state": BattleTypes.enemy_state_name(state),
		"damageApplied": core_damage_applied,
		"blockedBy": blocked_by_character_id,
	}
