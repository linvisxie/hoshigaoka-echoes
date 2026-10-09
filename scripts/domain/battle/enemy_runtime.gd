## EnemyRuntime — 单个敌人的运行时状态（V2.1.4 F 章）。
##
## 纯数据 + 纯逻辑，不依赖场景节点。渲染表现由 battle_scene 读取本对象绘制。
##
## A0.2 扩展（敌人生态）：
##   - wave_number：波次归属字段（解决 C-8「复制体导致波次永远差 1 → 战斗卡死」）；
##   - mechanic：从 enemies.json 的 mechanic 段原样读入的机制参数（数据驱动，
##     本类**不硬编码任何数值**，只提供读取与状态位）；
##   - 机制状态位：注视冷却、时间到、沉默、复制（每个都是实例级幂等）。
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

# ============================================================
#  A0.2：波次归属（解决冲突 C-8）
# ============================================================

## 本敌人所属的 Wave 编号（1 起；0 = 未归属，退回旧的 instance_id 区间判定）。
##
## 为什么必须有这个字段：`stage_runtime.gd` 原先用 `instance_id - 1` 落在
## spawnIndex 区间来归属波次。作弊纸偶的复制体是**运行中新增的实例**、不在 spawnPlan 里，
## 其 instance_id 必然落在区间之外 → 击杀与漏怪都不计入任何波次 →
## 本波 `killed + leaked` 永远差 1 → 波次无法完成、战斗无法判定胜负（卡死）。
## 因此衍生体一律**继承生成它的本体所在的 Wave**，而不是按实例序号推断。
var wave_number: int = 0
## 是否为衍生体（由本体机制生成，例如作弊纸偶的复制体）。仅作登记与调试用。
var is_derived: bool = false
## 衍生体的本体 instance_id（0 = 本体自身）
var parent_instance_id: int = 0

# ============================================================
#  A0.2：机制参数与实例级状态位
# ============================================================

## 从 enemies.json 的 mechanic 段原样读入的机制参数。
## 本类**只读取**，不写入任何默认数值——缺字段即视为该机制未配置。
var mechanic: Dictionary = {}

## 时间到（SELF_BUFF_ON_HP_THRESHOLD）是否已触发（实例级幂等：一生只触发一次）
var time_up_triggered: bool = false
## 注视（PERIODIC_DEBUFF）的剩余冷却（秒）。初值取自 mechanic.gaze.firstTriggerAtSeconds。
var gaze_cooldown: float = 0.0
## 沉默（SILENCE_ON_FIRST_CONTACT）是否已触发（repeatable=false 时为一次性）
var silence_triggered: bool = false
## 沉默能力的剩余冷却（秒）
var silence_cooldown: float = 0.0
## 复制（SPLIT_ON_HP_THRESHOLD）是否已触发（实例级幂等，防递归第 ② 层）
var copy_triggered: bool = false

## 配置声明的移动速度基准（时间到的 +30% 以此为基准，避免重复叠乘）
var base_move_speed: float = 0.0


## 从 EnemyConfig 字典与出生参数构建。
##
## wave_number / is_derived / parent_instance_id 为 A0.2 新增的可选参数；
## 缺省（0 / false / 0）时行为与 P0.2 完全一致——既有测试与夹具仍按 3 参调用。
static func from_config(
	config: Dictionary,
	lane: int,
	instance_id: int,
	wave_number: int = 0,
	is_derived: bool = false,
	parent_instance_id: int = 0
) -> EnemyRuntime:
	var e := EnemyRuntime.new()
	e.instance_id = instance_id
	e.enemy_id = str(config.get("id", ""))
	e.display_name = str(config.get("name", e.enemy_id))
	e.lane = lane
	e.move_speed = float(config.get("moveSpeed", 0.0))
	e.base_move_speed = e.move_speed
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
	# A0.2：机制参数（数据驱动；未配置时为空字典，全部机制判定直接短路）
	e.mechanic = (config.get("mechanic", {}) as Dictionary).duplicate(true)
	e.wave_number = wave_number
	e.is_derived = is_derived
	e.parent_instance_id = parent_instance_id
	e._init_mechanic_state()
	return e


