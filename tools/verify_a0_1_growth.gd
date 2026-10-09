## Alpha A0.1 一次性工具：角色成长闭环无头验证。
##
## 验证「战斗 → 结算奖励 → 升级 → 面板提升 → 影响战斗」这条链真的通了，
## 而不是各部分单独存在。同时产出可直接写进验收报告的实测数字。
##
## 注意：`--script` 模式下 Autoload 不生效，因此这里自行实例化数据加载与存档。
##
## 用法：
##   godot --headless --path <proj> --script res://tools/verify_a0_1_growth.gd
extends SceneTree

const DEMO_PATH := "res://data/stages/prototype/p1_0_demo.json"
const RECORD_SHORT := "study_record_short"


func _initialize() -> void:
	var data := _load_data()
	var growth: Dictionary = data["growth"]
	if growth.is_empty():
		printerr("character_growth.json 无法加载")
		quit(1)
		return

	print("=== Alpha A0.1 角色成长闭环验证 ===")
	print("")

	_verify_data(growth, data)
	_verify_curve(growth)
	_verify_level_stats(data)
	_verify_battle_rewards(data)
	_verify_battle_impact(data)

	quit(0)


# ---------- 数据 ----------

func _verify_data(growth: Dictionary, data: Dictionary) -> void:
	print("[1] 成长数据完整性")
	var rules: Dictionary = growth.get("globalRules", {})
	print("  maxLevel = %d" % int(rules.get("maxLevel", 0)))
	print("  breakthroughLevels = %s" % str(rules.get("breakthroughLevels", [])))
	print("  levelCapByBreakthrough = %s" % str(rules.get("levelCapByBreakthrough", {})))
	var profiles: Array = growth.get("growthProfiles", [])
	for p: Dictionary in profiles:
		print("  档位 %s：%s" % [str(p.get("id", "")), str(p.get("perLevel", {}))])
	var bts: Array = growth.get("breakthroughs", [])
	for b: Dictionary in bts:
		print("  突破 %d（需 Lv.%d）：成本 %s" % [
			int(b.get("level", 0)), int(b.get("requiredLevel", 0)), str(b.get("cost", {}))])
	var currencies: Array = data["currencies"].get("currencies", [])
	print("  五类资源：%s" % str(currencies.map(func(c: Dictionary) -> String:
		return "%s(%s)" % [str(c.get("name", "")), str(c.get("id", ""))])))
	print("  学习记录三档：%s" % str(data["currencies"].get("studyRecordItems", [])))
	print("")


func _verify_curve(growth: Dictionary) -> void:
	print("[2] 经验曲线（V2.1.4 H 章四 表 57：Lv.1→10 累计 2520）")
	var table: Dictionary = growth.get("expTable", {})
	var cum := 0
	var parts: Array[String] = []
	for lv: int in range(1, 10):
		var v := int(table.get(str(lv), 0))
		cum += v
		parts.append("%d" % v)
	print("  Lv.1→10 逐级：%s" % "/".join(parts))
	print("  累计 = %d（规格 2520，%s）" % [cum, "一致" if cum == 2520 else "**不一致**"])
	print("")


# ---------- 成长计算 ----------

func _verify_level_stats(data: Dictionary) -> void:
	print("[3] 面板成长（baseStats + perLevel × (level-1)，H 章三十七）")
	var growth: Dictionary = data["growth"]
	var profiles: Array = growth.get("growthProfiles", [])
	var per: Dictionary = (profiles[0] as Dictionary).get("perLevel", {})
	for c: Dictionary in data["char_list"]:
		var cid := str(c.get("id", ""))
		var base: Dictionary = (c.get("baseStats", {}) as Dictionary).duplicate(true)
		if c.has("healPower"):
			base["healPower"] = int(c.get("healPower", 0))
		var lv1 := _stats_at(base, per, 1)
		var lv11 := _stats_at(base, per, 11)
		var lv50 := _stats_at(base, per, 50)
		print("  %s（%s）" % [str(c.get("name", cid)), cid])
		print("    Lv.1  %s" % _fmt(lv1))
		print("    Lv.11 %s" % _fmt(lv11))
		print("    Lv.50 %s   HP 倍率 %.2f×（H 章三十一要求「不应达到几十倍」）"
			% [_fmt(lv50), float(lv50.get("hp", 0)) / maxf(1.0, float(lv1.get("hp", 0)))])
	print("")


func _stats_at(base: Dictionary, per: Dictionary, level: int) -> Dictionary:
	var out := {}
	var steps := float(level - 1)
	# 与 CharacterProgress.compute_stats() 同一规则：base <= 0 表示该角色不使用该属性
	for k: String in ["hp", "attack", "defense", "healPower"]:
		var b := float(base.get(k, 0))
		if b <= 0.0:
			continue
		out[k] = int(round(b + float(per.get(k, 0.0)) * steps))
	return out


func _fmt(s: Dictionary) -> String:
	var parts: Array[String] = []
	for k: String in ["hp", "attack", "defense", "healPower"]:
		if s.has(k):
			parts.append("%s %d" % [k, int(s[k])])
	return "  ".join(parts)


# ---------- 结算奖励 ----------

