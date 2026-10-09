## StageRewardService — 关卡奖励结算（Alpha A0.4）。
##
## 职责（L3 Application 层）：
##   把「关卡结算」翻译成「资源入账 + 一次性标记」，并保证：
##     ① **首通奖励只发一次**（V2.1.4 H 章二十二 / G-九：一次性 effect 必须幂等）；
##     ② 重复通关只发 repeatRewardId；
##     ③ 失败不发任何奖励（G-八 / J0.13：失败不执行 storyAfter、不发首次通关奖励）；
##     ④ 全部走 SaveService.commit() 事务式落盘。
##
## 数值来源：**唯一来自 data/stage_rewards.json 与关卡 StageConfig.battleRewards**，
## 本文件不出现任何金额。
##
## 存档结构（SaveGame.stages[stageId]）：
##   { "cleared": bool, "firstClearClaimed": bool, "clearCount": int }
class_name StageRewardService
extends RefCounted

const TAG := "StageReward"

## 单场结算结果
class Settlement:
	extends RefCounted
	var ok: bool = false
	var reason: String = ""
	## 本次实际发放的资源 { currencyId: amount }
	var granted: Dictionary = {}
	## 是否是首次通关（本次发放了首通奖励）
	var first_clear: bool = false
	## 本次是否发过奖励（失败时为 false）
	var rewarded: bool = false

	func granted_text() -> String:
		var parts: PackedStringArray = PackedStringArray()
		for k: String in granted.keys():
			parts.append("%s×%d" % [k, int(granted[k])])
		return "、".join(parts) if parts.size() > 0 else "（无）"


## 结算一场战斗。
##
## stage_config: 关卡配置（读 battleRewards / firstClearRewardId / repeatRewardId）
## victory:      是否胜利
## commit:       是否立即事务式落盘（测试可传 false 只做内存推演）
##
## 纪律：**失败不发奖励**；**首通只发一次**（以存档的 firstClearClaimed 为准）。
static func settle(stage_config: Dictionary, victory: bool, commit: bool = true) -> Settlement:
	var out := Settlement.new()
	if not victory:
		out.ok = true
		out.reason = "失败不发放奖励"
		return out

	var sid := str(stage_config.get("stageId", ""))
	if sid.is_empty():
		out.reason = "关卡缺少 stageId"
		return out

	var save := SaveService.get_current()
	if save.is_empty():
		SaveService.new_game()
		save = SaveService.get_current()
	if not save.has("stages"):
		save["stages"] = {}
	var stages: Dictionary = save["stages"]
	if not stages.has(sid):
		stages[sid] = {"cleared": false, "firstClearClaimed": false, "clearCount": 0}
	var st: Dictionary = stages[sid]

	var granted := {}
	var first_clear := false

	# ① 即时战斗奖励（每次通关都发；属关卡自身规则）
	_merge(granted, stage_config.get("battleRewards", {}))

	# ② 首通奖励（只发一次）
	var first_id := str(stage_config.get("firstClearRewardId", ""))
	if not bool(st.get("firstClearClaimed", false)) and not first_id.is_empty():
		var r := _find_reward(first_id)
		if r.is_empty():
			out.reason = "首通奖励 ID '%s' 不在 stage_rewards.json" % first_id
			return out
		_merge(granted, r.get("currencies", {}))
		first_clear = true
	else:
		# ③ 重复通关奖励（已首通时才发）
		var rep_id := str(stage_config.get("repeatRewardId", ""))
		if not rep_id.is_empty():
			var r := _find_reward(rep_id)
			if not r.is_empty():
				_merge(granted, r.get("currencies", {}))

	# ④ 入账（内存）
	var svc := _growth()
	if svc == null:
		out.reason = "成长/资源系统不可用"
		return out
	for cid: String in granted.keys():
		svc.add_currency(cid, int(granted[cid]))

	# ⑤ 更新一次性标记
	st["cleared"] = true
	st["clearCount"] = int(st.get("clearCount", 0)) + 1
	if first_clear:
		st["firstClearClaimed"] = true

	# ⑥ 事务式落盘
	if commit:
		if not svc.commit():
			out.reason = "奖励已入账内存但存档写入失败"
			return out

	out.ok = true
	out.granted = granted
	out.first_clear = first_clear
	out.rewarded = not granted.is_empty()
	GameLog.info(TAG, "关卡 %s 结算：%s%s，发放 %s" % [
		sid, "首通" if first_clear else "重复通关",
		"（第 %d 次）" % int(st["clearCount"]), out.granted_text()])
	return out


