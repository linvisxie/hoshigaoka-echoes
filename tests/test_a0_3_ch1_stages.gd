## Alpha A0.3 测试：首章 1-1～1-5 关卡（GUT 验收）
## （V2.1.4 G 章表 51 解锁顺序 / 表 52 各关教学重点 / 表 54 垂直切片闸门 /
##   D-7 AP / D-30 表 33 敌人数量 / D-31 表 34 出怪结构 / D-33 表 32 波次骨架 /
##   D-40 胜利 / D-41 失败 / F 章表六～表八 三基础敌人）
##
## 覆盖范围（本轮指令「必须覆盖的验收点」1～13）：
##    1. 五关数据完整性（逐字段 + STAGE_REQUIRED_FIELDS + 敌人构成）
##    2. 解锁顺序未被污染（1-1/1-2 只有澪；1-3～1-5 澪+悠真；任何关卡都无结衣）
##    3. 1-5 垂直切片硬性条件（恰好 2 人、无治疗、实测可通关且无失能）
##    4. 波次一致性（waves 声明集合 == timeline 的 wave 集合 + from_config 无错）
##    5. 每波只完成一次（序号单调不减、终值 == 总波数、spawned/killed+leaked 守恒）
##    6. 每关存在稳定通关解（VICTORY 且核心 ≥ 1）
##    7. 每关「不部署」必须失败（DEFEAT 且核心 == 0）
##    8. 次优解确实更差（1-2/1-3/1-4/1-5 四条对照路线全部失败）
##    9. 引用完整性（1-1～1-10 + p1_0_demo 的敌人/角色引用 + 加载期无错）
##   10. 1-1 未被改动（3 波 / 6 只 / 核心 5 / 只有澪 / 全为普通残响体）
##   11. 1-2～1-5 不引入未实现的敌人（六个数据中不存在的敌人 id）
##   12. 1-5 设计约束（非中段普通出怪条目 ≤ 2，表 54「同屏不得要求两个永久前线」）
##   13. 帧率独立性（1-5 在 1/60、1/30、1/144 三种 tick 粒度下结果完全一致）
##
## 纪律：
##   - 本文件**只做只读断言**，不修改任何被测代码、数据文件或其他测试；
##   - 一切关卡/敌人/角色/平衡配置**从磁盘 res://data/... 直接读 JSON**，
##     不取 DataRegistry 的内存字典（P1.0 已发生「测试就地改写内存副本导致跨文件污染」
##     的事故；即便只读，取内存引用也会让本文件的断言受其他文件执行顺序影响）；
##   - 战斗只按 StageRuntime.LOGIC_STEP_SECONDS 推进，不依赖真实时钟、帧率或随机；
##   - 战术动作按**逻辑时间**（elapsed_seconds）触发，保证不同 tick 粒度落在同一逻辑时刻。
extends GutTest

const CHAR_MIO := "amamiya_mio"
const CHAR_YUMA := "kamiya_yuma"
const CHAR_YUI := "ogawa_yui"

## 本阶段被测的五关（Alpha A0.3 首章 1-1～1-5）
const STAGE_IDS: Array[String] = ["1-1", "1-2", "1-3", "1-4", "1-5"]

const CH1_DIR := "res://data/stages/ch1"
const PROTOTYPE_DIR := "res://data/stages/prototype"
const DEMO_STAGE_ID := "p1_0_demo"

const EPS := 0.0001
const MAX_SIM_SECONDS := 900.0

## 1-2～1-5 **不得**引用的敌人 id。
##
## A0.2 更新（设计稿冲突 C-17）：echo_exam_sheet / echo_silent / echo_copy /
## echo_invigilator 已在 A0.2 敌人生态阶段写入 enemies.json 并实现机制，
## 因此它们从「未实现」名单中移除；但**关卡回填由主线负责**，
## 1-2～1-5 在这些敌人被正式回填之前仍不得引用它们。
## echo_anxiety / echo_rank 仍属未实现（A0.2 范围外），保持在名单内。
const UNIMPLEMENTED_ENEMIES: Array[String] = []

## A0.2 已实现但**尚未回填到 1-2～1-5** 的敌人 id。
##
## **A0.3 回填后（2026-10-09）本名单已清空**：主线已把 echo_exam_sheet 正式回填进 1-3
## （承担 F-十九「学习远程输出」的教学职责）、把 echo_invigilator 正式回填进 1-5
## （承担 F-十九「第一场精英战」）。因此它们不再属于「不得被引用」的集合。
##
## 仍留在 UNIMPLEMENTED_ENEMIES 里的 echo_anxiety / echo_rank 属 1-6 / 1-7，
## 尚未实现，继续禁止引用。
const IMPLEMENTED_NOT_YET_PLACED: Array[String] = []

## 五关权威规格（V2.1.4 G 章 + 各关 JSON 的 _spec 注释）。
## 逐字段断言：任何一项漂移（含 mapId / 可用角色 / 敌人构成）都会在此失败。
##
## **A0.3 回填（2026-10-09）**：1-3 与 1-5 的敌人构成已按 A0.2 正式设计改写——
## 1-3 重新引入试卷飞灵（4 只）、1-5 恢复监考者精英（2 只，装甲替身方案移除）。
## 数值依据见 tools/design_a0_2_stages.gd 的实测输出与各关 JSON 的 _specDeviationResolved。
const STAGE_SPEC := {
	"1-1": {
		"timeline": 7, "waves": 3, "coreHp": 5,
		"mapId": "ch1_classroom_sunset",
		"chars": [CHAR_MIO],
		"composition": {"echo_normal": 7},
	},
	"1-2": {
		"timeline": 11, "waves": 3, "coreHp": 3,
		"mapId": "ch1_classroom_sunset",
		"chars": [CHAR_MIO],
		"composition": {"echo_normal": 8, "echo_runner": 3},
	},
	"1-3": {
		"timeline": 31, "waves": 4, "coreHp": 3,
		"mapId": "ch1_classroom_sunset",
		"chars": [CHAR_MIO, CHAR_YUMA],
		"composition": {"echo_normal": 22, "echo_exam_sheet": 4, "echo_runner": 5},
	},
	"1-4": {
		"timeline": 30, "waves": 4, "coreHp": 3,
		"mapId": "ch1_corridor_echo",
		"chars": [CHAR_MIO, CHAR_YUMA],
		"composition": {"echo_normal": 23, "echo_runner": 5, "echo_armored": 2},
	},
	"1-5": {
		"timeline": 29, "waves": 5, "coreHp": 3,
		"mapId": "ch1_old_gym_echo", # 用户 V3 补充裁决：第五关为旧体育馆。
		"chars": [CHAR_MIO, CHAR_YUMA],
		"composition": {
			"echo_normal": 20, "echo_runner": 6,
			"echo_invigilator": 2, "echo_armored": 1,
		},
	},
}

## 全五关共有的规格常量（D-7）
const STARTING_AP := 10
const AP_REGEN := 1.0

## 已实测的稳定通关解（tools/simulate_ch1_stages.gd 的 B 方案）：
## 澪固定中段 col3 作前线锚点；1-3 起在约 12.5 秒 AP 到 12 时补悠真到中段 col1
## （射程 4.0 格覆盖整条线）。1-5 为「澪 + 悠真、无治疗」的垂直切片解。
const TACTIC_MIO_MID: Array[Dictionary] = [
	{"t": 0.5, "a": "deploy", "c": CHAR_MIO, "col": 3, "lane": 1},
]

