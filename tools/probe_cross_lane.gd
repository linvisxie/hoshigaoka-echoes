## 裁决 DEC-C-0003 一次性验证工具：跨路线攻击规则 + 三路线防守实测。
##
## 目的（第一/第二阶段验收依据）：
##   ① 逐条验证远程跨线规则（中路三路可选、边路只能本路+中路、上下路互不打）；
##   ② 验证跨线**不**增加攻击频率、**不**复制攻击次数（每次仍只选一个目标）；
##   ③ 验证玩家角色的跨线范围变化**没有**让敌人的攻击范围随之变化；
##   ④ 重跑 1-1～1-5 与 Prototype 演示关，实测「稳定通关 / 零漏怪可达性 / 失败路径 / 站位差异」。
##
## 用法：
##   godot --headless --path <proj> --script res://tools/probe_cross_lane.gd
extends SceneTree

const STAGE_DIR := "res://data/stages/ch1/"
const DEMO_PATH := "res://data/stages/prototype/p1_0_demo.json"
const MAX_SIM_SECONDS := 900.0
const EPS := 0.0001

var _fails: Array[String] = []
var _passes: int = 0


func _init() -> void:
	var chars := _load_char_table()
	var enemies := _load_enemy_table()
	var balance := _load_json("res://data/balance.json")

	if chars.is_empty() or enemies.is_empty() or balance.is_empty():
		print("[FATAL] 数据加载失败")
		quit(2)
		return

	print("=".repeat(78))
	print("  DEC-C-0003 跨路线攻击规则验证")
	print("=".repeat(78))
	_verify_cross_lane_rules(chars)

	print("")
	print("=".repeat(78))
	print("  跨线不改变攻击频率 / 不复制攻击次数")
	print("=".repeat(78))
	_verify_no_extra_attacks(chars, enemies, balance)

	print("")
	print("=".repeat(78))
	print("  敌人侧攻击范围未受影响（玩家改动不得外溢）")
	print("=".repeat(78))
	_verify_enemy_side_unchanged(enemies)

	print("")
	print("=".repeat(78))
	print("  三路线防守实测：1-1～1-5 + Prototype 演示关")
	print("=".repeat(78))
	_verify_stages(chars, enemies, balance)

	print("")
	print("=".repeat(78))
	print("  结果：%d 项通过，%d 项失败" % [_passes, _fails.size()])
	print("=".repeat(78))
	for f: String in _fails:
		print("  [FAIL] " + f)
	quit(0 if _fails.is_empty() else 1)


# ============================================================
#  数据加载
# ============================================================

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _load_char_table() -> Dictionary:
	var d := _load_json("res://data/characters.json")
	var out := {}
	for c: Dictionary in d.get("characters", []):
		out[str(c.get("id", ""))] = c
	return out


func _load_enemy_table() -> Dictionary:
	var d := _load_json("res://data/enemies.json")
	var out := {}
	for e: Dictionary in d.get("enemies", []):
		out[str(e.get("id", ""))] = e
	return out


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("  [PASS] " + msg)
	else:
		_fails.append(msg)
		print("  [FAIL] " + msg)


# ============================================================
#  ① 跨线规则逐条验证
# ============================================================

