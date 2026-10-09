## CharacterGrowthService — 角色成长的**应用层服务**（V2.1.4 H 章）。
##
## 职责（L3 Application 层）：
##   把「数据（DataRegistry 的成长/资源/成本配置）」「存档（SaveService 的 progression 段）」
##   与「领域对象（CharacterProgress）」串起来，并向 UI 暴露可用的操作：
##     查询面板 / 升级（投入学习记录）/ 突破 / 资源增减。
##
## 纪律：
##   - 本服务**不复制任何数值**，全部来自 DataRegistry；
##   - 所有会改变存档的操作都走 SaveService.commit()（事务式），避免"资源扣了但结果没保存"；
##   - 升级时若经验溢出上限，**未消耗的经验必须原样退回库存**（H 章三十四：不吞经验）。
##
## 生命周期：Autoload 之外的场景级服务会重复构建；本类设计为可被 App 持有单实例，
## 也允许测试直接 new() 后手动 load_from_save()。不注册为 Autoload（L4 未包含该职责）。
class_name CharacterGrowthService
extends RefCounted

const TAG := "CharacterGrowth"

## 角色 id -> CharacterProgress
var _progress: Dictionary = {}

## 构建期错误
var _errors: Array[String] = []

## 是否已初始化
var _ready: bool = false


## 从 DataRegistry 与存档初始化（幂等：可重复调用，会以存档为准重建）。
func setup() -> Array[String]:
	_errors.clear()
	_progress.clear()
	_ready = false

	if not DataRegistry.is_loaded():
		_errors.append("DataRegistry 未就绪")
		return _errors

	var growth: Dictionary = DataRegistry.get_domain("character_growth")
	if growth.is_empty():
		_errors.append("character_growth.json 未加载")
		return _errors

	# 构建期校验：成长档位必须存在，且经验表键完整
	var profiles: Array = growth.get("growthProfiles", [])
	if profiles.is_empty():
		_errors.append("character_growth.json 的 growthProfiles 为空")
	var rules: Dictionary = growth.get("globalRules", {})
	var max_level := int(rules.get("maxLevel", 0))
	if max_level <= 0:
		_errors.append("globalRules.maxLevel 非法（%d）" % max_level)
	var exp_table: Dictionary = growth.get("expTable", {})
	for lv: int in range(1, max_level):
		if not exp_table.has(str(lv)):
			_errors.append("expTable 缺少 Lv.%d → Lv.%d 的经验需求" % [lv, lv + 1])

	var save := SaveService.get_current()
	var saved: Dictionary = save.get("progression", {}).get("characters", {})

	# 档位 id 集合（用于校验角色引用；找不到就报错，不静默回落）
	var profile_ids := {}
	for pr: Variant in profiles:
		profile_ids[str((pr as Dictionary).get("id", ""))] = true

	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		var cid := str(c.get("id", ""))
		if cid.is_empty():
			continue
		var profile_id := str(c.get("growthProfileId", "growth_standard"))
		if not profile_ids.has(profile_id):
			_errors.append("角色 %s 引用了不存在的成长档位 '%s'（可用：%s）"
				% [cid, profile_id, ", ".join(profile_ids.keys())])
			continue
		var base: Dictionary = (c.get("baseStats", {}) as Dictionary).duplicate(true)
		# 治疗力不在 baseStats 里（P0.4 设计：attack=0、healPower 独立字段），补进来供成长计算
		if c.has("healPower"):
			base["healPower"] = int(c.get("healPower", 0))
		if saved.has(cid):
			_progress[cid] = CharacterProgress.from_save_dict(
				cid, saved[cid], growth, base, profile_id)
		else:
			_progress[cid] = CharacterProgress.from_growth_config(
				cid, growth, base, profile_id)
		# 双保险：即便上面漏了，也把 CharacterProgress 自身的缺失标记上报
		var p: CharacterProgress = _progress[cid]
		if p != null and p.has_missing_profile():
			_errors.append("角色 %s 的成长档位 '%s' 解析失败"
				% [cid, p.missing_profile_id()])

	_ready = _errors.is_empty()
	return _errors