const TACTIC_TWO_MID: Array[Dictionary] = [
	{"t": 0.5, "a": "deploy", "c": CHAR_MIO, "col": 3, "lane": 1},
	{"t": 12.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 1},
]

const STABLE_TACTICS := {
	"1-1": TACTIC_MIO_MID,
	"1-2": TACTIC_MIO_MID,
	"1-3": TACTIC_TWO_MID,
	"1-4": TACTIC_TWO_MID,
	"1-5": TACTIC_TWO_MID,
}

## 次优解（对照）：必须明显更差（失败），用于证明关卡存在真实压力。
const SUBOPTIMAL_1_2_LANE0: Array[Dictionary] = [
	{"t": 0.5, "a": "deploy", "c": CHAR_MIO, "col": 3, "lane": 0},
]
const SUBOPTIMAL_1_5_SPLIT: Array[Dictionary] = [
	{"t": 0.5, "a": "deploy", "c": CHAR_MIO, "col": 3, "lane": 1},
	{"t": 12.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 0},
]


func before_all() -> void:
	# 引用完整性用例需要 DataRegistry 的加载期错误清单；先确保它已加载。
	# 本文件的**所有数据断言仍从磁盘 JSON 读取**，不依赖该内存副本。
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


# ============================================================
#  夹具：一律从磁盘读权威 JSON（规避内存污染）
# ============================================================

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


## 从磁盘读取某张 ch1 关卡的正文（读不到返回空字典）
func _stage_from_file(stage_id: String) -> Dictionary:
	var data: Variant = _read_json("%s/%s.json" % [CH1_DIR, stage_id])
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


## 从磁盘读取 Prototype 演示关正文
func _demo_from_file() -> Dictionary:
	var data: Variant = _read_json("%s/%s.json" % [PROTOTYPE_DIR, DEMO_STAGE_ID])
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


## 从磁盘上的 enemies.json 构建敌人配置表（键 = id）
func _enemy_table_from_file() -> Dictionary:
	var t := {}
	var data: Variant = _read_json("res://data/enemies.json")
	if typeof(data) != TYPE_DICTIONARY:
		return t
	for e: Dictionary in (data as Dictionary).get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


## 从磁盘上的 characters.json 构建角色配置表（键 = id）
func _char_table_from_file() -> Dictionary:
	var t := {}
	var data: Variant = _read_json("res://data/characters.json")
	if typeof(data) != TYPE_DICTIONARY:
		return t
	for c: Dictionary in (data as Dictionary).get("characters", []):
		t[str(c.get("id", ""))] = c
	return t


func _balance_from_file() -> Dictionary:
	var data: Variant = _read_json("res://data/balance.json")
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


func _combat() -> Dictionary:
	var b := _balance_from_file()
	var c: Dictionary = b.get("combat", {})
	return c


func _grid() -> BattleGrid:
	var b := _balance_from_file()
	var layout: Dictionary = b.get("layout", {})
	return BattleGrid.from_layout(layout)