func _verify_cross_lane_rules(chars: Dictionary) -> void:
	var yuma_cfg: Dictionary = chars.get("kamiya_yuma", {})
	_check(not yuma_cfg.is_empty(), "神谷悠真配置存在")
	if yuma_cfg.is_empty():
		return
	var rng: Dictionary = yuma_cfg.get("attackRange", {})
	_check(float(rng.get("rangeTiles", 0.0)) == 4.0, "悠真本路线射程 = 4.0 格（保持原值）")
	_check(float(rng.get("adjacentLaneRangeTiles", 0.0)) == 3.0, "悠真相邻路线射程 = 3.0 格（第一轮候选值）")
	_check(int(rng.get("maxLaneDelta", 0)) == 1, "悠真 maxLaneDelta = 1")
	_check(bool(rng.get("allowCrossLane", false)), "悠真显式声明 allowCrossLane = true")
	_check(int(rng.get("targetLimit", 1)) == 1, "悠真 targetLimit = 1（每次只打一个目标）")

	# 用临时探针实例验证路线闸门（不进入战斗）
	var probe := CharacterRuntime.from_config(yuma_cfg, 1, 1, 0, {})

	# --- 中路（lane 1）：上/中/下三路合法 ---
	_check(probe.can_attack_lane(0), "中路角色可攻击上路")
	_check(probe.can_attack_lane(1), "中路角色可攻击本路（中路）")
	_check(probe.can_attack_lane(2), "中路角色可攻击下路")
	_check(absf(probe.attack_range_for_lane(0) - 3.0) < EPS, "中路上路目标用相邻射程 3.0")
	_check(absf(probe.attack_range_for_lane(1) - 4.0) < EPS, "中路本路目标用本路射程 4.0")
	_check(absf(probe.attack_range_for_lane(2) - 3.0) < EPS, "中路下路目标用相邻射程 3.0")

	# --- 上路（lane 0）：本路 + 中路，禁止下路 ---
	var up := CharacterRuntime.from_config(yuma_cfg, 1, 0, 0, {})
	_check(up.can_attack_lane(0), "上路角色可攻击上路（本路）")
	_check(up.can_attack_lane(1), "上路角色可攻击中路（相邻）")
	_check(not up.can_attack_lane(2), "**上路角色不得攻击下路**（laneDelta=2 被拒）")
	_check(absf(up.attack_range_for_lane(2)) < EPS, "上路 → 下路的有效射程为 0（不可攻击）")

	# --- 下路（lane 2）：本路 + 中路，禁止上路 ---
	var low := CharacterRuntime.from_config(yuma_cfg, 1, 2, 0, {})
	_check(low.can_attack_lane(2), "下路角色可攻击下路（本路）")
	_check(low.can_attack_lane(1), "下路角色可攻击中路（相邻）")
	_check(not low.can_attack_lane(0), "**下路角色不得攻击上路**（laneDelta=2 被拒）")

	# --- 前线角色不得跨线（澪 maxLaneDelta=0）---
	var mio_cfg: Dictionary = chars.get("amamiya_mio", {})
	var mio := CharacterRuntime.from_config(mio_cfg, 3, 1, 0, {})
	_check(not mio.can_attack_lane(0), "前线角色（雨宫澪）不得跨线攻击上路")
	_check(not mio.can_attack_lane(2), "前线角色（雨宫澪）不得跨线攻击下路")
	_check(mio.can_attack_lane(1), "前线角色可攻击本路")
	_check(not mio.allow_cross_lane, "前线角色 allowCrossLane = false")

	# --- 治疗角色仍走 manhattan + maxLaneDelta，未被本次裁决改动 ---
	var yui_cfg: Dictionary = chars.get("ogawa_yui", {})
	var yui := CharacterRuntime.from_config(yui_cfg, 1, 1, 0, {})
	_check(int(yui.max_lane_delta) == 1, "结衣治疗 maxLaneDelta 仍为 1（未被本次改动影响）")
	_check(not yui.allow_cross_lane, "结衣未声明 allowCrossLane（治疗走既有路径）")

	# --- 射程边界：逻辑格判定，且前方方向性成立 ---
	# 中路 col1，本路射程 4.0 → x=5.0 恰好命中（delta 4.0）
	_check(probe.is_target_in_attack_range(1, 5.0), "本路 x=5.0（delta 4.0）恰好在射程内")
	_check(not probe.is_target_in_attack_range(1, 5.1), "本路 x=5.1（delta 4.1）在射程外")
	# 相邻路射程 3.0 → 上路 x=4.0 命中（delta 3.0），x=4.1 不命中
	_check(probe.is_target_in_attack_range(0, 4.0), "相邻路上 x=4.0（delta 3.0）恰好在射程内")
	_check(not probe.is_target_in_attack_range(0, 4.1), "相邻路上 x=4.1（delta 3.1）在射程外")
	# 方向性：角色身后的敌人不可攻击
	_check(not probe.is_target_in_attack_range(1, 0.5), "角色身后的目标（x < column）不可攻击（方向性）")
	_check(not probe.is_target_in_attack_range(0, 0.5), "相邻路角色身后的目标不可攻击")