## 从本体生成一个「低生命复制体」（作弊纸偶 SPLIT_ON_HP_THRESHOLD）。
##
## 规格（v214_ordered.txt L1135，LOCKED）：「复制体拥有原敌人 35% HP，并且不能再次复制。」
## 因此：
##   ① 复制体的 hp_max = floor(本体 hp_max × copyHpRatio)，取整口径来自 mechanic.copyHpRounding；
##   ② 复制体的 mechanic.canCopy 强制为 false（防递归第 ① 层）；
##   ③ 其余战斗属性按 mechanic.copyInherits 从本体**继承实际值**（含时间到后的移速）；
##   ④ 波次归属继承本体（C-8 解决方案）。
static func make_derived_copy(
	parent: EnemyRuntime,
	instance_id: int,
	offset_tiles: float
) -> EnemyRuntime:
	var copy := EnemyRuntime.new()
	copy.instance_id = instance_id
	copy.enemy_id = parent.enemy_id
	copy.display_name = parent.display_name
	copy.lane = parent.lane
	# 继承本体**当前**的移速（若本体已触发「时间到」，复制体同步享有加速，
	# 保证与本体同速推进——设计稿 M3「与本体同速才能同时压到防线」）。
	copy.move_speed = parent.move_speed
	copy.base_move_speed = parent.base_move_speed
	copy.core_damage = parent.core_damage
	copy.logical_x = minf(BattleGrid.SPAWN_X, parent.logical_x + offset_tiles)
	copy.state = BattleTypes.EnemyState.MOVING
	copy.attack = parent.attack
	copy.defense = parent.defense
	copy.attack_interval = parent.attack_interval
	copy.damage_type = parent.damage_type
	copy.wave_number = parent.wave_number
	copy.is_derived = true
	copy.parent_instance_id = parent.instance_id

	# 机制段：整体继承后**覆写 canCopy = false**（防递归第 ① 层）。
	copy.mechanic = parent.mechanic.duplicate(true)
	copy.mechanic["canCopy"] = false

	# HP：floor(本体 hp_max × 继承比例)，比例与取整口径全部来自配置。
	var ratio := float(parent.mechanic.get("copyHpRatio", 0.0))
	copy.hp_max = int(floor(float(parent.hp_max) * ratio))
	copy.hp = copy.hp_max
	# 复制体自身不再触发任何一次性机制（其 canCopy 已为 false）
	copy._init_mechanic_state()
	return copy


## 初始化实例级机制状态位（冷却初值全部来自 mechanic 段，不写死）。
func _init_mechanic_state() -> void:
	var gaze: Dictionary = mechanic.get("gaze", {})
	if not gaze.is_empty():
		gaze_cooldown = float(gaze.get("firstTriggerAtSeconds", 0.0))
	var silence: Dictionary = mechanic.get("silence", {})
	if silence.is_empty():
		# 兼容两种写法：沉默参数既可内联在 mechanic 顶层，也可放在 mechanic.silence 子对象
		silence = mechanic if str(mechanic.get("kind", "")) == "SILENCE_ON_FIRST_CONTACT" else {}
	if not silence.is_empty():
		silence_cooldown = float(silence.get("firstTriggerAtSeconds", 0.0))


# ============================================================
#  机制查询（全部数据驱动：参数一律来自 mechanic 段）
# ============================================================

## 是否为远程攻击型（试卷飞灵 RANGED_ATTACK）
func is_ranged_attacker() -> bool:
	return str(mechanic.get("kind", "")) == "RANGED_ATTACK"


## 远程攻击距离（tile）。未配置返回 0（即不启用远程停驻）。
func ranged_range_tiles() -> float:
	return float(mechanic.get("rangeTiles", 0.0))


## 远程攻击允许的最大跨线数（0 = 仅同路线）
func ranged_max_lane_delta() -> int:
	return int(mechanic.get("maxLaneDelta", 0))


## 目标进入射程后是否停下（试卷飞灵）
func stops_when_target_in_range() -> bool:
	return bool(mechanic.get("stopWhenNearestTargetInRange", false))


## 射程内无目标时是否恢复移动
func resumes_when_no_target() -> bool:
	return bool(mechanic.get("resumeMoveWhenNoTargetInRange", false))


## 注视（PERIODIC_DEBUFF）配置；未配置返回空字典
func gaze_config() -> Dictionary:
	return mechanic.get("gaze", {})


## 时间到（SELF_BUFF_ON_HP_THRESHOLD）配置；未配置返回空字典
func time_up_config() -> Dictionary:
	return mechanic.get("timeUp", {})


## 沉默配置（兼容内联与子对象两种写法）；未配置返回空字典
func silence_config() -> Dictionary:
	if not mechanic.get("silence", {}).is_empty():
		return mechanic["silence"]
	if str(mechanic.get("kind", "")) == "SILENCE_ON_FIRST_CONTACT":
		return mechanic
	return {}


## 复制配置；未配置返回空字典
func split_config() -> Dictionary:
	if str(mechanic.get("kind", "")) == "SPLIT_ON_HP_THRESHOLD":
		return mechanic
	return mechanic.get("split", {})


## 本实例是否被允许复制（防递归第 ① 层的配置闸门）
func can_copy() -> bool:
	var cfg := split_config()
	if cfg.is_empty():
		return false
	return bool(cfg.get("canCopy", true))


# ============================================================
#  战斗行为
# ============================================================

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
		or state == BattleTypes.EnemyState.CASTING \
		or state == BattleTypes.EnemyState.RANGED_ATTACK


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
		# A0.2：波次归属与机制状态（调试/复盘用）
		"wave": wave_number,
		"derived": is_derived,
		"parentId": parent_instance_id,
		"copyTriggered": copy_triggered,
		"timeUpTriggered": time_up_triggered,
	}