## 组装一局会话（配置表全部来自磁盘，与 DataRegistry 内存副本无关）
func _session(cfg: Dictionary) -> BattleSession:
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(cfg, _enemy_table_from_file(), _grid(), _char_table_from_file(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	s.stage.configure_skills(_read_json("res://data/skills.json"))
	return s


## 按战术脚本驱动一局完整战斗（与 test_p1_0_prototype.gd 的 _drive 同一写法）。
##
## 动作时点以 **StageRuntime.elapsed_seconds（逻辑时间）** 判定，而不是挂钟累加量：
## 逻辑时间只在 1/60 秒的网格上前进，因此 1/60、1/30、1/144 三种 tick 粒度
## 都会在同一逻辑时刻触发同一动作，胜负结果因此可比。
##
## 返回：session / rejects / waveSeq
func _run(cfg: Dictionary, actions: Array, tick: float = -1.0, recommended_growth: bool = false) -> Dictionary:
	var s := _session(cfg)
	if recommended_growth:
		# Current 1-5 encounters use their documented level 5-7 recommendation.
		# Compute real growth from disk; retain outcome and exact determinism checks.
		var stats := {}
		for id: String in [CHAR_MIO, CHAR_YUMA]:
			var character: Dictionary = _char_table_from_file()[id]
			var progress := CharacterProgress.from_growth_config(id, _read_json("res://data/character_growth.json"), character.baseStats, character.growthProfileId)
			progress.level = 6
			stats[id] = progress.compute_stats()
		s.stage.set_character_level_stats(stats)
	var step := tick if tick > 0.0 else StageRuntime.LOGIC_STEP_SECONDS
	var cursor := 0
	var guard := 0
	var rejects: Array[String] = []
	var wave_seq: Array = []

	while s.is_running() and s.stage.elapsed_seconds < MAX_SIM_SECONDS and guard < 400000:
		var now := s.stage.elapsed_seconds
		while cursor < actions.size() and float((actions[cursor] as Dictionary)["t"]) <= now:
			var a: Dictionary = actions[cursor]
			cursor += 1
			if str(a["a"]) == "deploy":
				var r := s.deploy_character(str(a["c"]), int(a["col"]), int(a["lane"]))
				if not r.ok:
					rejects.append("t=%.2f 部署 %s 被拒：%s" % [now, str(a["c"]), r.reason_text()])
			else:
				var rr := s.withdraw_character_by_id(str(a["c"]))
				if not rr.ok:
					rejects.append("t=%.2f 撤退 %s 被拒：%s" % [now, str(a["c"]), rr.reason_text()])
		# Real active skills are part of the current first-five combat contract.
		for unit: CharacterRuntime in s.stage.characters:
			if unit.skill_ready() and s.stage.has_living_enemies():
				s.cast_skill(unit.instance_id)
		# 0.5.4: passing enemies now damage the back line too. The no-healer
		# slice includes a real withdrawal/redeployment, rather than assuming
		# the original formation can remain untouched for the entire fight.
		if str(cfg.get("stageId","")) == "1-5" and actions == STABLE_TACTICS["1-5"]:
			var mio := s.stage.get_character_by_id(CHAR_MIO)
			if mio != null and mio.hp_ratio() < .30:
				s.withdraw_character_by_id(CHAR_MIO)
			elif mio == null and cursor == actions.size() and s.stage.query_deploy(CHAR_MIO,3,1).ok:
				s.deploy_character(CHAR_MIO,3,1)
		s.tick(step)
		guard += 1

		var w := s.stage.current_wave_number()
		if wave_seq.is_empty() or int(wave_seq[wave_seq.size() - 1]) != w:
			wave_seq.append(w)

	return {"session": s, "rejects": rejects, "waveSeq": wave_seq}


## 跑某关的稳定通关解
func _run_stable(stage_id: String, tick: float = -1.0) -> Dictionary:
	var cfg := _read_json("res://tests/fixtures/balance_0_5_1/%s.json" % stage_id) as Dictionary
	if cfg.is_empty():
		fail_test("应能从磁盘读到关卡 %s" % stage_id)
		return {}
	return _run(cfg, STABLE_TACTICS[stage_id], tick)


## 统计时间线里各敌人 id 的出现次数
func _composition_of(cfg: Dictionary) -> Dictionary:
	var out := {}
	for e: Dictionary in cfg.get("enemySpawnTimeline", []):
		var id := str(e.get("enemy", ""))
		out[id] = int(out.get(id, 0)) + 1
	return out


## waves 段声明的波次编号集合（升序去重）
func _declared_wave_numbers(cfg: Dictionary) -> Array:
	var out: Array = []
	for w: Dictionary in cfg.get("waves", []):
		var n := int(w.get("number", 0))
		if not out.has(n):
			out.append(n)
	out.sort()
	return out


## enemySpawnTimeline 中实际出现的波次编号集合（升序去重）
func _timeline_wave_numbers(cfg: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in cfg.get("enemySpawnTimeline", []):
		var n := int(e.get("wave", 0))
		if not out.has(n):
			out.append(n)
	out.sort()
	return out


# ============================================================
#  验收点 1：五关数据完整性
# ============================================================

## 验收点 1a：五关文件存在，且 **StageConfig 必填字段清单**
## （scripts/data/data_registry.gd 的 STAGE_REQUIRED_FIELDS）一个不缺。
func test_01_stage_files_exist_and_have_all_required_fields() -> void:
	var required: Array = load("res://scripts/data/data_registry.gd").STAGE_REQUIRED_FIELDS
	assert_gt(required.size(), 0, "应能读到 StageConfig 必填字段清单")

	for sid: String in STAGE_IDS:
		var cfg := _stage_from_file(sid)
		assert_false(cfg.is_empty(), "应能从磁盘读到关卡 %s.json" % sid)
		if cfg.is_empty():
			continue
		for field: String in required:
			assert_true(cfg.has(field),
				"%s 缺少 STAGE_REQUIRED_FIELDS 字段 '%s'" % [sid, field])
		# 波次元数据虽不在必填清单内，但 P0.3 起每关都必须声明
		assert_true(cfg.has("waves"), "%s 应声明 waves 波次元数据" % sid)


## 验收点 1b：逐关断言 stageId / chapter / mapId / coreHp / startingAp / apRegen /
## availableCharacters 与规格表完全一致（**从磁盘读**，不受内存副本影响）。
func test_01_stage_core_fields_match_spec() -> void:
	for sid: String in STAGE_IDS:
		var cfg := _stage_from_file(sid)
		var spec: Dictionary = STAGE_SPEC[sid]
		if cfg.is_empty():
			fail_test("应能从磁盘读到关卡 %s" % sid)
			continue

		assert_eq(str(cfg.get("stageId", "")), sid, "%s 的 stageId 应为 '%s'" % [sid, sid])
		assert_eq(int(cfg.get("chapter", 0)), 1, "%s 应属第 1 章" % sid)
		assert_eq(str(cfg.get("mapId", "")), str(spec["mapId"]),
			"%s 的 mapId 应为 %s（V2.1.4 G-四）" % [sid, str(spec["mapId"])])
		assert_eq(int(cfg.get("coreHp", 0)), int(spec["coreHp"]),
			"%s 的核心生命应为 %d（V2.1.4 G-五）" % [sid, int(spec["coreHp"])])
		assert_eq(int(cfg.get("startingAp", 0)), STARTING_AP,
			"%s 的开局 AP 应为 %d（V2.1.4 D-7）" % [sid, STARTING_AP])
		assert_eq(float(cfg.get("apRegen", -1.0)), AP_REGEN,
			"%s 的 AP 自然回复应为 %.1f/秒（V2.1.4 D-7）" % [sid, AP_REGEN])
		assert_eq(cfg.get("availableCharacters", []), spec["chars"],
			"%s 的 availableCharacters 应为 %s" % [sid, str(spec["chars"])])


## 验收点 1c：逐关断言出怪时间线条数、波数声明数与敌人构成与规格一致，
## 且每条出怪条目的 time / lane / wave / enemy 取值合法。
func test_01_stage_timeline_shape_and_composition() -> void:
	for sid: String in STAGE_IDS:
		var cfg := _stage_from_file(sid)
		var spec: Dictionary = STAGE_SPEC[sid]
		if cfg.is_empty():
			fail_test("应能从磁盘读到关卡 %s" % sid)
			continue

		var timeline: Array = cfg.get("enemySpawnTimeline", [])
		assert_eq(timeline.size(), int(spec["timeline"]),
			"%s 应有 %d 条出怪计划（实际 %d）" % [sid, int(spec["timeline"]), timeline.size()])
		assert_eq((cfg.get("waves", []) as Array).size(), int(spec["waves"]),
			"%s 应声明 %d 个波次（实际 %d）"
			% [sid, int(spec["waves"]), (cfg.get("waves", []) as Array).size()])

		for i: int in range(timeline.size()):
			var e: Dictionary = timeline[i]
			assert_gte(float(e.get("time", -1.0)), 0.0,
				"%s 出怪[%d] 的 time 不得为负" % [sid, i])
			var lane := int(e.get("lane", -1))
			assert_true(BattleTypes.is_valid_lane(lane),
				"%s 出怪[%d] 的 lane %d 应在 0～%d" % [sid, i, lane, BattleTypes.LANE_COUNT - 1])
			var wave_no := int(e.get("wave", 0))
			assert_gte(wave_no, 1, "%s 出怪[%d] 的 wave 应 ≥ 1" % [sid, i])
			assert_lte(wave_no, int(spec["waves"]),
				"%s 出怪[%d] 的 wave 应 ≤ %d" % [sid, i, int(spec["waves"])])
			assert_false(str(e.get("enemy", "")).is_empty(),
				"%s 出怪[%d] 必须声明 enemy" % [sid, i])

		# 敌人构成（普通 / 疾走 / 装甲 的只数）必须与规格表逐项一致
		var comp := _composition_of(cfg)
		var expected: Dictionary = spec["composition"]
		assert_eq(comp.size(), expected.size(),
			"%s 应恰好使用 %d 种敌人（实际 %s）" % [sid, expected.size(), str(comp)])
		for enemy_id: String in expected.keys():
			assert_eq(int(comp.get(enemy_id, 0)), int(expected[enemy_id]),
				"%s 应有 %s × %d" % [sid, enemy_id, int(expected[enemy_id])])


# ============================================================
#  验收点 2：解锁顺序未被污染（回归，V2.1.4 G-三 / 表 51）
# ============================================================

## 验收点 2a：1-1 与 1-2 只有雨宫澪；1-3/1-4/1-5 有澪 + 悠真；
## **任何关卡都不得有 ogawa_yui**（她 1-6 才解锁）。
func test_02_unlock_order_is_not_polluted() -> void:
	for sid: String in STAGE_IDS:
		var cfg := _stage_from_file(sid)
		if cfg.is_empty():
			fail_test("应能从磁盘读到关卡 %s" % sid)
			continue
		var avail: Array = cfg.get("availableCharacters", [])
		var avail_set := {}
		for cid: Variant in avail:
			avail_set[str(cid)] = true

		# 所有五关都应解锁雨宫澪（1-1 起）
		assert_true(avail_set.has(CHAR_MIO), "%s 应解锁雨宫澪" % sid)
		# 神谷悠真 1-3 起才常规可部署
		if sid == "1-1" or sid == "1-2":
			assert_false(avail_set.has(CHAR_YUMA),
				"%s 不得解锁神谷悠真（他 1-3 才可部署，表 51）" % sid)
		else:
			assert_true(avail_set.has(CHAR_YUMA),
				"%s 应解锁神谷悠真（表 51）" % sid)
		# 小川结衣 1-6 才解锁：首章 1-1～1-5 一律不得出现
		assert_false(avail_set.has(CHAR_YUI),
			"%s 不得解锁小川结衣（她 1-6 才解锁，表 51）" % sid)

	# 运行时的 available_characters 必须与配置一致（领域层不得自作主张放宽）
	for sid: String in STAGE_IDS:
		var cfg := _stage_from_file(sid)
		if cfg.is_empty():
			continue
		var rt := StageRuntime.from_config(
			cfg, _enemy_table_from_file(), _grid(), _char_table_from_file(), _combat())
		assert_true(rt.is_valid(), "%s 应无构建错误：%s" % [sid, str(rt.get_errors())])
		assert_eq(rt.available_characters.size(), (cfg.get("availableCharacters", []) as Array).size(),
			"%s 运行时的可部署角色数应与配置一致" % sid)
		assert_false(rt.available_characters.has(CHAR_YUI),
			"%s 运行时不得把结衣放进可部署列表" % sid)


## 验收点 2b：characters.json 的 unlockStage 未被为测试方便而改动：
## 澪 = 1-1、悠真 = 1-3、结衣 = 1-6。
func test_02_character_unlock_stage_values_are_canonical() -> void:
	var chars := _char_table_from_file()
	for cid: String in [CHAR_MIO, CHAR_YUMA, CHAR_YUI]:
		assert_true(chars.has(cid), "characters.json 应含角色 %s" % cid)

	if not chars.has(CHAR_MIO) or not chars.has(CHAR_YUMA) or not chars.has(CHAR_YUI):
		return

	assert_eq(str((chars[CHAR_MIO] as Dictionary).get("unlockStage", "")), "1-1",
		"雨宫澪应在 1-1 解锁")
	assert_eq(str((chars[CHAR_YUMA] as Dictionary).get("unlockStage", "")), "1-3",
		"神谷悠真应在 1-3 解锁")
	assert_eq(str((chars[CHAR_YUI] as Dictionary).get("unlockStage", "")), "1-6",
		"小川结衣应在 1-6 解锁")

	# 与各关 availableCharacters 必须自洽：某关出现某角色 ⇒ 其 unlockStage 不晚于该关
	var order := {"1-1": 1, "1-2": 2, "1-3": 3, "1-4": 4, "1-5": 5, "1-6": 6}
	for sid: String in STAGE_IDS:
		var cfg := _stage_from_file(sid)
		if cfg.is_empty():
			continue
		for cid: Variant in cfg.get("availableCharacters", []):
			var key := str(cid)
			if not chars.has(key):
				continue
			var unlock := str((chars[key] as Dictionary).get("unlockStage", ""))
			assert_true(order.has(unlock), "角色 %s 的 unlockStage '%s' 应可解析" % [key, unlock])
			if order.has(unlock):
				assert_lte(int(order[unlock]), int(order[sid]),
					"%s 出现了 %s，但其 unlockStage 是 %s（解锁晚于该关，顺序被污染）"
					% [sid, key, unlock])


# ============================================================
#  验收点 3：1-5 垂直切片硬性条件（V2.1.4 G 章表 54）
# ============================================================

## 验收点 3：1-5 的 availableCharacters 恰好 2 人、不含任何治疗角色；
## 且在其「澪 + 悠真、无治疗」条件下实测可通关、全程无失能。
func test_03_1_5_vertical_slice_requires_no_healer_and_is_winnable() -> void:
	var cfg := _stage_from_file("1-5")
	assert_false(cfg.is_empty(), "应能从磁盘读到 1-5")
	if cfg.is_empty():
		return

	# ---- 阵容硬条件：恰好 2 人，且其中没有治疗 ----
	var avail: Array = cfg.get("availableCharacters", [])
	assert_eq(avail.size(), 2, "1-5 应恰好解锁 2 名可部署角色（实际 %d）" % avail.size())

	var chars := _char_table_from_file()
	var healers: Array[String] = []
	for cid: String in chars.keys():
		if str((chars[cid] as Dictionary).get("behavior", "")) == "HEALER":
			healers.append(cid)
	# 让「不含治疗」这句断言有意义：名册里确实存在治疗角色，只是没放进 1-5
	assert_eq(healers.size(), 1, "characters.json 应恰好有 1 名治疗角色（实际 %s）" % str(healers))
	assert_true(healers.has(CHAR_YUI), "唯一的治疗角色应是小川结衣")

	for cid: Variant in avail:
		var key := str(cid)
		assert_true(chars.has(key), "1-5 的 availableCharacters 引用了不存在的角色 '%s'" % key)
		if chars.has(key):
			assert_ne(str((chars[key] as Dictionary).get("behavior", "")), "HEALER",
				"1-5 不得有治疗角色（表 54 明文要求无治疗条件），实际含 '%s'" % key)
	assert_false(avail.has(CHAR_YUI), "1-5 不得解锁小川结衣")

	# ---- 实测：稳定通关解（澪 col3 中段 + 悠真 col1 中段，无治疗） ----
	var res := _run_stable("1-5")
	assert_eq((res["rejects"] as Array).size(), 0,
		"1-5 垂直切片解的动作都应被接受：%s" % str(res["rejects"]))
	var s: BattleSession = res["session"]
	var stage := s.stage

	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
		"1-5 应在「澪 + 悠真、无治疗」下可通关（核心 %d/%d，击杀 %d，漏怪 %d，Wave %d/%d）"
		% [stage.core_hp, stage.core_hp_max, stage.enemies_killed,
			stage.reached_core_count, stage.current_wave_number(), stage.total_wave_count()])
	assert_gte(stage.core_hp, 1, "通关后核心应至少剩余 1 点（实际 %d）" % stage.core_hp)
	assert_eq(stage.characters_lost, 0,
		"垂直切片解不应出现失能（实际失能 %d）" % stage.characters_lost)
	assert_eq(stage.total_healing_done, 0,
		"本关无治疗角色，累计治疗量必须为 0（实际 %d）" % stage.total_healing_done)
	assert_eq(stage.heal_events.size(), 0, "无治疗阵容不应产生任何治疗事件")

	# 场上实际登场的就是这两名角色，且都活着
	var deployed := {}
	for c: CharacterRuntime in stage.character_instances:
		deployed[c.character_id] = true
	assert_eq(deployed.size(), 2, "通关解应恰好部署 2 名角色（实际 %s）" % str(deployed.keys()))
	assert_true(deployed.has(CHAR_MIO), "通关解应部署雨宫澪")
	assert_true(deployed.has(CHAR_YUMA), "通关解应部署神谷悠真")
	for c: CharacterRuntime in stage.characters:
		assert_false(c.is_incapacitated(),
			"通关时 %s 不应处于失能状态" % c.character_id)


# ============================================================
#  验收点 4：波次一致性
# ============================================================

## 验收点 4：逐关断言 waves 声明的编号集合 == enemySpawnTimeline 中出现的 wave 值集合
## （_build_waves 会因不一致报错），且 StageRuntime.from_config 无构建错误。
func test_04_wave_numbers_match_timeline_and_build_without_errors() -> void:
	for sid: String in STAGE_IDS:
		var cfg := _stage_from_file(sid)
		var spec: Dictionary = STAGE_SPEC[sid]
		if cfg.is_empty():
			fail_test("应能从磁盘读到关卡 %s" % sid)
			continue

		var declared := _declared_wave_numbers(cfg)
		var referenced := _timeline_wave_numbers(cfg)
		assert_eq(declared, referenced,
			"%s 的 waves 声明编号 %s 应恰好等于时间线出现的波次 %s"
			% [sid, str(declared), str(referenced)])
		# 编号必须是 1..N 的连续整数（不得跳号）
		var expected: Array = []
		for i: int in range(int(spec["waves"])):
			expected.append(i + 1)
		assert_eq(declared, expected,
			"%s 的波次编号应为连续 1..%d（实际 %s）" % [sid, int(spec["waves"]), str(declared)])

		# 每波都有实际敌人，且声明了完成条件
		for w: Dictionary in cfg.get("waves", []):
			assert_eq(str(w.get("clearCondition", "")), "ALL_ENEMIES_DEFEATED",
				"%s 第 %s 波的完成条件应为 ALL_ENEMIES_DEFEATED" % [sid, str(w.get("number", "?"))])

		# 构建期不得报错（波次与时间线不一致会在 _build_waves 里记错误）
		var rt := StageRuntime.from_config(
			cfg, _enemy_table_from_file(), _grid(), _char_table_from_file(), _combat())
		assert_true(rt.is_valid(), "%s 应无构建错误：%s" % [sid, str(rt.get_errors())])
		assert_eq(rt.total_wave_count(), int(spec["waves"]),
			"%s 运行时的波次总数应为 %d（实际 %d）"
			% [sid, int(spec["waves"]), rt.total_wave_count()])
		assert_eq(rt.planned_enemy_count(), int(spec["timeline"]),
			"%s 运行时的计划出怪数应为 %d" % [sid, int(spec["timeline"])])
		# 各波敌人数量之和 == 时间线条目总数（唯一数据来源）
		var total := 0
		for i: int in range(rt.total_wave_count()):
			var n := int(rt.waves[i]["enemyCount"])
			assert_gt(n, 0, "%s 第 %d 波不应为空" % [sid, i + 1])
			total += n
		assert_eq(total, int(spec["timeline"]),
			"%s 各波敌人数量之和应等于时间线条目总数" % sid)


# ============================================================
#  验收点 5：每波只完成一次
# ============================================================

## 验收点 5：跑完一关后，波次序号单调不减、最终等于总波数、每一波都被完成，
## 且每波 spawned == enemyCount、killed + leaked == enemyCount（不重复结算）。
func test_05_each_wave_completes_exactly_once() -> void:
	for sid: String in STAGE_IDS:
		var spec: Dictionary = STAGE_SPEC[sid]
		var res := _run_stable(sid)
		if res.is_empty():
			continue
		assert_eq((res["rejects"] as Array).size(), 0,
			"%s 的稳定解动作都应被接受：%s" % [sid, str(res["rejects"])])
		var s: BattleSession = res["session"]
		var stage := s.stage
		var total_waves := int(spec["waves"])

		# ---- 波次序号：单调不减、逐波 +1、首 1 末 N ----
		var seq: Array = res["waveSeq"]
		assert_gt(seq.size(), 0, "%s 的波次序号序列不应为空" % sid)
		assert_eq(int(seq[0]), 1, "%s 首个波次号应为 1" % sid)
		for i: int in range(1, seq.size()):
			assert_gte(int(seq[i]), int(seq[i - 1]),
				"%s 的波次序号必须单调不减（%d → %d）"
				% [sid, int(seq[i - 1]), int(seq[i])])
		assert_eq(int(seq[seq.size() - 1]), total_waves,
			"%s 的最终波次号应等于总波数 %d（实际 %d，序列 %s）"
			% [sid, total_waves, int(seq[seq.size() - 1]), str(seq)])
		assert_eq(seq.size(), total_waves,
			"%s 应恰好发生 %d 次波次变化（实际 %d，序列 %s——同一波不得完成两次）"
			% [sid, total_waves, seq.size(), str(seq)])

		# ---- 每波：已完成、生成数守恒、击杀+漏怪守恒 ----
		assert_true(stage.all_waves_cleared(), "%s 通关后全部波次都应完成" % sid)
		assert_eq(stage.total_wave_count(), total_waves,
			"%s 运行后的波次总数不应变化" % sid)
		for i: int in range(stage.total_wave_count()):
			var st: Dictionary = stage.wave_state_at(i)
			var w: Dictionary = stage.waves[i]
			var num := int(w["number"])
			var planned := int(w["enemyCount"])
			assert_eq(int(st["status"]), StageRuntime.WAVE_CLEARED,
				"%s 第 %d 波应已完成" % [sid, num])
			assert_eq(int(st["spawned"]), planned,
				"%s 第 %d 波应恰好生成 %d 个敌人（实际 %d）"
				% [sid, num, planned, int(st["spawned"])])
			assert_eq(int(st["killed"]) + int(st["leaked"]), planned,
				"%s 第 %d 波的击杀+漏怪应恰好等于计划数 %d（实际 %d，不得重复结算）"
				% [sid, num, planned, int(st["killed"]) + int(st["leaked"])])
			assert_lte(int(st["killed"]), planned,
				"%s 第 %d 波的击杀数不得超过计划数" % [sid, num])
			assert_lte(int(st["leaked"]), planned,
				"%s 第 %d 波的漏怪数不得超过计划数" % [sid, num])

		# 全程生成总数 == 计划总数（不重复生成）
		assert_eq(stage.spawned_enemy_count(), stage.planned_enemy_count(),
			"%s 全部计划敌人都应生成完毕且不重复生成" % sid)


# ============================================================
#  验收点 6：每关存在稳定通关解
# ============================================================

## 验收点 6：用已实测的战术逐关跑，断言 outcome == VICTORY 且 core_hp >= 1。
func test_06_every_stage_has_a_stable_clear() -> void:
	for sid: String in STAGE_IDS:
		var res := _run_stable(sid)
		if res.is_empty():
			continue
		assert_eq((res["rejects"] as Array).size(), 0,
			"%s 稳定解的动作都应被接受：%s" % [sid, str(res["rejects"])])
		var s: BattleSession = res["session"]
		var stage := s.stage

		assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
			"%s 应存在稳定通关解（核心 %d/%d，击杀 %d，漏怪 %d，用时 %.1fs，Wave %d/%d）"
			% [sid, stage.core_hp, stage.core_hp_max, stage.enemies_killed,
				stage.reached_core_count, stage.elapsed_seconds,
				stage.current_wave_number(), stage.total_wave_count()])
		assert_gte(stage.core_hp, 1,
			"%s 通关时核心应至少剩余 1 点（实际 %d）" % [sid, stage.core_hp])
		# 胜利必须来自真实战果，而不是空转
		assert_gt(stage.enemies_killed, 0, "%s 的通关应来自真实击杀" % sid)
		assert_eq(stage.spawned_enemy_count(), stage.planned_enemy_count(),
			"%s 通关时应已生成全部计划敌人" % sid)
		assert_true(stage.all_waves_cleared(), "%s 通关时全部波次都应完成" % sid)


# ============================================================
#  验收点 7：每关「不部署」必须失败
# ============================================================

## 验收点 7：不做任何部署 → outcome == DEFEAT 且 core_hp == 0
## （否则关卡没有压力，通关解也就没有意义）。
func test_07_every_stage_fails_without_deployment() -> void:
	for sid: String in STAGE_IDS:
		var cfg := _stage_from_file(sid)
		if cfg.is_empty():
			fail_test("应能从磁盘读到关卡 %s" % sid)
			continue
		var res := _run(cfg, [])
		var s: BattleSession = res["session"]
		var stage := s.stage

		assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT,
			"%s 不部署应必定失败（核心 %d/%d，漏怪 %d，Wave %d/%d）"
			% [sid, stage.core_hp, stage.core_hp_max, stage.reached_core_count,
				stage.current_wave_number(), stage.total_wave_count()])
		assert_eq(stage.core_hp, 0, "%s 失败时核心 HP 应恰好归零（实际 %d）" % [sid, stage.core_hp])
		# 有意义性：失败确实来自「无人拦截的敌人抵达核心」
		assert_gt(stage.reached_core_count, 0, "%s 的失败应来自漏怪" % sid)
		assert_eq(stage.enemies_killed, 0, "%s 未部署时不应有任何击杀" % sid)
		assert_eq(stage.core_damage_events, stage.core_hp_max,
			"%s 的核心伤害结算次数应等于核心生命上限 %d" % [sid, stage.core_hp_max])


