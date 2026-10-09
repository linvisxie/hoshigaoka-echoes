## Alpha A0.2/A0.3 回填设计工具：1-3 试卷飞灵与 1-5 监考者的关卡重设计验证。
##
## 目的：为「把 1-3 的临时敌人组合换回试卷飞灵」「把 1-5 的装甲替身换回监考者精英」
## 提供**可复现的数值依据**，而不是纸面推演。
##
## 校验目标（V2.1.4 表 54 垂直切片 + G-十一 候选平衡参数）：
##   ① 每关至少存在 1 个稳定通关解（核心剩余 ≥ 1）；
##   ② 「不部署」必须失败；
##   ③ **1-5 必须在「雨宫澪 + 神谷悠真、无治疗」下可通关**（表 54 硬性条件）；
##   ④ 1-5 同屏不得要求两个永久前线（非中段敌人 ≤ 1）；
##   ⑤ 1-3 必须体现「试卷飞灵逼玩家使用远程」——只放澪应显著更差或失败。
##
## 注意：`--script` 模式下 Autoload 不生效，故本工具自行实例化数据加载
## （与 tools/simulate_ch1_stages.gd 同一写法）。
##
## 用法：
##   godot --headless --path . --script res://tools/design_a0_2_stages.gd
extends SceneTree

const STAGE_DIR := "res://data/stages/ch1/"
const MAX_SIM_SECONDS := 900.0

## 候选关卡设计（**本工具只做验证，不写盘**；写盘由主线按验证结果执行）
const CANDIDATES := {
	"1-3": {
		"coreHp": 3,
		"availableCharacters": ["amamiya_mio", "kamiya_yuma"],
		"timeline": [
			# Wave 1 热身：中段普通 ×3（沿用既有节奏）
			{"time": 4.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
			{"time": 11.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
			{"time": 18.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
			# Wave 2 引入试卷飞灵：它停在 x=5 打澪，澪够不到 → 必须上悠真
			{"time": 34.0, "lane": 1, "enemy": "echo_exam_sheet", "wave": 2},
			{"time": 41.0, "lane": 1, "enemy": "echo_normal", "wave": 2},
			{"time": 50.0, "lane": 1, "enemy": "echo_runner", "wave": 2},
			# Wave 3 双飞灵 + 普通：逼玩家确认悠真的位置能覆盖 x=5
			{"time": 66.0, "lane": 1, "enemy": "echo_exam_sheet", "wave": 3},
			{"time": 70.0, "lane": 1, "enemy": "echo_exam_sheet", "wave": 3},
			{"time": 82.0, "lane": 1, "enemy": "echo_normal", "wave": 3},
			{"time": 92.0, "lane": 2, "enemy": "echo_normal", "wave": 3},
			# Wave 4 最终波：飞灵 + 疾走 + 普通
			{"time": 108.0, "lane": 1, "enemy": "echo_exam_sheet", "wave": 4},
			{"time": 116.0, "lane": 1, "enemy": "echo_runner", "wave": 4},
			{"time": 124.0, "lane": 1, "enemy": "echo_runner", "wave": 4},
			{"time": 134.0, "lane": 1, "enemy": "echo_normal", "wave": 4},
		],
	},
	"1-5": {
		"coreHp": 3,
		"availableCharacters": ["amamiya_mio", "kamiya_yuma"],
		"timeline": [
			# Wave 1 预热
			{"time": 4.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
			{"time": 12.0, "lane": 1, "enemy": "echo_runner", "wave": 1},
			{"time": 21.0, "lane": 1, "enemy": "echo_normal", "wave": 1},
			# Wave 2 第一次精英接触：监考者（F-十九「第一场精英战」）
			{"time": 40.0, "lane": 1, "enemy": "echo_invigilator", "wave": 2},
			# Wave 3 喘息 + 取舍题（上段 1 只普通，表 54 非中段 ≤ 1）
			{"time": 74.0, "lane": 1, "enemy": "echo_runner", "wave": 3},
			{"time": 88.0, "lane": 0, "enemy": "echo_normal", "wave": 3},
			# Wave 4 复习 1-4 的集火（装甲），无精英
			{"time": 110.0, "lane": 1, "enemy": "echo_armored", "wave": 4},
			# Wave 5 最终波：监考者回归（「最后一场考试」）
			# 刻意**不再追加疾走小怪**：精英自身的承伤压力已足够构成最终波，
			# 额外小怪只贡献"削血"而不增加教学价值，且会把 Lv.1 的最差情形
			# 压到 25/1000（过薄，不利于"可学会"）。移速 +30% 的「时间到」
			# 在最终波依然可被玩家感知。
			{"time": 146.0, "lane": 1, "enemy": "echo_invigilator", "wave": 5},
		],
	},
}

## 候选战术（动作按逻辑时间触发，保证确定性）
##
## **等级维度**：表 54 的 1-5 验收条件是「推荐 Lv.5～7」，因此本工具对同一战术
## 分别以 Lv.1（无成长）与 Lv.6（推荐区间中点）各跑一次，用于回答
## 「该关的难度是按推荐等级设计的吗」以及「Lv.1 是否仍能通过」。
const TACTICS := {
	"1-3": {
		"A. 不部署（应失败）": [],
		"B. ★澪 col3 中段 + 悠真 col1 中段（应通关）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
		],
		"C. 只放澪（对照：够不到飞灵，应显著更差）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		],
		"D. 悠真放 col0（射程刚好差 1 格，够不到 x=5 的飞灵）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 0, "lane": 1},
		],
		"E. 悠真放 col2（射程覆盖 x=5）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 2, "lane": 1},
		],
	},
	"1-5": {
		"A. 不部署（应失败）": [],
		"B. ★表54 垂直切片：澪 col3 + 悠真 col1（无治疗，应通关）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
		],
		"C. 只放澪（无远程，对照）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
		],
		"D. 澪 col4 更靠前（对照：更早承伤）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 4, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 1},
		],
		"E. 悠真分兵上段（对照：中段集火不足）": [
			{"t": 0.5, "a": "deploy", "c": "amamiya_mio", "col": 3, "lane": 1},
			{"t": 12.5, "a": "deploy", "c": "kamiya_yuma", "col": 1, "lane": 0},
		],
	},
}


