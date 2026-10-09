## CharacterProgress — 单个角色的**持久成长状态**（V2.1.4 H 章）。
##
## 职责边界（L3 分层）：
##   本类是**纯数据 + 纯逻辑**，不依赖场景节点、不读写文件、不碰 DataRegistry。
##   它只回答两个问题：
##     ① 给定等级 / 突破阶数，这个角色的面板是多少？（compute_stats）
##     ② 投入这些经验 / 材料，能不能升级 / 突破？（add_exp / can_breakthrough）
##   存档读写由 SaveService 负责，界面由 UI 负责，战斗由 CharacterRuntime 负责。
##
## 纪律（V2.1.4 H 章三十六）：
##   所有成长数值必须来自 data/character_growth.json，**禁止在本文件写死**。
##   本类只持有「该角色当前是多少级、突破到第几阶、累计多少经验」这三件事。
class_name CharacterProgress
extends RefCounted

## 角色 id（对应 characters.json 的 id）
var character_id: String = ""

## 当前等级（1..maxLevel）
var level: int = 1

## 当前突破阶数（0 = 未突破，1..4 对应突破 I..IV）
var breakthrough: int = 0

## 当前等级内的累计经验（0 .. exp_to_next-1）
var exp: int = 0

## 该角色引用的成长档位 id（characters.json 的 growthProfileId）
var growth_profile_id: String = ""

## 成长数据快照（由 from_growth_config 注入；本类不自行读取数据文件）
var _max_level: int = 50
var _breakthrough_levels: Array[int] = []
var _level_cap_by_breakthrough: Dictionary = {}
var _exp_table: Dictionary = {}
var _per_level: Dictionary = {}
var _breakthroughs: Array[Dictionary] = []
var _base_stats: Dictionary = {}

## 引用的成长档位不存在时为 true（由 CharacterGrowthService 在构建期统一报错）。
## 存在的意义：让"数据错误"显式可查，而不是静默用别人的成长曲线。
var _profile_missing: bool = false
var _missing_profile_id: String = ""


## 从成长配置构建。
##
## growth_config: data/character_growth.json 的原始字典
## base_stats:    该角色的 Lv.1 基础面板（characters.json 的 baseStats）
## profile_id:    该角色引用的档位 id
static func from_growth_config(
	character_id: String,
	growth_config: Dictionary,
	base_stats: Dictionary,
	profile_id: String = "growth_standard"
) -> CharacterProgress:
	var p := CharacterProgress.new()
	p.character_id = character_id
	p.growth_profile_id = profile_id
	p._base_stats = base_stats.duplicate(true)

	var rules: Dictionary = growth_config.get("globalRules", {})
	p._max_level = int(rules.get("maxLevel", 50))
	p._exp_table = growth_config.get("expTable", {})
	p._level_cap_by_breakthrough = rules.get("levelCapByBreakthrough", {})

	var levels: Array = rules.get("breakthroughLevels", [])
	for lv: Variant in levels:
		p._breakthrough_levels.append(int(lv))

	var bts: Array = growth_config.get("breakthroughs", [])
	for b: Variant in bts:
		p._breakthroughs.append(b as Dictionary)

	# 取该角色引用的档位。
	# 纪律：**找不到就明确报错，绝不静默回落到 profiles[0]**。
	# 静默回落会让「角色引用了一个不存在的成长档位」这种数据错误
	# 表现为「数值看起来正常但用的是别人的成长曲线」，极难排查。
	var profiles: Array = growth_config.get("growthProfiles", [])
	var found := false
	for pr: Variant in profiles:
		var prof: Dictionary = pr
		if str(prof.get("id", "")) == profile_id:
			p._per_level = prof.get("perLevel", {})
			found = true
			break
	if not found:
		p._profile_missing = true
		p._missing_profile_id = profile_id

	return p


## 当前突破阶数下的等级上限（V2.1.4 H 章六：突破解除下一阶段等级上限）。
func level_cap() -> int:
	var key := str(breakthrough)
	if _level_cap_by_breakthrough.has(key):
		return int(_level_cap_by_breakthrough[key])
	# 无映射时按突破节点表推导：突破 n 阶 → 解除到 breakthroughLevels[n]
	if breakthrough <= 0:
		return _breakthrough_levels[0] if not _breakthrough_levels.is_empty() else 10
	var idx := breakthrough - 1
	if idx < _breakthrough_levels.size():
		return _breakthrough_levels[idx] if idx + 1 >= _breakthrough_levels.size() \
			else _breakthrough_levels[idx + 1]
	return _max_level


## 是否已达当前等级上限
func is_level_capped() -> bool:
	return level >= level_cap()


## 升到下一级所需 EXP（0 = 已满级 / 已到当前上限）
func exp_to_next() -> int:
	if is_level_capped():
		return 0
	return int(_exp_table.get(str(level), 0))


## 距下一次突破还差几级（0 = 现在就可突破；-1 = 无可突破阶段）
func levels_to_next_breakthrough() -> int:
	var next := breakthrough + 1
	if next > _breakthroughs.size():
		return -1
	var need := int((_breakthroughs[next - 1] as Dictionary).get("requiredLevel", 0))
	return maxi(0, need - level)


