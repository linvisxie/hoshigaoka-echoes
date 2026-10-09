## A0.2 敌人生态验收测试（V2.1.4 F 章十/十三/十四/十五）。
##
## 覆盖四个敌人：echo_exam_sheet 试卷飞灵 / echo_invigilator 监考者 /
## echo_silent 沉默学生 / echo_copy 作弊纸偶。
##
## 纪律：
##   - LOCKED 字段逐字对照 v214_ordered.txt 行号（规格原文）；
##   - CANDIDATE 字段（规格未给的基础属性）只断言「可加载 + 已标 _candidate」，
##     **不把候选值伪装成规格值**；
##   - 沉默机制在当前构建下**无实战效果**（技能系统未实现），
##     因此只断言「状态容器可生效/可过期」与「不改变普通攻击频率」，
##     **不宣称完整实战已通过**（设计稿 §2.2.5 M4 / 冲突 C-18）。
extends GutTest

const CHAR_MIO := "amamiya_mio"

const AP_MAX := 30
const EPS := 0.0001
const MAX_SIM_SECONDS := 900.0

const NEW_ENEMY_IDS: Array[String] = [
	"echo_exam_sheet", "echo_silent", "echo_copy", "echo_invigilator",
]

## LOCKED 字段值（v214_ordered.txt 规格原文；见设计稿 §4.1 / §4.3）。
## 前两个敌人全部为规格值；后两个敌人的基础属性规格完全未给，此处写的是
## **第一轮候选值**（仅用于断言「数据文件与设计稿候选表一致」，不是规格断言）。
const LOCKED_SPEC := {
	"echo_exam_sheet": {
		"tier": 2, "hp": 330, "attack": 75, "defense": 15,
		"moveSpeed": 0.45, "attackInterval": 1.6, "weightClass": "LIGHT",
		"specLine": "L1094-L1100",
	},
	"echo_invigilator": {
		"tier": 3, "hp": 1600, "attack": 120, "defense": 65,
		"moveSpeed": 0.3, "attackInterval": 1.8, "weightClass": "HEAVY",
		"specLine": "L1141-L1146",
	},
	"echo_silent": {
		"tier": 2, "hp": 400, "attack": 60, "defense": 30,
		"moveSpeed": 0.5, "attackInterval": 1.2, "weightClass": "MEDIUM",
		"specLine": "CANDIDATE（规格未给基础属性）",
	},
	"echo_copy": {
		"tier": 2, "hp": 450, "attack": 70, "defense": 25,
		"moveSpeed": 0.45, "attackInterval": 1.3, "weightClass": "MEDIUM",
		"specLine": "CANDIDATE（规格未给基础属性）",
	},
}

## 规格未给基础属性、全部为候选的敌人（必须带 _candidate 说明）
const ALL_CANDIDATE_ENEMIES: Array[String] = ["echo_silent", "echo_copy"]


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


# ============================================================
#  夹具
# ============================================================

func _grid() -> BattleGrid:
	return BattleGrid.from_layout(DataRegistry.get_layout())


func _enemy_table() -> Dictionary:
	var t := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


func _char_table() -> Dictionary:
	var t := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		t[str(c.get("id", ""))] = c
	return t


func _combat() -> Dictionary:
	return DataRegistry.get_domain("balance").get("combat", {})


func _stage_config() -> Dictionary:
	return DataRegistry.get_entry("stages", "1-1")


## 直接从磁盘读取权威数据文件（断言对象是**数据文件本身**，
## 而不是可能被其他用例就地改写过的内存副本）。
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


func _enemy_table_from_file() -> Dictionary:
	var t := {}
	var data: Variant = _read_json("res://data/enemies.json")
	if typeof(data) != TYPE_DICTIONARY:
		return t
	for e: Dictionary in (data as Dictionary).get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


## 可控夹具：出怪 / 角色 / AP / 核心完全由参数决定（waves 元数据清空，
## 使波次由 enemySpawnTimeline 自动推导）。
func _cfg(
	spawns: Array, chars: Array = [], ap: int = AP_MAX, regen: float = 0.0, core: int = 99
) -> Dictionary:
	var c := _stage_config().duplicate(true)
	c.erase("waves")
	c["coreHp"] = core
	c["startingAp"] = ap
	c["apRegen"] = regen
	c["enemySpawnTimeline"] = spawns
	c["availableCharacters"] = chars
	return c


func _runtime(cfg: Dictionary) -> StageRuntime:
	return _runtime_with_table(cfg, _enemy_table())


func _runtime_with_table(cfg: Dictionary, table: Dictionary) -> StageRuntime:
	return StageRuntime.from_config(cfg, table, _grid(), _char_table(), _combat())


func _session(cfg: Dictionary) -> BattleSession:
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	return s


func _deploy_ok(rt: StageRuntime, character_id: String, column: int, lane: int) -> CharacterRuntime:
	var r := rt.deploy_character(character_id, column, lane)
	assert_true(r.ok, "应能部署 %s 到 (col%d, lane%d)：%s"
		% [character_id, column, lane, r.reason_text()])
	return r.character


## 手动放置一个敌人（instance_id 落在 9000+，wave_number = 0 →
## 退回 instance_id 区间判定，因而不影响任何波次的计数，保持既有夹具语义）。
##
## table 可选：传入自定义敌人表时，放置的实例读取该表（用于「参数来自配置」的验证，
## 否则会误用全局权威表，使数据驱动断言失效）。
func _place_enemy(
	rt: StageRuntime, lane: int, x: float, enemy_id: String, table: Dictionary = {}
) -> EnemyRuntime:
	var src: Dictionary = table if not table.is_empty() else _enemy_table()
	var e := EnemyRuntime.from_config(src[enemy_id], lane, 9000 + rt.enemies.size())
	e.logical_x = x
	e.state = BattleTypes.EnemyState.MOVING
	rt.enemies.append(e)
	return e


func _step_n(rt: StageRuntime, seconds: float) -> void:
	var t := 0.0
	while t < seconds - EPS:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS


func _advance_until(rt: StageRuntime, target_logic_seconds: float) -> void:
	var guard := 0
	while rt.elapsed_seconds < target_logic_seconds - EPS and guard < 500000:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1


