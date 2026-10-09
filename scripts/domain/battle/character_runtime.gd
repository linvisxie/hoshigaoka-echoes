## CharacterRuntime — 已部署角色的运行时状态（V2.1.4 D 章 / E 章）。
##
## 纯逻辑，不依赖场景节点。表现层只读取本对象绘制。
##
## 注意（V2.1.4 L4）：角色运行时实例存于 StageRuntime，随战斗会话创建销毁，
## **不是** 全局 Autoload。
##
## P0.3：本类额外承载「再部署冷却」计时。计时**只在 StageRuntime 的逻辑步内推进**，
## 因此与渲染帧率无关，并随暂停 / 胜负确定一起冻结。
##
## P0.4：三职业统一运行框架。本类以 **behavior（基础战斗行为）** 区分前线 / 远程 / 治疗，
## 而不是为每个角色写一套逻辑。行为只决定「由哪条结算路径处理」：
##   FRONTLINE / RANGED → 走统一的攻击结算（射程与阻挡能力全部来自数据，不来自行为本身）
##   HEALER             → 走统一的治疗结算
## 因此「远程不阻挡」并不是行为特例，而是 blockCount=0 + 较长 rangeTiles 的自然结果。
class_name CharacterRuntime
extends RefCounted

## 基础战斗行为（P0.4 三职业统一框架的分类维度）。
## 注意：这是**行为**而非职业；职业信息另存 classType。
enum Behavior {
	FRONTLINE = 0,  ## 前线：可阻挡、近战射程、承伤
	RANGED = 1,     ## 远程：不阻挡（blockCount=0）、较长射程的物理攻击
	HEALER = 2,     ## 治疗：不阻挡、自动治疗范围内受伤友军
}

const BEHAVIOR_NAMES := {
	Behavior.FRONTLINE: "FRONTLINE",
	Behavior.RANGED: "RANGED",
	Behavior.HEALER: "HEALER",
}

## 把配置里的 behavior 字符串解析为枚举；未知值返回 -1（由 StageRuntime 报错，不静默兜底）
static func parse_behavior(text: String) -> int:
	match text:
		"FRONTLINE":
			return Behavior.FRONTLINE
		"RANGED":
			return Behavior.RANGED
		"HEALER":
			return Behavior.HEALER
		_:
			return -1


static func behavior_name(value: int) -> String:
	return str(BEHAVIOR_NAMES.get(value, "UNKNOWN(%d)" % value))

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

## ---- P0.4 三职业统一框架字段 ----
## 基础战斗行为（见 Behavior 枚举）
var behavior: int = Behavior.FRONTLINE
## 配置里的行为原始字符串（便于报错与调试）
var behavior_text: String = ""
## 职业标识（仅用于显示与后续成长系统，不参与战斗判定）
var class_type: String = ""
## 治疗力（仅 HEALER 使用，来自 healPower；非治疗角色为 0）
var heal_power: int = 0
## 治疗间隔（秒，仅 HEALER 使用）
var heal_interval: float = 1.5
## 治疗范围是否使用曼哈顿距离（来自 attackRange.shape == "manhattan"）
var heal_uses_manhattan: bool = false
## 允许的最大跨线数（来自 attackRange.maxLaneDelta，0 = 不可跨线）
var max_lane_delta: int = 0
## 是否显式声明允许跨线攻击（来自 attackRange.allowCrossLane）。
##
## 裁决 DEC-C-0003 要求：跨线能力必须由角色数据**显式声明**，
## 禁止仅凭 behavior == RANGED 就让所有远程单位无条件获得同样的跨线范围。
## 因此本字段默认 false，只有数据显式写 true 才生效（max_lane_delta 仍须 > 0）。
var allow_cross_lane: bool = false
## 相邻路线的前方射程（tile，来自 attackRange.adjacentLaneRangeTiles）。
## 仅在本路线之外、且跨线数 ≤ max_lane_delta 时使用；未配置时回落到本路线射程。
var adjacent_lane_range_tiles: float = 0.0
## 单次普通攻击的目标数量上限（来自 attackRange.targetLimit，缺省 1）。
## DEC-C-0003 明文：每次普通攻击仍只选择一个目标，跨线不增加攻击次数。
var target_limit: int = 1
## 累计造成的治疗量（调试与测试用）
var total_healing_done: int = 0
## 最近一次成功治疗的逻辑时刻（-1 = 从未治疗；用于表现层反馈）
var last_heal_at: float = -1.0

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

