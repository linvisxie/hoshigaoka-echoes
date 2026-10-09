## InBattleUpgrades — 局内强化（三选一构筑）的领域层状态。
##
## 规格依据（V2.1.4 I 章，v214_ordered.txt）：
##   * L2035～2036「强化数据必须配置化」：全部数值/标签/层级/叠上限
##     **唯一来自 data/upgrades.json**，本类不写死任何效果数字。
##   * L2049～2056 候选算法原则：读队伍标签 → 排除完全无效项 →
##     按 COMMON/ADVANCED/CORE 权重抽取 → 3 选项尽量不同类别 →
##     检查重复与叠加上限。
##   * L2118「局内强化离开关卡后清空」：本类随 StageRuntime 一起创建/销毁，
##     **不落盘、不跨关保留**。
##   * L2116～2117 普通关约 2 次、Boss 关约 3 次；每场默认 1 次免费重掷。
##     开放次数由 upgrades.json 的 openByStage 承载（A0.6 只开放 1-5 教学 1 次）。
##   * L2092「禁止局内强化无限叠层导致数值爆炸」：maxStacks 由数据声明，
##     本类在 apply 时强制夹取，达到上限的条目**不再进入候选池**。
##
## 分层纪律：
##   本类是**纯逻辑 RefCounted**，不依赖场景节点、不读存档、不碰 UI。
##   它只回答两件事：「现在能选什么」「选完之后倍率是多少」。
##   倍率由 StageRuntime / CharacterRuntime 在结算处消费，
##   因此强化**不可能**绕过伤害公式或 AP 规则。
class_name InBattleUpgrades
extends RefCounted

const TAG := "InBattleUpgrades"

## 效果类型（upgrades.json 的 effect.type）
const EFFECT_STAT_MOD := "STAT_MOD"
const EFFECT_RETREAT_REFUND_BONUS := "RETREAT_REFUND_BONUS"

## 受影响的属性名（upgrades.json 的 effect.stat）
const STAT_ATTACK := "ATTACK"
const STAT_DEFENSE := "DEFENSE"
const STAT_HEAL := "HEAL"
const STAT_AP_REGEN := "AP_REGEN"
const STAT_RETREAT_REFUND := "RETREAT_REFUND"

## appliesTo 取值：作用于哪一类单位
const APPLIES_ALL := "ALL"
const APPLIES_FRONTLINE := "FRONTLINE"
const APPLIES_RANGED := "RANGED"
const APPLIES_HEALER := "HEALER"
const APPLIES_STAGE := "STAGE"

## 全部强化定义（来自数据，构造时注入；不复制数值）
var _definitions: Dictionary = {}
## 层级权重（来自数据）
var _tier_weights: Dictionary = {}
## 已选强化：upgradeId -> 已选次数（叠加计数）
var _selected: Dictionary = {}
## 每场免费重掷次数（L2117；由数据/关卡配置给定，本类只记账）
var rerolls_remaining: int = 0
## 本场可选择的总次数（L2116 普通关约 2 次、Boss 关约 3 次；由 openByStage 给定）
var total_opens: int = 0
## 已使用（成功应用）的选择次数
var selections_used: int = 0
## 已消耗的重掷次数（诊断用）
var reroll_count: int = 0
## 构建期校验错误（**必须被调用方读取**，否则就是"配置写错但游戏照跑"的静默失效）。
## 纪律：本类不自行 push_error，交由 StageRuntime / DataRegistry 决定报错级别；
## 但 load_errors 非空时调用方**不得**继续把该系统当作可用。
var load_errors: Array[String] = []


func get_errors() -> Array[String]:
	return load_errors

