## 独立复核：C-8「复制体导致战斗无法判定胜负」的对照实验。
##
## 由主线（Lead）自行编写，用于**独立验证** A0.2 子智能体的结论，
## 而不是采信其报告。做法：
##   ① 用真实数据构建一个含作弊纸偶（echo_copy）的最小关卡；
##   ② 让复制体必然触发（角色输出足够高）；
##   ③ 观察战斗能否收敛到胜负、以及波次计数是否自洽。
##
## 用法：
##   godot --headless --path . res://tools/probe_c8_wave_attribution.tscn
extends Node

const SAVE_PATH := "user://save/savegame.json"


func _ready() -> void:
	print("=== C-8 独立复核：含作弊纸偶的关卡能否正常判定胜负 ===")
	await get_tree().process_frame

	# 用真实数据构建一个最小关卡：中段放 2 只作弊纸偶 + 1 只普通
	var stage := {
		"stageId": "probe_c8",
		"coreHp": 3,
		"startingAp": 30,
		"apRegen": 1,
		"availableCharacters": ["amamiya_mio", "kamiya_yuma"],
		"enemySpawnTimeline": [
			{"time": 1.0, "lane": 1, "enemy": "echo_copy", "wave": 1},
			{"time": 3.0, "lane": 1, "enemy": "echo_copy", "wave": 2},
		],
		"waves": [
			{"number": 1, "label": "W1", "clearCondition": "ALL_ENEMIES_DEFEATED"},
			{"number": 2, "label": "W2", "clearCondition": "ALL_ENEMIES_DEFEATED"},
		],
		"battleRewards": {},
		"firstClearRewardId": "",
		"repeatRewardId": "",
	}

	var enemy_table := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		enemy_table[str(e.get("id", ""))] = e
	var char_table := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		char_table[str(c.get("id", ""))] = c
	var grid := BattleGrid.from_layout(DataRegistry.get_layout())
	var combat: Dictionary = DataRegistry.get_domain("balance").get("combat", {})

	var session := BattleSession.new()
	var errs := session.setup(stage, enemy_table, grid, char_table, combat)
	if not errs.is_empty():
		print("构建失败：%s" % str(errs))
		get_tree().quit(1)
		return

	# 部署两人集火中段，保证能打死作弊纸偶（触发复制）
	session.deploy_character("amamiya_mio", 3, 1)
	session.deploy_character("kamiya_yuma", 1, 1)

	var step := StageRuntime.LOGIC_STEP_SECONDS
	var t := 0.0
	var max_t := 300.0
	while session.is_running() and t < max_t:
		session.tick(step)
		t += step

	var s := session.stage
	print("结果: %s" % BattleTypes.outcome_name(session.outcome))
	print("用时: %.1fs（上限 %.0fs）" % [s.elapsed_seconds, max_t])
	print("Wave: %d/%d ｜ 生成 %d/%d ｜ 击杀 %d ｜ 漏怪 %d"
		% [s.current_wave_number(), s.total_wave_count(),
			s.spawned_enemy_count(), s.planned_enemy_count(),
			s.enemies_killed, s.reached_core_count])
	print("场上存活: %d" % s.enemies.size())
	# 区分「数组里还有条目」与「真正还能作战」：
	# enemies 数组可能仍含已死亡（hp<=0）或已抵达核心（REACHED_CORE）尚未被移除的条目，
	# 而胜负判定用的是 has_living_enemies()。两者必须分开看，否则会误判成"带活怪判胜"。
	var still_active := 0
	var detail: Array[String] = []
	for e: EnemyRuntime in s.enemies:
		if e.is_active():
			still_active += 1
		detail.append("%s#%d hp=%d/%d state=%s derived=%s" % [
			e.enemy_id, e.instance_id, e.hp, e.hp_max,
			BattleTypes.enemy_state_name(e.state), str(e.is_derived)])
	print("其中真正可作战（is_active）: %d" % still_active)
	print("has_living_enemies(): %s" % str(s.has_living_enemies()))
	for d: String in detail:
		print("  剩余条目: %s" % d)

	# 逐波计数自洽性
	print("逐波状态:")
	for i: int in range(s.total_wave_count()):
		var st: Dictionary = s.wave_state_at(i)
		print("  Wave %s: spawned=%s killed=%s leaked=%s derivedKilled=%s"
			% [st.get("number"), st.get("spawned"), st.get("killed"),
				st.get("leaked"), st.get("killedDerived", 0)])

	var ok := session.outcome == BattleTypes.Outcome.VICTORY
	print("")
	print("=== 判定：%s ===" % ("通过（战斗正常收敛到胜利）" if ok else "**未通过**（战斗未收敛）"))
	session.free()
	get_tree().quit(0 if ok else 1)
