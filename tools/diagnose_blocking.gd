## 一次性工具：细粒度诊断 1-1 的阻挡与攻击时序。
##
## 用于确认"阻挡确实建立（敌人进入 BLOCKED 且有 blocked_by）"，
## 而不是敌人仅仅在射程内被击杀。
##
## 用法：
##   godot --headless --path <proj> --script res://tools/diagnose_blocking.gd
extends SceneTree

const STAGE_ID := "1-1"
const CHAR_ID := "amamiya_mio"


func _initialize() -> void:
	var data := _load_data()
	var stage: Dictionary = data["stage"]
	var grid: BattleGrid = data["grid"]

	var session := BattleSession.new()
	session.setup(stage, data["enemies"], grid, data["characters"], data["combat"])
	session.deploy_character(CHAR_ID, 2, 1)  # 中段 col2

	print("=== 1-1 阻挡/攻击时序诊断（雨宫澪 @ col2 lane1）===")
	var step := StageRuntime.LOGIC_STEP_SECONDS
	var t := 0.0
	var last_report := -1.0
	var block_events := 0
	var attack_events := 0
	var enemy_attack_events := 0
	var seen_blocked := {}
	var seen_attackers := {}

	while session.is_running() and t < 300.0:
		var chars_before := {}
		for c: CharacterRuntime in session.stage.characters:
			chars_before[c.instance_id] = c.hp
		var enemies_before := {}
		for e: EnemyRuntime in session.stage.enemies:
			enemies_before[e.instance_id] = e.hp

		session.tick(step)
		t += step

		# 检测本帧内新建的阻挡
		for e: EnemyRuntime in session.stage.enemies:
			if e.state == BattleTypes.EnemyState.BLOCKED and not seen_blocked.has(e.instance_id):
				seen_blocked[e.instance_id] = true
				block_events += 1
				print("  [t=%.2fs] 阻挡建立: 敌人#%d 被 walled (blockedBy=%d) 位置 x=%.3f"
					% [t, e.instance_id, e.blocked_by_character_id, e.logical_x])

		# 角色造成伤害
		for c: CharacterRuntime in session.stage.characters:
			if c.total_damage_dealt > 0:
				attack_events = c.total_damage_dealt
		# 角色受伤
		for c: CharacterRuntime in session.stage.characters:
			if c.total_damage_taken > 0:
				enemy_attack_events = c.total_damage_taken

		# 每 5 秒打一次状态
		if t - last_report >= 5.0:
			last_report = t
			var mio := session.stage.get_character_by_id(CHAR_ID)
			var blocked_ids: Array = mio.blocking_enemy_ids if mio != null else []
			var on_field: Array[String] = []
			for e: EnemyRuntime in session.stage.enemies:
				on_field.append("#%d(l%d,hp%d,%s)" % [
					e.instance_id, e.lane, e.hp,
					BattleTypes.enemy_state_name(e.state).substr(0, 4),
				])
			print("  [t=%.1fs] AP=%d 核心=%d 雨宫澪HP=%s 阻挡中=%s 场上=%s"
				% [t, session.stage.ap, session.stage.core_hp,
					(str(mio.hp) if mio != null else "—"),
					str(blocked_ids), str(on_field)])

	var s := session.stage
	print("")
	print("=== 汇总 ===")
	print("  结果=%s  用时=%.1fs  核心=%d/%d" % [
		BattleTypes.outcome_name(session.outcome), s.elapsed_seconds,
		s.core_hp, s.core_hp_max])
	print("  击杀=%d  漏怪=%d  失能=%d" % [s.enemies_killed, s.reached_core_count, s.characters_lost])
	print("  阻挡建立次数=%d（应为击杀数+仍在场被挡者）" % block_events)
	print("  雨宫澪累计造成伤害=%d  累计受到伤害=%d" % [attack_events, enemy_attack_events])
	var mio := s.get_character_by_id(CHAR_ID)
	if mio != null:
		print("  雨宫澪最终 HP=%d/%d  存活=%s" % [mio.hp, mio.max_hp, str(mio.alive)])

	quit(0)


func _load_data() -> Dictionary:
	var out := {"stage": {}, "enemies": {}, "characters": {}, "combat": {}, "grid": null}
	var stage: Variant = _read_json("res://data/stages/ch1/%s.json" % STAGE_ID)
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
