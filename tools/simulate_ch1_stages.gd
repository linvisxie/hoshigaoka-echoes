## Alpha A0.3 一次性工具：首章 1-2～1-5 平衡验证。
##
## 目标（V2.1.4 G 章表 54 垂直切片闸门）：
##   ① 每关至少存在 1 个稳定通关解（核心剩余 ≥ 1）；
##   ② 「不部署」必须失败（否则关卡没有压力）；
##   ③ **1-5 必须实测出「雨宫澪 + 神谷悠真、无治疗」的通关解**。
##
## 注意：`--script` 模式下 Autoload 不生效，因此这里自行实例化数据加载。
##
## 用法：
##   godot --headless --path <proj> --script res://tools/simulate_ch1_stages.gd
extends SceneTree

const STAGE_DIR := "res://data/stages/ch1/"
const STAGES := ["1-1", "1-2", "1-3", "1-4", "1-5"]
const MAX_SIM_SECONDS := 900.0

## 每关的候选战术。动作按逻辑时间触发，保证确定性。
## 部署位置原则（与角色射程/阻挡数一致）：
##   雨宫澪（前线，射程 1.25 格、blockCount 2）→ 中段 col3 作锚点
##   神谷悠真（远程，射程 4.0 格、blockCount 0）→ 中段 col1 覆盖整条线
const TACTICS := {
	"1-1": {
		"A. 不部署（应失败）": [],
		"B. 中段 col3 锚点（稳定解）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		],
		"C. 中段 col1（靠后）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 1, "lane": 1},
		],
	},
	"1-2": {
		"A. 不部署（应失败）": [],
		"B. 中段 col3 锚点（稳定解）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		],
		"C. 上段 col3（守疾走来路）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 0},
		],
	},
	"1-3": {
		"A. 不部署（应失败）": [],
		"B. 澪 col3 中段 + 悠真 col1 中段（稳定解）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
		],
		"C. 只放澪（对照，应更差）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		],
		"D. 悠真放 col3（射程未覆盖整线，对照）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 3, "lane": 1},
		],
	},
	"1-4": {
		"A. 不部署（应失败）": [],
		"B. 澪 col3 中段 + 悠真 col1 中段（稳定解，集火）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
		],
		"C. 只放澪（单挑装甲，对照）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		],
		"D. 悠真分兵上段（对照，中段输出不足）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		],
	},
	"1-5": {
		"A. 不部署（应失败）": [],
		"B. ★垂直切片解：澪 col3 中段 + 悠真 col1 中段（无治疗）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
		],
		"C. 只放澪（无远程，对照）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		],
		"D. 澪 col4 更靠前（对照，承伤更早）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 4, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
		],
		"E. 悠真分兵上段（对照，中段集火不足）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		],
	},
}


func _initialize() -> void:
	var data := _load_data()
	print("=== Alpha A0.3 首章 1-1～1-5 平衡验证 ===")
	print("")
	for sid: String in STAGES:
		var stage: Dictionary = data["stages"].get(sid, {})
		if stage.is_empty():
			print("[%s] **无法加载**" % sid)
			continue
		_verify_stage(sid, stage, data)
	quit(0)


func _verify_stage(sid: String, stage: Dictionary, data: Dictionary) -> void:
	var timeline: Array = stage.get("enemySpawnTimeline", [])
	var counts := {}
	for e: Variant in timeline:
		var id := str((e as Dictionary).get("enemy", ""))
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array[String] = []
	for k: String in counts.keys():
		parts.append("%s×%d" % [k, int(counts[k])])
	print("[%s] 核心 %d / 开局 AP %d / 可用角色 %s / %d 波 / %d 只（%s）" % [
		sid, int(stage.get("coreHp", 0)), int(stage.get("startingAp", 0)),
		str(stage.get("availableCharacters", [])),
		(stage.get("waves", []) as Array).size(), timeline.size(), ", ".join(parts)])

	var tactics: Dictionary = TACTICS.get(sid, {})
	for label: String in tactics.keys():
		_run_case(sid, label, tactics[label], stage, data)
	print("")


func _run_case(sid: String, label: String, actions: Array, stage: Dictionary, data: Dictionary) -> void:
	var session := BattleSession.new()
	var errs := session.setup(stage, data["enemies"], data["grid"], data["characters"], data["combat"])
	if not errs.is_empty():
		print("  [%s] 构建失败：%s" % [label, str(errs)])
		session.free()
		return

	var step := StageRuntime.LOGIC_STEP_SECONDS
	var t := 0.0
	var cursor := 0
	while session.is_running() and t < MAX_SIM_SECONDS:
		while cursor < actions.size() and float((actions[cursor] as Dictionary)["t"]) <= t:
			var a: Dictionary = actions[cursor]
			cursor += 1
			session.deploy_character(str(a["c"]), int(a["col"]), int(a["lane"]))
		session.tick(step)
		t += step

	var s := session.stage
	var roles: Array[String] = []
	for c: CharacterRuntime in s.character_instances:
		roles.append("%s %d/%d" % [c.display_name, maxi(0, c.hp), c.max_hp])
	print("  %-52s 结果=%s 用时=%5.1fs 核心=%d/%d 击杀=%2d 漏怪=%d 失能=%d  %s" % [
		label, BattleTypes.outcome_name(session.outcome), s.elapsed_seconds,
		s.core_hp, s.core_hp_max, s.enemies_killed, s.reached_core_count,
		s.characters_lost, " ｜ ".join(roles)])
	session.free()


func _load_data() -> Dictionary:
	var out := {"stages": {}, "enemies": {}, "characters": {}, "combat": {}, "grid": null}
	for sid: String in STAGES:
		var st: Variant = _read_json("%s%s.json" % [STAGE_DIR, sid])
		if typeof(st) == TYPE_DICTIONARY:
			out["stages"][sid] = st

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