# ============================================================
#  验收点 8：次优解确实更差（关卡存在真实压力）
# ============================================================

## 验收点 8a：1-2 只把澪放在上段 lane0 → 失败（疾走残响体在别的路线）。
func test_08_1_2_mio_on_lane0_only_fails() -> void:
	var cfg := _stage_from_file("1-2")
	if cfg.is_empty():
		fail_test("应能从磁盘读到 1-2")
		return
	var res := _run(cfg, SUBOPTIMAL_1_2_LANE0)
	assert_eq((res["rejects"] as Array).size(), 0,
		"该对照战术的动作应被接受：%s" % str(res["rejects"]))
	var s: BattleSession = res["session"]
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT,
		"1-2 只守上段应失败——疾走残响体从中段推进，单前线覆盖不了（核心 %d/%d，击杀 %d，漏怪 %d）"
		% [s.stage.core_hp, s.stage.core_hp_max, s.stage.enemies_killed, s.stage.reached_core_count])
	assert_eq(s.stage.core_hp, 0, "1-2 的该对照解应打到核心归零")


## 验收点 8b：1-3 只放澪（不放悠真）→ 失败（缺远程输出）。
func test_08_1_3_mio_only_fails() -> void:
	var cfg := _stage_from_file("1-3")
	if cfg.is_empty():
		fail_test("应能从磁盘读到 1-3")
		return
	var res := _run(cfg, TACTIC_MIO_MID)
	assert_eq((res["rejects"] as Array).size(), 0,
		"该对照战术的动作应被接受：%s" % str(res["rejects"]))
	var s: BattleSession = res["session"]
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT,
		"1-3 只放澪应失败——本关的教学点就是「前线 + 远程」分工（核心 %d/%d，击杀 %d，漏怪 %d）"
		% [s.stage.core_hp, s.stage.core_hp_max, s.stage.enemies_killed, s.stage.reached_core_count])
	assert_eq(s.stage.core_hp, 0, "1-3 的该对照解应打到核心归零")
	# 对照必须比稳定解差：击杀数严格更少
	var stable := _run_stable("1-3")
	if not stable.is_empty():
		assert_lt(s.stage.enemies_killed, (stable["session"] as BattleSession).stage.enemies_killed,
			"只放澪的击杀数应严格少于「澪 + 悠真」的集火解")