func is_ready() -> bool:
	return _ready


func get_errors() -> Array[String]:
	return _errors


## 取某角色的成长状态（不存在返回 null）
func get_progress(character_id: String) -> CharacterProgress:
	return _progress.get(character_id, null)


## 全部角色 id
func all_character_ids() -> Array:
	return _progress.keys()


# ============================================================
#  资源（五类，唯一来自 currencies.json 的 id）
# ============================================================

## 某资源的当前库存（从存档 currencies 段读取）
func get_currency(currency_id: String) -> int:
	var save := SaveService.get_current()
	var cur: Dictionary = save.get("currencies", {})
	return int(cur.get(currency_id, 0))


## 增减资源（正数增加、负数扣除）。返回实际变化量。
##
## 纪律：扣除时**不足即拒绝整笔**（不做部分扣除），并把库存夹在 0 以上。
## 本函数只改内存存档；调用方必须在同一事务内 commit()。
func add_currency(currency_id: String, amount: int) -> int:
	var save := SaveService.get_current()
	if save.is_empty():
		return 0
	if not save.has("currencies"):
		save["currencies"] = {}
	var cur: Dictionary = save["currencies"]
	var before := int(cur.get(currency_id, 0))
	var after := before + amount
	if after < 0:
		return 0
	cur[currency_id] = after
	return after - before


## 是否付得起一组成本（{currencyId: amount}）
func can_afford(cost: Dictionary) -> bool:
	for cid: String in cost.keys():
		if get_currency(cid) < int(cost[cid]):
			return false
	return true


## 扣除一组成本。**全部可付才扣**，否则不做任何改动并返回 false。
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for cid: String in cost.keys():
		add_currency(cid, -int(cost[cid]))
	return true


## 发放一组资源（奖励用）
func grant(rewards: Dictionary) -> void:
	for cid: String in rewards.keys():
		add_currency(cid, int(rewards[cid]))


# ============================================================
#  升级（投入学习记录）
# ============================================================

## 学习记录道具 id -> 折算经验（唯一来自 currencies.json 的 studyRecordItems）
func study_record_items() -> Dictionary:
	var out := {}
	for item: Dictionary in DataRegistry.get_domain("currencies").get("studyRecordItems", []):
		out[str(item.get("id", ""))] = int(item.get("expValue", 0))
	return out


## 投入指定数量的学习记录给某角色。
##
## record_item_id: study_record_short / _note / _archive
## count:          投入本数
##
## 返回 {ok, reason, expSpent, expRefunded, levelsGained, levelAfter}。
## 纪律（H 章三十四）：到达等级上限时，**未消耗的经验折算回学习记录原样退回**，
## 不允许吞掉玩家材料。
func level_up_with_records(character_id: String, record_item_id: String, count: int) -> Dictionary:
	var out := {"ok": false, "reason": "", "expSpent": 0, "expRefunded": 0,
		"levelsGained": 0, "levelAfter": 0}
	if count <= 0:
		out["reason"] = "投入数量必须为正"
		return out
	var p := get_progress(character_id)
	if p == null:
		out["reason"] = "未知角色：%s" % character_id
		return out
	var items := study_record_items()
	if not items.has(record_item_id):
		out["reason"] = "未知学习记录：%s" % record_item_id
		return out
	if get_currency(record_item_id) < count:
		out["reason"] = "学习记录不足（需要 %d，持有 %d）" % [count, get_currency(record_item_id)]
		return out
	if p.is_level_capped():
		out["reason"] = "已达当前等级上限 Lv.%d（需要突破）" % p.level_cap()
		return out

	var exp_value := int(items[record_item_id])
	var total_exp := exp_value * count
	var res := p.add_exp(total_exp)
	var refunded_exp := int(res["leftover"])

	# 扣掉真正投入的本数
	var consumed := count
	var refunded_items := 0
	if refunded_exp > 0 and exp_value > 0:
		# 未消耗的经验折算回整本（向下取整），不足一本的零头无法归还 → 计入已消耗
		refunded_items = refunded_exp / exp_value
		consumed = count - refunded_items
	add_currency(record_item_id, -consumed)
	if refunded_items > 0:
		add_currency(record_item_id, refunded_items)

	out["ok"] = true
	out["expSpent"] = int(res["gained"])
	out["expRefunded"] = refunded_exp
	out["levelsGained"] = int(res["levels"])
	out["levelAfter"] = p.level
	return out


