## UpgradeCandidateRoller — 局内三选一的候选生成（纯逻辑，确定性）。
##
## 规格依据（V2.1.4 I 章）：
##   L2049～2056 候选算法原则：
##     1. 读取当前队伍标签
##     2. 排除完全无效强化
##     3. 按 COMMON / ADVANCED / CORE 权重抽取
##     4. 保证 3 个选项尽量来自不同类别
##     5. 检查重复与叠加上限
##   L2139 候选池根据当前队伍标签加权，**至少保证 2 个选项对当前阵容有实际价值**。
##   L2082 首轮测试指标：三选一是否存在明显"永远正确"的选项。
##
## 确定性纪律（LOCKED：战斗结果可复现）：
##   本类使用**自带种子的 RandomNumberGenerator**，不使用 randf()/randi() 全局随机。
##   同一种子 + 同一输入 ⇒ 同一候选集，因此自动化测试可以精确断言，
##   也不会破坏「不同帧率/分辨率结果一致」的既有回归。
class_name UpgradeCandidateRoller
extends RefCounted

## 每次给出的候选数量（L2054「3 个选项」）
const CANDIDATE_COUNT := 3

## 队伍画像：行为集合 + 标签集合
##   behaviors: ["FRONTLINE","RANGED"] 之类（来自 CharacterRuntime.behavior_name）
##   tags:      队伍 roleTags 的并集（来自 characters.json 的 roleTags）
static func roll(upgrades: InBattleUpgrades, behaviors: Array[String],
		tags: Array[String], seed_value: int,
		count: int = CANDIDATE_COUNT) -> Array[String]:
	var result: Array[String] = []
	if upgrades == null:
		return result

	# ---- 步骤 1/2/5：筛出「对当前队伍有效 且 未达叠加上限」的池 ----
	var pool: Array[Dictionary] = []
	for id: String in upgrades.all_ids():
		var cfg := upgrades.definition(id)
		if cfg.is_empty():
			continue
		if not upgrades.can_select(id):
			continue          # 步骤 5：叠加上限
		if not _useful_for(cfg, behaviors, tags):
			continue          # 步骤 2：完全无效项排除
		pool.append({
			"id": id,
			"tier": str(cfg.get("tier", "")),
			"categories": _categories_of(cfg),
			# 步骤 1：命中队伍标签的条目加权（L2139）
			"tagHit": _tag_bonus_weight(cfg, tags, behaviors),
		})
	if pool.is_empty():
		return result

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# ---- 步骤 4：尽量来自不同类别（先按类别去重抽取，不足再回填） ----
	var used_categories: Dictionary = {}
	var picked_ids: Dictionary = {}
	var remaining: Array[Dictionary] = pool.duplicate(true)

	while result.size() < count and not remaining.is_empty():
		# 优先挑「类别未被占用」的候选；全被占用时退化为允许同类别
		var distinct: Array[Dictionary] = []
		var any_pool: Array[Dictionary] = []
		for item: Dictionary in remaining:
			any_pool.append(item)
			if not _overlaps_used(item, used_categories):
				distinct.append(item)
		var choices: Array[Dictionary] = distinct if not distinct.is_empty() else any_pool
		var chosen: Dictionary = _weighted_pick(choices, upgrades, rng)
		if chosen.is_empty():
			break
		result.append(str(chosen["id"]))
		picked_ids[str(chosen["id"])] = true
		for c: String in (chosen["categories"] as Array):
			used_categories[c] = true
		# 注意：Array.filter() 返回**无类型** Array，直接赋给 Array[Dictionary]
		# 在 Godot 4 会触发运行时报错，因此这里用显式循环重建。
		var next_remaining: Array[Dictionary] = []
		for leftover: Dictionary in remaining:
			if str(leftover["id"]) != str(chosen["id"]):
				next_remaining.append(leftover)
		remaining = next_remaining

	# ---- 步骤 3 的兜底：不足 3 个时，用剩余池补齐（仍不重复） ----
	if result.size() < count:
		for item: Dictionary in pool:
			if result.size() >= count:
				break
			if picked_ids.has(item["id"]):
				continue
			result.append(str(item["id"]))
			picked_ids[str(item["id"])] = true
	return result


## 该强化对当前队伍是否有实际价值。
##   * STAGE / ALL 级：恒有价值（AP 回复、撤退返还、全队攻击）
##   * 职业专属：队伍里必须有该行为，否则"完全无效"（L2052 第 2 步）
static func _useful_for(cfg: Dictionary, behaviors: Array[String], tags: Array[String]) -> bool:
	var applies := str(cfg.get("appliesTo", ""))
	if applies == InBattleUpgrades.APPLIES_ALL or applies == InBattleUpgrades.APPLIES_STAGE:
		return true
	return behaviors.has(applies)


## 类别（用于 L2054「尽量来自不同类别」）。取 tags 首项为主类别。
static func _categories_of(cfg: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var t: Variant = cfg.get("tags", [])
	if typeof(t) == TYPE_ARRAY:
		for v: Variant in (t as Array):
			out.append(str(v))
	if out.is_empty():
		out.append(str(cfg.get("tier", "UNCATEGORIZED")))
	return out


static func _overlaps_used(item: Dictionary, used_categories: Dictionary) -> bool:
	for c: String in (item["categories"] as Array):
		if used_categories.has(c):
			return true
	return false


## 标签加权（L2139「候选池根据当前队伍标签加权」）。
## 命中队伍 roleTags 或命中队伍行为时给 2 倍权重；否则 1 倍。
static func _tag_bonus_weight(cfg: Dictionary, tags: Array[String], behaviors: Array[String]) -> float:
	var weight := 1.0
	var cfg_tags: Variant = cfg.get("tags", [])
	if typeof(cfg_tags) == TYPE_ARRAY:
		for v: Variant in (cfg_tags as Array):
			if tags.has(str(v)):
				weight = maxf(weight, 2.0)
	var applies := str(cfg.get("appliesTo", ""))
	if applies != InBattleUpgrades.APPLIES_STAGE and behaviors.has(applies):
		weight = maxf(weight, 2.0)
	return weight


## 按「层级权重 × 标签权重」抽取一个。层级权重缺失时按 1 计（不静默丢弃条目）。
static func _weighted_pick(choices: Array[Dictionary], upgrades: InBattleUpgrades,
		rng: RandomNumberGenerator) -> Dictionary:
	if choices.is_empty():
		return {}
	var weights: Array[float] = []
	var total := 0.0
	for item: Dictionary in choices:
		var tier_w := upgrades.tier_weight(str(item["tier"]))
		var w := tier_w * float(item["tagHit"])
		weights.append(w)
		total += w
	if total <= 0.0:
		# 全部权重为 0（数据异常）：等权兜底，但由调用方的数据校验负责暴露
		return choices[rng.randi_range(0, choices.size() - 1)]
	var pick_value := rng.randf() * total
	var acc := 0.0
	for i: int in range(choices.size()):
		acc += weights[i]
		if pick_value <= acc:
			return choices[i]
	return choices[choices.size() - 1]