## 从 data/upgrades.json 构建。校验错误记入 load_errors（调用方必须读取，
## 否则就是"配置写错但游戏照跑"的静默失效）。
static func from_data(upgrade_domain: Dictionary) -> InBattleUpgrades:
	var u := InBattleUpgrades.new()
	var list: Variant = upgrade_domain.get("upgrades", [])
	if typeof(list) != TYPE_ARRAY:
		u.load_errors.append("upgrades 必须是数组")
		return u
	for item: Variant in list:
		if typeof(item) != TYPE_DICTIONARY:
			u.load_errors.append("upgrades 条目必须是对象")
			continue
		var cfg: Dictionary = item
		var id := str(cfg.get("id", ""))
		if id.is_empty():
			u.load_errors.append("upgrades 条目缺少 id")
			continue
		if u._definitions.has(id):
			u.load_errors.append("upgrades id 重复：%s" % id)
			continue
		var effect: Variant = cfg.get("effect", {})
		if typeof(effect) != TYPE_DICTIONARY:
			u.load_errors.append("强化 %s 的 effect 必须是对象" % id)
			continue
		var etype := str(effect.get("type", ""))
		if etype != EFFECT_STAT_MOD and etype != EFFECT_RETREAT_REFUND_BONUS:
			u.load_errors.append("强化 %s 的 effect.type 未知：%s" % [id, etype])
			continue
		var value := float(effect.get("value", 0.0))
		if value <= 0.0:
			u.load_errors.append("强化 %s 的 effect.value 必须为正，实际 %s" % [id, value])
			continue
		var stacks := int(cfg.get("maxStacks", 0))
		if stacks <= 0:
			u.load_errors.append("强化 %s 的 maxStacks 必须为正整数，实际 %s" % [id, stacks])
			continue
		var applies := str(cfg.get("appliesTo", ""))
		if not [APPLIES_ALL, APPLIES_FRONTLINE, APPLIES_RANGED,
				APPLIES_HEALER, APPLIES_STAGE].has(applies):
			u.load_errors.append("强化 %s 的 appliesTo 未知：%s" % [id, applies])
			continue
		u._definitions[id] = cfg.duplicate(true)
	var tiers: Variant = upgrade_domain.get("tiers", {})
	if typeof(tiers) == TYPE_DICTIONARY:
		for tier: String in tiers.keys():
			if tier.begins_with("_"):
				continue
			var tw: Variant = tiers[tier]
			if typeof(tw) == TYPE_DICTIONARY:
				u._tier_weights[tier] = float((tw as Dictionary).get("weight", 0.0))
	# 定义里出现但 tiers 未声明的层级，权重记 0 并报错（不静默兜底成等权）
	for id: String in u._definitions.keys():
		var tier := str(_tier_of(u._definitions[id]))
		if not u._tier_weights.has(tier):
			u.load_errors.append("强化 %s 的 tier '%s' 未在 tiers 中声明权重" % [id, tier])
	return u


static func _tier_of(cfg: Dictionary) -> String:
	return str(cfg.get("tier", ""))


## 已选次数
func stacks_of(upgrade_id: String) -> int:
	return int(_selected.get(upgrade_id, 0))


## 总选择次数
func total_selections() -> int:
	var n := 0
	for k: String in _selected.keys():
		n += int(_selected[k])
	return n


## 该强化是否还能再选（未达 maxStacks）
func can_select(upgrade_id: String) -> bool:
	if not _definitions.has(upgrade_id):
		return false
	return stacks_of(upgrade_id) < int(_definitions[upgrade_id].get("maxStacks", 0))


## 应用一次强化。成功返回 true；未知 id 或已达叠加上限返回 false（不静默生效）。
func apply(upgrade_id: String) -> bool:
	if not can_select(upgrade_id):
		GameLog.warn(TAG, "强化不可选：%s（未知或已达叠加上限）" % upgrade_id)
		return false
	_selected[upgrade_id] = stacks_of(upgrade_id) + 1
	GameLog.info(TAG, "局内强化生效：%s ×%d/%d" % [
		upgrade_id, int(_selected[upgrade_id]),
		int(_definitions[upgrade_id].get("maxStacks", 0))])
	return true


## 取强化定义（表现层显示用；返回副本，调用方改不动内部数据）
func definition(upgrade_id: String) -> Dictionary:
	if not _definitions.has(upgrade_id):
		return {}
	return (_definitions[upgrade_id] as Dictionary).duplicate(true)


func has_definition(upgrade_id: String) -> bool:
	return _definitions.has(upgrade_id)


func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: String in _definitions.keys():
		ids.append(k)
	ids.sort()
	return ids