## 复制配置的一份深拷贝（用于就地改参数做「数据驱动」验证，不污染权威数据）
func _table_with_invigilator_gaze(interval: float, duration: float) -> Dictionary:
	var table := _enemy_table()
	var cfg: Dictionary = (table["echo_invigilator"] as Dictionary).duplicate(true)
	var mech: Dictionary = (cfg["mechanic"] as Dictionary).duplicate(true)
	var gaze: Dictionary = (mech["gaze"] as Dictionary).duplicate(true)
	gaze["intervalSeconds"] = interval
	gaze["durationSeconds"] = duration
	mech["gaze"] = gaze
	cfg["mechanic"] = mech
	table["echo_invigilator"] = cfg
	return table


# ============================================================
#  一、四个敌人的配置可加载 + LOCKED 字段逐字一致
# ============================================================

func test_four_new_enemies_are_loadable() -> void:
	var table := _enemy_table_from_file()
	for enemy_id: String in NEW_ENEMY_IDS:
		assert_true(table.has(enemy_id), "enemies.json 应含 A0.2 新增敌人 %s" % enemy_id)


## 四个敌人的面板字段与设计稿一致。前两个为 LOCKED 规格值（逐字对照行号），
## 后两个为 CANDIDATE 第一轮候选值（规格未给）。
func test_new_enemy_panel_values_match_design_doc() -> void:
	var table := _enemy_table_from_file()
	for enemy_id: String in NEW_ENEMY_IDS:
		if not table.has(enemy_id):
			fail_test("enemies.json 缺少 %s" % enemy_id)
			continue
		var cfg: Dictionary = table[enemy_id]
		var spec: Dictionary = LOCKED_SPEC[enemy_id]
		var origin := str(spec["specLine"])
		assert_eq(int(cfg.get("tier", -1)), int(spec["tier"]),
			"%s 的 tier 应为 %d（%s）" % [enemy_id, int(spec["tier"]), origin])
		assert_eq(int(cfg.get("hp", -1)), int(spec["hp"]),
			"%s 的 hp 应为 %d（%s）" % [enemy_id, int(spec["hp"]), origin])
		assert_eq(int(cfg.get("attack", -1)), int(spec["attack"]),
			"%s 的 attack 应为 %d（%s）" % [enemy_id, int(spec["attack"]), origin])
		assert_eq(int(cfg.get("defense", -1)), int(spec["defense"]),
			"%s 的 defense 应为 %d（%s）" % [enemy_id, int(spec["defense"]), origin])
		assert_eq(float(cfg.get("moveSpeed", -1.0)), float(spec["moveSpeed"]),
			"%s 的 moveSpeed 应为 %s（%s）" % [enemy_id, str(spec["moveSpeed"]), origin])
		assert_eq(float(cfg.get("attackInterval", -1.0)), float(spec["attackInterval"]),
			"%s 的 attackInterval 应为 %s（%s）"
			% [enemy_id, str(spec["attackInterval"]), origin])
		assert_eq(str(cfg.get("weightClass", "")), str(spec["weightClass"]),
			"%s 的 weightClass 应为 %s（%s）" % [enemy_id, str(spec["weightClass"]), origin])
		# 每个条目都必须声明来源（LOCKED 引用行号 / CANDIDATE 说明）
		assert_false(str(cfg.get("_spec", "")).is_empty(),
			"%s 必须声明 _spec 来源" % enemy_id)


## 试卷飞灵的 LOCKED 值逐字对照 v214_ordered.txt L1094～L1100。
func test_exam_sheet_locked_values_are_verbatim() -> void:
	var cfg: Dictionary = _enemy_table_from_file().get("echo_exam_sheet", {})
	assert_false(cfg.is_empty(), "应含 echo_exam_sheet")
	assert_eq(int(cfg.get("hp", 0)), 330, "L1094：HP 330")
	assert_eq(int(cfg.get("attack", 0)), 75, "L1095：攻击 75")
	assert_eq(int(cfg.get("defense", 0)), 15, "L1096：防御 15")
	assert_eq(float(cfg.get("moveSpeed", 0.0)), 0.45, "L1097：移动速度 0.45 格/秒")
	assert_eq(float(cfg.get("attackRange", {}) if typeof(cfg.get("attackRange")) == TYPE_DICTIONARY else 0.0),
		0.0, "占位：attackRange 为字符串枚举，数值走 mechanic.rangeTiles")
	assert_eq(float((cfg.get("mechanic", {}) as Dictionary).get("rangeTiles", 0.0)), 3.0,
		"L1098：攻击距离 3 格")
	assert_eq(float(cfg.get("attackInterval", 0.0)), 1.6, "L1099：攻击间隔 1.6 秒")
	assert_eq(str(cfg.get("weightClass", "")), "LIGHT", "L1100：重量轻")
	assert_eq(str(cfg.get("id", "")), "echo_exam_sheet", "L1092：内部 ID 逐字")


## 监考者的 LOCKED 值逐字对照 v214_ordered.txt L1141～L1150。
func test_invigilator_locked_values_are_verbatim() -> void:
	var cfg: Dictionary = _enemy_table_from_file().get("echo_invigilator", {})
	assert_false(cfg.is_empty(), "应含 echo_invigilator")
	assert_eq(int(cfg.get("hp", 0)), 1600, "L1141：HP 1600")
	assert_eq(int(cfg.get("attack", 0)), 120, "L1142：攻击 120")
	assert_eq(int(cfg.get("defense", 0)), 65, "L1143：防御 65")
	assert_eq(float(cfg.get("moveSpeed", 0.0)), 0.3, "L1144：移动速度 0.3 格/秒")
	assert_eq(float(cfg.get("attackInterval", 0.0)), 1.8, "L1145：攻击间隔 1.8 秒")
	assert_eq(str(cfg.get("weightClass", "")), "HEAVY", "L1146：重量重")
	assert_eq(int(cfg.get("tier", 0)), 3, "L1139：等级 III 级")

	var gaze: Dictionary = (cfg.get("mechanic", {}) as Dictionary).get("gaze", {})
	assert_eq(float(gaze.get("intervalSeconds", 0.0)), 10.0, "L1148：每隔 10 秒")
	assert_eq(float(gaze.get("durationSeconds", 0.0)), 5.0, "L1148：持续 5 秒")
	assert_eq(float(gaze.get("attackSpeedPct", 0.0)), -0.25, "L1148：攻击速度 -25%")
	assert_eq(str(gaze.get("effectId", "")), "invigilator_gaze", "注视的 effectId 唯一")

	var time_up: Dictionary = (cfg.get("mechanic", {}) as Dictionary).get("timeUp", {})
	assert_eq(float(time_up.get("triggerHpRatio", 0.0)), 0.4, "L1150：生命低于 40%")
	assert_eq(float(time_up.get("moveSpeedPct", 0.0)), 0.3, "L1150：移动速度提高 30%")