## 某关是否已首通（读存档）
static func is_first_cleared(stage_id: String) -> bool:
	var save := SaveService.get_current()
	var st: Dictionary = save.get("stages", {}).get(stage_id, {})
	return bool(st.get("firstClearClaimed", false))


## 某关的通关次数（读存档）
static func clear_count(stage_id: String) -> int:
	var save := SaveService.get_current()
	var st: Dictionary = save.get("stages", {}).get(stage_id, {})
	return int(st.get("clearCount", 0))


## 汇总 1-1～1-10 的首通总收益（供 H 章二十一-A 表 71 预算校验）。
## 返回 { school_coin, study_record_exp, club_badge, echo_crystal, equipment_part, missing: Array }
##
## 口径（与表 71 的注释一致）：「全部结算与首通奖励」= Σ battleRewards + Σ firstClear。
## 学园币与材料按 id 直接累加；学习记录按 currencies.json 的 studyRecordItems.expValue 折算成 EXP。
static func first_clear_budget_total() -> Dictionary:
	var out := {
		"school_coin": 0, "study_record_exp": 0, "club_badge": 0,
		"echo_crystal": 0, "equipment_part": 0, "missing": [],
	}
	var exp_of := {}
	for item: Dictionary in DataRegistry.get_domain("currencies").get("studyRecordItems", []):
		exp_of[str(item.get("id", ""))] = int(item.get("expValue", 0))

	for i: int in range(1, 11):
		var sid := "1-%d" % i
		var cfg: Dictionary = DataRegistry.get_entry("stages", sid)
		if cfg.is_empty():
			out["missing"].append(sid)
			continue
		var timeline: Variant = cfg.get("enemySpawnTimeline", [])
		if typeof(timeline) != TYPE_ARRAY or (timeline as Array).is_empty():
			# 1-6～1-10 仍是 Phase 0 占位，尚未配置奖励
			out["missing"].append(sid)
			continue
		_accumulate(out, cfg.get("battleRewards", {}), exp_of)
		var fid := str(cfg.get("firstClearRewardId", ""))
		if not fid.is_empty():
			var r := _find_reward(fid)
			if r.is_empty():
				out["missing"].append("%s:firstClear" % sid)
			else:
				_accumulate(out, r.get("currencies", {}), exp_of)
	return out


static func _accumulate(acc: Dictionary, currencies: Variant, exp_of: Dictionary) -> void:
	if typeof(currencies) != TYPE_DICTIONARY:
		return
	for cid: String in (currencies as Dictionary).keys():
		var amount := int((currencies as Dictionary)[cid])
		if exp_of.has(cid):
			acc["study_record_exp"] = int(acc["study_record_exp"]) + amount * int(exp_of[cid])
		elif acc.has(cid):
			acc[cid] = int(acc[cid]) + amount


static func _merge(target: Dictionary, source: Variant) -> void:
	if typeof(source) != TYPE_DICTIONARY:
		return
	for k: String in (source as Dictionary).keys():
		target[k] = int(target.get(k, 0)) + int((source as Dictionary)[k])


static func _find_reward(reward_id: String) -> Dictionary:
	for r: Dictionary in DataRegistry.get_domain("stage_rewards").get("rewards", []):
		if str(r.get("id", "")) == reward_id:
			return r
	return {}


static func _growth() -> CharacterGrowthService:
	if not App.ensure_growth():
		return null
	return App.growth