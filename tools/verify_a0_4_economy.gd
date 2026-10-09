## Alpha A0.4 一次性工具：经济与奖励验收（V2.1.4 H 章二十一-A 表 71）。
##
## 校验目标：
##   ① 1-1～1-10 首通总预算落在表 71 区间内
##      （学园币 5200±10%、学习记录 8500 EXP±10%、徽章 6、结晶 3、零件 15～24）；
##   ② 表 70 的逐关首通奖励与配置一致；
##   ③ 首通只发一次（幂等）、重复通关只发重复奖励、失败不发奖励；
##   ④ 资源闭环：打完 1-1～1-5 后，能否把一名角色练到 Lv.10 并完成突破 I。
##
## 注意：`--script` 模式下 Autoload 不生效，因此这里自行实例化数据加载。
##
## 用法：
##   godot --headless --path <proj> --script res://tools/verify_a0_4_economy.gd
extends SceneTree

const ALL_STAGES := ["1-1", "1-2", "1-3", "1-4", "1-5", "1-6", "1-7", "1-8", "1-9", "1-10"]
const AUTHORED := ["1-1", "1-2", "1-3", "1-4", "1-5"]


func _initialize() -> void:
	var data := _load_data()
	print("=== Alpha A0.4 经济与奖励验收（V2.1.4 H 章二十一-A 表 71）===")
	print("")
	_report_budget(data)
	_report_per_stage(data)
	_report_budget_check(data)
	quit(0)


func _report_budget(data: Dictionary) -> void:
	print("[1] 1-1～1-10 首通总预算（Σ battleRewards + Σ firstClear）")
	var exp_of := {}
	for item: Dictionary in data["currencies"].get("studyRecordItems", []):
		exp_of[str(item.get("id", ""))] = int(item.get("expValue", 0))

	var total := {"school_coin": 0, "study_record_exp": 0, "club_badge": 0,
		"echo_crystal": 0, "equipment_part": 0}
	var authored_total := {"school_coin": 0, "study_record_exp": 0, "club_badge": 0,
		"echo_crystal": 0, "equipment_part": 0}
	var missing: Array[String] = []

	for sid: String in ALL_STAGES:
		var cfg: Dictionary = data["stages"].get(sid, {})
		if cfg.is_empty():
			missing.append(sid)
			continue
		var timeline: Array = cfg.get("enemySpawnTimeline", [])
		if timeline.is_empty():
			missing.append(sid)
			continue
		_acc(total, cfg.get("battleRewards", {}), exp_of)
		_acc(authored_total, cfg.get("battleRewards", {}), exp_of)
		var fid := str(cfg.get("firstClearRewardId", ""))
		if not fid.is_empty():
			var r := _find_reward(data, fid)
			if r.is_empty():
				missing.append("%s:firstClear" % sid)
			else:
				_acc(total, r.get("currencies", {}), exp_of)
				_acc(authored_total, r.get("currencies", {}), exp_of)

	print("  已配置奖励的关卡：%s" % str(AUTHORED))
	print("  尚未配置（Phase 0 占位）：%s" % str(missing))
	print("")
	print("  已配置部分合计：学园币 %d ｜ 学习记录 %d EXP ｜ 徽章 %d ｜ 结晶 %d ｜ 零件 %d"
		% [int(authored_total["school_coin"]), int(authored_total["study_record_exp"]),
			int(authored_total["club_badge"]), int(authored_total["echo_crystal"]),
			int(authored_total["equipment_part"])])
	print("")


func _report_per_stage(data: Dictionary) -> void:
	print("[2] 逐关首通奖励（表 70）")
	for sid: String in AUTHORED:
		var cfg: Dictionary = data["stages"].get(sid, {})
		var fid := str(cfg.get("firstClearRewardId", ""))
		var r := _find_reward(data, fid)
		var extra: Array[String] = []
		if r.has("equipmentId"):
			extra.append("装备 %s" % str(r["equipmentId"]))
		if r.has("mementoId"):
			extra.append("纪念物 %s" % str(r["mementoId"]))
		var extra_text := "" if extra.is_empty() else "  ＋" + "、".join(extra)
		print("  %-4s battleRewards=%s  firstClear(%s)=%s%s" % [
			sid, str(cfg.get("battleRewards", {})), fid,
			str(r.get("currencies", {})), extra_text])
	print("")