## 沉默学生 / 作弊纸偶：基础属性规格**完全未给**，因此必须带 _candidate 说明。
func test_candidate_enemies_are_marked_as_candidate() -> void:
	var table := _enemy_table_from_file()
	for enemy_id: String in ALL_CANDIDATE_ENEMIES:
		var cfg: Dictionary = table.get(enemy_id, {})
		assert_false(cfg.is_empty(), "应含 %s" % enemy_id)
		var note := str(cfg.get("_candidate", ""))
		assert_false(note.is_empty(),
			"%s 的基础属性规格未给，必须声明 _candidate（不得伪装成 LOCKED）" % enemy_id)
		assert_string_contains(note, "候选",
			"%s 的 _candidate 说明应明示「第一轮候选」" % enemy_id)


## 沉默学生的 LOCKED 机制参数逐字对照 L1129 / L557。
func test_silent_locked_mechanic_is_verbatim() -> void:
	var cfg: Dictionary = _enemy_table_from_file().get("echo_silent", {})
	var mech: Dictionary = cfg.get("mechanic", {})
	assert_eq(str(cfg.get("id", "")), "echo_silent", "L1127：内部 ID 逐字")
	assert_eq(int(cfg.get("tier", 0)), 2, "L1127：等级 II 级")
	assert_eq(str(mech.get("kind", "")), "SILENCE_ON_FIRST_CONTACT", "能力种类")
	assert_eq(str(mech.get("trigger", "")), "FIRST_CONTACT_WITH_DEFENSE_LINE",
		"L1129：首次接触玩家防线后")
	assert_eq(float(mech.get("durationSeconds", 0.0)), 3.0, "L1129：3 秒内无法主动释放技能")
	assert_eq(str(mech.get("category", "")), "SILENCE", "控制类沉默")
	assert_eq(str(mech.get("effectId", "")), "silent_student_mute", "effectId 唯一")
	# L557 LOCKED：控制类沉默仅禁止主动技能，不改变普通攻击频率
	assert_false(bool(mech.get("affectsAttackInterval", true)),
		"L557：沉默不得改变普通攻击频率")


## 作弊纸偶的 LOCKED 机制参数逐字对照 L1135。
func test_copy_locked_mechanic_is_verbatim() -> void:
	var cfg: Dictionary = _enemy_table_from_file().get("echo_copy", {})
	var mech: Dictionary = cfg.get("mechanic", {})
	assert_eq(str(cfg.get("id", "")), "echo_copy", "L1133：内部 ID 逐字")
	assert_eq(int(cfg.get("tier", 0)), 2, "L1133：等级 II 级")
	assert_eq(str(mech.get("kind", "")), "SPLIT_ON_HP_THRESHOLD", "能力种类")
	assert_eq(float(mech.get("triggerHpRatio", 0.0)), 0.5, "L1135：生命首次低于 50%")
	assert_eq(str(mech.get("triggerComparison", "")), "STRICTLY_LESS_THAN",
		"L1135「低于」按严格小于实现（设计稿 C-7 候选口径）")
	assert_eq(int(mech.get("spawnCount", 0)), 1, "L1135：生成 1 个低生命复制体")
	assert_eq(float(mech.get("copyHpRatio", 0.0)), 0.35, "L1135：复制体拥有原敌人 35% HP")
	assert_false(bool(mech.get("copyCanCopy", true)), "L1135：复制体不能再次复制")
	assert_true(bool(mech.get("copyCountsTowardWave", false)),
		"复制体必须计入波次（否则其击杀/漏怪会丢失归属）")


# ============================================================
#  二、balance.json 的减益下限（V2.1.4 L556～557 / 冲突 C-15）
# ============================================================

func test_debuff_floor_is_carried_by_balance_json() -> void:
	var data: Variant = _read_json("res://data/balance.json")
	assert_not_null(data, "balance.json 应可解析")
	if data == null:
		return
	var combat: Dictionary = (data as Dictionary).get("combat", {})
	assert_true(combat.has("debuffFloor"),
		"L557：减益下限必须存于 balance.json 的 combat.debuffFloor")
	var floor_cfg: Dictionary = combat.get("debuffFloor", {})
	assert_eq(float(floor_cfg.get("attackSpeedPct", 0.0)), 0.4, "L556：攻速下限 40%")
	assert_eq(float(floor_cfg.get("attackPct", 0.0)), 0.4, "L556：攻击力下限 40%")
	assert_eq(float(floor_cfg.get("cdRecoveryPct", 0.0)), 0.4, "L556：CD 恢复速度下限 40%")
	assert_false(bool(floor_cfg.get("appliesToEnemies", true)),
		"L556 的属性清单是封闭枚举，敌人不适用该下限（设计稿 C-9）")


func test_runtime_reads_debuff_floor_from_balance() -> void:
	var rt := _runtime(_cfg([]))
	assert_true(rt.is_valid(), "夹具应无构建错误：%s" % str(rt.get_errors()))
	assert_eq(rt.debuff_floor_pct, 0.4, "运行时的减益下限应来自 balance.json")


func test_missing_debuff_floor_is_reported() -> void:
	var combat := _combat().duplicate(true)
	combat.erase("debuffFloor")
	var rt := StageRuntime.from_config(_cfg([]), _enemy_table(), _grid(), _char_table(), combat)
	assert_false(rt.is_valid(), "balance.combat 缺 debuffFloor 应报错（不得静默通过）")
	var joined := "\n".join(rt.get_errors())
	assert_string_contains(joined, "debuffFloor", "错误信息应指出 debuffFloor")