## 投入经验（V2.1.4 H 章三十四：「达到突破上限时明确提示，而不是吞掉经验」）。
##
## 返回 {gained, levels, leftover, capped, dataMissing}：
##   gained      —— 实际消耗的经验
##   levels      —— 本次提升的等级数
##   leftover    —— 因到达等级上限而**未被消耗**的剩余经验（调用方必须原样退回，不得吞掉）
##   capped      —— 是否因**等级上限**而提前停止（调用方应提示玩家去突破）
##   dataMissing —— 是否因**经验表缺该等级条目**而停止
##
## 纪律：
##   - 只有「升到上限」才停止；上限内的经验一定被消耗；
##   - `capped` 与 `dataMissing` 必须分开：前者是正常的玩法状态（该突破了），
##     后者是数据缺陷。混在一起会让「数据缺键」被当成「到上限」，
##     从而把玩家材料静默消耗掉。
func add_exp(amount: int) -> Dictionary:
	var result := {"gained": 0, "levels": 0, "leftover": 0, "capped": false, "dataMissing": false}
	if amount <= 0:
		return result
	var remaining := amount
	while remaining > 0:
		if is_level_capped():
			result["capped"] = true
			break
		var need := exp_to_next()
		if need <= 0:
			# 数据缺失（expTable 无该等级条目）→ 停止，不静默吞经验
			result["dataMissing"] = true
			break
		var to_add := mini(remaining, need - exp)
		exp += to_add
		remaining -= to_add
		result["gained"] = int(result["gained"]) + to_add
		if exp >= need:
			exp = 0
			level += 1
			result["levels"] = int(result["levels"]) + 1
	result["leftover"] = remaining
	return result


## 是否满足下一次突破的等级条件
func can_breakthrough_by_level() -> bool:
	var next := breakthrough + 1
	if next > _breakthroughs.size():
		return false
	var need := int((_breakthroughs[next - 1] as Dictionary).get("requiredLevel", 0))
	return level >= need


## 下一次突破的阶数（已满 0 时返回 0）
func next_breakthrough_level() -> int:
	var next := breakthrough + 1
	return next if next <= _breakthroughs.size() else 0


## 下一次突破的成本字典（无则空字典）
func next_breakthrough_cost() -> Dictionary:
	var next := breakthrough + 1
	if next > _breakthroughs.size():
		return {}
	return ((_breakthroughs[next - 1] as Dictionary).get("cost", {}) as Dictionary).duplicate(true)


## 执行一次突破（**只改自身状态**；材料扣除由调用方在事务内完成）。
## 返回 false 表示不满足条件、状态未变。
func apply_breakthrough() -> bool:
	if not can_breakthrough_by_level():
		return false
	breakthrough += 1
	return true


## 按当前等级 / 突破计算面板（V2.1.4 H 章三十七：baseStats + growth × (level-1)）。
##
## 纪律：
##   - 只提升 hp / attack / defense / healPower 四项（H 章三明文）；
##   - 攻击范围、阻挡数、部署费用**不随等级变化**（H 章三明文），因此本函数不返回它们；
##   - **只对角色「本来就有」的属性做成长**：某个属性的 Lv.1 基础值为 0 时，
##     说明该角色不使用该属性（例如治疗角色 baseStats.attack = 0、非治疗角色没有 healPower），
##     此时不为其凭空长出该属性。否则会出现「雨宫澪在 Lv.11 获得治疗力 46」
##     或「小川结衣在 Lv.11 获得攻击 52」这类与角色定位矛盾的数值。
##   - 取整口径与 D-22 一致：ROUND_HALF_UP。
func compute_stats() -> Dictionary:
	var out := {}
	var steps := float(maxi(0, level - 1))
	for key: String in ["hp", "attack", "defense", "healPower"]:
		var base := float(_base_stats.get(key, 0))
		# base <= 0 表示该角色不使用该属性 → 保持不出现（而不是从 0 长起来）
		if base <= 0.0:
			continue
		var per := float(_per_level.get(key, 0.0))
		out[key] = int(round(base + per * steps))
	return out


## 到 Lv.50 的总成长倍率（V2.1.4 H 章三十一：不应达到 Lv.1 的几十倍 —— 供验收断言使用）。
func max_level_multiplier(key: String) -> float:
	var base := float(_base_stats.get(key, 0))
	if base <= 0.0:
		return 0.0
	var per := float(_per_level.get(key, 0.0))
	return (base + per * float(_max_level - 1)) / base


## 序列化为存档字段（snake_case，与 SaveGame 其余部分一致）
func to_save_dict() -> Dictionary:
	return {
		"level": level,
		"breakthrough": breakthrough,
		"exp": exp,
	}


## 从存档字段恢复（不校验合法性；合法性由 SaveService 的 schema 校验负责）
static func from_save_dict(
	character_id: String,
	data: Dictionary,
	growth_config: Dictionary,
	base_stats: Dictionary,
	profile_id: String = "growth_standard"
) -> CharacterProgress:
	var p := from_growth_config(character_id, growth_config, base_stats, profile_id)
	p.level = maxi(1, int(data.get("level", 1)))
	p.breakthrough = maxi(0, int(data.get("breakthrough", 0)))
	p.exp = maxi(0, int(data.get("exp", 0)))
	return p


## 引用的成长档位是否缺失（缺失时面板只等于 baseStats，不会成长）
func has_missing_profile() -> bool:
	return _profile_missing


func missing_profile_id() -> String:
	return _missing_profile_id


func to_debug_dict() -> Dictionary:
	return {
		"characterId": character_id,
		"level": level,
		"levelCap": level_cap(),
		"breakthrough": breakthrough,
		"exp": exp,
		"expToNext": exp_to_next(),
		"profile": growth_profile_id,
		"stats": compute_stats(),
	}
