## StageRewardService — 关卡奖励结算（Alpha A0.4；A0.4 加固：待领取权益）。
##
## 职责（L3 Application 层）：
##   把「关卡结算」翻译成「资源入账 + 一次性标记 + 待领取权益登记」，并保证：
##     ① **首通奖励只发一次**（V2.1.4 H 章二十二 / G-九：一次性 effect 必须幂等）；
##     ② 重复通关只发 repeatRewardId；
##     ③ 失败不发任何奖励（G-八 / J0.13：失败不执行 storyAfter、不发首次通关奖励）；
##     ④ 全部走 SaveService.commit() 事务式落盘；
##     ⑤ **尚未实现的奖励类型（装备 / 纪念物）不得丢失**——登记为「待领取权益」。
##
## 数值来源：**唯一来自 data/stage_rewards.json 与关卡 StageConfig.battleRewards**，
## 本文件不出现任何金额。
##
## ── 待领取权益（pending entitlement）为什么存在 ──
## V2.1.4 H 章二十 表 70 规定 1-2「优秀级基础武器」、1-6「治疗饰品」、
## 1-9「固定稀有级通用饰品 equip_ch1_1_9_rare_accessory」、1-10「Boss 纪念物」。
## 这些奖励需要 equipment.json / mementos.json 与实例化系统（A0.5 / A0.8）。
##
## 但**首通只有一次**。若结算时因为"装备系统还没做"而跳过它们，同时又把
## firstClearClaimed 置为 true，那么这些装备就**永久无法补发**——玩家首通 1-9
## 之后，无论怎么重玩都不会再拿到那件稀有饰品。这是不可逆的奖励损失。
##
## 因此：结算时把这类奖励登记成一条**待领取权益**，与首通结算**同一事务**写入存档。
## 权益记录 stageId / rewardId / itemId / 奖励类型 / 唯一发放标识，并且：
##   - 重复结算不会重复登记（以 entitlementId 去重）；
##   - 装备系统接入后，把权益**兑现**为真实装备实例，并标记已兑现；
##   - 兑现是幂等的：重复兑现不会复制装备。
##
## ── 存档结构 ──
## SaveGame.stages[stageId]：
##   { "cleared": bool, "firstClearClaimed": bool, "clearCount": int }
## SaveGame.entitlements（顶层，与 stages 同级）：
##   {
##     "pending":     [ {entitlementId, stageId, rewardId, kind, itemId, source} ],
##     "fulfilled":   [ {entitlementId, stageId, rewardId, kind, itemId, instanceId, fulfilledAt} ],
##   }
class_name StageRewardService
extends RefCounted

const TAG := "StageReward"

## 存档中承载待领取权益的顶层键（与 stages 同级）。
const ENTITLEMENTS_KEY := "entitlements"
## 权益来源：首通结算登记
const SOURCE_FIRST_CLEAR := "FIRST_CLEAR"