# ============================================================
#  三、试卷飞灵：达到射程后停下、能远程命中、恢复移动
# ============================================================

## 飞灵在出生点即处于射程内（|3 − 5| = 2 ≤ 3）→ 立即停驻，不再前进。
func test_ranged_enemy_stops_when_nearest_target_in_range() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	assert_eq(mio.column, 3, "雨宫澪应部署在 col3")

	# 生成一只飞灵于入口（x = SPAWN_X = 5.0）
	var flyer := _place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_exam_sheet")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(flyer.state, BattleTypes.EnemyState.RANGED_ATTACK,
		"目标已在 3 格射程内，飞灵应进入停驻射击态（实际 %s）"
		% BattleTypes.enemy_state_name(flyer.state))

	# 停驻后位置不得再变化（「达到攻击距离后停下」）
	var stopped_x := flyer.logical_x
	_step_n(rt, 2.0)
	assert_almost_eq(flyer.logical_x, stopped_x, EPS,
		"进入停驻射击态后不得继续移动（%.4f → %.4f）" % [stopped_x, flyer.logical_x])


## 飞灵能远程命中角色：75 × 100 / (100 + 80) = 41.67 → 42。
func test_ranged_enemy_hits_character_at_range() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	var hp_before := mio.hp

	var flyer := _place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_exam_sheet")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(flyer.state, BattleTypes.EnemyState.RANGED_ATTACK, "应已进入停驻射击态")
	assert_eq(mio.hp, hp_before - 42,
		"飞灵（攻 75）打雨宫澪（防 80）应为 75×100/180 = 41.67 → 42（实际扣 %d）"
		% (hp_before - mio.hp))
	assert_eq(mio.blocking_enemy_ids.size(), 0,
		"停驻射击态**不得**占用角色的阻挡名额（射程 3 格 ≫ 接触线 0.5 格）")


## 飞灵按 attackInterval 出手：1.6 秒内 1 次，3.3 秒内 3 次。
func test_ranged_enemy_fires_on_configured_interval() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	_place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_exam_sheet")

	_step_n(rt, 0.5)
	var hits_05 := _count_damage_to_character(rt)
	assert_eq(hits_05, 1, "0.5 秒内应恰好出手 1 次（实际 %d）" % hits_05)

	_step_n(rt, 2.8)  # 累计 3.3 秒
	var hits_33 := _count_damage_to_character(rt)
	assert_eq(hits_33, 3, "3.3 秒内应出手 3 次（间隔 1.6 秒，首次 t=0；实际 %d）" % hits_33)


## 合法目标全部消失后，飞灵恢复移动（resumeMoveWhenNoTargetInRange）。
func test_ranged_enemy_resumes_moving_when_no_target() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	var flyer := _place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_exam_sheet")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(flyer.state, BattleTypes.EnemyState.RANGED_ATTACK, "应先在射程内停驻")

	# 角色撤退 → 无合法目标
	var rr := rt.withdraw_character(mio.instance_id)
	assert_true(rr.ok, "雨宫澪应能主动撤退")
	var x_before := flyer.logical_x
	_step_n(rt, 1.0)

	assert_eq(flyer.state, BattleTypes.EnemyState.MOVING,
		"无合法目标时应恢复移动（实际 %s）" % BattleTypes.enemy_state_name(flyer.state))
	assert_lt(flyer.logical_x, x_before - 0.1,
		"恢复移动后应继续向左推进（%.4f → %.4f）" % [x_before, flyer.logical_x])


## 跨线目标不算「合法目标」（maxLaneDelta = 0，D-3A L425）。
func test_ranged_enemy_ignores_targets_on_other_lanes() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	_deploy_ok(rt, CHAR_MIO, 3, 0)  # 上段
	var flyer := _place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_exam_sheet")  # 中段
	_step_n(rt, 1.0)

	assert_eq(flyer.state, BattleTypes.EnemyState.MOVING,
		"中段的飞灵不得把上段角色当作合法目标（实际 %s）"
		% BattleTypes.enemy_state_name(flyer.state))


# ============================================================
#  四、监考者：注视（10s 节奏 / 5s 持续 / 攻速 -25% / 40% 下限）
# ============================================================

## 注视每 10 秒施加一次（L1148）。
##
## 夹具说明：监考者移速 0.3 tile/s，若放在接触线上会在约 10 秒内走到核心离场，
## 从而观察不到第二次注视。故把**角色放在 col0**（接触线 0.5）、监考者放在 x = 5.0，
## 使其步行 15 格 ≈ 50 秒才抵达接触线，保证 10 秒节奏可被完整观察。
func test_gaze_applies_on_ten_second_cadence() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 0, 1)
	_place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_invigilator")

	_step_n(rt, 4.9)
	var first := mio.get_status_effect("invigilator_gaze")
	assert_not_null(first, "首次注视应在入场后立即施加（firstTriggerAtSeconds = 0.0）")
	if first == null:
		return
	var t1 := first.applied_at

	_step_n(rt, 5.4)  # 累计约 10.3 秒
	var second := mio.get_status_effect("invigilator_gaze")
	assert_not_null(second, "第二次注视应在 10 秒后重新施加")
	if second == null:
		return
	var t2 := second.applied_at

	assert_almost_eq(t2 - t1, 10.0, 0.1,
		"两次注视的间隔应为 10 秒（实际 %.4f 秒）" % (t2 - t1))


## 注视持续 5 秒后失效（L1148）。
func test_gaze_expires_after_five_seconds() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 0, 1)
	_place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_invigilator")

	_step_n(rt, 4.9)
	assert_true(mio.has_status_effect("invigilator_gaze"),
		"施加后 4.9 秒仍应在生效期内")

	_step_n(rt, 0.5)  # 累计约 5.4 秒 > 5.0 秒
	assert_false(mio.has_status_effect("invigilator_gaze"),
		"持续 5 秒后应自动失效")