# ============================================================
#  A0.2：通用状态效果容器（V2.1.4 L556～557 Debuff 结算规则）
# ============================================================

## balance.json 的 combat.debuffFloor 缺失时的兜底下限（与 L556 的规格值一致，
## 不是可调平衡参数；正常路径一律由 StageRuntime 注入配置值）。
const DEFAULT_DEBUFF_FLOOR := 0.4

## balance.json 的 combat.buffCeiling 缺失时的兜底上限（表 81 的 +80% ⇒ 1.8）。
## 与下限不同，这是「首版建议软上限」（L2113 明标测试基线），因此可配置。
const DEFAULT_BUFF_CEILING := 1.8

## 挂在本角色身上的状态效果（按施加顺序）。同一 effectId 只允许存在一条（L556）。
var status_effects: Array[StatusEffect] = []

## 减益下限（相对基础值的比例），来自 balance.json 的 combat.debuffFloor。
##
## 规格（LOCKED，L556～557）：「有效攻击力、有效攻击频率、有效技能冷却恢复速度均不得
## 低于各自基础值的 40%（首轮可配置下限）。上述减益下限首章统一存于 balance.json」。
## 因此**权威值来自 balance.json**，代码内不复制第二份。
var debuff_floor_pct: float = DEFAULT_DEBUFF_FLOOR

## 增益上限（相对基础值的比例），来自 balance.json 的 combat.buffCeiling。
##
## 规格依据：表 81（L2105～2113）「攻击速度加成｜局内总增益原则上不超过 +80%」，
## 且 L2113 明标「以上均为测试基线，不是最终数值」——故上限**可配置、非 LOCKED**。
## 默认 1.8 = 基础 1.0 + 80%。当前构建无增益来源，该上限不可达（属 A0.6）。
var buff_ceiling_pct: float = DEFAULT_BUFF_CEILING


## 从 CharacterConfig 字典构建。
##
## stats_override（可选，P1.0/Alpha A0.1 新增）：
##   由成长系统算出的面板（CharacterProgress.compute_stats()）。
##   传入时覆盖 baseStats 的 hp/attack/defense/healPower，
##   使「等级 → 战斗面板」生效，而**不需要**在数据文件里复制第二份面板。
##   攻击范围 / 阻挡数 / 部署费用**不随等级变化**（V2.1.4 H 章三明文），
##   因此本函数只覆盖这四项，其余一律仍读配置。
static func from_config(
	config: Dictionary,
	column: int,
	lane: int,
	instance_id: int,
	stats_override: Dictionary = {}
) -> CharacterRuntime:
	var c := CharacterRuntime.new()
	c.instance_id = instance_id
	c.character_id = str(config.get("id", ""))
	c.display_name = str(config.get("name", c.character_id))
	c.column = column
	c.lane = lane

	var stats: Dictionary = config.get("baseStats", {})
	c.max_hp = int(stats.get("hp", 0))
	c.attack = int(stats.get("attack", 0))
	c.defense = int(stats.get("defense", 0))
	# 成长面板覆盖（只在提供时生效；未提供时行为与 P0.4 完全一致）
	if not stats_override.is_empty():
		c.max_hp = int(stats_override.get("hp", c.max_hp))
		c.attack = int(stats_override.get("attack", c.attack))
		c.defense = int(stats_override.get("defense", c.defense))
	c.hp = c.max_hp

	c.attack_interval = float(config.get("attackInterval", 1.0))

	var range_cfg: Dictionary = config.get("attackRange", {})
	c.attack_range_tiles = float(range_cfg.get("rangeTiles", 0.0))

	c.block_count_max = int(config.get("blockCount", 0))

	# ---- P0.4：行为分类与治疗参数（全部来自数据，不按职业名猜）----
	c.behavior_text = str(config.get("behavior", "FRONTLINE"))
	var parsed := parse_behavior(c.behavior_text)
	# 解析失败时保持默认 FRONTLINE，但把原文保留；StageRuntime 会在构建期报错，
	# 因此这里不做静默兜底以外的额外处理。
	if parsed >= 0:
		c.behavior = parsed
	c.class_type = str(config.get("classType", ""))
	c.heal_power = int(config.get("healPower", 0))
	if not stats_override.is_empty() and stats_override.has("healPower"):
		c.heal_power = int(stats_override["healPower"])
	if config.has("healInterval"):
		c.heal_interval = float(config["healInterval"])
	else:
		c.heal_interval = c.attack_interval
	c.heal_uses_manhattan = str(range_cfg.get("shape", "")) == "manhattan"
	c.max_lane_delta = int(range_cfg.get("maxLaneDelta", 0))
	# ---- 裁决 DEC-C-0003：跨线攻击能力（必须显式声明，不按 behavior 推导）----
	c.allow_cross_lane = bool(range_cfg.get("allowCrossLane", false))
	c.adjacent_lane_range_tiles = float(
		range_cfg.get("adjacentLaneRangeTiles", c.attack_range_tiles))
	c.target_limit = maxi(1, int(range_cfg.get("targetLimit", 1)))

	var dtype := str(config.get("damageType", "PHYSICAL"))
	if dtype == "SPECIAL":
		c.damage_type = CombatMath.DamageType.SPECIAL

	# V2.1.4 D 章表 47「再部署」列
	c.redeploy_time = float(config.get("redeployTime", 0.0))

	# 首次攻击不需要等待一个完整间隔
	c.attack_cooldown = 0.0
	return c