func _verify_battle_rewards(data: Dictionary) -> void:
	print("[4] 演示关结算奖励（H 章十八/十九：即时战斗奖励）")
	var rewards: Dictionary = data["stage"].get("battleRewards", {})
	if rewards.is_empty():
		print("  **未配置 battleRewards**")
		print("")
		return
	var exp_total := 0
	for cid: String in rewards.keys():
		var amount := int(rewards[cid])
		print("  %s ×%d" % [cid, amount])
		for item: Dictionary in data["currencies"].get("studyRecordItems", []):
			if str(item.get("id", "")) == cid:
				exp_total += amount * int(item.get("expValue", 0))
	print("  学习记录折算经验 = %d EXP（表 69 区间 100～300：%s）"
		% [exp_total, "在区间内" if exp_total >= 100 and exp_total <= 300 else "**越界**"])
	print("")


# ---------- 战斗影响 ----------

func _verify_battle_impact(data: Dictionary) -> void:
	print("[5] 等级是否真的影响战斗（同一战术、Lv.1 vs Lv.20）")
	var growth: Dictionary = data["growth"]
	var profiles: Array = growth.get("growthProfiles", [])
	var per: Dictionary = (profiles[0] as Dictionary).get("perLevel", {})

	# Lv.1 与 Lv.20 两套面板，各跑一次战术 B
	for level: int in [1, 20]:
		var stats := {}
		for c: Dictionary in data["char_list"]:
			var cid := str(c.get("id", ""))
			var base: Dictionary = (c.get("baseStats", {}) as Dictionary).duplicate(true)
			if c.has("healPower"):
				base["healPower"] = int(c.get("healPower", 0))
			stats[cid] = _stats_at(base, per, level)
		var r := _run_tactic_b(data, stats)
		print("  Lv.%d：结果=%s  用时=%.1fs  核心=%d/%d  击杀=%d  漏怪=%d  治疗=%d"
			% [level, str(r["outcome"]), float(r["elapsed"]), int(r["core"]), int(r["coreMax"]),
				int(r["kills"]), int(r["leaked"]), int(r["healed"])])
	print("  → 若高等级下核心剩余更高 / 漏怪更少，说明等级确实传导进了战斗。")
	print("")


## 与 tools/simulate_p1_demo.gd 的战术 B 完全一致（同一关卡、同一时序），
## 只替换角色面板，因此差异只能来自成长。
func _run_tactic_b(data: Dictionary, level_stats: Dictionary) -> Dictionary:
	var session := BattleSession.new()
	var errs := session.setup(data["stage"], data["enemies"], data["grid"],
		data["characters"], data["combat"])
	if not errs.is_empty():
		session.free()
		return {"outcome": "构建失败: %s" % str(errs), "elapsed": 0.0, "core": 0,
			"coreMax": 0, "kills": 0, "leaked": 0, "healed": 0}
	session.stage.set_character_level_stats(level_stats)

	var actions := [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "ogawa_yui", "col": 2, "lane": 0},
		{"t": 26.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		{"t": 118.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 138.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 2},
		{"t": 225.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 245.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
	]
	var step := StageRuntime.LOGIC_STEP_SECONDS
	var t := 0.0
	var cursor := 0
	while session.is_running() and t < 900.0:
		while cursor < actions.size() and float(actions[cursor]["t"]) <= t:
			var a: Dictionary = actions[cursor]
			cursor += 1
			if str(a["a"]) == "deploy":
				session.deploy_character(str(a["c"]), int(a["col"]), int(a["lane"]))
			else:
				session.withdraw_character_by_id(str(a["c"]))
		session.tick(step)
		t += step
	var s := session.stage
	var out := {
		"outcome": BattleTypes.outcome_name(session.outcome),
		"elapsed": s.elapsed_seconds,
		"core": s.core_hp, "coreMax": s.core_hp_max,
		"kills": s.enemies_killed, "leaked": s.reached_core_count,
		"healed": s.total_healing_done,
	}
	session.free()
	return out


# ---------- 数据加载 ----------

func _load_data() -> Dictionary:
	var out := {
		"stage": {}, "enemies": {}, "characters": {}, "combat": {}, "grid": null,
		"growth": {}, "currencies": {}, "char_list": [],
	}
	var stage: Variant = _read_json(DEMO_PATH)
	if typeof(stage) == TYPE_DICTIONARY:
		out["stage"] = stage

	var enemies: Variant = _read_json("res://data/enemies.json")
	if typeof(enemies) == TYPE_DICTIONARY:
		for e: Dictionary in (enemies as Dictionary).get("enemies", []):
			out["enemies"][str(e.get("id", ""))] = e

	# 角色：既保留有序列表（按 id 遍历用于展示），也建 id 索引（战斗侧使用）
	var char_list: Array = []
	var char_table := {}
	var chars: Variant = _read_json("res://data/characters.json")
	if typeof(chars) == TYPE_DICTIONARY:
		for c: Dictionary in (chars as Dictionary).get("characters", []):
			char_list.append(c)
			char_table[str(c.get("id", ""))] = c
	out["char_list"] = char_list
	out["characters"] = char_table

	var growth: Variant = _read_json("res://data/character_growth.json")
	if typeof(growth) == TYPE_DICTIONARY:
		out["growth"] = growth

	var cur: Variant = _read_json("res://data/currencies.json")
	if typeof(cur) == TYPE_DICTIONARY:
		out["currencies"] = cur

	var balance: Variant = _read_json("res://data/balance.json")
	var layout := {}
	if typeof(balance) == TYPE_DICTIONARY:
		var b: Dictionary = balance
		out["combat"] = b.get("combat", {})
		layout = b.get("layout", {})
	out["grid"] = BattleGrid.from_layout(layout)
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