## 注视使攻速 -25%：interval_eff = 1.1 / clamp(0.75) = 1.4667 秒。
##
## ⚠️ 换算口径为**首轮候选（需人裁决，设计稿冲突 C-3）**：规格只定义频率下限，
## 未明文规定百分数到攻击间隔的换算；本工程采用频率倒数关系。
func test_gaze_reduces_attack_speed_by_25_percent() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	assert_eq(mio.attack_interval, 1.1, "雨宫澪基础攻击间隔应为 1.1 秒（权威数值）")
	assert_almost_eq(mio.effective_attack_interval(), 1.1, EPS,
		"无减益时有效间隔应等于基础间隔")

	var gaze_cfg := {
		"effectId": "invigilator_gaze", "sourceId": "echo_invigilator",
		"category": StatusEffect.CATEGORY_ATTACK_SPEED, "pct": -0.25,
		"durationSeconds": 5.0, "stackPolicy": "REFRESH_DURATION",
	}
	mio.apply_status_effect_from_config(gaze_cfg, 0.0)

	assert_almost_eq(mio.attack_speed_factor(), 0.75, EPS,
		"攻速系数应为 1 - 0.25 = 0.75")
	assert_almost_eq(mio.effective_attack_interval(), 1.1 / 0.75, 0.0001,
		"有效攻击间隔应为 1.1 / 0.75 = 1.4667 秒（频率倒数口径）")


## 攻速减益受 40% 下限夹取（L556）：Σ = -0.85 → clamp(0.15, 0.4) = 0.4。
func test_gaze_respects_forty_percent_debuff_floor() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)

	mio.apply_status_effect_from_config({
		"effectId": "invigilator_gaze", "sourceId": "echo_invigilator",
		"category": StatusEffect.CATEGORY_ATTACK_SPEED, "pct": -0.25,
		"durationSeconds": 5.0, "stackPolicy": "REFRESH_DURATION",
	}, 0.0)
	# 不同 effectId 的减益先相加（L556）
	mio.apply_status_effect_from_config({
		"effectId": "synthetic_anxiety_field", "sourceId": "test",
		"category": StatusEffect.CATEGORY_ATTACK_SPEED, "pct": -0.6,
		"durationSeconds": 5.0, "stackPolicy": "REFRESH_DURATION",
	}, 0.0)

	assert_almost_eq(mio.sum_effect_pct(StatusEffect.CATEGORY_ATTACK_SPEED), -0.85, EPS,
		"不同 effectId 的攻速减益应先相加")
	assert_almost_eq(mio.attack_speed_factor(), 0.4, EPS,
		"Σ = -0.85 → 1 - 0.85 = 0.15，应被 40% 下限夹到 0.4")
	assert_almost_eq(mio.effective_attack_interval(), 1.1 / 0.4, 0.0001,
		"触底时有效攻击间隔应为 1.1 / 0.4 = 2.75 秒")


## 同一 effectId 重复施加只刷新持续时间，不产生第二条（L556）。
func test_gaze_reapply_refreshes_without_stacking() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)

	var cfg := {
		"effectId": "invigilator_gaze", "sourceId": "echo_invigilator",
		"category": StatusEffect.CATEGORY_ATTACK_SPEED, "pct": -0.25,
		"durationSeconds": 5.0, "stackPolicy": "REFRESH_DURATION",
	}
	mio.apply_status_effect_from_config(cfg, 0.0)
	mio.apply_status_effect_from_config(cfg, 2.0)

	assert_eq(mio.status_effects.size(), 1,
		"同一 effectId 不得叠层（应只有 1 条，实际 %d）" % mio.status_effects.size())
	assert_almost_eq(mio.get_status_effect("invigilator_gaze").expires_at, 7.0, EPS,
		"重复施加应把 expiresAt 刷新为 now + duration = 2.0 + 5.0")
	# 减益强度不得因重复施加而叠加
	assert_almost_eq(mio.attack_speed_factor(), 0.75, EPS,
		"重复施加不得叠加百分数（仍应为 0.75）")


## 注视参数全部来自 enemies.json 的 mechanic 段（数据驱动，不硬编码）。
func test_gaze_parameters_are_data_driven() -> void:
	var table := _table_with_invigilator_gaze(3.0, 1.0)
	var rt := _runtime_with_table(_cfg([], [CHAR_MIO]), table)
	var mio := _deploy_ok(rt, CHAR_MIO, 0, 1)
	# 必须用**改过的表**放置敌人，否则读到的仍是权威表里的 10 秒间隔
	_place_enemy(rt, 1, BattleGrid.SPAWN_X, "echo_invigilator", table)

	# 配置改为 3 秒间隔：累计 3.2 秒后应已发生第二次施加
	_step_n(rt, 3.2)
	var eff := mio.get_status_effect("invigilator_gaze")
	assert_not_null(eff, "配置间隔 3 秒时，3.2 秒内应已有注视")
	if eff == null:
		return
	assert_gt(eff.applied_at, 2.9,
		"若参数硬编码为 10 秒，3.2 秒内不可能出现第二次施加（实际 applied_at = %.3f）"
		% eff.applied_at)


# ============================================================
#  五、监考者：时间到（HP < 40% → 移速 +30%，严格小于）
# ============================================================

func test_time_up_triggers_below_forty_percent() -> void:
	var rt := _runtime(_cfg([]))
	var boss := _place_enemy(rt, 1, 3.0, "echo_invigilator")
	assert_eq(boss.hp_max, 1600, "监考者 HP 应为 1600")
	assert_eq(boss.move_speed, 0.3, "初始移速应为 0.3 格/秒")

	# 639 < 1600 × 0.4 = 640 → 应触发
	boss.hp = 639
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_true(boss.time_up_triggered, "HP 639 < 640 应触发「时间到」")
	assert_almost_eq(boss.move_speed, 0.3 * 1.3, 0.0001,
		"移速应提高 30%%：0.3 → 0.39 格/秒（实际 %.4f）" % boss.move_speed)