# ============================================================ 倍率汇总
#
# 纪律：本组函数只**汇总已选强化**的百分数，不含任何写死的数值。
# 消费方（CharacterRuntime / StageRuntime）负责把它们乘到基础值上，
# 并沿用既有的下限夹取规则（L556 的 40% 下限只作用于减益，
# 增益上限由数据侧 maxStacks 控制，见 upgrades.json 的 _specRef）。

## 某属性 + 某 appliesTo 目标 的合计百分数。
##
## stat: STAT_ATTACK / STAT_DEFENSE / ...
## behavior: 单位行为（CharacterRuntime.Behavior）；STAGE 级强化不看此参数
func bonus_pct(stat: String, behavior: String = "") -> float:
	var total := 0.0
	for id: String in _selected.keys():
		var cfg: Dictionary = _definitions[id]
		var effect: Dictionary = cfg.get("effect", {})
		if str(effect.get("stat", "")) != stat:
			continue
		if not _matches_target(cfg, behavior):
			continue
		total += float(effect.get("value", 0.0)) * float(_selected[id])
	return total


## 强化是否作用于该行为的单位（ALL / STAGE 恒真；其余按 appliesTo 精确匹配）。
static func _matches_target(cfg: Dictionary, behavior: String) -> bool:
	var applies := str(cfg.get("appliesTo", APPLIES_ALL))
	if applies == APPLIES_ALL or applies == APPLIES_STAGE:
		return true
	if behavior.is_empty():
		# 未提供行为时只放行 ALL/STAGE，避免把职业专属强化误算给未知单位
		return false
	return applies == behavior


## 阶段级（AP 回复）增益
func ap_regen_bonus_pct() -> float:
	return bonus_pct(STAT_AP_REGEN)


## 阶段级（撤退返还比例）增益
func retreat_refund_bonus() -> float:
	var total := 0.0
	for id: String in _selected.keys():
		var cfg: Dictionary = _definitions[id]
		var effect: Dictionary = cfg.get("effect", {})
		if str(effect.get("type", "")) != EFFECT_RETREAT_REFUND_BONUS:
			continue
		if str(cfg.get("appliesTo", "")) != APPLIES_STAGE:
			continue
		total += float(effect.get("value", 0.0)) * float(_selected[id])
	return total


## 层级权重（候选抽取用）。未声明的层级返回 0，由数据校验负责暴露。
func tier_weight(tier: String) -> float:
	return float(_tier_weights.get(tier, 0.0))


# ============================================================ 倍率（消费入口）
#
# 这些方法是 StageRuntime 唯一的读取口。**没有强化时一律返回 1.0**，
# 因此接入后对既有关卡行为零影响（有回归测试保证）。

## 攻击倍率（按单位行为取职业专属强化 + 全队强化）
func attack_multiplier(behavior: String) -> float:
	return 1.0 + bonus_pct(STAT_ATTACK, behavior)


## 防御倍率
func defense_multiplier(behavior: String) -> float:
	return 1.0 + bonus_pct(STAT_DEFENSE, behavior)


## 治疗倍率
func heal_multiplier(behavior: String) -> float:
	return 1.0 + bonus_pct(STAT_HEAL, behavior)


## AP 自然回复倍率（阶段级）
func ap_regen_multiplier() -> float:
	return 1.0 + ap_regen_bonus_pct()


## 撤退返还比例（基础比例 + 阶段级加成，夹在 [0, 1]：返还不可能超过原费用）
func retreat_refund_rate(base_rate: float) -> float:
	return clampf(base_rate + retreat_refund_bonus(), 0.0, 1.0)


## 导出给表现层/调试的快照（不含任何可被篡改的内部引用）
func to_debug_dict() -> Dictionary:
	var sel := {}
	for k: String in _selected.keys():
		sel[k] = int(_selected[k])
	return {
		"selected": sel,
		"totalSelections": total_selections(),
		"rerollsRemaining": rerolls_remaining,
		"apRegenBonusPct": snappedf(ap_regen_bonus_pct(), 0.001),
		"retreatRefundBonus": snappedf(retreat_refund_bonus(), 0.001),
	}