## 尚未实现、需要登记为待领取权益的奖励字段 -> 奖励类型。
##
## 纪律：新增一类「需要实例化系统才能发放」的奖励时，只在此表登记，
## 不要在 settle() 里写分支。
const PENDING_KINDS := {
	"equipmentId": "EQUIPMENT",
	"mementoId": "MEMENTO",
}


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
	## 本次**新登记**的待领取权益（已存在的不会重复登记）
	var pending_registered: Array[Dictionary] = []
	## 本次结算时被补登记的旧存档权益（兼容性回填）
	var backfilled: Array[Dictionary] = []

	func granted_text() -> String:
		var parts: PackedStringArray = PackedStringArray()
		for k: String in granted.keys():
			parts.append("%s×%d" % [k, int(granted[k])])
		return "、".join(parts) if parts.size() > 0 else "（无）"

	## 待领取权益的口播/日志文本
	func pending_text() -> String:
		if pending_registered.is_empty() and backfilled.is_empty():
			return ""
		var parts: PackedStringArray = PackedStringArray()
		for e: Dictionary in pending_registered:
			parts.append("%s(%s)" % [e.get("itemId", "?"), e.get("kind", "?")])
		var text := ""
		if parts.size() > 0:
			text = "待领取权益已登记：%s" % "、".join(parts)
		if not backfilled.is_empty():
			var b: PackedStringArray = PackedStringArray()
			for e: Dictionary in backfilled:
				b.append("%s(%s)" % [e.get("itemId", "?"), e.get("stageId", "?")])
			text += ("；" if text != "" else "") + "旧存档权益已补登记：%s" % "、".join(b)
		return text


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

	# 兜底取存档：优先读回磁盘既有进度，**绝不用新档覆盖玩家进度**。
	if not SaveService.ensure_loaded():
		out.reason = "存档不可用（磁盘存档无法读取），本次结算未执行"
		return out

	# **事务快照**：必须在任何内存改动之前取，失败时才能整体回滚。
	var snap := SaveService.snapshot()

	var save := SaveService.get_current()
	if not save.has("stages"):
		save["stages"] = {}
	var stages: Dictionary = save["stages"]
	if not stages.has(sid):
		stages[sid] = {"cleared": false, "firstClearClaimed": false, "clearCount": 0}
	var st: Dictionary = stages[sid]

	var granted := {}
	var first_clear := false
	# 本关可能涉及的待领取权益（无论是否首通都要检查，用于旧存档回填）
	var pending_specs: Array[Dictionary] = []

	# ① 即时战斗奖励（每次通关都发；属关卡自身规则）
	_merge(granted, stage_config.get("battleRewards", {}))

	# ② 首通奖励（只发一次）
	var first_id := str(stage_config.get("firstClearRewardId", ""))
	if not bool(st.get("firstClearClaimed", false)) and not first_id.is_empty():
		var r := _find_reward(first_id)
		if r.is_empty():
			SaveService.restore(snap)
			out.reason = "首通奖励 ID '%s' 不在 stage_rewards.json" % first_id
			return out
		_merge(granted, r.get("currencies", {}))
		first_clear = true
		pending_specs = _pending_specs_of(r, sid, SOURCE_FIRST_CLEAR)
	else:
		# ③ 重复通关奖励（已首通时才发）
		var rep_id := str(stage_config.get("repeatRewardId", ""))
		if not rep_id.is_empty():
			var r := _find_reward(rep_id)
			if not r.is_empty():
				_merge(granted, r.get("currencies", {}))
		# 已首通的关卡：仍需检查首通奖励里的待领取权益是否已登记
		# （旧存档兼容路径——见 backfill_entitlements 的说明）。
		#
		# 这里**不按关卡内容是否已填充来过滤**：权益是否应登记，取决于
		# 「该关有没有配置首通奖励」，而不是「关卡内容填了没有」。
		# 两者由不同阶段负责（关卡内容属 A0.3、奖励表属 A0.4），
		# 用后者去卡前者会在两阶段错位时静默漏发玩家应得的装备。
		if not first_id.is_empty():
			var r2 := _find_reward(first_id)
			if not r2.is_empty():
				pending_specs = _pending_specs_of(r2, sid, SOURCE_FIRST_CLEAR)

	# ④ 入账（内存）
	var svc := _growth()
	if svc == null:
		SaveService.restore(snap)
		out.reason = "成长/资源系统不可用"
		return out
	for cid: String in granted.keys():
		svc.add_currency(cid, int(granted[cid]))

	# ⑤ 登记待领取权益（与首通结算同一事务）
	#
	# 两种来源都走同一条登记路径：
	#   - 本次首通 → 新登记（幂等：已存在则不重复）；
	#   - 已首通但权益缺失（旧存档）→ 补登记（同样幂等）。
	# 因此「旧存档补登记」不需要单独的迁移脚本，也不存在重复发放风险。
	out.pending_registered = _register_entitlements(save, pending_specs)

	# ⑥ 更新一次性标记
	st["cleared"] = true
	st["clearCount"] = int(st.get("clearCount", 0)) + 1
	if first_clear:
		st["firstClearClaimed"] = true
	# Persist the required post-battle story in the SAME reward transaction.
	# Restarting during a story therefore cannot repeat first-clear rewards.
	var flow: Dictionary = save.get("flow_state", {})
	if bool(flow.get("campaign_active", false)) and str(flow.get("pending_stage_id", "")) == sid:
		var after := str(stage_config.get("storyAfter", ""))
		var flags: Dictionary = save.get("story", {}).get("flags", {})
		if not after.is_empty() and not bool(flags.get("done:" + after, false)):
			flow["pending_story_after"] = after
			flow["current_story_id"] = after
			flow["current_story_node"] = "0"
			flow["mode"] = "post_battle"
		save["flow_state"] = flow

	# ⑦ 事务式落盘（失败 → 整体回滚到快照，不留任何半结算痕迹）
	if commit:
		if not svc.commit():
			SaveService.restore(snap)
			out.reason = "奖励已入账内存但存档写入失败（内存已整体回滚，本次未生效）"
			return out

	out.ok = true
	out.granted = granted
	out.first_clear = first_clear
	out.rewarded = not granted.is_empty() or not out.pending_registered.is_empty()
	GameLog.info(TAG, "关卡 %s 结算：%s%s，发放 %s%s" % [
		sid, "首通" if first_clear else "重复通关",
		"（第 %d 次）" % int(st["clearCount"]), out.granted_text(),
		"" if out.pending_text() == "" else "；" + out.pending_text()])
	return out