## HP 恰好等于 40%（640）时**不**触发——验证「低于」的严格性。
func test_time_up_does_not_trigger_at_exactly_forty_percent() -> void:
	var rt := _runtime(_cfg([]))
	var boss := _place_enemy(rt, 1, 3.0, "echo_invigilator")

	boss.hp = int(float(boss.hp_max) * 0.4)  # 恰好 640
	assert_eq(boss.hp, 640, "前置：HP 应恰好为 40% 阈值 640")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_false(boss.time_up_triggered,
		"HP 恰好等于 40% 时不得触发（「低于」是严格小于）")
	assert_almost_eq(boss.move_speed, 0.3, EPS, "未触发时移速应保持 0.3")

	# 再降 1 点即触发（证明阈值确实在 640 而非其他值）
	boss.hp = 639
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_true(boss.time_up_triggered, "HP 降到 639 应立即触发")


## 「时间到」为永久且只触发一次（不叠乘）。
func test_time_up_is_permanent_and_triggers_once() -> void:
	var rt := _runtime(_cfg([]))
	var boss := _place_enemy(rt, 1, 3.0, "echo_invigilator")
	boss.hp = 500
	_step_n(rt, 1.0)
	assert_almost_eq(boss.move_speed, 0.39, 0.0001, "触发后移速 0.39")

	# 继续推进：不得再次叠乘（0.39 × 1.3 = 0.507 是错误值）
	_step_n(rt, 2.0)
	assert_almost_eq(boss.move_speed, 0.39, 0.0001,
		"「时间到」只触发一次，移速不得叠乘（实际 %.4f）" % boss.move_speed)


# ============================================================
#  六、沉默学生：状态容器可生效 / 可过期 / 不影响普通攻击频率
# ============================================================

## 沉默施加到最近角色（此处为该敌人的阻挡者，设计稿 §2.2.5 M1 方案 A）。
func test_silence_is_applied_to_nearest_character() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	assert_true(mio.can_cast_active_skill(), "初始应可释放主动技能")

	var silent := _place_enemy(rt, 1, 3.5, "echo_silent")  # 接触线上
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(silent.state, BattleTypes.EnemyState.BLOCKED, "沉默学生应被雨宫澪阻挡")
	assert_true(silent.silence_triggered, "首次接触玩家防线应触发「无声」")
	assert_true(mio.has_status_effect("silent_student_mute"),
		"沉默状态应已挂到雨宫澪身上")
	assert_false(mio.can_cast_active_skill(),
		"被沉默角色在持续期内不得主动释放技能")


## 沉默 3 秒后自动过期（L1129）。
func test_silence_expires_after_three_seconds() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	_place_enemy(rt, 1, 3.5, "echo_silent")

	_step_n(rt, 2.9)
	assert_true(mio.has_status_effect("silent_student_mute"),
		"施加后 2.9 秒仍应在生效期内")
	assert_false(mio.can_cast_active_skill(), "生效期内应禁止主动技能")

	_step_n(rt, 0.5)  # 累计约 3.4 秒 > 3.0 秒
	assert_false(mio.has_status_effect("silent_student_mute"),
		"持续 3 秒后沉默状态应自动移除")
	assert_true(mio.can_cast_active_skill(),
		"沉默过期后应恢复主动技能释放能力")


## ★关键断言（L557 LOCKED）：沉默**不改变普通攻击频率**。
func test_silence_does_not_change_attack_interval() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	_place_enemy(rt, 1, 3.5, "echo_silent")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_true(mio.has_status_effect("silent_student_mute"), "前置：应已被沉默")
	# 有效攻击间隔必须与基础间隔完全相等（浮点相等）
	assert_almost_eq(mio.effective_attack_interval(), mio.attack_interval, EPS,
		"L557：控制类沉默不改变普通攻击频率，有效间隔应等于基础间隔")
	# 沉默的 pct 恒为 0，且不进攻速百分数求和
	assert_almost_eq(mio.sum_effect_pct(StatusEffect.CATEGORY_ATTACK_SPEED), 0.0, EPS,
		"沉默不得进入攻速百分数求和（category = SILENCE 被跳过）")
	assert_almost_eq(mio.attack_speed_factor(), 1.0, EPS,
		"沉默不得影响攻速系数（应仍为 1.0）")


## ★关键断言（L557）：沉默期间普通攻击照常出手，出手次数与未沉默时**完全一致**。
##
## 对照设计：两次运行只有「被阻挡的敌人种类」不同——
##   运行 A 放置 echo_silent（会施加沉默），运行 B 放置 echo_normal（不施加沉默）。
## 两者的角色侧出手节奏必须相同。
func test_silence_does_not_change_attack_cadence_in_combat() -> void:
	var hits_silenced := _count_character_attacks_over(3.0, "echo_silent")
	var hits_control := _count_character_attacks_over(3.0, "echo_normal")
	assert_eq(hits_silenced, hits_control,
		"沉默期间的普通攻击出手次数应与未沉默时完全一致（沉默 %d 次 vs 对照 %d 次）"
		% [hits_silenced, hits_control])
	assert_gt(hits_control, 0, "对照组应确实出手（否则本断言空转）")


## 沉默与攻速减益是正交的，可同时存在且互不覆盖（设计稿 §2.2.5 M3）。
func test_silence_coexists_with_attack_speed_debuff() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)

	mio.apply_status_effect_from_config({
		"effectId": "silent_student_mute", "sourceId": "echo_silent",
		"category": StatusEffect.CATEGORY_SILENCE, "pct": 0.0,
		"durationSeconds": 3.0, "stackPolicy": "REFRESH_DURATION",
	}, 0.0)
	mio.apply_status_effect_from_config({
		"effectId": "invigilator_gaze", "sourceId": "echo_invigilator",
		"category": StatusEffect.CATEGORY_ATTACK_SPEED, "pct": -0.25,
		"durationSeconds": 5.0, "stackPolicy": "REFRESH_DURATION",
	}, 0.0)

	assert_eq(mio.status_effects.size(), 2, "不同 effectId 应并存")
	assert_false(mio.can_cast_active_skill(), "沉默仍应生效")
	assert_almost_eq(mio.effective_attack_interval(), 1.1 / 0.75, 0.0001,
		"攻速减益仍应生效（两者互不覆盖）")