# ============================================================
#  突破
# ============================================================

## 查询某角色能否突破，以及原因（无副作用，供 UI 显示）。
func query_breakthrough(character_id: String) -> Dictionary:
	var p := get_progress(character_id)
	if p == null:
		return {"ok": false, "reason": "未知角色"}
	var next := p.next_breakthrough_level()
	if next <= 0:
		return {"ok": false, "reason": "已完成全部突破"}
	if not p.can_breakthrough_by_level():
		return {"ok": false, "reason": "需要等级 Lv.%d（当前 Lv.%d）" % [
			_required_level_for(p), p.level]}
	var cost := p.next_breakthrough_cost()
	if not can_afford(cost):
		var missing: Array[String] = []
		for cid: String in cost.keys():
			var need := int(cost[cid])
			if need > 0 and get_currency(cid) < need:
				missing.append("%s %d/%d" % [_currency_name(cid), get_currency(cid), need])
		return {"ok": false, "reason": "材料不足：%s" % ", ".join(missing)}
	return {"ok": true, "reason": "", "cost": cost, "nextLevel": next}


## 下一次突破所需的等级（由 CharacterProgress 的突破节点表推导，不在此硬编码 10/20/30/40）。
func _required_level_for(p: CharacterProgress) -> int:
	var next := p.next_breakthrough_level()
	if next <= 0:
		return p.level_cap()
	# 突破 next 阶要求角色到达 breakthroughLevels[next-1]
	var growth: Dictionary = DataRegistry.get_domain("character_growth")
	var rules: Dictionary = growth.get("globalRules", {})
	var levels: Array = rules.get("breakthroughLevels", [])
	var idx := next - 1
	if idx >= 0 and idx < levels.size():
		return int(levels[idx])
	return p.level_cap()


## 执行突破：扣材料 + 提升突破阶数。返回 {ok, reason, breakthroughAfter}。
func do_breakthrough(character_id: String) -> Dictionary:
	var q := query_breakthrough(character_id)
	if not bool(q.get("ok", false)):
		return {"ok": false, "reason": q.get("reason", ""), "breakthroughAfter": 0}
	var p := get_progress(character_id)
	var cost: Dictionary = q["cost"]
	if not spend(cost):
		return {"ok": false, "reason": "材料扣除失败", "breakthroughAfter": p.breakthrough}
	p.apply_breakthrough()
	return {"ok": true, "reason": "", "breakthroughAfter": p.breakthrough}


# ============================================================
#  存档
# ============================================================

## 把当前成长状态写回存档字典（不提交；由调用方 commit）。
func write_to_save(save: Dictionary) -> void:
	if not save.has("progression"):
		save["progression"] = {}
	if not (save["progression"] as Dictionary).has("characters"):
		save["progression"]["characters"] = {}
	var out: Dictionary = save["progression"]["characters"]
	for cid: String in _progress.keys():
		out[cid] = (_progress[cid] as CharacterProgress).to_save_dict()


## 写回并事务式提交。
func commit() -> bool:
	var save := SaveService.get_current()
	if save.is_empty():
		# 无存档时先建一份，保证成长状态有地方落盘
		SaveService.new_game()
		save = SaveService.get_current()
	write_to_save(save)
	return SaveService.commit(save)


func _currency_name(currency_id: String) -> String:
	for c: Dictionary in DataRegistry.get_domain("currencies").get("currencies", []):
		if str(c.get("id", "")) == currency_id:
			return str(c.get("name", currency_id))
	return currency_id