## 该关卡是否**已填充内容**（而不是 Phase 0 占位）。
##
## 口径与 first_clear_budget_total() 及 DataRegistry._validate_core_hp_against_balance()
## 完全一致：enemySpawnTimeline 为空即视为占位。1-6～1-10 目前都是占位，
## 因此**不计入表 71 首通预算**（它们的内容与奖励由后续阶段接入）。
##
## 注意：本函数**只用于预算统计口径**，不得用来决定"是否登记玩家权益"——
## 那取决于奖励表是否配置了该关的首通奖励（见 backfill_entitlements 的说明）。
static func cfg_has_content(stage_config: Dictionary) -> bool:
	var timeline: Variant = stage_config.get("enemySpawnTimeline", [])
	return typeof(timeline) == TYPE_ARRAY and not (timeline as Array).is_empty()


## 兼容性回填（旧存档升级）。
##
## 对**已经首通、但当时还没有权益系统**的存档：按固定奖励定义把应得的
## 装备 / 纪念物权益补登记进来。
##
## 幂等保证：_register_entitlements 以 entitlementId 去重，
## 因此本函数**可以安全地重复调用**，绝不会重复发放或重复登记。
##
## 返回本次新补登记的权益列表（已存在的不计入）。
static func backfill_entitlements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not SaveService.ensure_loaded():
		GameLog.error(TAG, "旧存档权益回填失败：存档不可用")
		return out
	var save := SaveService.get_current()
	if save.is_empty():
		return out

	var snap := SaveService.snapshot()
	var specs: Array[Dictionary] = []

	# 遍历**首通奖励定义**（而不是遍历关卡内容）：
	# 权益该不该登记，取决于「这条首通奖励里有没有 equipmentId / mementoId」，
	# 而奖励表本身就带着 stageId。这样即使某关的内容还是占位
	# （1-6～1-10 属后续阶段），只要它的奖励已配置，玩家应得的装备就不会丢。
	for r: Dictionary in DataRegistry.get_domain("stage_rewards").get("rewards", []):
		if str(r.get("kind", "")) != "FIRST_CLEAR":
			continue
		var sid := str(r.get("stageId", ""))
		if sid.is_empty():
			continue
		# 只补「玩家确实已首通」的关卡
		var st: Dictionary = save.get("stages", {}).get(sid, {})
		if not bool(st.get("firstClearClaimed", false)):
			continue
		specs.append_array(_pending_specs_of(r, sid, SOURCE_FIRST_CLEAR))

	out = _register_entitlements(save, specs)
	if out.is_empty():
		return out

	# 补登记同样要落盘，否则重启后又丢失。
	if not SaveService.commit(save):
		SaveService.restore(snap)
		GameLog.error(TAG, "旧存档权益回填：登记成功但写入失败（内存已回滚）")
		return []
	GameLog.info(TAG, "旧存档权益回填：新登记 %d 条" % out.size())
	return out


# ============================================================
#  待领取权益：登记 / 查询 / 兑现
# ============================================================

## 权益的唯一发放标识。
##
## 构成：stageId : rewardId : kind : itemId
## 为什么不带序号：同一关的同一条首通奖励对同一件装备**只应发放一次**，
## 带序号反而会让重复登记产生不同的 id，去重就失效了。
static func entitlement_id(stage_id: String, reward_id: String, kind: String, item_id: String) -> String:
	return "%s:%s:%s:%s" % [stage_id, reward_id, kind, item_id]