## 沉默能力默认不可重复触发（repeatable = false，尊重 L1129「首次」字面）。
func test_silence_trigger_is_one_shot_by_default() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	var silent := _place_enemy(rt, 1, 3.5, "echo_silent")
	_step_n(rt, 1.0)
	assert_true(silent.silence_triggered, "应已触发一次")

	# 让沉默过期后继续观察：不得再次施加（首次 = 一次性）
	_step_n(rt, 4.0)
	assert_false(mio.has_status_effect("silent_student_mute"),
		"repeatable = false 时沉默只施加一次，过期后不得再次施加")


# ============================================================
#  七、作弊纸偶：首次低于 50% 触发一次 / 复制体 HP / 不可再复制
# ============================================================

## 复制体 HP = floor(本体 HP × 0.35) = floor(450 × 0.35) = floor(157.5) = 157。
func test_copy_hp_is_floor_of_thirty_five_percent() -> void:
	var rt := _runtime(_cfg([]))
	var parent := _place_enemy(rt, 1, 3.0, "echo_copy")
	assert_eq(parent.hp_max, 450, "作弊纸偶 HP 应为 450（第一轮候选值）")

	parent.hp = 224  # < 450 × 0.5 = 225
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_true(parent.copy_triggered, "HP 224 < 225 应触发复制")
	var copies := _derived_of(rt, parent.instance_id)
	assert_eq(copies.size(), 1, "应生成恰好 1 个复制体（L1135：生成 1 个）")
	if copies.is_empty():
		return
	assert_eq(copies[0].hp_max, 157,
		"复制体 HP 应为 floor(450 × 0.35) = 157（实际 %d）" % copies[0].hp_max)
	assert_eq(copies[0].hp, 157, "复制体应以满血入场")
	assert_eq(copies[0].enemy_id, "echo_copy", "复制体沿用同一敌人种类")


## HP 恰好等于 50%（225）时**不**触发——验证「首次低于」的严格性。
func test_copy_does_not_trigger_at_exactly_fifty_percent() -> void:
	var rt := _runtime(_cfg([]))
	var parent := _place_enemy(rt, 1, 3.0, "echo_copy")
	parent.hp = 225
	assert_eq(parent.hp, int(450 * 0.5), "前置：HP 应恰好为 50% 阈值 225")

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_false(parent.copy_triggered, "HP 恰好 225 时不得触发（「低于」是严格小于）")
	assert_eq(_derived_of(rt, parent.instance_id).size(), 0, "不得生成复制体")

	parent.hp = 224
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_true(parent.copy_triggered, "HP 降到 224 应立即触发")


## ★防递归：复制体不再复制 → echo_copy 家族实例总数 = 本体数 × 2。
func test_copy_never_copies_again() -> void:
	var rt := _runtime(_cfg([
		{"time": 0.5, "lane": 1, "enemy": "echo_copy"},
		{"time": 0.5, "lane": 0, "enemy": "echo_copy"},
	]))
	_step_n(rt, 1.0)
	assert_eq(rt.enemies.size(), 2, "应先生成 2 个本体")

	# 把两个本体都打到 50% 以下 → 各生成 1 个复制体
	for e: EnemyRuntime in rt.enemies.duplicate():
		e.hp = 200
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt.enemies.size(), 4, "2 个本体应各生成 1 个复制体（共 4 个实例）")

	# 复制体自己再被打到 50% 以下也不得再复制（防递归）
	for e: EnemyRuntime in rt.enemies:
		if e.is_derived:
			e.hp = 10
	_step_n(rt, 2.0)

	assert_eq(rt.enemies.size(), 4,
		"复制体不得再次复制：实例总数应恒为 本体数 × 2 = 4（实际 %d）" % rt.enemies.size())
	for e: EnemyRuntime in rt.enemies:
		if e.is_derived:
			assert_false(e.can_copy(), "复制体的 mechanic.canCopy 必须为 false")
			assert_false(e.copy_triggered, "复制体不得触发复制")


## 已死亡的本体不生成复制体（「低于 50% 但存活」不成立）。
func test_dead_copy_parent_does_not_spawn() -> void:
	var rt := _runtime(_cfg([]))
	var parent := _place_enemy(rt, 1, 3.0, "echo_copy")
	parent.hp = 0
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(_derived_of(rt, parent.instance_id).size(), 0,
		"已死亡（HP ≤ 0）的本体不得生成复制体")
	assert_false(parent.copy_triggered, "死亡路径不应标记复制已触发")


## 复制体继承本体的波次归属（C-8 解决方案的实例级验证）。
func test_derived_copy_inherits_parent_wave() -> void:
	var table := _enemy_table()
	var parent := EnemyRuntime.from_config(table["echo_copy"], 1, 1, 2)  # wave 2
	assert_eq(parent.wave_number, 2, "本体应带有 spawnPlan 带入的波次号")

	var copy := EnemyRuntime.make_derived_copy(parent, 2, 0.1)
	assert_eq(copy.wave_number, 2, "复制体必须继承本体波次（否则击杀/漏怪会丢失归属）")
	assert_true(copy.is_derived, "复制体应标记为衍生体")
	assert_eq(copy.parent_instance_id, 1, "复制体应记录本体 instance_id")
	# 本体位于出生点（x = SPAWN_X = 5.0）时，偏移后被夹回 SPAWN_X（不得越出战场）
	assert_almost_eq(copy.logical_x, BattleGrid.SPAWN_X, 0.0001,
		"本体在出生点时，复制体位置应被夹取到 SPAWN_X（实际 %.4f）" % copy.logical_x)

	# 本体已推进到战场中部时，复制体应落在本体**后方** 0.1 格
	parent.logical_x = 3.0
	var copy2 := EnemyRuntime.make_derived_copy(parent, 3, 0.1)
	assert_almost_eq(copy2.logical_x, 3.1, 0.0001,
		"复制体应略微靠后生成（3.0 → 3.1），避免与本体完全重合（实际 %.4f）" % copy2.logical_x)


# ============================================================
#  八、★回归 C-8：含作弊纸偶的关卡仍能正常判定胜负
# ============================================================