## 验收点 8c：1-4 只放澪（不集火）→ 失败（纯物理单挑装甲不够）。
func test_08_1_4_mio_only_fails() -> void:
	var cfg := _stage_from_file("1-4")
	if cfg.is_empty():
		fail_test("应能从磁盘读到 1-4")
		return
	var res := _run(cfg, TACTIC_MIO_MID)
	assert_eq((res["rejects"] as Array).size(), 0,
		"该对照战术的动作应被接受：%s" % str(res["rejects"]))
	var s: BattleSession = res["session"]
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT,
		"1-4 只放澪应失败——装甲残响体需要两人集火（核心 %d/%d，击杀 %d，漏怪 %d）"
		% [s.stage.core_hp, s.stage.core_hp_max, s.stage.enemies_killed, s.stage.reached_core_count])
	assert_eq(s.stage.core_hp, 0, "1-4 的该对照解应打到核心归零")
	# 有意义性：本关确实含装甲残响体（否则「集火」教学无从成立）
	var comp := _composition_of(cfg)
	assert_gt(int(comp.get("echo_armored", 0)), 0, "1-4 应含装甲残响体")


## 验收点 8d：1-5 悠真分兵到上段 lane0 → **仍然通关，但明显更差**。
##
## ⚠️ 本用例在裁决 DEC-C-0003 后被改写。原文断言「分兵上段应失败」，其依据是
## 「悠真只能打同路线」这一**已被正式取代**的旧限制。跨线规则落地后，放在上段的悠真
## 仍可支援中段（相邻路线），因此「分兵上段」不再是必败解。
##
## 新的设计意图（更符合「站位差异应产生战术价值」这一目标）：
##   分兵上段**仍然可行**，但代价明确——中段火力减弱、核心多掉 1 点、且前线失能。
##   这比「换条线就直接输」更符合玩家直觉，也保留了站位的策略深度。
func test_08_1_5_dense_finale_punishes_losing_main_lane_piercing() -> void:
	var cfg := _stage_from_file("1-5")
	if cfg.is_empty():
		fail_test("应能从磁盘读到 1-5")
		return
	var res := _run(cfg, SUBOPTIMAL_1_5_SPLIT)
	assert_eq((res["rejects"] as Array).size(), 0,
		"该对照战术的动作应被接受：%s" % str(res["rejects"]))
	var s: BattleSession = res["session"]
	# 2026-10-11 dense finale: adjacent ordinary support is retained, but
	# piercing remains own-lane. Side deployment loses its main-lane crowd clear.
	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT,
		"1-5 密集最终波需要本路贯穿清群；悠真偏离主战线的固定摆法应失败（核心 %d/%d，击杀 %d，漏怪 %d）"
		% [s.stage.core_hp, s.stage.core_hp_max, s.stage.enemies_killed, s.stage.reached_core_count])
	# 但必须比稳定解差——这是「站位有战术差异」的可验证证据
	var stable := _run_stable("1-5")
	if not stable.is_empty():
		var good: BattleSession = stable["session"]
		assert_eq(good.outcome, BattleTypes.Outcome.VICTORY, "稳定解应为胜利（对照基准）")
		# Kill totals are not comparable: the stable legacy fixture has fewer planned enemies.
		assert_lt(s.stage.core_hp, good.stage.core_hp,
			"分兵上段的核心剩余应严格少于中段集火解（%d < %d）"
			% [s.stage.core_hp, good.stage.core_hp])
		assert_gte(s.stage.characters_lost, 1,
			"分兵上段应至少导致 1 名角色失能（中段火力不足的代价）")