# ============================================================
#  ② 跨线不增加攻击频率 / 不复制攻击次数
# ============================================================

func _verify_no_extra_attacks(
	chars: Dictionary, enemies: Dictionary, balance: Dictionary
) -> void:
	var grid := BattleGrid.from_layout(balance.get("layout", {}))
	var combat: Dictionary = balance.get("combat", {})

	# --- 场景 A：同路 1 个目标 vs 三路各有 1 个目标，攻击次数必须相同 ---
	var same := _make_runtime(chars, enemies, grid, combat)
	var yuma_a := same.deploy_character("kamiya_yuma", 1, 1)
	_check(yuma_a.ok, "悠真可部署到中路 col1")
	# 本路放一个敌人（x=3.0，delta 2.0）
	var e_same := EnemyRuntime.from_config(enemies["echo_normal"], 1, 1, 1)
	e_same.logical_x = 3.0
	e_same.hp = 1000000
	same.enemies.append(e_same)

	var multi := _make_runtime(chars, enemies, grid, combat)
	var yuma_b := multi.deploy_character("kamiya_yuma", 1, 1)
	_check(yuma_b.ok, "悠真可部署到中路 col1（多目标场景）")
	# 三路各放一个敌人，全部在射程内
	var placed: Array[EnemyRuntime] = []
	for lane_i: int in [0, 1, 2]:
		var e := EnemyRuntime.from_config(enemies["echo_normal"], lane_i, 100 + lane_i, 1)
		e.logical_x = 3.0
		e.hp = 1000000
		multi.enemies.append(e)
		placed.append(e)

	# 跑 1 秒（约 0.77 个攻击间隔），统计各敌人受到的伤害次数
	_step_n(same, 1.0)
	_step_n(multi, 1.0)

	var same_attacks := 1 if e_same.hp < 1000000 else 0
	var multi_hits := 0
	for e: EnemyRuntime in placed:
		if e.hp < 1000000:
			multi_hits += 1

	_check(same_attacks == 1, "同路单目标：1 秒内至少攻击 1 次")
	_check(multi_hits == 1,
		"三路同时有目标时**仍然只打 1 个目标**（实际 %d 个被打）——跨线不复制攻击次数" % multi_hits)

	# --- 场景 B：跨线目标的攻击频率与同路一致（比较冷却）---
	# 同路：目标在 x=3.0（delta 2.0，本路射程 4.0 内）
	var rt_same := _make_runtime(chars, enemies, grid, combat)
	rt_same.deploy_character("kamiya_yuma", 1, 1)
	var t1 := EnemyRuntime.from_config(enemies["echo_normal"], 1, 1, 1)
	t1.logical_x = 3.0
	t1.hp = 1000000
	rt_same.enemies.append(t1)
	_step_n(rt_same, 0.0167)
	var yuma_same := rt_same.get_character_by_id("kamiya_yuma")
	var cd_same := yuma_same.attack_cooldown

	# 跨线：目标在上路 x=3.0（delta 2.0，相邻射程 3.0 内）
	var rt_cross := _make_runtime(chars, enemies, grid, combat)
	rt_cross.deploy_character("kamiya_yuma", 1, 1)
	var t2 := EnemyRuntime.from_config(enemies["echo_normal"], 0, 1, 1)
	t2.logical_x = 3.0
	t2.hp = 1000000
	rt_cross.enemies.append(t2)
	_step_n(rt_cross, 0.0167)
	var yuma_cross := rt_cross.get_character_by_id("kamiya_yuma")
	var cd_cross := yuma_cross.attack_cooldown

	_check(absf(cd_same - cd_cross) < EPS,
		"同路与跨线的攻击冷却完全相同（%.4f vs %.4f）——跨线不加快也不减慢攻击频率"
		% [cd_same, cd_cross])
	_check(absf(cd_cross - 1.3) < EPS,
		"跨线攻击后进入完整 1.3 秒冷却（实际 %.4f）" % cd_cross)

	# --- 场景 C：优先打最靠近核心的目标（跨线不改变优先级）---
	var rt_pri := _make_runtime(chars, enemies, grid, combat)
	rt_pri.deploy_character("kamiya_yuma", 1, 1)
	# 上路目标更靠近核心（x=1.5），本路目标较远（x=3.0）
	var near_upper := EnemyRuntime.from_config(enemies["echo_normal"], 0, 1, 1)
	near_upper.logical_x = 1.5
	near_upper.hp = 1000000
	var far_mid := EnemyRuntime.from_config(enemies["echo_normal"], 1, 2, 1)
	far_mid.logical_x = 3.0
	far_mid.hp = 1000000
	rt_pri.enemies.append(near_upper)
	rt_pri.enemies.append(far_mid)
	_step_n(rt_pri, 0.0167)
	_check(near_upper.hp < 1000000,
		"跨线目标若更靠近核心，仍按 D-11 优先级被优先攻击（跨线不改变优先级）")
	_check(far_mid.hp == 1000000, "较远的本路目标本轮未被攻击（单目标约束）")