## 从一条奖励定义中提取「需要实例化系统才能发放」的权益规格。
static func _pending_specs_of(reward: Dictionary, stage_id: String, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reward_id := str(reward.get("id", ""))
	for field: String in PENDING_KINDS.keys():
		var item_id := str(reward.get(field, ""))
		if item_id.is_empty():
			continue
		var kind := str(PENDING_KINDS[field])
		out.append({
			"entitlementId": entitlement_id(stage_id, reward_id, kind, item_id),
			"stageId": stage_id,
			"rewardId": reward_id,
			"kind": kind,
			"itemId": item_id,
			"source": source,
		})
	return out


## 把权益规格登记进存档（幂等：entitlementId 已存在于 pending 或 fulfilled 则跳过）。
##
## 只改内存；调用方负责在同一事务里 commit()。
static func _register_entitlements(
	save: Dictionary,
	specs: Array[Dictionary]
) -> Array[Dictionary]:
	var registered: Array[Dictionary] = []
	if specs.is_empty():
		return registered
	if not save.has(ENTITLEMENTS_KEY):
		save[ENTITLEMENTS_KEY] = {"pending": [], "fulfilled": []}
	var ent: Dictionary = save[ENTITLEMENTS_KEY]
	if not ent.has("pending"):
		ent["pending"] = []
	if not ent.has("fulfilled"):
		ent["fulfilled"] = []

	# 已存在的标识集合（pending + fulfilled 一起算：
	# **已兑现的权益绝不能再回到待领取**，否则会重复发装备）。
	var known := {}
	for e: Variant in ent["pending"]:
		known[str((e as Dictionary).get("entitlementId", ""))] = true
	for e: Variant in ent["fulfilled"]:
		known[str((e as Dictionary).get("entitlementId", ""))] = true

	for spec: Dictionary in specs:
		var eid := str(spec.get("entitlementId", ""))
		if eid.is_empty() or known.has(eid):
			continue
		known[eid] = true
		var entry := spec.duplicate(true)
		entry["registeredAt"] = Time.get_datetime_string_from_system(true)
		(ent["pending"] as Array).append(entry)
		registered.append(entry)
	return registered


## 当前全部待领取权益（副本，调用方改它不影响存档）。
static func pending_entitlements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var save := SaveService.get_current()
	var ent: Dictionary = save.get(ENTITLEMENTS_KEY, {})
	for e: Variant in ent.get("pending", []):
		out.append((e as Dictionary).duplicate(true))
	return out


## 已兑现的权益列表（副本）。
static func fulfilled_entitlements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var save := SaveService.get_current()
	var ent: Dictionary = save.get(ENTITLEMENTS_KEY, {})
	for e: Variant in ent.get("fulfilled", []):
		out.append((e as Dictionary).duplicate(true))
	return out


## 某关卡当前待领取的权益。
static func pending_for_stage(stage_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in pending_entitlements():
		if str(e.get("stageId", "")) == stage_id:
			out.append(e)
	return out


## 按标识查一条待领取权益（不存在返回空字典）。
static func find_pending(entitlement_id_value: String) -> Dictionary:
	for e: Dictionary in pending_entitlements():
		if str(e.get("entitlementId", "")) == entitlement_id_value:
			return e
	return {}


## 把一条待领取权益标记为已兑现（**A0.5 装备系统接入后的兑现入口**）。
##
## instance_id: 兑现产生的实际实例 ID（装备的 instanceId；纪念物可为空串）。
##   V2.1.4 H 章十二：「equipmentId = 固定模板 ID，instanceId = 背包内的独立持有
##   实例 ID；可持有同一模板的多件实例。」因此这里记录的是**实例**，
##   而非模板——同一模板的多条权益应兑现出不同的 instanceId。
##
## 幂等纪律（**重复运行不得复制装备**）：
##   - 权益不在 pending 中（已兑现或从未登记）→ 返回 false，不做任何改动；
##   - 兑现成功 → 从 pending 移入 fulfilled，并写入 instanceId 与兑现时间。
##   因此"兑现两次"第二次必然失败，不可能产出第二件装备。
##
## commit_now: 是否立即落盘（默认 true）。兑现涉及背包变更时，
## 调用方应把背包改动与本次兑现放在**同一次 commit** 里（传 false 后自行 commit）。
static func fulfill_entitlement(
	entitlement_id_value: String,
	instance_id: String = "",
	commit_now: bool = true
) -> bool:
	if entitlement_id_value.is_empty():
		return false
	if not SaveService.ensure_loaded():
		GameLog.error(TAG, "权益兑现失败：存档不可用")
		return false
	var save := SaveService.get_current()
	if save.is_empty():
		return false
	var ent: Dictionary = save.get(ENTITLEMENTS_KEY, {})
	var pending: Array = ent.get("pending", [])
	var idx := -1
	for i: int in range(pending.size()):
		if str((pending[i] as Dictionary).get("entitlementId", "")) == entitlement_id_value:
			idx = i
			break
	if idx < 0:
		# 已在 fulfilled 中，或从未登记 —— 两种都不得再发一份。
		GameLog.warn(TAG, "权益 %s 不在待领取列表中（可能已兑现），拒绝重复发放" % entitlement_id_value)
		return false

	var entry: Dictionary = (pending[idx] as Dictionary).duplicate(true)
	pending.remove_at(idx)
	entry["instanceId"] = instance_id
	entry["fulfilledAt"] = Time.get_datetime_string_from_system(true)
	if not ent.has("fulfilled"):
		ent["fulfilled"] = []
	(ent["fulfilled"] as Array).append(entry)

	if commit_now:
		if not SaveService.commit(save):
			GameLog.error(TAG, "权益 %s 兑现登记写入失败（内存已回滚）" % entitlement_id_value)
			return false
	GameLog.info(TAG, "权益 %s 已兑现（实例 %s）" % [
		entitlement_id_value, instance_id if instance_id != "" else "无"])
	return true


# ============================================================
#  查询
# ============================================================

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