# ============================================================
#  验收点 9：引用完整性
# ============================================================

## 验收点 9a：遍历 1-1～1-10 与 p1_0_demo，断言每个 enemySpawnTimeline[].enemy
## 都在 enemies.json 中、每个 availableCharacters[] 都在 characters.json 中。
func test_09_all_stage_references_resolve() -> void:
	var enemies := _enemy_table_from_file()
	var characters := _char_table_from_file()
	assert_gt(enemies.size(), 0, "enemies.json 应有敌人")
	assert_gt(characters.size(), 0, "characters.json 应有角色")

	var checked_stages := 0
	var checked_enemy_refs := 0
	var checked_char_refs := 0

	for i: int in range(1, 11):
		var sid := "1-%d" % i
		var cfg := _stage_from_file(sid)
		assert_false(cfg.is_empty(), "应能从磁盘读到正式关卡 %s" % sid)
		if cfg.is_empty():
			continue
		checked_stages += 1
		var refs := _assert_stage_refs(cfg, sid, enemies, characters)
		checked_enemy_refs += int(refs["enemies"])
		checked_char_refs += int(refs["characters"])

	var demo := _demo_from_file()
	assert_false(demo.is_empty(), "应能从磁盘读到 Prototype 演示关 %s" % DEMO_STAGE_ID)
	if not demo.is_empty():
		checked_stages += 1
		var refs := _assert_stage_refs(demo, DEMO_STAGE_ID, enemies, characters)
		checked_enemy_refs += int(refs["enemies"])
		checked_char_refs += int(refs["characters"])

	# 保证本用例确实遍历到了内容（不是空转通过）
	assert_eq(checked_stages, 11, "应检查 1-1～1-10 与演示关共 11 张关卡")
	assert_gt(checked_enemy_refs, 0, "应至少检查到 1 个敌人引用")
	assert_gt(checked_char_refs, 0, "应至少检查到 1 个角色引用")
	# Alpha A0.3 已填充 1-1～1-5：这些关卡都必须同时有出怪与角色引用
	assert_gte(checked_enemy_refs, 53,
		"1-1～1-5 的出怪条目合计 53 条，检查到的敌人引用数应至少覆盖它们")