# ============================================================
#  ③ 敌人侧攻击范围未被改动
# ============================================================

func _verify_enemy_side_unchanged(enemies: Dictionary) -> void:
	# 试卷飞灵：射程 3 格、maxLaneDelta 0（仅同路线）——不得因玩家侧改动而变化
	var flyer: Dictionary = enemies.get("echo_exam_sheet", {})
	_check(not flyer.is_empty(), "试卷飞灵配置存在")
	if flyer.is_empty():
		return
	var mech: Dictionary = flyer.get("mechanic", {})
	_check(float(mech.get("rangeTiles", 0.0)) == 3.0,
		"试卷飞灵射程仍为 3 格（未被玩家侧改动外溢影响）")
	_check(int(mech.get("maxLaneDelta", -1)) == 0,
		"试卷飞灵 maxLaneDelta 仍为 0（敌人仍只打同路线）")

	# 用运行时实例复核
	var e := EnemyRuntime.from_config(flyer, 1, 1, 1)
	_check(absf(e.ranged_range_tiles() - 3.0) < EPS, "飞灵运行时射程 = 3.0")
	_check(e.ranged_max_lane_delta() == 0, "飞灵运行时 maxLaneDelta = 0")


# ============================================================
#  ④ 三路线防守实测
# ============================================================