## ★回归 C-8：作弊纸偶的复制体不得导致波次卡死，关卡必须能判定胜利。
##
## 同时验证两条旧实现会失败的断言：
##   ① 本体已清空但复制体仍在场时，本波**不得**被判为完成（否则会串波，
##      两波敌人同时在场的非预期局面）；
##   ② 复制体的击杀必须计入**本体所在波次**的统计（旧实现按 instance_id 区间归属，
##      复制体落在区间外 → 不计入任何波次 → 统计丢失）。
func test_stage_with_copy_can_still_reach_victory() -> void:
	var cfg := _cfg([
		{"time": 0.5, "lane": 1, "enemy": "echo_copy", "wave": 1},
		{"time": 30.0, "lane": 1, "enemy": "echo_normal", "wave": 2},
	], [CHAR_MIO], AP_MAX, 0.0, 99)
	cfg["waves"] = [{"number": 1}, {"number": 2}]
	var s := _session(cfg)
	_deploy_ok(s.stage, CHAR_MIO, 3, 1)

	var observed_window := false
	var guard := 0
	while s.is_running() and s.stage.elapsed_seconds < MAX_SIM_SECONDS and guard < 200000:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1
		# 观察「本体已全部离场、复制体仍在场」的窗口
		if not observed_window:
			var parent_alive := false
			var copy_alive := false
			for e: EnemyRuntime in s.stage.enemies:
				if not e.is_active():
					continue
				if e.is_derived:
					copy_alive = true
				else:
					parent_alive = true
			if not parent_alive and copy_alive:
				observed_window = true
				assert_eq(int(s.stage.wave_state_at(0)["status"]), StageRuntime.WAVE_ACTIVE,
					"本体已清空但复制体仍在场时，第 1 波不得被判为完成（否则会串波）")
				assert_eq(s.stage.current_wave_number(), 1,
					"复制体仍在场时不得提前进入第 2 波")

	assert_true(observed_window,
		"本用例应观察到「本体已清空、复制体仍在场」的窗口（否则断言空转）")

	# ★核心回归：战斗必须能判定胜负（旧实现若卡死则此处超时）
	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
		"含作弊纸偶的关卡应能正常判胜（核心 %d/%d，击杀 %d，漏怪 %d，Wave %d/%d，耗时 %.1fs）"
		% [s.stage.core_hp, s.stage.core_hp_max, s.stage.enemies_killed,
			s.stage.reached_core_count, s.stage.current_wave_number(),
			s.stage.total_wave_count(), s.stage.elapsed_seconds])

	# 计划敌人 2 个（1 纸偶 + 1 普通），复制体额外 1 个 → 总击杀 3
	assert_eq(s.stage.planned_enemy_count(), 2, "计划出怪应为 2 个")
	assert_eq(s.stage.kills_by_enemy_type().get("echo_copy", 0), 2,
		"echo_copy 家族应被击杀 2 个（1 本体 + 1 复制体）")
	assert_eq(int(s.stage.wave_state_at(0)["killedDerived"]), 1,
		"复制体的击杀应计入第 1 波的衍生体子计数")

	# 两波都必须完成
	assert_true(s.stage.all_waves_cleared(), "全部 Wave 应已完成")
	assert_eq(int(s.stage.wave_state_at(0)["status"]), StageRuntime.WAVE_CLEARED,
		"第 1 波应已完成")


## 复制体的漏怪同样计入本体所在波次，且正常扣核心（不丢账）。
func test_derived_copy_leak_is_counted_in_parent_wave() -> void:
	var cfg := _cfg([
		{"time": 0.5, "lane": 1, "enemy": "echo_copy", "wave": 1},
	], [], AP_MAX, 0.0, 99)  # 无角色 → 敌人自由推进
	cfg["waves"] = [{"number": 1}]
	var rt := _runtime(cfg)
	assert_true(rt.is_valid(), "夹具应无错误：%s" % str(rt.get_errors()))

	# 推进到本体生成，并把它打到 50% 以下触发复制
	_step_n(rt, 1.0)
	assert_eq(rt.enemies.size(), 1, "应先生成 1 个本体")
	rt.enemies[0].hp = 200
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt.enemies.size(), 2, "应生成 1 个复制体")

	# 让两者都走到核心（速度 0.45 tile/s，5 格 ≈ 11.2 秒）
	_step_n(rt, 20.0)

	var st: Dictionary = rt.wave_state_at(0)
	assert_eq(int(st["leaked"]), 2, "本体 + 复制体都应计入第 1 波漏怪（实际 %d）"
		% int(st["leaked"]))
	assert_eq(int(st["leakedDerived"]), 1, "其中 1 个应为衍生体")
	assert_eq(int(st["status"]), StageRuntime.WAVE_CLEARED, "第 1 波应已完成")
	assert_true(rt.all_waves_cleared(), "全部波次应已完成（不卡死）")


# ============================================================
#  辅助
# ============================================================

## 统计本场对**角色**造成的伤害事件次数（表现层数据源，只含实际扣血）
func _count_damage_to_character(rt: StageRuntime) -> int:
	var n := 0
	for ev: Dictionary in rt.damage_events:
		if str(ev.get("targetKind", "")) == "character":
			n += 1
	return n


## 统计本场对**敌人**造成的伤害事件次数（= 角色出手次数）
func _count_damage_to_enemy(rt: StageRuntime) -> int:
	var n := 0
	for ev: Dictionary in rt.damage_events:
		if str(ev.get("targetKind", "")) == "enemy":
			n += 1
	return n


## 构造「雨宫澪被某敌人阻挡」的场景并推进 seconds 秒，返回澪的出手次数。
func _count_character_attacks_over(seconds: float, blocker_enemy_id: String) -> int:
	var rt := _runtime(_cfg([], [CHAR_MIO]))
	_deploy_ok(rt, CHAR_MIO, 3, 1)
	_place_enemy(rt, 1, 3.5, blocker_enemy_id)
	_step_n(rt, seconds)
	return _count_damage_to_enemy(rt)


## 取某本体的全部衍生体
func _derived_of(rt: StageRuntime, parent_instance_id: int) -> Array[EnemyRuntime]:
	var out: Array[EnemyRuntime] = []
	for e: EnemyRuntime in rt.enemies:
		if e.is_derived and e.parent_instance_id == parent_instance_id:
			out.append(e)
	return out