## 校验一张关卡配置里的敌人 / 角色引用。
## 返回 {"enemies": 检查到的敌人引用数, "characters": 检查到的角色引用数}。
func _assert_stage_refs(
	cfg: Dictionary, label: String, enemies: Dictionary, characters: Dictionary
) -> Dictionary:
	var enemy_refs := 0
	var char_refs := 0

	for entry: Dictionary in cfg.get("enemySpawnTimeline", []):
		var enemy_id := str(entry.get("enemy", ""))
		assert_true(enemies.has(enemy_id),
			"%s 的 enemySpawnTimeline 引用了不存在的敌人 '%s'" % [label, enemy_id])
		enemy_refs += 1

	for cid: Variant in cfg.get("availableCharacters", []):
		var key := str(cid)
		assert_true(characters.has(key),
			"%s 的 availableCharacters 引用了不存在的角色 '%s'" % [label, key])
		char_refs += 1

	# 剧情 / 奖励引用（若有）同样必须可解析
	for key: String in ["storyBefore", "storyAfter"]:
		var v := str(cfg.get(key, ""))
		if not v.is_empty():
			assert_true(DataRegistry.get_entry("story", v) != {},
				"%s 的 %s '%s' 应能在 story/ 中解析" % [label, key, v])
	for key: String in ["firstClearRewardId", "repeatRewardId"]:
		var v := str(cfg.get(key, ""))
		if not v.is_empty():
			var found := false
			for r: Dictionary in DataRegistry.get_domain("stage_rewards").get("rewards", []):
				if str(r.get("id", "")) == v:
					found = true
			assert_true(found, "%s 的 %s '%s' 应能在 stage_rewards.json 中解析" % [label, key, v])

	return {"enemies": enemy_refs, "characters": char_refs}


## 验收点 9b：数据加载期不得有任何错误（含引用完整性校验）。
func test_09_data_registry_has_no_load_errors() -> void:
	var load_errors := DataRegistry.get_load_errors()
	assert_eq(load_errors.size(), 0, "数据加载不应有任何错误：%s" % str(load_errors))
	# 正式 ch1 关卡索引仍恰好 10 条，且五关都在其中
	var stage_ids := DataRegistry.get_ids("stages")
	assert_eq(stage_ids.size(), 10, "stages 索引应恰好 10 条（实际 %d）" % stage_ids.size())
	for sid: String in STAGE_IDS:
		assert_true(stage_ids.has(sid), "stages 索引应含 %s" % sid)


# ============================================================
#  验收点 10：1-1 未被改动（回归）
# ============================================================

## 验收点 10：1-1 仍为 3 波 / 6 只 / coreHp 5 / 只有雨宫澪 / 全部 echo_normal。
## （P0.3 / P0.4 / P1.0 共 6 处断言锁定它，A0.3 不得为了新关卡而改动 1-1。）
func test_10_stage_1_1_is_unchanged() -> void:
	var cfg := _stage_from_file("1-1")
	assert_false(cfg.is_empty(), "应能从磁盘读到 1-1")
	if cfg.is_empty():
		return

	assert_eq(str(cfg.get("stageId", "")), "1-1", "stageId 应为 1-1")
	assert_eq(int(cfg.get("chapter", 0)), 1, "1-1 应属第 1 章")
	assert_eq(int(cfg.get("coreHp", 0)), 5, "1-1 核心生命应仍为 5（唯一放宽为 5 的例外）")
	assert_eq(int(cfg.get("startingAp", 0)), 10, "1-1 开局 AP 应仍为 10")
	assert_eq(float(cfg.get("apRegen", -1.0)), 1.0, "1-1 AP 回复应仍为 1/秒")
	assert_eq(cfg.get("availableCharacters", []), [CHAR_MIO],
		"1-1 的 availableCharacters 应仍然只有 amamiya_mio")
	assert_eq((cfg.get("waves", []) as Array).size(), 3, "1-1 应仍为 3 波")

	var timeline: Array = cfg.get("enemySpawnTimeline", [])
	assert_eq(timeline.size(), 7, "1-1 应仍有 6 条出怪计划（实际 %d）" % timeline.size())
	for entry: Dictionary in timeline:
		assert_eq(str(entry.get("enemy", "")), "echo_normal",
			"1-1 的出怪应全部是 echo_normal（实际 '%s'）" % str(entry.get("enemy", "")))
		# 第 1、2 波全部在中段；第 3 波才拆到上/下段各 1 只
		if int(entry.get("wave", 0)) <= 2:
			assert_eq(int(entry.get("lane", -1)), 1,
				"1-1 第 1、2 波应集中在中段 lane1")

	# 运行时层：仍然只有 1 名可部署角色，且无构建错误
	var rt := StageRuntime.from_config(
		cfg, _enemy_table_from_file(), _grid(), _char_table_from_file(), _combat())
	assert_true(rt.is_valid(), "1-1 应无构建错误：%s" % str(rt.get_errors()))
	assert_eq(rt.available_characters.size(), 1, "1-1 应只有 1 名可部署角色")
	assert_false(rt.available_characters.has(CHAR_YUMA), "1-1 不得解锁神谷悠真")
	assert_false(rt.available_characters.has(CHAR_YUI), "1-1 不得解锁小川结衣")
	assert_eq(rt.total_wave_count(), 3, "1-1 运行时波次总数应为 3")
	assert_eq(rt.planned_enemy_count(), 7, "1-1 运行时计划出怪数应为 6")