func _verify_stages(
	chars: Dictionary, enemies: Dictionary, balance: Dictionary
) -> void:
	var grid := BattleGrid.from_layout(balance.get("layout", {}))
	var combat: Dictionary = balance.get("combat", {})

	# --- Prototype 演示关 ---
	var demo := _load_json(DEMO_PATH)
	if not demo.is_empty():
		_run_stage_case("P1.0演示关", demo, chars, enemies, grid, combat, [
			{"name": "不部署（应失败）", "acts": []},
			{"name": "澪中段col3 + 悠真中段col1（稳定解）", "acts": [
				{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
				{"t": 12.5, "c": "kamiya_yuma", "col": 1, "lane": 1},
			]},
		])
	else:
		_fails.append("Prototype 演示关读取失败")

	# --- 1-1 ~ 1-5 ---
	for i: int in range(1, 6):
		var sid := "1-%d" % i
		var cfg := _load_json(STAGE_DIR + sid + ".json")
		if cfg.is_empty():
			_fails.append("关卡 %s 读取失败" % sid)
			continue
		var cases: Array = _cases_for(sid)
		_run_stage_case(sid, cfg, chars, enemies, grid, combat, cases)


func _cases_for(sid: String) -> Array:
	match sid:
		"1-1":
			return [
				{"name": "不部署（应失败）", "acts": []},
				{"name": "澪中段col3（不换线，对照）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
				]},
				{"name": "★澪换线：中段→上段→下段（零漏怪解）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 30.0, "a": "retreat", "c": "amamiya_mio"},
					{"t": 50.5, "c": "amamiya_mio", "col": 3, "lane": 0},
					{"t": 57.0, "a": "retreat", "c": "amamiya_mio"},
					{"t": 77.5, "c": "amamiya_mio", "col": 3, "lane": 2},
				]},
				{"name": "澪上段col3", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 0},
				]},
			]
		"1-2":
			return [
				{"name": "不部署（应失败）", "acts": []},
				{"name": "澪中段col3（稳定解）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
				]},
				{"name": "★澪换线：中段→上段（t=79撤退，零漏怪解）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 79.0, "a": "retreat", "c": "amamiya_mio"},
					{"t": 99.5, "c": "amamiya_mio", "col": 3, "lane": 0},
				]},
				{"name": "对照：晚 2 秒撤退即被 20s 冷却卡住", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 81.0, "a": "retreat", "c": "amamiya_mio"},
					{"t": 99.5, "c": "amamiya_mio", "col": 3, "lane": 0},
				]},
				{"name": "澪上段col3", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 0},
				]},
				{"name": "澪下段col3", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 2},
				]},
			]
		"1-3":
			return [
				{"name": "不部署（应失败）", "acts": []},
				{"name": "★澪中段col3 + 悠真中段col1（零漏怪解）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 12.5, "c": "kamiya_yuma", "col": 1, "lane": 1},
				]},
				{"name": "只放澪（对照）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
				]},
				{"name": "悠真放上段col1（跨线支援中段）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 12.5, "c": "kamiya_yuma", "col": 1, "lane": 0},
				]},
			]
		"1-4":
			return [
				{"name": "不部署（应失败）", "acts": []},
				{"name": "★澪中段col3 + 悠真中段col1（零漏怪解）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 12.5, "c": "kamiya_yuma", "col": 1, "lane": 1},
				]},
				{"name": "只放澪（对照）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
				]},
				{"name": "★悠真上段col1（跨线支援中段，同样零漏怪）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 12.5, "c": "kamiya_yuma", "col": 1, "lane": 0},
				]},
			]
		"1-5":
			return [
				{"name": "不部署（应失败）", "acts": []},
				{"name": "★澪中段col3 + 悠真中段col1（垂直切片零漏怪解）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 12.5, "c": "kamiya_yuma", "col": 1, "lane": 1},
				]},
				{"name": "只放澪（对照）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
				]},
				{"name": "悠真上段col1（跨线支援中段）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 12.5, "c": "kamiya_yuma", "col": 1, "lane": 0},
				]},
				{"name": "悠真下段col1（跨线支援中段）", "acts": [
					{"t": 0.5, "c": "amamiya_mio", "col": 3, "lane": 1},
					{"t": 12.5, "c": "kamiya_yuma", "col": 1, "lane": 2},
				]},
			]
	return []


