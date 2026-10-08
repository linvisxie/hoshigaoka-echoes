## CombatMath — 战斗数值计算（V2.1.4 D-22 / D-23）。
##
## 纯静态工具，不依赖场景与实例状态。
##
## V2.1.4 正式公式：
##   物理伤害：最终伤害 = 攻击 × 100 / (100 + 防御)
##   特殊伤害：最终伤害 = 攻击 × 100 / (100 + 防御 × 0.40)
##   物理与特殊伤害最低均为 1。
##   内部保留浮点数，最终扣除 HP 时四舍五入为整数（保证 GUT 测试可确定复现）。
##
## 保留物理/特殊两类伤害的扩展能力；P0.2 只使用 PHYSICAL。
class_name CombatMath
extends RefCounted

## 伤害类型（V2.1.4 D-22：V2.1 不新增独立魔法抗性或元素克制）
enum DamageType {
	PHYSICAL = 0,
	SPECIAL = 1,
}

## 默认参数（若数据未提供时使用；正常情况下应来自 balance.json）
const DEFAULT_PHYSICAL_DEF_FACTOR := 1.0
const DEFAULT_SPECIAL_DEF_FACTOR := 0.4
const DEFAULT_MINIMUM_DAMAGE := 1.0

## 由 balance.json 的 combat.damage 段构建的计算器
var physical_defense_factor: float = DEFAULT_PHYSICAL_DEF_FACTOR
var special_defense_factor: float = DEFAULT_SPECIAL_DEF_FACTOR
var minimum_damage: float = DEFAULT_MINIMUM_DAMAGE

var _errors: Array[String] = []


## 从 balance.json 的 combat.damage 段构建。
static func from_config(damage_config: Dictionary) -> CombatMath:
	var m := CombatMath.new()
	if damage_config.is_empty():
		m._errors.append("combat.damage 段为空，将使用代码默认值")
		return m
	if damage_config.has("physicalDefenseFactor"):
		m.physical_defense_factor = float(damage_config["physicalDefenseFactor"])
	if damage_config.has("specialDefenseFactor"):
		m.special_defense_factor = float(damage_config["specialDefenseFactor"])
	if damage_config.has("minimumDamage"):
		m.minimum_damage = float(damage_config["minimumDamage"])

	if m.physical_defense_factor < 0.0:
		m._errors.append("physicalDefenseFactor 不能为负")
	if m.special_defense_factor < 0.0:
		m._errors.append("specialDefenseFactor 不能为负")
	if m.minimum_damage < 0.0:
		m._errors.append("minimumDamage 不能为负")
	return m


func get_errors() -> Array[String]:
	return _errors


func is_valid() -> bool:
	return _errors.is_empty()


## 计算最终伤害（返回**整数**，已按规格四舍五入并应用最低伤害）。
## attack 为攻击方攻击力/治疗力口径的攻击值；defense 为受击方防御。
func compute_damage(
	attack: float,
	defense: float,
	damage_type: int = DamageType.PHYSICAL
) -> int:
	var value := compute_damage_float(attack, defense, damage_type)
	return roundi(value)


## 计算最终伤害的浮点值（供需要更高精度的场景使用）。
func compute_damage_float(
	attack: float,
	defense: float,
	damage_type: int = DamageType.PHYSICAL
) -> float:
	var atk := maxf(0.0, attack)
	var def := maxf(0.0, defense)
	var def_factor := physical_defense_factor
	if damage_type == DamageType.SPECIAL:
		def_factor = special_defense_factor

	var denominator := 100.0 + def * def_factor
	if denominator <= 0.0:
		# 理论上不会发生（def ≥ 0 时分母 ≥ 100），保守取最低伤害
		return minimum_damage

	var raw := atk * 100.0 / denominator
	return maxf(minimum_damage, raw)


## 该伤害类型是否需要计入"特殊伤害只计 40% 防御"的规则
static func is_special(damage_type: int) -> bool:
	return damage_type == DamageType.SPECIAL


## 伤害类型显示名
static func damage_type_name(damage_type: int) -> String:
	match damage_type:
		DamageType.PHYSICAL:
			return "物理"
		DamageType.SPECIAL:
			return "特殊"
		_:
			return "未知(%d)" % damage_type