## 是否为治疗型（走治疗结算路径）
func is_healer() -> bool:
	return behavior == Behavior.HEALER


## 是否为输出型（走攻击结算路径：前线与远程共用同一条路径）
func is_attacker() -> bool:
	return behavior == Behavior.FRONTLINE or behavior == Behavior.RANGED


## 该角色当前能否建立阻挡（治疗与远程因 blockCount=0 天然不能）
func can_block_at_all() -> bool:
	return block_count_max > 0


## 治疗量：V2.1.4 治疗公式「实际治疗 = 治疗力 × 技能倍率」。
## P0.4 只做基础治疗，无技能倍率，故倍率固定 1.0（不引入任何隐藏加成）。
func compute_heal_amount(multiplier: float = 1.0) -> int:
	if heal_power <= 0 or multiplier <= 0.0:
		return 0
	return int(round(float(heal_power) * multiplier))


## 接受治疗。返回实际回复的 HP（不超过最大 HP，规格「治疗不能超过目标最大生命值」）。
func receive_healing(amount: int) -> int:
	if amount <= 0 or is_incapacitated():
		return 0
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before


## 当前生命百分比（0.0 ~ 1.0）；用于治疗目标优先级「当前生命百分比最低」
func hp_ratio() -> float:
	if max_hp <= 0:
		return 0.0
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)


## 是否处于「受伤但仍在场」状态（治疗只针对这类目标）
func is_wounded() -> bool:
	return not is_incapacitated() and hp < max_hp


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


# ============================================================
#  裁决 DEC-C-0003：跨路线攻击的射程查询
# ============================================================

## 本角色对目标路线是否具备跨线攻击资格（与射程无关的**路线闸门**）。
##
## 判定链（缺一不可）：
##   ① 数据显式声明 allowCrossLane = true（禁止按 behavior 推导）；
##   ② 目标路线 != 本路线（同路线走原有路径）；
##   ③ |lane_delta| ≤ max_lane_delta（相邻 1 条，绝不允许上路直接打下路）。
func can_attack_lane(target_lane: int) -> bool:
	var delta := absi(target_lane - lane)
	if delta == 0:
		return true
	if not allow_cross_lane:
		return false
	return delta <= max_lane_delta


## 对指定路线生效的前方射程（tile）。
## 本路线用 rangeTiles；相邻路线用 adjacentLaneRangeTiles（未配置时回落本路线射程）。
## 不具备跨线资格的路线返回 0.0（表示不可攻击该路线）。
func attack_range_for_lane(target_lane: int) -> float:
	var delta := absi(target_lane - lane)
	if delta == 0:
		return attack_range_tiles
	if not can_attack_lane(target_lane):
		return 0.0
	if adjacent_lane_range_tiles > 0.0:
		return adjacent_lane_range_tiles
	return attack_range_tiles