func _initialize() -> void:
	var data := _load_data()
	print("=== Alpha A0.2/A0.3 回填设计验证：1-3 试卷飞灵 / 1-5 监考者 ===")
	print("")
	for sid: String in ["1-3", "1-5"]:
		_verify_stage(sid, data)
	quit(0)


func _verify_stage(sid: String, data: Dictionary) -> void:
	var cand: Dictionary = CANDIDATES[sid]
	var timeline: Array = cand["timeline"]
	var counts := {}
	for e: Variant in timeline:
		var id := str((e as Dictionary).get("enemy", ""))
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array[String] = []
	for k: String in counts.keys():
		parts.append("%s×%d" % [k, int(counts[k])])
	print("[%s] 核心 %d ｜ 可用角色 %s ｜ %d 只（%s）"
		% [sid, int(cand["coreHp"]), str(cand["availableCharacters"]),
			timeline.size(), ", ".join(parts)])

	# 非中段敌人数量（表 54：同屏不得要求两个永久前线）
	var non_mid := 0
	for e: Variant in timeline:
		if int((e as Dictionary).get("lane", 1)) != 1:
			non_mid += 1
	print("    非中段条目: %d（表 54 要求 ≤ 1）" % non_mid)

	var stage := _build_stage(sid, cand)
	for label: String in (TACTICS[sid] as Dictionary).keys():
		_run_case(sid, label, (TACTICS[sid] as Dictionary)[label], stage, data)
	print("")

	# 等级维度：表 54 的 1-5 验收条件是「推荐 Lv.5～7」。
	# 用同一套战术在 Lv.1 与 Lv.6 各跑一次，回答「该关是否按推荐等级设计」。
	var star_label := ""
	for label: String in (TACTICS[sid] as Dictionary).keys():
		if label.begins_with("B."):
			star_label = label
			break
	if star_label != "":
		print("  ── 等级维度（同一战术）──")
		for lv: int in [1, 6]:
			var stats := _level_stats(lv, data)
			_run_case_at_level(sid, "%s @ Lv.%d" % [star_label, lv],
				(TACTICS[sid] as Dictionary)[star_label], stage, data, stats)
		print("")


