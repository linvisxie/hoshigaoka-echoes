## CharacterRuntime — 已部署角色的运行时状态（V2.1.4 D 章 / E 章）。
##
## 纯逻辑，不依赖场景节点。表现层只读取本对象绘制。
##
## 注意（V2.1.4 L4）：角色运行时实例存于 StageRuntime，随战斗会话创建销毁，
## **不是** 全局 Autoload。
##
## P0.3：本类额外承载「再部署冷却」计时。计时**只在 StageRuntime 的逻辑步内推进**，
## 因此与渲染帧率无关，并随暂停 / 胜负确定一起冻结。
class_name CharacterRuntime
extends RefCounted

## 实例唯一 id（同一关卡内递增）
var instance_id: int = 0
## 角色配置 id（对应 characters.json 的 id）
var character_id: String = ""
## 显示名
var display_name: String = ""
## 所在部署格
var column: int = 0
var lane: int = 0

## 战斗数值（全部来自 CharacterConfig，不在代码中复制常量）
var max_hp: int = 0
var hp: int = 0
var attack: int = 0
var defense: int = 0
var attack_interval: float = 1.0
var attack_range_tiles: float = 0.0
var block_count_max: int = 0
var damage_type: int = CombatMath.DamageType.PHYSICAL

## 攻击冷却计时（秒，递减到 0 即可攻击）
var attack_cooldown: float = 0.0

## 当前阻挡的敌人（instance_id 列表，按建立顺序）
var blocking_enemy_ids: Array[int] = []

## 是否仍在战场上（HP > 0）
var alive: bool = true

## 再部署冷却（V2.1.4 D-9 / 表 24）。
## redeploy_time 来自 CharacterConfig.redeployTime（缺省由 balance.combat.redeploy 兜底）；
## redeploy_cooldown_remaining 只在角色**离场后**由 StageRuntime 按逻辑步推进。
var redeploy_time: float = 0.0
var redeploy_cooldown_remaining: float = 0.0

## 累计造成的伤害与受到的伤害（调试与测试用）
var total_damage_dealt: int = 0
var total_damage_taken: int = 0


## 从 CharacterConfig 字典构建。
static func from_config(config: Dictionary, column: int, lane: int, instance_id: int) -> CharacterRuntime:
	var c := CharacterRuntime.new()
	c.instance_id = instance_id
	c.character_id = str(config.get("id", ""))
	c.display_name = str(config.get("name", c.character_id))
	c.column = column
	c.lane = lane

	var stats: Dictionary = config.get("baseStats", {})
	c.max_hp = int(stats.get("hp", 0))
	c.hp = c.max_hp
	c.attack = int(stats.get("attack", 0))
	c.defense = int(stats.get("defense", 0))

	c.attack_interval = float(config.get("attackInterval", 1.0))

	var range_cfg: Dictionary = config.get("attackRange", {})
	c.attack_range_tiles = float(range_cfg.get("rangeTiles", 0.0))

	c.block_count_max = int(config.get("blockCount", 0))

	var dtype := str(config.get("damageType", "PHYSICAL"))
	if dtype == "SPECIAL":
		c.damage_type = CombatMath.DamageType.SPECIAL

	# V2.1.4 D 章表 47「再部署」列
	c.redeploy_time = float(config.get("redeployTime", 0.0))

	# 首次攻击不需要等待一个完整间隔
	c.attack_cooldown = 0.0
	return c


## 当前剩余的阻挡名额
func block_slots_remaining() -> int:
	return maxi(0, block_count_max - blocking_enemy_ids.size())


## 能否再阻挡一名敌人
func can_block_more() -> bool:
	return alive and block_slots_remaining() > 0


## 记录建立阻挡关系
func add_blocking(enemy_instance_id: int) -> bool:
	if not can_block_more():
		return false
	if blocking_enemy_ids.has(enemy_instance_id):
		return false
	blocking_enemy_ids.append(enemy_instance_id)
	return true


## 解除某敌人的阻挡关系
func remove_blocking(enemy_instance_id: int) -> bool:
	var idx := blocking_enemy_ids.find(enemy_instance_id)
	if idx < 0:
		return false
	blocking_enemy_ids.remove_at(idx)
	return true


## 是否正在阻挡指定敌人
func is_blocking(enemy_instance_id: int) -> bool:
	return blocking_enemy_ids.has(enemy_instance_id)


## 受到伤害。返回实际扣减的 HP。
func take_damage(amount: int) -> int:
	if not alive or amount <= 0:
		return 0
	var applied := mini(amount, hp)
	hp -= applied
	total_damage_taken += applied
	if hp <= 0:
		hp = 0
		alive = false
		# 失去战斗能力时清空阻挡关系（敌人随后按规则恢复移动）。
		# 注意：这只清空本对象自己的列表；StageRuntime 仍以敌人侧的
		# blocked_by_character_id 反查并释放，二者互为冗余但都必须存在。
		blocking_enemy_ids.clear()
	return applied


## 是否处于失能状态
func is_incapacitated() -> bool:
	return not alive or hp <= 0


## 是否处于再部署冷却（离场后未到期）
func is_redeploy_cooling() -> bool:
	return redeploy_cooldown_remaining > 0.0


## 再部署冷却进度（1 = 刚离场，0 = 可再部署）
func redeploy_progress() -> float:
	if redeploy_time <= 0.0:
		return 0.0
	return clampf(redeploy_cooldown_remaining / redeploy_time, 0.0, 1.0)


func to_debug_dict() -> Dictionary:
	return {
		"instanceId": instance_id,
		"characterId": character_id,
		"column": column,
		"lane": lane,
		"hp": hp,
		"maxHp": max_hp,
		"attack": attack,
		"defense": defense,
		"blocking": blocking_enemy_ids.duplicate(),
		"blockSlots": block_slots_remaining(),
		"alive": alive,
		"cooldown": snappedf(attack_cooldown, 0.001),
		"redeployRemaining": snappedf(redeploy_cooldown_remaining, 0.001),
		"redeployTime": redeploy_time,
	}