## 目标点（路线 + 逻辑 x）是否落在本角色的攻击范围内。
##
## 射程判定（与敌人侧相反方向，角色只打**前方**）：
##   0 ≤ (target_x − column) ≤ 该路线的有效射程。
## 纪律：距离一律以**逻辑格**计算，绝不用屏幕像素（V2.1.4 LOCKED 度量规则）。
func is_target_in_attack_range(target_lane: int, target_x: float) -> bool:
	var eff_range := attack_range_for_lane(target_lane)
	if eff_range <= 0.0:
		return false
	var delta_x := target_x - float(column)
	if delta_x < -0.0001:
		return false
	return delta_x <= eff_range + 0.0001


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


# ============================================================
#  A0.2：状态效果施加 / 推进 / 查询（V2.1.4 L556～557）
# ============================================================

## 施加一个状态效果。参数全部由调用方从配置读出（数据驱动，本类不含任何数值常量）。
##
## 叠加裁决（LOCKED，L556「同一 effectId 的减益不可无限叠层，重复施加默认只刷新
## 持续时间」）：
##   - 已存在同 effectId 且 stackPolicy = REFRESH_DURATION → 只刷新 expiresAt，不新增条目；
##   - 已存在同 effectId 且 stackPolicy = IGNORE → 忽略本次施加。
## 不同 effectId 一律**并存**（L556「不同 effectId 的攻击、攻击速度…减益先相加」）。
func apply_status_effect(effect: StatusEffect, now: float) -> bool:
	if effect == null or effect.effect_id.is_empty():
		return false
	for existing: StatusEffect in status_effects:
		if existing.effect_id != effect.effect_id:
			continue
		if existing.stack_policy == StatusEffect.StackPolicy.IGNORE:
			return false
		existing.refresh(now)
		return false
	status_effects.append(effect)
	return true


## 便捷入口：直接按配置字典施加（字段名与 enemies.json 的 mechanic 段一致）。
func apply_status_effect_from_config(cfg: Dictionary, now: float) -> bool:
	var effect := StatusEffect.from_config(cfg, now)
	# sourceId 允许由调用方单独提供（配置里的来源就是敌人自身）
	if effect.source_id.is_empty():
		effect.source_id = str(cfg.get("sourceId", ""))
	return apply_status_effect(effect, now)


## 按逻辑步推进状态效果：到期者移除。
## 返回本次移除的效果 ID 列表（供表现层播放「状态结束」反馈）。
func tick_status_effects(now: float) -> Array[String]:
	var expired: Array[String] = []
	var kept: Array[StatusEffect] = []
	for e: StatusEffect in status_effects:
		if e.is_expired(now):
			expired.append(e.effect_id)
		else:
			kept.append(e)
	status_effects = kept
	return expired


## 查询某 effectId 当前是否生效
func has_status_effect(effect_id: String) -> bool:
	for e: StatusEffect in status_effects:
		if e.effect_id == effect_id:
			return true
	return false


## 取某 effectId 的效果（不存在返回 null）
func get_status_effect(effect_id: String) -> StatusEffect:
	for e: StatusEffect in status_effects:
		if e.effect_id == effect_id:
			return e
	return null


## 清空全部状态效果（角色离场/再部署时使用：新实例不继承旧减益）
func clear_status_effects() -> void:
	status_effects.clear()


## 某一属性分类的百分数求和（减益为负、增益为正）。
## 控制类（SILENCE）**不参与**求和——L557 明文「控制类沉默仅禁止主动技能，
## 不改变普通攻击频率」，故其 pct 恒为 0 且被本函数跳过。
func sum_effect_pct(category: String) -> float:
	var total := 0.0
	for e: StatusEffect in status_effects:
		if e.is_control():
			continue
		if e.category == category:
			total += e.pct
	return total