func _run_stage_case(
	label: String,
	cfg: Dictionary,
	chars: Dictionary,
	enemies: Dictionary,
	grid: BattleGrid,
	combat: Dictionary,
	cases: Array
) -> void:
	print("")
	print("  --- %s ---" % label)
	for c: Dictionary in cases:
		var rt := StageRuntime.from_config(cfg, enemies, grid, chars, combat)
		if not rt.is_valid():
			_fails.append("%s 构建失败：%s" % [label, str(rt.get_errors())])
			print("    [FAIL] 构建失败：%s" % str(rt.get_errors()))
			continue
		var rejects: Array[String] = []
		for act: Dictionary in c["acts"]:
			_advance_to(rt, float(act["t"]))
			var verb := str(act.get("a", "deploy"))
			if verb == "retreat":
				var rr := rt.withdraw_character_by_id(str(act["c"]))
				if not rr.ok:
					rejects.append("撤退 %s:%s" % [act["c"], rr.reason_text()])
				continue
			var dr := rt.deploy_character(str(act["c"]), int(act["col"]), int(act["lane"]))
			if not dr.ok:
				rejects.append("%s@col%d/lane%d:%s"
					% [act["c"], int(act["col"]), int(act["lane"]), dr.reason_text()])
		_advance_to(rt, MAX_SIM_SECONDS)

		var outcome := _outcome_of(rt)
		print("    %-42s %s  核心 %d/%d  生成 %d/%d  击杀 %d  漏怪 %d  失能 %d  %.1fs"
			% [c["name"], outcome,
				rt.core_hp, rt.core_hp_max,
				rt.spawned_enemy_count(), rt.planned_enemy_count(),
				rt.enemies_killed, rt.reached_core_count, rt.characters_lost,
				rt.elapsed_seconds])
		if not rejects.is_empty():
			print("      拒绝的动作：%s" % str(rejects))

		# 断言：不部署必须失败
		if str(c["name"]).begins_with("不部署"):
			_check(outcome == "失败", "%s：不部署必须失败（实际 %s）" % [label, outcome])
		elif str(c["name"]).begins_with("对照"):
			# 负面对照：预期会被拒（用于证明约束真实存在），因此不校验 rejects 为空。
			# 但必须**确实被拒**，否则说明该约束已失效、对照失去意义。
			_check(not rejects.is_empty(),
				"%s：%s 应确实被规则拒绝（证明该约束真实存在），实际拒绝 %s"
				% [label, c["name"], str(rejects)])
		else:
			# 非「不部署」的对照组不强制胜负，但必须无动作被拒
			_check(rejects.is_empty(),
				"%s：%s 的动作应全部被接受（拒绝 %s）" % [label, c["name"], str(rejects)])
			# 标星号的用例是「零漏怪可达性」证据，必须真正零漏怪
			if str(c["name"]).begins_with("★"):
				_check(rt.reached_core_count == 0 and rt.core_hp == rt.core_hp_max,
					"%s：%s 应达成零漏怪且核心满值（实际漏 %d、核心 %d/%d）"
					% [label, c["name"], rt.reached_core_count, rt.core_hp, rt.core_hp_max])


func _cases_with_zero_leak_check(label: String, rt: StageRuntime, name: String) -> void:
	if rt.reached_core_count == 0:
		print("      ★ 零漏怪达成：%s / %s" % [label, name])


# ============================================================
#  运行时辅助
# ============================================================

func _make_runtime(
	chars: Dictionary, enemies: Dictionary, grid: BattleGrid, combat: Dictionary
) -> StageRuntime:
	var cfg := {
		"stageId": "probe",
		"coreHp": 3,
		"startingAp": 30,
		"apRegen": 1,
		"availableCharacters": ["amamiya_mio", "kamiya_yuma", "ogawa_yui"],
		"enemySpawnTimeline": [],
	}
	var rt := StageRuntime.from_config(cfg, enemies, grid, chars, combat)
	rt.ap = 30
	return rt


func _advance_to(rt: StageRuntime, target: float) -> void:
	var guard := 0
	while rt.elapsed_seconds < target - EPS and guard < 200000:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1
		_apply_outcome_stop(rt)


func _step_n(rt: StageRuntime, seconds: float) -> void:
	var steps := int(round(seconds / StageRuntime.LOGIC_STEP_SECONDS))
	for _i: int in range(steps):
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		_apply_outcome_stop(rt)


func _apply_outcome_stop(rt: StageRuntime) -> void:
	if rt.core_hp <= 0:
		rt.running = false
		return
	# 胜利也要停：否则「已通关」的用例会空转到 MAX_SIM_SECONDS，
	# 把 900.0s 这种无意义的时长写进报告。
	if rt.all_waves_cleared() and not rt.has_living_enemies():
		rt.running = false


func _outcome_of(rt: StageRuntime) -> String:
	if rt.core_hp <= 0:
		return "失败"
	if rt.all_waves_cleared() and not rt.has_living_enemies():
		return "胜利"
	return "未结束"