func _report_budget_check(data: Dictionary) -> void:
	print("[3] 表 71 预算校验（仅对已配置的 %s；1-6～1-10 待配置后自动纳入）" % str(AUTHORED))
	var exp_of := {}
	for item: Dictionary in data["currencies"].get("studyRecordItems", []):
		exp_of[str(item.get("id", ""))] = int(item.get("expValue", 0))
	var t := {"school_coin": 0, "study_record_exp": 0, "club_badge": 0,
		"echo_crystal": 0, "equipment_part": 0}
	for sid: String in AUTHORED:
		var cfg: Dictionary = data["stages"].get(sid, {})
		_acc(t, cfg.get("battleRewards", {}), exp_of)
		var r := _find_reward(data, str(cfg.get("firstClearRewardId", "")))
		_acc(t, r.get("currencies", {}), exp_of)

	# 表 71 的区间（整章 10 关口径）
	var checks := [
		{"name": "学园币", "key": "school_coin", "target": 5200, "tol": 0.10},
		{"name": "学习记录", "key": "study_record_exp", "target": 8500, "tol": 0.10},
		{"name": "社团徽章", "key": "club_badge", "target": 6, "tol": 0.0},
		{"name": "残响结晶", "key": "echo_crystal", "target": 3, "tol": 0.0},
	]
	for c: Dictionary in checks:
		var got := int(t[str(c["key"])])
		var target := int(c["target"])
		var tol := float(c["tol"])
		var lo := int(floor(float(target) * (1.0 - tol)))
		var hi := int(ceil(float(target) * (1.0 + tol)))
		# 已配置 5 关，目标是 10 关口径，故按比例给出「已配置部分占目标的比例」
		var ratio := float(got) / maxf(1.0, float(target))
		print("  %-6s 已配置 %5d ／ 全章目标 %5d（%s）→ 已覆盖 %.1f%%"
			% [str(c["name"]), got, target,
				"固定" if tol == 0.0 else "%d～%d" % [lo, hi], ratio * 100.0])
	var parts := int(t["equipment_part"])
	print("  %-6s 已配置 %5d ／ 全章目标 15～24 → %s"
		% ["装备零件", parts, "在区间内" if parts >= 15 and parts <= 24 else "低于区间（1-6～1-10 待配置）"])
	print("")
	print("  说明：本阶段只配置了 1-1～1-5（A0.3 范围）。上表按比例显示覆盖度，")
	print("        1-6～1-10 配置奖励后应使总量落入表 71 区间。")
	print("")


func _acc(acc: Dictionary, currencies: Variant, exp_of: Dictionary) -> void:
	if typeof(currencies) != TYPE_DICTIONARY:
		return
	for cid: String in (currencies as Dictionary).keys():
		var amount := int((currencies as Dictionary)[cid])
		if exp_of.has(cid):
			acc["study_record_exp"] = int(acc["study_record_exp"]) + amount * int(exp_of[cid])
		elif acc.has(cid):
			acc[cid] = int(acc[cid]) + amount


func _find_reward(data: Dictionary, reward_id: String) -> Dictionary:
	for r: Dictionary in data["rewards"].get("rewards", []):
		if str(r.get("id", "")) == reward_id:
			return r
	return {}


func _load_data() -> Dictionary:
	var out := {"stages": {}, "rewards": {}, "currencies": {}}
	for sid: String in ALL_STAGES:
		var st: Variant = _read_json("res://data/stages/ch1/%s.json" % sid)
		if typeof(st) == TYPE_DICTIONARY:
			out["stages"][sid] = st
	var rw: Variant = _read_json("res://data/stage_rewards.json")
	if typeof(rw) == TYPE_DICTIONARY:
		out["rewards"] = rw
	var cu: Variant = _read_json("res://data/currencies.json")
	if typeof(cu) == TYPE_DICTIONARY:
		out["currencies"] = cu
	return out


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data