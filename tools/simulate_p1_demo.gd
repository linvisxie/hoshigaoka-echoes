## P1.0 一次性工具：Prototype 演示关平衡验证（多战术对照）。
##
## 目的：在写表现层之前，先用**领域层**验证：
##   ① 演示关存在稳定通关路线，且总时长落在 V2.1.4 D-30 的 3～5 分钟目标内；
##   ② 通关不依赖唯一硬编码操作——多种合法战术都能通关（本轮指令 三·7）；
##   ③ 失败可解释——不部署/乱部署会输，且原因（漏怪/核心归零）清晰；
##   ④ 装甲残响体确实需要阻挡（高防减伤成立）。
##
## 注意：`--script` 模式下 **Autoload 不生效**，因此这里自行实例化数据加载。
##
## 用法：
##   godot --headless --path <proj> --script res://tools/simulate_p1_demo.gd
extends SceneTree

const STAGE_ID := "p1_0_demo"
const STAGE_PATH := "res://data/stages/prototype/p1_0_demo.json"

## 每个战术 = 按时间排序的行动列表。
## action: "deploy" | "withdraw"
## 时间以战斗逻辑时间为准（秒）。
const TACTICS := {
	"A. 不部署（基线对照，应失败）": [],

	"B. 稳定通关解（锚点 col3 + 治疗 lane0 + 远程按波换线）": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "ogawa_yui", "col": 2, "lane": 0},
		{"t": 26.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		{"t": 118.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 138.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 2},
		{"t": 225.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 245.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
	],

	"C. 替代解：远程守 lane2 后转 lane0（放弃上段而非下段）": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "ogawa_yui", "col": 2, "lane": 0},
		{"t": 26.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		{"t": 118.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 138.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 2},
		{"t": 192.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 212.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		{"t": 226.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 246.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
	],

	"D. 结构不同的合法解：治疗挂主路 (2,1)，远程按波换线": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "ogawa_yui", "col": 2, "lane": 1},
		{"t": 26.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		{"t": 118.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 138.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 2},
		{"t": 225.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 245.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
	],

	"D2. 结构不同的合法解：治疗挂下路 (2,2)，远程全程守主路": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "ogawa_yui", "col": 2, "lane": 2},
		{"t": 26.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		{"t": 118.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 138.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 2},
		{"t": 225.0, "a": "withdraw", "c": "kamiya_yuma"},
		{"t": 245.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
	],

	"E. 从不撤退换线（远程全程守 lane0，应失败）": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "ogawa_yui", "col": 2, "lane": 0},
		{"t": 26.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
	],

	"F. 只部署前线（无远程/无治疗，应失败）": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
	],

	"G. 三人全挤中段 col0（有治疗但无副路覆盖，应失败）": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 0, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "kamiya_yuma", "col": 0, "lane": 0},
		{"t": 26.5, "a": "deploy", "c": "ogawa_yui", "col": 0, "lane": 2},
	],

	"H. 三职业齐备但锚点过前（col5，应失败）": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 5, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "ogawa_yui", "col": 2, "lane": 0},
		{"t": 26.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
	],

	"I. 完全被动：三职业齐备但不换线不撤退（应失败）": [
		{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		{"t": 14.5, "a": "deploy", "c": "ogawa_yui", "col": 2, "lane": 0},
		{"t": 26.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
	],
}

const MAX_SIM_SECONDS := 900.0


func _initialize() -> void:
	var data := _load_data()
	var stage: Dictionary = data["stage"]
	if stage.is_empty():
		printerr("无法加载 %s" % STAGE_PATH)
		quit(1)
		return

	print("=== P1.0 Prototype 演示关平衡验证 ===")
	print("关卡: %s   核心 HP: %d   开局 AP: %d   AP 回复: %s/s"
		% [stage.get("stageId", "?"), int(stage.get("coreHp", 0)),
			int(stage.get("startingAp", 0)), str(stage.get("apRegen", 0))])
	print("可部署角色: %s" % str(stage.get("availableCharacters", [])))
	var timeline: Array = stage.get("enemySpawnTimeline", [])
	print("计划出怪: %d 只   末次出怪: %.0fs   波次: %d"
		% [timeline.size(), _last_spawn_time(timeline),
			(stage.get("waves", []) as Array).size()])
	var counts := {}
	for e: Variant in timeline:
		var id := str((e as Dictionary).get("enemy", ""))
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array[String] = []
	for k: String in counts.keys():
		parts.append("%s×%d" % [k, int(counts[k])])
	print("敌人构成: %s" % ", ".join(parts))
	print("")

	for label: String in TACTICS.keys():
		_run_case(label, TACTICS[label], data)

	quit(0)


func _last_spawn_time(timeline: Array) -> float:
	var last := 0.0
	for e: Variant in timeline:
		last = maxf(last, float((e as Dictionary).get("time", 0.0)))
	return last


func _load_data() -> Dictionary:
	var out := {
		"stage": {}, "enemies": {}, "characters": {}, "combat": {}, "grid": null,
	}
	var stage: Variant = _read_json(STAGE_PATH)
	if typeof(stage) == TYPE_DICTIONARY:
		out["stage"] = stage

	var enemies: Variant = _read_json("res://data/enemies.json")
	if typeof(enemies) == TYPE_DICTIONARY:
		for e: Dictionary in (enemies as Dictionary).get("enemies", []):
			out["enemies"][str(e.get("id", ""))] = e

	var chars: Variant = _read_json("res://data/characters.json")
	if typeof(chars) == TYPE_DICTIONARY:
		for c: Dictionary in (chars as Dictionary).get("characters", []):
			out["characters"][str(c.get("id", ""))] = c

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


func _run_case(label: String, actions: Array, data: Dictionary) -> void:
	var session := BattleSession.new()
	var errs := session.setup(
		data["stage"], data["enemies"], data["grid"], data["characters"], data["combat"])
	if not errs.is_empty():
		print("[%s] 构建失败: %s" % [label, str(errs)])
		session.free()
		return

	var step := StageRuntime.LOGIC_STEP_SECONDS
	var t := 0.0
	var cursor := 0
	var action_log: Array[String] = []
	var rejected: Array[String] = []

	while session.is_running() and t < MAX_SIM_SECONDS:
		# 到点执行战术动作（用**同一逻辑时间**判定，保证可复现）
		while cursor < actions.size() and float((actions[cursor] as Dictionary)["t"]) <= t:
			var a: Dictionary = actions[cursor]
			cursor += 1
			if str(a["a"]) == "deploy":
				var r := session.deploy_character(
					str(a["c"]), int(a["col"]), int(a["lane"]))
				if r.ok:
					action_log.append("t=%.1f 部署 %s @(col%d,lane%d) -%dAP"
						% [t, str(a["c"]), int(a["col"]), int(a["lane"]), r.cost])
				else:
					rejected.append("t=%.1f 部署 %s 被拒: %s"
						% [t, str(a["c"]), r.reason_text()])
			else:
				var rr := session.withdraw_character_by_id(str(a["c"]))
				if rr.ok:
					action_log.append("t=%.1f 撤退 %s 返还 %dAP 冷却 %.0fs"
						% [t, str(a["c"]), rr.refund_granted, rr.cooldown])
				else:
					rejected.append("t=%.1f 撤退 %s 被拒: %s"
						% [t, str(a["c"]), rr.reason_text()])
		session.tick(step)
		t += step

	var s := session.stage
	print("[%s]" % label)
	print("  结果=%s  逻辑用时=%.1fs  核心=%d/%d  生成=%d/%d  Wave=%d/%d"
		% [BattleTypes.outcome_name(session.outcome), s.elapsed_seconds,
			s.core_hp, s.core_hp_max, s.spawned_enemy_count(), s.planned_enemy_count(),
			s.current_wave_number(), s.total_wave_count()])
	print("  击杀=%d  漏怪=%d  失能=%d  撤退=%d  治疗量=%d  最终AP=%d"
		% [s.enemies_killed, s.reached_core_count, s.characters_lost,
			s.retreat_count, s.total_healing_done, s.ap])
	# 漏怪明细：哪一波、哪条线、什么敌人 —— 用于判断「失败原因是否可解释」
	var leaks: Array[String] = []
	for r: Dictionary in s.removals:
		if int(r.get("kind", -1)) == StageRuntime.Removal.REACHED_CORE:
			leaks.append("%s@lane%d" % [str(r.get("enemyId", "?")), int(r.get("lane", -1))])
	if not leaks.is_empty():
		print("  漏怪明细: %s" % " ｜ ".join(leaks))
	var role_hp: Array[String] = []
	for c: CharacterRuntime in s.character_instances:
		role_hp.append("%s %d/%d" % [c.display_name, maxi(0, c.hp), c.max_hp])
	if not role_hp.is_empty():
		print("  角色: %s" % " ｜ ".join(role_hp))
	for line: String in action_log:
		print("    · %s" % line)
	for line: String in rejected:
		print("    × %s" % line)
	print("")
	session.free()