## 有效攻击频率系数：clamp(1 + Σ攻速百分数, debuffFloor, buffCeiling)。
##
## 换算口径已由**产品裁决 DEC-C-0004（2026-10-09）正式裁决**：
##   攻速百分数先在**攻击频率**口径下依 L556 叠加（不同 effectId 先相加、
##   与增益统一结算），应用已锁定的上下限，再换算为间隔：
##     f_eff      = f_base × clamp(1 + Σ, floor, ceiling)
##     interval_eff = interval_base / clamp(1 + Σ, floor, ceiling)
##
## 规格依据（L556，LOCKED）明文把下限作用于「**有效攻击频率**」：
##   「有效攻击力、有效攻击频率、有效技能冷却恢复速度均不得低于各自基础值的 40%」
## 因此 40% 夹取的是**频率系数**本身，而不是间隔。这一读法与规格自洽；
## 「间隔直接 × (1+|Σ|)」的读法会使增益侧（+X% ⇒ ×(1+X)）与减益侧不对称，
## 破坏 L556「减益与增益统一结算」，故已排除（原设计稿冲突 C-3 至此关闭）。
##
## 上限（表 81「首版建议软上限」攻击速度 +80% ⇒ 系数 1.8）来自 balance.json 的
## combat.buffCeiling；规格 L2113 明标该表为「测试基线，不是最终数值」，
## 因此上限同样可配置、非 LOCKED。
func attack_speed_factor() -> float:
	var raw := 1.0 + sum_effect_pct(StatusEffect.CATEGORY_ATTACK_SPEED)
	return clampf(raw, debuff_floor_pct, buff_ceiling_pct)


## 有效攻击间隔（秒）。
##
## 裁决 DEC-C-0004 的正式口径：**频率倒数**。
##   interval_eff = interval_base / clamp(1 + Σ攻速百分数, floor, ceiling)
## 例：-25% ⇒ clamp(0.75) ⇒ interval × 1.3333；+80% ⇒ clamp(1.8) ⇒ interval ÷ 1.8。
## 无任何攻速效果时恒等于 attack_interval（既有行为完全不变）。
func effective_attack_interval() -> float:
	var factor := attack_speed_factor()
	if factor <= 0.0:
		# 防御性兜底：下限已由配置保证为正，此处只为避免除零
		return attack_interval
	return attack_interval / factor


## 有效攻击力：clamp(1 + Σ攻击百分数, debuffFloor, +∞) × 基础攻击，取整。
## 40% 下限作用于「有效攻击力」本身（L556），故此处先夹取系数再乘基础值。
func effective_attack() -> int:
	var factor := maxf(debuff_floor_pct, 1.0 + sum_effect_pct(StatusEffect.CATEGORY_ATTACK))
	return int(round(float(attack) * factor))


## 有效技能冷却恢复速度系数：clamp(1 + ΣCD 百分数, debuffFloor, +∞)。
## 当前构建尚无技能系统，本接口为 A0.6 技能系统接入预留（与 L556 的属性清单一一对应）。
func effective_cd_recovery_factor() -> float:
	return maxf(debuff_floor_pct, 1.0 + sum_effect_pct(StatusEffect.CATEGORY_CD_RECOVERY))


## 当前能否主动释放技能（V2.1.4 L557：控制类沉默仅禁止主动技能）。
##
## 现状核实（设计稿 §2.2.5 M4）：`data/skills.json` 为 `{"skills": []}`、
## 三角色 `skillIds` 全为 `[]`、全工程无技能系统实现，因此本方法在无沉默时恒为 true，
## **不代表技能系统已可用**。它存在的意义是让「沉默」这一状态可被独立测试与验收，
## 技能系统接入后无需改动任何调用点。
func can_cast_active_skill() -> bool:
	for e: StatusEffect in status_effects:
		if e.is_control():
			return false
	return true


## 是否处于再部署冷却（离场后未到期）
func is_redeploy_cooling() -> bool:
	return redeploy_cooldown_remaining > 0.0

## 再部署冷却进度（1 = 刚离场，0 = 可再部署）
func redeploy_progress() -> float:
	if redeploy_time <= 0.0:
		return 0.0
	return clampf(redeploy_cooldown_remaining / redeploy_time, 0.0, 1.0)


func to_debug_dict() -> Dictionary:
	var effects: Array[Dictionary] = []
	for e: StatusEffect in status_effects:
		effects.append(e.to_debug_dict())
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
		"behavior": behavior_name(behavior),
		"classType": class_type,
		"healPower": heal_power,
		"healingDone": total_healing_done,
		"hpRatio": snappedf(hp_ratio(), 0.001),
		# A0.2：状态效果与攻速换算（调试/复盘用）
		"statusEffects": effects,
		"effectiveAttackInterval": snappedf(effective_attack_interval(), 0.0001),
		"attackSpeedFactor": snappedf(attack_speed_factor(), 0.0001),
		"buffCeilingPct": buff_ceiling_pct,
		"canCastActiveSkill": can_cast_active_skill(),
	}
