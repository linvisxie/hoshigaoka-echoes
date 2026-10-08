## 一次性工具：无头模拟 1-1，用于校准教学关平衡。
##
## 目的：在实现 UI 之前，先用领域层跑通"首个可部署角色能否在 1-1 完成教学并通关"。
##
## 注意：`--script` 模式下 **Autoload 不生效**，因此这里自行实例化数据加载。
##
## 用法：
##   godot --headless --path <proj> --script res://tools/simulate_stage.gd
extends SceneTree

const STAGE_ID := "1-1"
const CHAR_ID := "amamiya_mio"


func _initialize() -> void:
	var data := _load_data()
	var stage: Dictionary = data["stage"]
	var enemy_table: Dictionary = data["enemies"]
	var char_table: Dictionary = data["characters"]
	var balance_combat: Dictionary = data["combat"]
	var grid: BattleGrid = data["grid"]

	if stage.is_empty():
		printerr("无法加载关卡配置")
		quit(1)
		return

	print("=== 1-1 无头模拟 ===")
	print("可部署角色: %s" % str(stage.get("availableCharacters", [])))
	print("计划出怪: %d  核心 HP: %d  开局 AP: %d  上限 AP: %d  回复: %s/s"
		% [
			(stage.get("enemySpawnTimeline", []) as Array).size(),
			int(stage.get("coreHp", 0)), int(stage.get("startingAp", 0)),
			int(balance_combat.get("maxAp", 0)), str(stage.get("apRegen", 0)),
		])
	var mio: Dictionary = char_table.get(CHAR_ID, {})
	if not mio.is_empty():
		var st: Dictionary = mio.get("baseStats", {})
		print("雨宫澪: HP %s 攻击 %s 防御 %s 间隔 %s 阻挡 %s 费用 %s 射程 %s"
			% [st.get("hp"), st.get("attack"), st.get("defense"),
				mio.get("attackInterval"), mio.get("blockCount"),
				mio.get("deployCost"), (mio.get("attackRange", {}) as Dictionary).get("rangeTiles")])
	print("")

	_run_case("A. 不部署（基线对照，应失败）",
		stage, enemy_table, char_table, balance_combat, grid, -1, -1)
	for col: int in range(6):
		_run_case("B. 部署中段 col%d" % col,
			stage, enemy_table, char_table, balance_combat, grid, col, 1)

	quit(0)


func _load_data() -> Dictionary:
	var out := {
		"stage": {}, "enemies": {}, "characters": {}, "combat": {}, "grid": null,
	}
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


func _run_case(
	label: String,
	stage: Dictionary,
	enemy_table: Dictionary,
	char_table: Dictionary,
	balance_combat: Dictionary,
	grid: BattleGrid,
	col: int,
	lane: int
) -> void:
	var session := BattleSession.new()
	var errs := session.setup(stage, enemy_table, grid, char_table, balance_combat)
	if not errs.is_empty():
		print("  [%s] 构建失败: %s" % [label, str(errs)])
		session.free()
		return

	if col >= 0:
		var r := session.deploy_character(CHAR_ID, col, lane)
		if not r.ok:
			print("  [%s] 部署失败: %s" % [label, r.reason_text()])
			session.free()
			return

	var step := StageRuntime.LOGIC_STEP_SECONDS
	var t := 0.0
	while session.is_running() and t < 300.0:
		session.tick(step)
		t += step

	var s := session.stage
	var mio := s.get_character_by_id(CHAR_ID)
	var hp_text := "—"
	if mio != null:
		hp_text = "%d/%d" % [mio.hp, mio.max_hp]
	print("  [%s] 结果=%s 用时=%.1fs 核心=%d/%d 击杀=%d 漏怪=%d 失能=%d AP=%d 雨宫澪HP=%s"
		% [label, BattleTypes.outcome_name(session.outcome), s.elapsed_seconds,
			s.core_hp, s.core_hp_max, s.enemies_killed, s.reached_core_count,
			s.characters_lost, s.ap, hp_text])
	session.free()