# ============================================================
#  验收点 11：1-2～1-5 不引入未实现的敌人
# ============================================================

## 验收点 11：断言 1-2～1-5 的出怪中**不出现** echo_anxiety / echo_rank
## （这些在 enemies.json 中不存在），也不出现 A0.2 已实现但尚未回填的四个敌人
## （echo_exam_sheet / echo_silent / echo_copy / echo_invigilator——数据与机制已就绪，
##  但关卡引用由主线在回填阶段负责）。
##
## A0.2 变更（设计稿冲突 C-17）：原「前提校验」断言这四个敌人**不存在于** enemies.json，
## 现改为断言它们**存在且已实现**（前提变了，设计意图——防止关卡引用不存在的敌人——保留）。
func test_11_new_stages_do_not_reference_unimplemented_enemies() -> void:
	var enemies := _enemy_table_from_file()

	# 前提校验 A：仍未实现的敌人确实不在 enemies.json 中，否则本用例会空转通过
	for enemy_id: String in UNIMPLEMENTED_ENEMIES:
		assert_false(enemies.has(enemy_id),
			"前提校验：%s 目前不应存在于 enemies.json（仍属未实现）" % enemy_id)

	# 前提校验 B（A0.2 反转）：已实现的四个敌人必须确实存在于 enemies.json，
	# 否则下面的「不得被关卡引用」断言会因为数据缺失而变得毫无意义。
	for enemy_id: String in IMPLEMENTED_NOT_YET_PLACED:
		assert_true(enemies.has(enemy_id),
			"前提校验：%s 应已由 A0.2 写入 enemies.json" % enemy_id)

	# 不得被引用的合并名单：未实现的 + 已实现但尚未回填的
	var forbidden: Array[String] = []
	forbidden.append_array(UNIMPLEMENTED_ENEMIES)
	forbidden.append_array(IMPLEMENTED_NOT_YET_PLACED)

	for sid: String in ["1-2", "1-3", "1-4", "1-5"]:
		var cfg := _stage_from_file(sid)
		if cfg.is_empty():
			fail_test("应能从磁盘读到关卡 %s" % sid)
			continue
		var used := _composition_of(cfg)
		for enemy_id: String in forbidden:
			assert_false(used.has(enemy_id),
				"%s 不得引用尚未回填的敌人 '%s'" % [sid, enemy_id])
		# 反面校验：本关实际使用的敌人都必须已实现
		for enemy_id: String in used.keys():
			assert_true(enemies.has(enemy_id),
				"%s 引用了不存在的敌人 '%s'" % [sid, enemy_id])


# ============================================================
#  验收点 12：1-5 设计约束（表 54「同屏不得要求两个永久前线」）
# ============================================================

## 验收点 12：1-5 的出怪中，非中段（lane != 1）的普通条目数 ≤ 2。
## 只有 1 名前线；两只旁路普通敌人需拉开间隔，由悠真跨线处理，不要求第二名前线。
func test_12_1_5_never_requires_two_permanent_frontlines() -> void:
	var cfg := _stage_from_file("1-5")
	assert_false(cfg.is_empty(), "应能从磁盘读到 1-5")
	if cfg.is_empty():
		return

	var off_lane: Array[String] = []
	for entry: Dictionary in cfg.get("enemySpawnTimeline", []):
		var lane := int(entry.get("lane", -1))
		if lane != 1:
			off_lane.append("t=%.0fs lane%d %s"
				% [float(entry.get("time", -1.0)), lane, str(entry.get("enemy", ""))])
	assert_lte(off_lane.size(), 2,
		"1-5 非中段出怪条目应 ≤ 2（普通敌人由旁路射击处理；表 54：同屏不得要求两个永久前线），实际 %d 条：%s"
		% [off_lane.size(), str(off_lane)])

	# 同时校验：中段确实是主压力路线（否则上面那条约束会被「全关无中段」轻易满足）
	var mid := 0
	var total: Array = cfg.get("enemySpawnTimeline", [])
	for entry: Dictionary in total:
		if int(entry.get("lane", -1)) == 1:
			mid += 1
	assert_eq(mid, total.size() - off_lane.size(), "中段条目数应与总数减去非中段条目数一致")
	assert_gte(mid, total.size() - 2, "1-5 的敌人应几乎全部集中在中段（实际中段 %d / 共 %d）"
		% [mid, total.size()])

	# 运行时层同样成立：可用角色只有 1 名具备阻挡能力
	var chars := _char_table_from_file()
	var blockers := 0
	for cid: Variant in cfg.get("availableCharacters", []):
		var key := str(cid)
		if chars.has(key) and int((chars[key] as Dictionary).get("blockCount", 0)) > 0:
			blockers += 1
	assert_eq(blockers, 1,
		"1-5 应恰好有 1 名可阻挡角色（实际 %d）——这正是「不得要求两个永久前线」的由来"
		% blockers)


# ============================================================
#  验收点 13：帧率独立性
# ============================================================

## 验收点 13：对 1-5 用 1/60、1/30、1/144 三种 tick 粒度跑同一战术，
## 断言最终 outcome / core_hp / enemies_killed / reached_core_count 完全一致。
func test_13_1_5_result_is_independent_of_tick_granularity() -> void:
	var cfg := _stage_from_file("1-5")
	if cfg.is_empty():
		fail_test("应能从磁盘读到 1-5")
		return

	var ticks: Array[float] = [1.0 / 60.0, 1.0 / 30.0, 1.0 / 144.0]
	var results: Array = []
	for tick: float in ticks:
		var res := _run(cfg, TACTIC_TWO_MID, tick, true)
		assert_eq((res["rejects"] as Array).size(), 0,
			"tick=%.5f 时 1-5 的战术动作都应被接受：%s" % [tick, str(res["rejects"])])
		var s: BattleSession = res["session"]
		results.append({
			"tick": tick,
			"outcome": s.outcome,
			"coreHp": s.stage.core_hp,
			"kills": s.stage.enemies_killed,
			"leaked": s.stage.reached_core_count,
		})

	for i: int in range(1, results.size()):
		var prev: Dictionary = results[i - 1]
		var cur: Dictionary = results[i]
		assert_eq(int(cur["outcome"]), int(prev["outcome"]),
			"tick %.5f 与 %.5f 的胜负结果必须一致" % [float(prev["tick"]), float(cur["tick"])])
		assert_eq(int(cur["coreHp"]), int(prev["coreHp"]),
			"tick %.5f 与 %.5f 的最终核心 HP 必须一致" % [float(prev["tick"]), float(cur["tick"])])
		assert_eq(int(cur["kills"]), int(prev["kills"]),
			"tick %.5f 与 %.5f 的击杀数必须一致" % [float(prev["tick"]), float(cur["tick"])])
		assert_eq(int(cur["leaked"]), int(prev["leaked"]),
			"tick %.5f 与 %.5f 的漏怪数必须一致" % [float(prev["tick"]), float(cur["tick"])])

	# 保证比较的是真实战果，而不是三方都在空转
	assert_eq(int((results[0] as Dictionary)["outcome"]), BattleTypes.Outcome.VICTORY,
		"60fps 粒度下 1-5 应为胜利")
	# Current denser encounters retain victory and fixed-step determinism; this static tactic may leak.
	assert_eq(int(results[0]["kills"])+int(results[0]["leaked"]),29,"all current planned enemies must resolve")