## 按指定等级构造「角色 id -> 成长面板」表（唯一来源 data/character_growth.json）。
## level=1 时返回空字典（= 不启用成长，与既有测试口径一致）。
func _level_stats(level: int, data: Dictionary) -> Dictionary:
	if level <= 1:
		return {}
	var growth: Dictionary = data["growth"]
	var out := {}
	for cid: String in (data["characters"] as Dictionary).keys():
		var cfg: Dictionary = data["characters"][cid]
		var base: Dictionary = (cfg.get("baseStats", {}) as Dictionary).duplicate(true)
		if cfg.has("healPower"):
			base["healPower"] = int(cfg.get("healPower", 0))
		var p := CharacterProgress.from_growth_config(
			cid, growth, base, str(cfg.get("growthProfileId", "growth_standard")))
		# 直接推进到目标等级所需的经验（绕过突破上限，仅供设计期取面板）
		var guard := 0
		while p.level < level and guard < 500:
			var need := p.exp_to_next()
			if need <= 0:
				break
			p.add_exp(need)
			guard += 1
		out[cid] = p.compute_stats()
	return out


func _build_stage(sid: String, cand: Dictionary) -> Dictionary:
	# 由 timeline 推导 waves 元数据（与 StageRuntime 的引用校验保持一致）
	var wave_numbers := {}
	for e: Variant in cand["timeline"]:
		wave_numbers[int((e as Dictionary).get("wave", 1))] = true
	var nums: Array = wave_numbers.keys()
	nums.sort()
	var waves: Array = []
	for n: int in nums:
		waves.append({"number": n, "label": "Wave %d" % n,
			"clearCondition": "ALL_ENEMIES_DEFEATED"})
	return {
		"stageId": sid,
		"coreHp": int(cand["coreHp"]),
		"startingAp": 10,
		"apRegen": 1,
		"availableCharacters": cand["availableCharacters"],
		"enemySpawnTimeline": cand["timeline"],
		"waves": waves,
		"battleRewards": {},
		"firstClearRewardId": "",
		"repeatRewardId": "",
	}


func _run_case(sid: String, label: String, actions: Array, stage: Dictionary, data: Dictionary) -> void:
	_run_case_at_level(sid, label, actions, stage, data, {})


## 带成长面板的用例执行（level_stats 为空 = 不启用成长）。
func _run_case_at_level(
	sid: String, label: String, actions: Array, stage: Dictionary,
	data: Dictionary, level_stats: Dictionary
) -> void:
	var session := BattleSession.new()
	var errs := session.setup(stage, data["enemies"], data["grid"], data["characters"], data["combat"])
	if not errs.is_empty():
		print("  [%s] 构建失败：%s" % [label, str(errs)])
		session.free()
		return
	session.stage.set_character_level_stats(level_stats)

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
	# 精英相关统计（用于验收精英机制确实发生）
	var gaze_note := ""
	print("  %-56s 结果=%s 用时=%5.1fs 核心=%d/%d 击杀=%2d 漏怪=%d 失能=%d  %s" % [
		label, BattleTypes.outcome_name(session.outcome), s.elapsed_seconds,
		s.core_hp, s.core_hp_max, s.enemies_killed, s.reached_core_count,
		s.characters_lost, " ｜ ".join(roles)])
	session.free()


func _load_data() -> Dictionary:
	var out := {"enemies": {}, "characters": {}, "combat": {}, "grid": null, "growth": {}}
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
	var growth: Variant = _read_json("res://data/character_growth.json")
	if typeof(growth) == TYPE_DICTIONARY:
		out["growth"] = growth
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


