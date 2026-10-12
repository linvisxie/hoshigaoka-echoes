## P1.0 测试：三基础敌人 + Prototype 演示关 + 基础反馈数据源
## （V2.1.4 M2 表 114 / D-30 表 33 敌人数量 / D-31 表 34 出怪结构 /
##   D-22 伤害公式 / F-六·F-七·F-八 三敌人 / D-33～D-35 Wave 与暂停 / D-40·D-41 胜负）
##
## 覆盖范围（本轮指令 三 · 14 项重点验收）：
##    1. 三种敌人数据完整且符合规格（9 字段 + weightClass→spriteFramePx 映射）
##    2. 三敌人的移动 / 伤害 / 死亡 / 漏怪正确（含漏怪幂等）
##    3. 快速敌人确实比普通敌人推进更快（比值 ≈ 1.0/0.55）
##    4. 装甲敌人受到物理攻击时正确计算高防减伤
##    5. 多路混合波次按配置执行，不提前或重复完成
##    6. 三职业能共同应对合理设计的混合波次
##    7. 玩家可通过不同合法战术完成挑战（不是唯一硬编码操作）
##    8. 撤退 / 再部署 / 治疗 / AP 系统在长局中无状态泄漏
##    9. 暂停 / 失败 / 胜利 / 重新挑战 / 退出战斗形成完整闭环
##   10. 固定逻辑步长、帧率和分辨率独立性继续成立
##   11. 所有正式数据的角色、敌人、关卡引用均有效
##   12. 演示关规格一致性
##   13. 正式主线解锁顺序未被污染（回归）
##   14. 伤害事件是表现层的正确数据源（只含实际扣减、长度有上限）
##
## 纪律：
##   - 所有夹具先 duplicate(true) 再改，绝不修改 DataRegistry 里的权威字典；
##   - 整体替换 enemySpawnTimeline 时必须同时 erase("waves")（见 _cfg_no_waves）；
##   - 战斗只按 StageRuntime.LOGIC_STEP_SECONDS 推进，不依赖真实时钟、帧率或随机；
##   - 战术动作按**逻辑时间**触发，保证不同 tick 粒度下落在同一逻辑时刻；
##   - 本文件只做**只读**断言，不修改任何被测代码或数据文件。
extends GutTest

const CHAR_MIO := "amamiya_mio"
const CHAR_YUMA := "kamiya_yuma"
const CHAR_YUI := "ogawa_yui"

## 三职业（与 PrototypeRoster.TRIPLE_ROSTER 一致）
const TRIPLE: Array[String] = [CHAR_MIO, CHAR_YUMA, CHAR_YUI]

## Prototype 演示关 id（data/stages/prototype/p1_0_demo.json）
const DEMO_STAGE_ID := "p1_0_demo"

## 权威角色数值（data/characters.json，表 26 / 表 28 / 表 30 / 表 47）
const COST := {CHAR_MIO: 10, CHAR_YUMA: 12, CHAR_YUI: 14}
const CHAR_ATTACK := {CHAR_MIO: 120, CHAR_YUMA: 150, CHAR_YUI: 0}
const CHAR_DEFENSE := {CHAR_MIO: 80, CHAR_YUMA: 30, CHAR_YUI: 35}

## 三基础敌人的权威数值（data/enemies.json，V2.1.4 F-六 / F-七 / F-八）。
## 逐字段断言，任何一项被改动都会在此失败。
const ENEMY_SPEC := {
	"echo_normal": {
		"hp": 420, "attack": 65, "defense": 20, "moveSpeed": 0.55,
		"attackInterval": 1.2, "coreDamage": 1,
		"weightClass": "MEDIUM", "spriteFramePx": 64,
	},
	"echo_runner": {
		"hp": 260, "attack": 50, "defense": 10, "moveSpeed": 1.0,
		"attackInterval": 1.0, "coreDamage": 1,
		"weightClass": "LIGHT", "spriteFramePx": 64,
	},
	"echo_armored": {
		"hp": 800, "attack": 85, "defense": 100, "moveSpeed": 0.35,
		"attackInterval": 1.5, "coreDamage": 1,
		"weightClass": "HEAVY", "spriteFramePx": 96,
	},
}

## weightClass → 精灵帧边长（像素）映射：轻/中 = 64，重 = 96。
const SPRITE_PX_BY_WEIGHT := {"LIGHT": 64, "MEDIUM": 64, "HEAVY": 96,"BOSS":160}

## 演示关敌人构成（data/stages/prototype/p1_0_demo.json）
const DEMO_COMPOSITION := {"echo_normal": 12, "echo_runner": 3, "echo_armored": 5}
const DEMO_WAVE_COUNT := 6
const DEMO_TIMELINE_SIZE := 20
## V2.1.4 D-30 表 33：建议总敌人数 18～24
const D30_MIN_ENEMIES := 18
const D30_MAX_ENEMIES := 24

const AP_MAX := 30
const REDEPLOY_SECONDS := 8.0
const EPS := 0.0001
const MAX_SIM_SECONDS := 900.0

## 已实测的通关战术（tools/simulate_p1_demo.gd 的 B / C / D）。
## 三者**结构不同**：B 治疗挂上段 lane0、C 放弃上段改守下段、D 治疗挂主路中段。
const TACTIC_B: Array[Dictionary] = [
	{"t": 0.5, "a": "deploy", "c": CHAR_MIO, "col": 3, "lane": 1},
	{"t": 14.5, "a": "deploy", "c": CHAR_YUI, "col": 2, "lane": 0},
	{"t": 26.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 0},
	{"t": 118.0, "a": "withdraw", "c": CHAR_YUMA},
	{"t": 138.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 2},
	{"t": 225.0, "a": "withdraw", "c": CHAR_YUMA},
	{"t": 245.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 1},
]

const TACTIC_C: Array[Dictionary] = [
	{"t": 0.5, "a": "deploy", "c": CHAR_MIO, "col": 3, "lane": 1},
	{"t": 14.5, "a": "deploy", "c": CHAR_YUI, "col": 2, "lane": 0},
	{"t": 26.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 0},
	{"t": 118.0, "a": "withdraw", "c": CHAR_YUMA},
	{"t": 138.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 2},
	{"t": 192.0, "a": "withdraw", "c": CHAR_YUMA},
	{"t": 212.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 0},
	{"t": 226.0, "a": "withdraw", "c": CHAR_YUMA},
	{"t": 246.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 1},
]

const TACTIC_D: Array[Dictionary] = [
	{"t": 0.5, "a": "deploy", "c": CHAR_MIO, "col": 3, "lane": 1},
	{"t": 14.5, "a": "deploy", "c": CHAR_YUI, "col": 2, "lane": 1},
	{"t": 26.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 0},
	{"t": 118.0, "a": "withdraw", "c": CHAR_YUMA},
	{"t": 138.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 2},
	{"t": 225.0, "a": "withdraw", "c": CHAR_YUMA},
	{"t": 245.5, "a": "deploy", "c": CHAR_YUMA, "col": 1, "lane": 1},
]


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


# ============================================================
#  夹具（与 tests/test_p0_4_three_class.gd 同一套写法）
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


## 直接从磁盘读取权威数据文件（与 tests/test_data_ssot.gd 同一写法）。
##
## 用途：验收点 1 要断言的是「**数据文件**是否符合 V2.1.4 规格」，
## 因此以文件原文为准，而不是以进程内可能被其他测试就地改写过的内存副本为准
## （本仓库的 _enemy_table() 返回的是 DataRegistry 内部字典的**引用**，
##   任何一处忘记 duplicate(true) 的夹具都会永久污染后续用例，见回报中的「发现的问题」）。
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


## 从磁盘上的 enemies.json 构建敌人配置表（键 = id）。
func _enemy_table_from_file() -> Dictionary:
	var t := {}
	var data: Variant = _read_json("res://data/enemies.json")
	if typeof(data) != TYPE_DICTIONARY:
		return t
	for e: Dictionary in (data as Dictionary).get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


func _combat() -> Dictionary:
	return DataRegistry.get_domain("balance").get("combat", {})


func _stage_config() -> Dictionary:
	return DataRegistry.get_entry("stages", "1-1")


## Prototype 演示关配置（权威，只读；任何用例都不得就地修改它）。
func _demo_config() -> Dictionary:
	return DataRegistry.get_entry("prototype_stages", DEMO_STAGE_ID)


## 出怪时序类夹具：清空 waves 元数据，让波次由 enemySpawnTimeline 自动推导，
## 避免「waves 声明了第 N 波但无敌人归属」的一致性报错。
func _cfg_no_waves(cfg: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	c.erase("waves")
	return c


## 可控夹具：出怪、AP、核心与可部署角色完全由参数决定。
## regen 默认 0.0，使 AP 断言不受自然回复干扰（需要回复的用例显式传入）。
func _cfg(
	spawns: Array,
	chars: Array = [],
	ap: int = AP_MAX,
	regen: float = 0.0,
	core: int = 99
) -> Dictionary:
	var c := _cfg_no_waves(_stage_config())
	c["coreHp"] = core
	c["startingAp"] = ap
	c["apRegen"] = regen
	c["enemySpawnTimeline"] = spawns
	c.erase("availableCharacters")
	c["availableCharacters"] = chars
	return c


func _runtime(cfg: Dictionary) -> StageRuntime:
	return StageRuntime.from_config(cfg, _enemy_table(), _grid(), _char_table(), _combat())


func _session(cfg: Dictionary) -> BattleSession:
	var s := BattleSession.new()
	add_child_autofree(s)
	var errs := s.setup(cfg, _enemy_table(), _grid(), _char_table(), _combat())
	assert_eq(errs.size(), 0, "会话构建应无错误：%s" % str(errs))
	return s


## 部署并断言成功（失败时带出拒绝原因，便于定位）。
func _deploy_ok(rt: StageRuntime, character_id: String, column: int, lane: int) -> CharacterRuntime:
	var r := rt.deploy_character(character_id, column, lane)
	assert_true(r.ok, "应能部署 %s 到 (col%d, lane%d)：%s"
		% [character_id, column, lane, r.reason_text()])
	return r.character


## 手动放置一个敌人到指定位置（用于精确构造射程 / 阻挡 / 漏怪场景）
func _place_enemy(
	rt: StageRuntime, lane: int, x: float, enemy_id: String = "echo_normal"
) -> EnemyRuntime:
	var e := EnemyRuntime.from_config(_enemy_table()[enemy_id], lane, 9000 + rt.enemies.size())
	e.logical_x = x
	e.state = BattleTypes.EnemyState.MOVING
	rt.enemies.append(e)
	return e


## 按固定逻辑步长推进 StageRuntime 指定的逻辑秒数
func _step_n(rt: StageRuntime, seconds: float) -> void:
	var t := 0.0
	while t < seconds - EPS:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS


## 推进到**同一逻辑时刻**（而不是喂入同样的挂钟时长）。
## elapsed_seconds 只在 1/60 秒的网格上前进，因此不同 tick 粒度下
## 必然停在同一个逻辑步边界上，可以公平比较逻辑结果。
func _advance_until(rt: StageRuntime, target_logic_seconds: float, tick: float) -> void:
	var guard := 0
	while rt.elapsed_seconds < target_logic_seconds - EPS and guard < 500000:
		rt.advance(tick)
		guard += 1


## 推进逻辑步直到 AP 足以支付指定角色（用于需要自然回复的场景）
func _wait_ap_for(rt: StageRuntime, character_id: String) -> void:
	var guard := 0
	var need := int(COST[character_id])
	while rt.ap < need and guard < 20000:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1
	assert_true(rt.ap >= need, "自然回复应补足 %s 的费用 %d（实际 AP %d）"
		% [character_id, need, rt.ap])


## 按战术脚本驱动一局完整战斗。
##
## 动作时点以 **StageRuntime.elapsed_seconds（逻辑时间）** 判定，而不是挂钟累加量：
## 逻辑时间只会在 1/60 秒的网格上前进，因此 1/60、1/30、1/144 三种 tick 粒度
## 都会在同一逻辑时刻触发同一动作，胜负结果因此可比。
##
## 返回：
##   session    — 结束时的 BattleSession（胜负已判定或超时）
##   rejects    — 被拒绝的动作（正常战术应为空）
##   maxChars   — 全程场上角色数的峰值（用于「不超过场上上限」断言）
##   maxAp      — 全程 AP 的峰值（用于「不超过 AP 上限」断言）
##   waveSeq    — 波次序号的变化序列（用于「单调不减、不提前完成」断言）
func _run_tactic(cfg: Dictionary, actions: Array, tick: float = -1.0) -> Dictionary:
	var s := _session(cfg)
	var out := _drive(s, actions, tick)
	out["session"] = s
	return out


## 在一个**已构建好**的 StageRuntime 上重放战术，返回结果元组。
## 供「不同参考分辨率」用例使用（该用例需要自行构建带自定义 BattleGrid 的运行时，
## 无法走 _run_tactic 的统一构建路径）。
func _run_tactic_with(rt: StageRuntime, actions: Array) -> Dictionary:
	var s := BattleSession.new()
	add_child_autofree(s)
	s.stage = rt
	s.grid = rt.grid
	s.outcome = BattleTypes.Outcome.RUNNING
	_drive(s, actions, -1.0)
	return _result_tuple(s)


## 按战术脚本推进一个已构建的会话，返回过程性统计（不含 session 本身）。
func _drive(s: BattleSession, actions: Array, tick: float = -1.0) -> Dictionary:
	var step := tick if tick > 0.0 else StageRuntime.LOGIC_STEP_SECONDS
	var cursor := 0
	var guard := 0
	var rejects: Array[String] = []
	var wave_seq: Array = []
	var max_chars := 0
	var max_ap := 0

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
		s.tick(step)
		guard += 1

		var w := s.stage.current_wave_number()
		if wave_seq.is_empty() or int(wave_seq[wave_seq.size() - 1]) != w:
			wave_seq.append(w)
		max_chars = maxi(max_chars, s.stage.characters.size())
		max_ap = maxi(max_ap, s.stage.ap)

	return {
		"rejects": rejects,
		"maxChars": max_chars,
		"maxAp": max_ap,
		"waveSeq": wave_seq,
	}


## 跑完整演示关并返回结果字典；构建失败时直接失败。
func _run_demo(actions: Array = TACTIC_B, tick: float = -1.0) -> Dictionary:
	var cfg := _demo_config()
	if cfg.is_empty():
		fail_test("应能取到 Prototype 演示关 %s" % DEMO_STAGE_ID)
		return {}
	var rt := _runtime(cfg)
	assert_true(rt.is_valid(), "演示关应无构建错误：%s" % str(rt.get_errors()))
	return _run_tactic(cfg, actions, tick)


## 结果元组（用于跨战术 / 跨帧率的确定性比较）
func _result_tuple(s: BattleSession) -> Dictionary:
	return {
		"outcome": s.outcome,
		"coreHp": s.stage.core_hp,
		"kills": s.stage.enemies_killed,
		"leaked": s.stage.reached_core_count,
	}


# ============================================================
#  验收点 1：三种敌人数据完整且符合规格
# ============================================================

## 验收点 1a：三基础敌人的 8 个规格字段逐项符合 V2.1.4 F-六 / F-七 / F-八。
##
## 从**磁盘上的权威数据文件**读取，断言的是数据文件本身是否符合规格
## （内存副本可能被其他测试的就地改写污染，见 _enemy_table_from_file 注释）。
func test_three_enemies_match_spec_values() -> void:
	var table := _enemy_table_from_file()
	# A0.2 更新：enemies.json 现已包含 A0.2 敌人生态的 4 个新敌人，
	# 因此「恰好 3 种」改为「至少含这 3 种基础敌人」——本用例的断言对象仍是
	# 三基础敌人的逐字段数值（下方的循环），数量断言只用于保证三者在场且不被裁剪。
	assert_gte(table.size(), ENEMY_SPEC.size(),
		"enemies.json 至少应含 %d 种基础敌人（实际 %d）" % [ENEMY_SPEC.size(), table.size()])
	for enemy_id: String in ENEMY_SPEC.keys():
		assert_true(table.has(enemy_id), "enemies.json 应含 %s" % enemy_id)
		if not table.has(enemy_id):
			continue
		var cfg: Dictionary = table[enemy_id]
		var spec: Dictionary = ENEMY_SPEC[enemy_id]

		assert_eq(int(cfg.get("hp", -1)), int(spec["hp"]),
			"%s 的 hp 应为 %d" % [enemy_id, int(spec["hp"])])
		assert_eq(int(cfg.get("attack", -1)), int(spec["attack"]),
			"%s 的 attack 应为 %d" % [enemy_id, int(spec["attack"])])
		assert_eq(int(cfg.get("defense", -1)), int(spec["defense"]),
			"%s 的 defense 应为 %d" % [enemy_id, int(spec["defense"])])
		assert_eq(float(cfg.get("moveSpeed", -1.0)), float(spec["moveSpeed"]),
			"%s 的 moveSpeed 应为 %s 格/秒" % [enemy_id, str(spec["moveSpeed"])])
		assert_eq(float(cfg.get("attackInterval", -1.0)), float(spec["attackInterval"]),
			"%s 的 attackInterval 应为 %s 秒" % [enemy_id, str(spec["attackInterval"])])
		assert_eq(int(cfg.get("coreDamage", -1)), int(spec["coreDamage"]),
			"%s 的 coreDamage 应为 %d" % [enemy_id, int(spec["coreDamage"])])
		assert_eq(str(cfg.get("weightClass", "")), str(spec["weightClass"]),
			"%s 的 weightClass 应为 %s" % [enemy_id, str(spec["weightClass"])])
		assert_eq(int(cfg.get("spriteFramePx", -1)), int(spec["spriteFramePx"]),
			"%s 的 spriteFramePx 应为 %d" % [enemy_id, int(spec["spriteFramePx"])])

	# 推进速度的规格序关系：疾走 > 普通 > 装甲（验收点 3 的数据基础）
	var speeds := {}
	for enemy_id: String in ENEMY_SPEC.keys():
		speeds[enemy_id] = float((table[enemy_id] as Dictionary).get("moveSpeed", 0.0))
	assert_gt(float(speeds["echo_runner"]), float(speeds["echo_normal"]),
		"疾走残响体应比普通残响体快")
	assert_gt(float(speeds["echo_normal"]), float(speeds["echo_armored"]),
		"普通残响体应比装甲残响体快")
	# 防御的规格序关系：装甲 > 普通 > 疾走
	assert_gt(float((table["echo_armored"] as Dictionary).get("defense", 0.0)),
		float((table["echo_normal"] as Dictionary).get("defense", 0.0)),
		"装甲残响体应是最高防御单位")


## 验收点 1b：weightClass → spriteFramePx 映射（轻/中 = 64，重 = 96）对**全部**敌人都成立。
func test_weight_class_drives_sprite_frame_size() -> void:
	var enemies: Array = []
	var data: Variant = _read_json("res://data/enemies.json")
	if typeof(data) == TYPE_DICTIONARY:
		enemies = (data as Dictionary).get("enemies", [])
	assert_gt(enemies.size(), 0, "enemies.json 应至少定义 1 个敌人")
	# A0.2 更新：数量断言改为「至少含三基础敌人」（见验收点 1a 的同款说明）；
	# 下方循环对**全部**敌人断言 weightClass → spriteFramePx 映射，
	# 因此新增敌人同样受该映射约束（A0.2 的 4 个新敌人均为 64/64/64/96，符合映射）。
	assert_gte(enemies.size(), ENEMY_SPEC.size(),
		"enemies.json 至少应含 %d 种基础敌人（实际 %d）" % [ENEMY_SPEC.size(), enemies.size()])
	for e: Dictionary in enemies:
		var enemy_id := str(e.get("id", ""))
		var weight := str(e.get("weightClass", ""))
		assert_true(SPRITE_PX_BY_WEIGHT.has(weight),
			"%s 的 weightClass '%s' 应是已知重量级" % [enemy_id, weight])
		if not SPRITE_PX_BY_WEIGHT.has(weight):
			continue
		assert_eq(int(e.get("spriteFramePx", -1)), int(SPRITE_PX_BY_WEIGHT[weight]),
			"%s（%s）的精灵帧边长应为 %d" % [enemy_id, weight, int(SPRITE_PX_BY_WEIGHT[weight])])


# ============================================================
#  验收点 2：三敌人的移动 / 伤害 / 死亡 / 漏怪正确
# ============================================================

## 验收点 2a（移动）：固定逻辑步推进下，位移 ≈ moveSpeed × 逻辑时间（tile）。
func test_enemy_movement_matches_configured_speed() -> void:
	# 三种敌人各占一条路线，同时生成；核心 HP 充足，保证测量期间无人抵达核心
	var spawns: Array = []
	var lanes := {"echo_normal": 0, "echo_runner": 1, "echo_armored": 2}
	for enemy_id: String in ENEMY_SPEC.keys():
		spawns.append({"time": 0.0, "lane": int(lanes[enemy_id]), "enemy": enemy_id})
	var rt := _runtime(_cfg(spawns, [], AP_MAX, 0.0, 99))
	assert_true(rt.is_valid(), "夹具应无构建错误：%s" % str(rt.get_errors()))

	# 4 秒内最快的疾走残响体只走 4 格（< 5 格全程），不会抵达核心
	var travel := 4.0
	_advance_until(rt, travel, StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(rt.enemies.size(), 3, "三只敌人都应在场上")
	for e: EnemyRuntime in rt.enemies:
		var speed := float((ENEMY_SPEC[e.enemy_id] as Dictionary)["moveSpeed"])
		var expected := speed * travel
		var moved := BattleGrid.SPAWN_X - e.logical_x
		assert_almost_eq(moved, expected, 0.02,
			"%s 在 %.1f 秒内应前进 %.3f 格（moveSpeed %.2f × 时间），实际 %.4f"
			% [e.enemy_id, travel, expected, speed, moved])
		# 位移必须来自 moveSpeed，而不是任何按敌人名写死的分支
		assert_eq(e.move_speed, speed, "%s 的 move_speed 应直接来自配置" % e.enemy_id)


## 验收点 2b（伤害）：敌人攻击阻挡者时，扣血 = 攻击×100/(100+防御) 四舍五入。
func test_enemy_attack_damage_matches_formula() -> void:
	# 期望值按 V2.1.4 D-22 公式手工推导：攻击×100/(100+防御)，四舍五入
	#   echo_normal  65 ×100/180 = 36.11 → 36
	#   echo_runner  50 ×100/180 = 27.78 → 28
	#   echo_armored 85 ×100/180 = 47.22 → 47
	var expected := {"echo_normal": 36, "echo_runner": 28, "echo_armored": 47}

	for enemy_id: String in expected.keys():
		var rt := _runtime(_cfg([], [CHAR_MIO], AP_MAX, 0.0, 99))
		var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
		assert_eq(mio.defense, int(CHAR_DEFENSE[CHAR_MIO]), "雨宫澪防御应为 80（权威数值）")

		# 放在接触线（col3 中心 3.0 + contactLineTiles 0.5 = 3.5）上，本逻辑步即被阻挡并出手
		var e := _place_enemy(rt, 1, 3.5, enemy_id)
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

		assert_eq(e.state, BattleTypes.EnemyState.BLOCKED,
			"%s 应被雨宫澪阻挡" % enemy_id)
		assert_eq(mio.hp, mio.max_hp - int(expected[enemy_id]),
			"%s 攻击阻挡者应造成 %d 伤害（攻击 %d × 100/(100+防御 %d)），实际扣血 %d"
			% [enemy_id, int(expected[enemy_id]), e.attack, mio.defense,
				mio.max_hp - mio.hp])

		# 同一笔伤害必须同时进入表现层数据源（角色侧）
		var found := false
		for ev: Dictionary in rt.damage_events:
			if str(ev["targetKind"]) == "character" \
				and int(ev["targetId"]) == mio.instance_id \
				and int(ev["amount"]) == int(expected[enemy_id]):
				found = true
		assert_true(found, "%s 对角色造成的 %d 伤害应被记录为伤害事件"
			% [enemy_id, int(expected[enemy_id])])


## 验收点 2c（死亡）：HP 归零后从场上移除、计入击杀、并**立即释放阻挡名额**。
func test_enemy_death_removes_and_releases_block_slot() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO], AP_MAX, 0.0, 99))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	assert_eq(mio.block_count_max, 2, "雨宫澪阻挡数应为 2（权威数值）")

	# 两名敌人同时接触：恰好占满 2 个阻挡名额
	var a := _place_enemy(rt, 1, 3.5, "echo_normal")
	var b := _place_enemy(rt, 1, 3.5, "echo_normal")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(a.state, BattleTypes.EnemyState.BLOCKED, "第 1 名敌人应被阻挡")
	assert_eq(b.state, BattleTypes.EnemyState.BLOCKED, "第 2 名敌人应被阻挡")
	assert_eq(mio.block_slots_remaining(), 0, "两个阻挡名额应已被占满")

	# 第 3 名敌人此刻无法被阻挡（名额已满 → 继续前进，V2.1.4 D-10）
	var c := _place_enemy(rt, 1, 3.5, "echo_normal")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_ne(c.state, BattleTypes.EnemyState.BLOCKED,
		"阻挡名额已满时第 3 名敌人不得被阻挡（应继续前进）")
	assert_true(c.logical_x < 3.5, "未被阻挡的敌人应继续向核心推进")

	# 击杀第 1 名敌人：移除、计数、并释放其阻挡名额
	var killed_id := a.instance_id
	a.take_damage(a.hp_max + 1)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(rt.enemies_killed, 1, "HP 归零的敌人应计入击杀")
	assert_null(rt.get_enemy(killed_id), "被击杀的敌人应从场上移除")
	assert_false(mio.blocking_enemy_ids.has(killed_id),
		"被击杀的敌人不应再占用阻挡名额")
	assert_eq(rt.characters_lost, 0, "击杀敌人不应误伤角色")
	# 注：真实击杀路径当前**不**写入 removals 中的 KILLED 记录
	# （StageRuntime._cleanup_dead 只计数 + 记 Wave，未调用 _append_enemy_removal），
	# 因此此处不断言该记录；已作为「发现的问题」上报主理人，不在测试里固化现状。

	# 名额释放后，第 3 名敌人应在**同一逻辑步**内接上（D-10：清理先于建立阻挡）。
	# 因此本步结束时阻挡名单应恰好是「仍存活的 b + 刚接管的 c」——这同时证明了
	# a 的名额已被释放、且该名额被立刻回收而非空置。
	assert_eq(c.state, BattleTypes.EnemyState.BLOCKED,
		"释放的名额应能被后续敌人立即接管（不出现空档）")
	assert_eq(mio.blocking_enemy_ids.size(), 2,
		"击杀并接管后应恰好占用 2 个阻挡名额（实际 %d）" % mio.blocking_enemy_ids.size())
	assert_true(mio.is_blocking(b.instance_id), "仍存活的 b 应继续被阻挡")
	assert_true(mio.is_blocking(c.instance_id), "接管的 c 应被阻挡")
	assert_eq(mio.block_slots_remaining(), 0, "接管后名额应再次占满")


## 验收点 2d（漏怪）：抵达核心 → 核心 HP 减 coreDamage、计入漏怪，且**幂等**。
func test_leak_settles_core_damage_once_and_is_idempotent() -> void:
	# 三种敌人各占一条路线，场上无角色，核心 HP 充足
	var spawns: Array = [
		{"time": 0.0, "lane": 0, "enemy": "echo_normal"},
		{"time": 0.0, "lane": 1, "enemy": "echo_runner"},
		{"time": 0.0, "lane": 2, "enemy": "echo_armored"},
	]
	var rt := _runtime(_cfg(spawns, [], AP_MAX, 0.0, 99))
	assert_true(rt.is_valid(), "夹具应无构建错误：%s" % str(rt.get_errors()))

	# 累积「本步首次抵达核心」的敌人（advance 的返回值天然恰好一次）
	var reached: Array[EnemyRuntime] = []
	var guard := 0
	while rt.reached_core_count < 3 and guard < 200:
		reached.append_array(rt.advance(1.0))
		guard += 1

	assert_eq(rt.reached_core_count, 3, "三只敌人都应抵达核心")
	assert_eq(reached.size(), 3, "抵达列表应恰好包含三只敌人（每只一次）")
	assert_eq(rt.core_damage_events, 3, "应恰好发生 3 次核心伤害结算")
	assert_eq(rt.core_hp, 99 - 3, "三只 coreDamage=1 的敌人应使核心 99 → 96")
	assert_eq(rt.removal_count(StageRuntime.Removal.REACHED_CORE), 3,
		"应恰好留下 3 条漏怪离场记录")

	# 幂等：对同一敌人重复结算不得二次扣血
	for e: EnemyRuntime in reached:
		assert_true(e.core_damage_applied, "抵达核心的敌人应被标记为已结算")
		assert_eq(rt.apply_core_damage(e), 0, "重复结算应返回 0（不再造成伤害）")
	assert_eq(rt.core_hp, 96, "重复调用 apply_core_damage 不得再次扣除核心 HP")
	assert_eq(rt.core_damage_events, 3, "重复调用不得增加核心伤害事件计数")
	assert_eq(rt.reached_core_count, 3, "重复调用不得增加漏怪计数")
	assert_eq(rt.removal_count(StageRuntime.Removal.REACHED_CORE), 3,
		"重复调用不得产生重复的离场记录")


# ============================================================
#  验收点 3：快速敌人确实比普通敌人推进更快
# ============================================================

## 验收点 3：同一逻辑时长内疾走残响体的位移 > 普通残响体，且比值 ≈ 1.0/0.55。
func test_runner_outpaces_normal_by_speed_ratio() -> void:
	var spawns: Array = [
		{"time": 0.0, "lane": 0, "enemy": "echo_normal"},
		{"time": 0.0, "lane": 1, "enemy": "echo_runner"},
	]
	var rt := _runtime(_cfg(spawns, [], AP_MAX, 0.0, 99))

	# 4 秒：疾走走满 4 格、普通走 2.2 格，两者都未抵达核心（全程 5 格）
	var travel := 4.0
	_advance_until(rt, travel, StageRuntime.LOGIC_STEP_SECONDS)

	var normal: EnemyRuntime = null
	var runner: EnemyRuntime = null
	for e: EnemyRuntime in rt.enemies:
		if e.enemy_id == "echo_normal":
			normal = e
		elif e.enemy_id == "echo_runner":
			runner = e
	assert_not_null(normal, "场上应有普通残响体")
	assert_not_null(runner, "场上应有疾走残响体")
	if normal == null or runner == null:
		return

	var normal_moved := BattleGrid.SPAWN_X - normal.logical_x
	var runner_moved := BattleGrid.SPAWN_X - runner.logical_x
	assert_gt(runner_moved, normal_moved,
		"疾走残响体（%.3f 格）应比普通残响体（%.3f 格）推进更快" % [runner_moved, normal_moved])

	var ratio := runner_moved / normal_moved
	var expected_ratio := 1.0 / 0.55
	assert_almost_eq(ratio, expected_ratio, 0.02,
		"推进速度比值应约等于 1.0/0.55 = %.4f，实际 %.4f" % [expected_ratio, ratio])
	# 领先幅度也必须真实可观察，而不是浮点噪声
	assert_gt(runner_moved - normal_moved, 1.0,
		"同一时长内疾走的领先幅度应显著（实际领先 %.3f 格）" % (runner_moved - normal_moved))


# ============================================================
#  验收点 4：装甲敌人受到物理攻击时正确计算高防减伤
# ============================================================

## 验收点 4：装甲残响体（防御 100）显著减免物理伤害：悠真 75 / 澪 60，均远低于对普通敌人的 100。
func test_armored_enemy_mitigates_physical_damage() -> void:
	# ---- 公式层：直接验证 D-22 在权威参数下的取值 ----
	var math := CombatMath.from_config(_combat().get("damage", {}))
	var armored_def := float((ENEMY_SPEC["echo_armored"] as Dictionary)["defense"])
	var normal_def := float((ENEMY_SPEC["echo_normal"] as Dictionary)["defense"])

	assert_eq(math.compute_damage(float(CHAR_ATTACK[CHAR_YUMA]), armored_def),
		75, "悠真（攻 150）打装甲（防 100）应为 150×100/200 = 75")
	assert_eq(math.compute_damage(float(CHAR_ATTACK[CHAR_MIO]), armored_def),
		60, "澪（攻 120）打装甲（防 100）应为 120×100/200 = 60")
	assert_eq(math.compute_damage(float(CHAR_ATTACK[CHAR_MIO]), normal_def),
		100, "澪（攻 120）打普通（防 20）应为 120×100/120 = 100")
	assert_lt(math.compute_damage(float(CHAR_ATTACK[CHAR_YUMA]), armored_def),
		math.compute_damage(float(CHAR_ATTACK[CHAR_YUMA]), normal_def),
		"悠真打装甲应显著低于打普通敌人（高防减伤成立）")

	# ---- 运行时层：实际战斗中的扣血必须与公式一致 ----
	# 悠真（远程，射程 4.0）从 col1 打 x=3.5 的装甲（距离 2.5 ≤ 4.0）
	var rt_ranged := _runtime(_cfg([], [CHAR_YUMA], AP_MAX, 0.0, 99))
	var yuma := _deploy_ok(rt_ranged, CHAR_YUMA, 1, 1)
	assert_eq(yuma.attack, int(CHAR_ATTACK[CHAR_YUMA]), "悠真攻击应为 150（权威数值）")
	var far_armored := _place_enemy(rt_ranged, 1, 3.5, "echo_armored")
	rt_ranged.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(far_armored.hp, 800 - 75,
		"悠真一次攻击应使装甲从 800 降到 725（实际 %d）" % far_armored.hp)

	# 澪（前线，射程 1.25）阻挡 x=3.5 的装甲并攻击
	var rt_front := _runtime(_cfg([], [CHAR_MIO], AP_MAX, 0.0, 99))
	var mio := _deploy_ok(rt_front, CHAR_MIO, 3, 1)
	assert_eq(mio.attack, int(CHAR_ATTACK[CHAR_MIO]), "雨宫澪攻击应为 120（权威数值）")
	var near_armored := _place_enemy(rt_front, 1, 3.5, "echo_armored")
	rt_front.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(near_armored.state, BattleTypes.EnemyState.BLOCKED, "装甲应被澪阻挡")
	assert_eq(near_armored.hp, 800 - 60,
		"澪一次攻击应使装甲从 800 降到 740（实际 %d）" % near_armored.hp)

	# 同一角色打普通敌人应打出更高伤害（证明减伤来自防御，而非角色差异）
	var rt_normal := _runtime(_cfg([], [CHAR_MIO], AP_MAX, 0.0, 99))
	_deploy_ok(rt_normal, CHAR_MIO, 3, 1)
	var normal := _place_enemy(rt_normal, 1, 3.5, "echo_normal")
	rt_normal.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(normal.hp, 420 - 100,
		"澪打普通残响体应造成 100 伤害（实际扣 %d）" % (420 - normal.hp))
	assert_gt(420 - normal.hp, 800 - near_armored.hp,
		"澪对普通敌人的伤害应高于对装甲的伤害（高防确实减伤）")


# ============================================================
#  验收点 5：多路混合波次按配置执行，不提前或重复完成
# ============================================================

## 验收点 5：演示关 6 波按序完成，每波生成数等于计划数、只完成一次、总数不变。
func test_demo_waves_execute_in_order_without_early_or_duplicate_clear() -> void:
	var cfg := _demo_config()
	var rt := _runtime(cfg)
	assert_true(rt.is_valid(), "演示关应无构建错误：%s" % str(rt.get_errors()))

	# 运行前的静态事实：6 波、编号 1..6、全部 ALL_ENEMIES_DEFEATED
	assert_eq(rt.total_wave_count(), DEMO_WAVE_COUNT, "演示关应有 6 波")
	assert_eq(rt.current_wave_number(), 1, "开局应处于第 1 波")
	for i: int in range(rt.total_wave_count()):
		var w: Dictionary = rt.waves[i]
		assert_eq(int(w["number"]), i + 1, "第 %d 波的编号应为 %d" % [i + 1, i + 1])
		assert_eq(str(w["clearCondition"]), "ALL_ENEMIES_DEFEATED",
			"第 %d 波的完成条件应为 ALL_ENEMIES_DEFEATED" % (i + 1))
		assert_gt(int(w["enemyCount"]), 0, "第 %d 波应有敌人" % (i + 1))

	# 跑完整局（战术 B 为已实测通关解）
	var res := _run_demo()
	assert_eq((res["rejects"] as Array).size(), 0,
		"战术 B 的每个动作都应被接受：%s" % str(res["rejects"]))
	var stage := (res["session"] as BattleSession).stage

	# 波次总数不得在运行中变化
	assert_eq(stage.total_wave_count(), DEMO_WAVE_COUNT, "运行后波次总数仍应为 6")
	assert_eq(stage.waves.size(), DEMO_WAVE_COUNT, "waves 元数据不应被追加或删除")

	# 波次序号单调不减、逐波 +1、首 1 末 6（不提前也不跳过）
	var seq: Array = res["waveSeq"]
	assert_eq(seq.size(), DEMO_WAVE_COUNT,
		"波次应恰好发生 %d 次变化，实际序列 %s" % [DEMO_WAVE_COUNT, str(seq)])
	assert_eq(int(seq[0]), 1, "首个波次号应为 1")
	assert_eq(int(seq[seq.size() - 1]), 6, "最终波次号应为 6")
	for i: int in range(1, seq.size()):
		assert_eq(int(seq[i]), int(seq[i - 1]) + 1,
			"波次应逐波 +1（第 %d 个变化：%d → %d，不得跳波或回退）"
			% [i, int(seq[i - 1]), int(seq[i])])

	# 每波：生成数 == 计划数、已完成、击杀+漏怪恰好等于计划数（不重复结算）
	assert_true(stage.all_waves_cleared(), "全部 6 波都应已完成")
	for i: int in range(stage.total_wave_count()):
		var st: Dictionary = stage.wave_state_at(i)
		var w: Dictionary = stage.waves[i]
		var num := int(w["number"])
		var planned := int(w["enemyCount"])
		assert_eq(int(st["status"]), StageRuntime.WAVE_CLEARED, "第 %d 波应已完成" % num)
		assert_eq(int(st["spawned"]), planned,
			"第 %d 波应恰好生成 %d 个敌人（实际 %d）" % [num, planned, int(st["spawned"])])
		assert_eq(int(st["killed"]) + int(st["leaked"]), planned,
			"第 %d 波的击杀+漏怪应恰好等于计划数 %d（实际 %d，不得重复结算）"
			% [num, planned, int(st["killed"]) + int(st["leaked"])])
		assert_lte(int(st["killed"]), planned,
			"第 %d 波的击杀数不得超过计划数" % num)
		assert_lte(int(st["leaked"]), planned,
			"第 %d 波的漏怪数不得超过计划数" % num)

	# 全程生成总数 == 计划总数（不重复生成）
	assert_eq(stage.spawned_enemy_count(), stage.planned_enemy_count(),
		"全部计划敌人都应生成完毕且不重复生成")


# ============================================================
#  验收点 6：三职业能共同应对合理设计的混合波次
# ============================================================

## 验收点 6：三职业同场可稳定通关演示关（胜利 / 击杀 20 / 漏怪 0 / 核心 5-5）。
func test_three_classes_clear_mixed_demo_waves_together() -> void:
	var res := _run_demo()
	assert_eq((res["rejects"] as Array).size(), 0,
		"战术 B 的每个动作都应被接受：%s" % str(res["rejects"]))
	var s: BattleSession = res["session"]
	var stage := s.stage

	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
		"三职业应能通关（核心 %d/%d，击杀 %d，漏怪 %d，Wave %d/%d）"
		% [stage.core_hp, stage.core_hp_max, stage.enemies_killed,
			stage.reached_core_count, stage.current_wave_number(), stage.total_wave_count()])
	assert_eq(stage.enemies_killed, DEMO_TIMELINE_SIZE,
		"应击杀全部 %d 名敌人（实际 %d）" % [DEMO_TIMELINE_SIZE, stage.enemies_killed])
	assert_eq(stage.reached_core_count, 0,
		"不应有任何漏怪（实际 %d）" % stage.reached_core_count)
	assert_eq(stage.core_hp, stage.core_hp_max,
		"核心应保持满血 %d/%d（实际 %d）" % [stage.core_hp_max, stage.core_hp_max, stage.core_hp])

	# 三名角色都实际参战（不是「放上去但没生效」）
	var deployed_ids := {}
	for c: CharacterRuntime in stage.character_instances:
		deployed_ids[c.character_id] = true
	for cid: String in TRIPLE:
		assert_true(deployed_ids.has(cid), "三职业应全部登场：%s" % cid)
	assert_gt(stage.deploy_success_count, 3, "含换线再部署，成功部署次数应多于 3 次")
	assert_gt(stage.retreat_count, 0, "通关路线包含主动撤退换线")
	assert_gt(stage.total_healing_done, 0, "治疗职业应实际产生治疗量")

	# 结算摘要与领域层一致
	var summary := s.result_summary()
	assert_eq(int(summary["kills"]), stage.enemies_killed, "结算摘要的击杀数应与领域层一致")
	assert_eq(int(summary["leaked"]), stage.reached_core_count, "结算摘要的漏怪数应与领域层一致")
	assert_true(bool(summary["victory"]), "结算摘要应标记为胜利")


# ============================================================
#  验收点 7：玩家可通过不同合法战术完成挑战
# ============================================================

## 验收点 7：至少 3 个**结构不同**的合法战术都能通关（本关不依赖唯一硬编码操作）。
func test_multiple_valid_tactics_can_win() -> void:
	var tactics := {
		"B（治疗挂上段 lane0，远程按波换线）": TACTIC_B,
		"C（放弃上段改守下段，低损耗解）": TACTIC_C,
		"D（治疗挂主路中段，远程按波换线）": TACTIC_D,
	}
	var sessions := {}
	var results := {}
	for label: String in tactics.keys():
		var res := _run_demo(tactics[label])
		assert_eq((res["rejects"] as Array).size(), 0,
			"战术 %s 的动作都应被接受：%s" % [label, str(res["rejects"])])
		var s: BattleSession = res["session"]
		assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
			"战术 %s 应能通关（核心 %d/%d，击杀 %d，漏怪 %d）"
			% [label, s.stage.core_hp, s.stage.core_hp_max,
				s.stage.enemies_killed, s.stage.reached_core_count])
		sessions[label] = s
		results[label] = _result_tuple(s)

	# 结构差异必须是真实的：B 与 D 的治疗位不同，且 C 以「放弃一条线」的方式收敛。
	var label_b := "B（治疗挂上段 lane0，远程按波换线）"
	var label_c := "C（放弃上段改守下段，低损耗解）"
	var label_d := "D（治疗挂主路中段，远程按波换线）"
	assert_ne(results[label_b], results[label_c],
		"战术 B 与 C 的结果元组应不同（证明不是同一套操作的复述）")

	var b_healer: CharacterRuntime = (sessions[label_b] as BattleSession).stage \
		.get_character_instance(CHAR_YUI)
	var d_healer: CharacterRuntime = (sessions[label_d] as BattleSession).stage \
		.get_character_instance(CHAR_YUI)
	assert_not_null(b_healer, "战术 B 应部署过结衣")
	assert_not_null(d_healer, "战术 D 应部署过结衣")
	if b_healer != null and d_healer != null:
		assert_eq(b_healer.lane, 0, "战术 B 的治疗位应在上段 lane0")
		assert_eq(d_healer.lane, 1, "战术 D 的治疗位应在主路中段 lane1")
		assert_ne(b_healer.lane, d_healer.lane,
			"两个战术的治疗位必须不同，否则不构成结构不同的合法解")

	# 至少两个战术做到零漏怪（B 与 D），全部为胜利
	assert_eq(int((results[label_b] as Dictionary)["leaked"]), 0, "战术 B 应零漏怪")
	assert_eq(int((results[label_d] as Dictionary)["leaked"]), 0, "战术 D 应零漏怪")
	for label: String in results.keys():
		assert_eq(int((results[label] as Dictionary)["outcome"]),
			BattleTypes.Outcome.VICTORY, "战术 %s 应为胜利" % label)


# ============================================================
#  验收点 8：撤退 / 再部署 / 治疗 / AP 在长局中无状态泄漏
# ============================================================

## 验收点 8a：撤退后 AP 返还正确、角色离场、原格可立即再用，且不重复返还。
func test_retreat_refunds_ap_and_frees_cell() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO], AP_MAX, 0.0, 99))
	var mio := _deploy_ok(rt, CHAR_MIO, 2, 1)
	var cost := int(COST[CHAR_MIO])
	assert_eq(rt.ap, AP_MAX - cost, "部署后 AP 应为 %d" % (AP_MAX - cost))

	var r := rt.withdraw_character(mio.instance_id)
	assert_true(r.ok, "主动撤退应成功：%s" % r.reason_text())
	assert_eq(r.refund, cost / 2, "撤退应返还费用的 50%%（%d AP）" % (cost / 2))
	assert_eq(r.refund_granted, cost / 2, "AP 充足时应全额入账 %d AP" % (cost / 2))
	assert_eq(rt.ap, AP_MAX - cost + cost / 2, "撤退后 AP 应回到 %d" % (AP_MAX - cost / 2))
	assert_eq(rt.retreat_count, 1, "应记录 1 次撤退")
	assert_eq(rt.retreat_refunded_ap_total, cost / 2, "累计返还应等于本次返还")

	# 角色离场、原格立即释放
	assert_null(rt.get_character_by_id(CHAR_MIO), "撤退后角色应不在场上")
	assert_null(rt.get_character_at(2, 1), "撤退后原格应立即变为可用")
	assert_eq(rt.characters.size(), 0, "场上不应残留角色实体")
	assert_eq(rt.get_redeploy_remaining(CHAR_MIO), REDEPLOY_SECONDS,
		"撤退后应进入 %.0f 秒再部署冷却" % REDEPLOY_SECONDS)

	# 幂等：重复撤退同一实例不得二次返还 AP
	var again := rt.withdraw_character(mio.instance_id)
	assert_false(again.ok, "重复撤退应被拒绝")
	assert_eq(again.reason, StageRuntime.RetreatReject.CHARACTER_NOT_DEPLOYED,
		"重复撤退的原因应为「该角色不在场上」")
	assert_eq(rt.ap, AP_MAX - cost / 2, "重复撤退不得二次返还 AP")
	assert_eq(rt.retreat_count, 1, "重复撤退不得增加撤退计数")

	# 原格可再用：冷却结束后可在**同一格**重新部署，且不产生重复实体
	_wait_ap_for(rt, CHAR_MIO)
	_advance_until(rt, rt.elapsed_seconds + REDEPLOY_SECONDS + 0.5, StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt.get_redeploy_remaining(CHAR_MIO), 0.0, "冷却结束后应可再部署")
	var again_deploy := rt.deploy_character(CHAR_MIO, 2, 1)
	assert_true(again_deploy.ok, "原格应可再次部署：%s" % again_deploy.reason_text())
	assert_eq(rt.characters.size(), 1, "再部署后场上应恰好 1 个实体")
	assert_eq(rt.character_instances.size(), 2, "再部署应产生新实例（保留离场历史）")

	# AP 返还受上限截断：refund 是应返额，refund_granted 才是实际入账
	var rt_cap := _runtime(_cfg([], [CHAR_MIO], AP_MAX, 0.0, 99))
	var mio2 := _deploy_ok(rt_cap, CHAR_MIO, 2, 1)
	rt_cap.ap = AP_MAX - 2
	var capped := rt_cap.withdraw_character(mio2.instance_id)
	assert_true(capped.ok, "撤退应成功")
	assert_eq(capped.refund, cost / 2, "应返额仍为 %d AP（不受上限影响）" % (cost / 2))
	assert_eq(capped.refund_granted, 2, "实际入账应被 AP 上限截断为 2")
	assert_eq(rt_cap.ap, AP_MAX, "AP 不得超过上限 %d" % AP_MAX)
	assert_eq(rt_cap.retreat_refunded_ap_total, 2, "累计返还应记录**实际入账**量")


## 验收点 8b：再部署冷却只在逻辑步内推进，且**暂停时冻结**。
func test_redeploy_cooldown_advances_only_in_logic_steps_and_freezes_when_paused() -> void:
	var rt := _runtime(_cfg([], [CHAR_MIO], AP_MAX, 0.0, 99))
	_deploy_ok(rt, CHAR_MIO, 2, 1)
	rt.withdraw_character_by_id(CHAR_MIO)
	assert_eq(rt.get_redeploy_remaining(CHAR_MIO), REDEPLOY_SECONDS,
		"撤退瞬间冷却应为 %.0f 秒" % REDEPLOY_SECONDS)

	# 冷却只在逻辑步内按步长递减
	var steps := 60
	for i: int in range(steps):
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	var expected := REDEPLOY_SECONDS - float(steps) * StageRuntime.LOGIC_STEP_SECONDS
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_MIO), expected, 0.001,
		"%d 个逻辑步后冷却应约为 %.4f 秒" % [steps, expected])

	# 暂停：冷却与逻辑时间都必须冻结
	var frozen_at := rt.get_redeploy_remaining(CHAR_MIO)
	var elapsed_at := rt.elapsed_seconds
	rt.set_paused(true)
	assert_true(rt.is_paused(), "应已进入暂停")
	_step_n(rt, 5.0)
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_MIO), frozen_at, 0.0001,
		"暂停期间再部署冷却必须冻结（不得推进）")
	assert_almost_eq(rt.elapsed_seconds, elapsed_at, 0.0001,
		"暂停期间逻辑时间必须冻结")

	# 恢复后从同一状态继续（不补跑暂停期间的时间）
	rt.set_paused(false)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_MIO),
		frozen_at - StageRuntime.LOGIC_STEP_SECONDS, 0.0001,
		"恢复后冷却应从冻结值继续递减（不补跑暂停时长）")

	# 冷却归零后可再部署
	_advance_until(rt, rt.elapsed_seconds + REDEPLOY_SECONDS, StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt.get_redeploy_remaining(CHAR_MIO), 0.0, "冷却应已归零")
	assert_false(rt.is_redeploy_cooling(CHAR_MIO), "应不再处于再部署冷却")
	var r := rt.deploy_character(CHAR_MIO, 2, 1)
	assert_true(r.ok, "冷却结束后应可再部署：%s" % r.reason_text())


## 验收点 8c：长局（完整演示关）结束后 AP、场上人数与角色实例均无状态泄漏。
func test_long_battle_leaves_no_state_leak() -> void:
	var res := _run_demo()
	var stage := (res["session"] as BattleSession).stage
	var field_limit := int(_combat().get("fieldDeployLimit", 0))
	assert_eq(field_limit, 5, "场上同时部署上限应来自 balance.combat.fieldDeployLimit = 5")

	# AP 全程不得越界
	assert_lte(stage.ap, stage.ap_max, "结束时 AP %d 不得超过上限 %d" % [stage.ap, stage.ap_max])
	assert_gte(stage.ap, 0, "AP 不得为负")
	assert_lte(int(res["maxAp"]), stage.ap_max,
		"全程 AP 峰值 %d 不得超过上限 %d" % [int(res["maxAp"]), stage.ap_max])

	# 场上人数全程不得超过场上上限
	assert_lte(stage.characters.size(), field_limit,
		"结束时场上角色数不得超过 %d（实际 %d）" % [field_limit, stage.characters.size()])
	assert_lte(int(res["maxChars"]), field_limit,
		"全程场上角色数峰值不得超过 %d（实际 %d）" % [field_limit, int(res["maxChars"])])

	# 同一 character_id 的**在场**实例至多 1 个（撤退/再部署不得复制实体）
	for cid: String in TRIPLE:
		var live := 0
		for c: CharacterRuntime in stage.character_instances:
			if c.character_id == cid and stage.get_character(c.instance_id) != null:
				live += 1
		assert_lte(live, 1,
			"角色 %s 在同一时刻至多只能有 1 个在场实例（实际 %d）" % [cid, live])

	# 场上数组本身也不得出现同 id 重复
	var on_field := {}
	for c: CharacterRuntime in stage.characters:
		on_field[c.character_id] = int(on_field.get(c.character_id, 0)) + 1
	for cid: String in on_field.keys():
		assert_eq(int(on_field[cid]), 1, "场上不得出现重复的 %s 实体" % cid)

	# 换线再部署必须走「新实例 + 旧实例留在历史」的路径，而不是复用同一实例
	assert_gte(stage.character_instances.size(), stage.characters.size(),
		"实例历史数不应少于场上数（历史只增不减）")
	var instance_ids := {}
	for c: CharacterRuntime in stage.character_instances:
		assert_false(instance_ids.has(c.instance_id),
			"实例 id 必须唯一（发现重复 %d）" % c.instance_id)
		instance_ids[c.instance_id] = true

	# 每个在场角色确实都出现在 characters 中，且恰好占据其记录的格子
	for c: CharacterRuntime in stage.characters:
		assert_not_null(stage.get_character(c.instance_id),
			"场上角色 %s 应能按 instance_id 查到" % c.character_id)
		assert_eq(stage.get_character_at(c.column, c.lane).instance_id, c.instance_id,
			"角色 %s 应恰好占据其记录的格子" % c.character_id)


## 验收点 8d：治疗不超上限，且累计治疗量 == 各次实际治疗之和。
func test_healing_never_exceeds_max_hp_and_totals_match() -> void:
	# 无敌人：隔离出纯治疗场景
	var rt := _runtime(_cfg([], [CHAR_MIO, CHAR_YUI], AP_MAX, 0.0, 99))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	var yui := _deploy_ok(rt, CHAR_YUI, 2, 1)
	assert_eq(yui.heal_power, 110, "小川结衣治疗力应为 110（权威数值）")

	# 只留 10 点缺口：治疗量（110）必须被夹到缺口 10，而不是溢出
	var missing := 10
	mio.take_damage(missing)
	assert_eq(mio.hp, mio.max_hp - missing, "雨宫澪应只缺 %d HP" % missing)

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(rt.heal_events.size(), 1, "应有 1 次治疗")
	var first: Dictionary = rt.heal_events[0]
	assert_eq(int(first["amount"]), missing,
		"实际治疗量应被夹到缺口 %d（而不是治疗力 110）" % missing)
	assert_eq(mio.hp, mio.max_hp, "治疗后应恰好满血，不得超过上限")
	assert_eq(rt.total_healing_done, missing, "累计治疗量应为 %d" % missing)

	# 满血时不得继续治疗，也不得空转消耗间隔
	_step_n(rt, 5.0)
	assert_eq(rt.heal_events.size(), 1, "全部满血时不应产生新的治疗事件")
	assert_eq(mio.hp, mio.max_hp, "满血角色不应被过度治疗")

	# 多次治疗：累计量必须等于各次实际治疗之和，且每次都不越上限
	var events_before := rt.heal_events.size()
	var total_before := rt.total_healing_done
	mio.take_damage(300)
	assert_eq(mio.hp, mio.max_hp - 300, "雨宫澪应被扣到 %d HP" % (mio.max_hp - 300))
	_step_n(rt, 10.0)
	assert_gt(rt.heal_events.size() - events_before, 1, "10 秒内应产生多次治疗")

	var sum := 0
	for i: int in range(events_before, rt.heal_events.size()):
		var ev: Dictionary = rt.heal_events[i]
		var amount := int(ev["amount"])
		assert_gt(amount, 0, "每次治疗都必须实际生效（amount > 0）")
		assert_lte(amount, yui.heal_power, "单次治疗量不得超过治疗力 %d" % yui.heal_power)
		sum += amount
	assert_eq(rt.total_healing_done - total_before, sum,
		"新增累计治疗量 %d 应恰好等于本轮各次实际治疗之和 %d"
		% [rt.total_healing_done - total_before, sum])
	assert_eq(yui.total_healing_done, rt.total_healing_done,
		"治疗者自身的累计量应与全队一致（唯一治疗来源）")
	assert_lte(mio.hp, mio.max_hp, "治疗后 HP 不得超过最大 HP")
	assert_eq(mio.hp, mio.max_hp, "持续治疗应把雨宫澪补满")
	assert_eq(sum, 300, "本轮治疗的有效总量应恰好等于缺口 300（实际 %d）" % sum)


# ============================================================
#  验收点 9：暂停 / 失败 / 胜利 / 重新挑战 / 退出战斗闭环
# ============================================================

## 验收点 9a：暂停冻结**全部**计时器（移动、AP、攻击、再部署、Wave、逻辑时间）。
func test_pause_freezes_all_timers() -> void:
	# 悠真放在 lane0（与敌人不同路线），因此不会干扰 lane1 的交手，只用于制造再部署冷却
	var spawns: Array = [{"time": 0.0, "lane": 1, "enemy": "echo_normal"}]
	var rt := _runtime(_cfg(spawns, [CHAR_MIO, CHAR_YUMA], AP_MAX, 1.0, 99))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	_deploy_ok(rt, CHAR_YUMA, 0, 0)

	# 推进到敌人被阻挡、双方已交手、攻击冷却正在走
	_step_n(rt, 4.0)
	assert_eq(rt.enemies.size(), 1, "场上应恰好有 1 名敌人")
	var e: EnemyRuntime = rt.enemies[0]
	assert_eq(e.state, BattleTypes.EnemyState.BLOCKED, "敌人应已被阻挡")
	assert_gt(e.hp, 0, "敌人应仍然存活（保证暂停时仍有可观察的移动/攻击状态）")

	# 再撤退悠真，制造一条再部署冷却
	rt.withdraw_character_by_id(CHAR_YUMA)
	assert_gt(rt.get_redeploy_remaining(CHAR_YUMA), 0.0, "悠真应处于再部署冷却")

	var snap := {
		"elapsed": rt.elapsed_seconds,
		"ap": rt.ap,
		"enemyX": e.logical_x,
		"enemyCooldown": e.attack_cooldown,
		"mioHp": mio.hp,
		"mioCooldown": mio.attack_cooldown,
		"redeploy": rt.get_redeploy_remaining(CHAR_YUMA),
		"wave": rt.current_wave_number(),
		"spawned": rt.spawned_enemy_count(),
	}

	rt.set_paused(true)
	_step_n(rt, 10.0)

	assert_almost_eq(rt.elapsed_seconds, float(snap["elapsed"]), 0.0001,
		"暂停应冻结逻辑时间")
	assert_eq(rt.ap, int(snap["ap"]), "暂停应冻结 AP 自然回复")
	assert_almost_eq(e.logical_x, float(snap["enemyX"]), 0.0001,
		"暂停应冻结敌人移动")
	assert_almost_eq(e.attack_cooldown, float(snap["enemyCooldown"]), 0.0001,
		"暂停应冻结敌人攻击冷却")
	assert_eq(mio.hp, int(snap["mioHp"]), "暂停期间不得结算任何伤害")
	assert_almost_eq(mio.attack_cooldown, float(snap["mioCooldown"]), 0.0001,
		"暂停应冻结角色攻击冷却")
	assert_almost_eq(rt.get_redeploy_remaining(CHAR_YUMA), float(snap["redeploy"]), 0.0001,
		"暂停应冻结再部署冷却")
	assert_eq(rt.current_wave_number(), int(snap["wave"]), "暂停应冻结 Wave 计时")
	assert_eq(rt.spawned_enemy_count(), int(snap["spawned"]), "暂停期间不得生成敌人")

	# 恢复后从同一状态继续
	rt.set_paused(false)
	_step_n(rt, 1.0)
	assert_gt(rt.elapsed_seconds, float(snap["elapsed"]),
		"恢复后逻辑时间应继续推进")
	assert_lt(rt.get_redeploy_remaining(CHAR_YUMA), float(snap["redeploy"]),
		"恢复后再部署冷却应继续递减")


## 验收点 9b：核心归零 → 立即失败，且失败后所有计时器与玩家操作都被冻结。
func test_defeat_when_core_reaches_zero() -> void:
	var spawns: Array = [{"time": 0.0, "lane": 1, "enemy": "echo_normal"}]
	var cfg := _cfg(spawns, [CHAR_MIO], AP_MAX, 1.0, 1)
	var s := _session(cfg)

	var guard := 0
	while s.is_running() and guard < 20000:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1

	assert_eq(s.outcome, BattleTypes.Outcome.DEFEAT,
		"核心归零应判失败（核心 %d/%d）" % [s.stage.core_hp, s.stage.core_hp_max])
	assert_eq(s.stage.core_hp, 0, "失败时核心 HP 应为 0")
	assert_eq(s.stage.reached_core_count, 1, "应有 1 次漏怪")
	assert_true(s.is_frozen(), "失败后会话应进入冻结状态")
	assert_false(s.stage.running, "失败后领域层应停表")
	assert_false(s.stage.paused, "胜负确定时应清除暂停位（避免残留暂停状态）")

	# 退出战斗的领域语义：玩家操作与逻辑推进全部被拒
	var elapsed_at := s.stage.elapsed_seconds
	var ap_at := s.stage.ap
	s.tick(StageRuntime.LOGIC_STEP_SECONDS * 600)
	assert_almost_eq(s.stage.elapsed_seconds, elapsed_at, 0.0001,
		"胜负确定后逻辑时间不得再推进")
	assert_eq(s.stage.ap, ap_at, "胜负确定后 AP 不得再变化")

	var d := s.deploy_character(CHAR_MIO, 2, 1)
	assert_false(d.ok, "失败后不得再部署")
	assert_eq(d.reason, StageRuntime.DeployReject.BATTLE_FINISHED,
		"失败后的部署拒绝原因应为「战斗已结束」")
	assert_eq(s.stage.characters.size(), 0, "失败后不得新增角色实体")

	var w := s.withdraw_character_by_id(CHAR_MIO)
	assert_false(w.ok, "失败后不得再撤退")
	assert_eq(w.reason, StageRuntime.RetreatReject.BATTLE_FINISHED,
		"失败后的撤退拒绝原因应为「战斗已结束」")


## 验收点 9c：胜利闭环——全部波次清空后判胜，且胜利后玩家操作被冻结。
func test_victory_closes_the_loop_and_freezes_player_actions() -> void:
	var spawns: Array = [{"time": 0.5, "lane": 1, "enemy": "echo_normal", "wave": 1}]
	var cfg := _cfg(spawns, [CHAR_MIO], AP_MAX, 1.0, 5)
	cfg["waves"] = [{"number": 1}]
	var s := _session(cfg)
	_deploy_ok(s.stage, CHAR_MIO, 2, 1)

	var guard := 0
	while s.is_running() and guard < 20000:
		s.tick(StageRuntime.LOGIC_STEP_SECONDS)
		guard += 1

	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY,
		"全部波次清空后应判胜（击杀 %d，漏怪 %d）"
		% [s.stage.enemies_killed, s.stage.reached_core_count])
	assert_gt(s.stage.enemies_killed, 0, "胜利应来自真实击杀，而不是夹具清场")
	assert_eq(s.stage.reached_core_count, 0, "胜利时不应有漏怪")
	assert_eq(s.stage.core_hp, 5, "胜利时核心应保持 5")
	assert_true(s.stage.all_waves_cleared(), "全部波次应已完成")
	assert_true(s.is_frozen(), "胜利后会话应进入冻结状态")
	assert_false(s.stage.running, "胜利后领域层应停表")

	# 退出战斗：胜利后同样不得再操作或推进
	var elapsed_at := s.stage.elapsed_seconds
	s.tick(StageRuntime.LOGIC_STEP_SECONDS * 600)
	assert_almost_eq(s.stage.elapsed_seconds, elapsed_at, 0.0001,
		"胜负确定后逻辑时间不得再推进")
	assert_false(s.deploy_character(CHAR_MIO, 4, 1).ok, "胜利后不得再部署")
	assert_false(s.withdraw_character_by_id(CHAR_MIO).ok, "胜利后不得再撤退")

	# 结果只提交一次：再次 tick 不得改写 outcome
	assert_eq(s.outcome, BattleTypes.Outcome.VICTORY, "outcome 应保持胜利")


## 验收点 9d（重新挑战）：同一配置两次构建必须得到完全一致的结果（确定性）。
func test_same_config_rebuild_is_deterministic() -> void:
	# 「重新挑战」在领域层的等价语义 = 用同一配置重新构建会话并重放同一战术
	var first := _run_demo(TACTIC_B)
	var second := _run_demo(TACTIC_B)
	var a: BattleSession = first["session"]
	var b: BattleSession = second["session"]

	assert_eq(_result_tuple(a), _result_tuple(b),
		"同一配置两次构建的结果元组必须完全一致（重新挑战不得有随机差异）")
	assert_eq(a.stage.spawned_enemy_count(), b.stage.spawned_enemy_count(),
		"两次运行的生成数应一致")
	assert_eq(a.stage.enemies_killed, b.stage.enemies_killed, "两次运行的击杀数应一致")
	assert_eq(a.stage.reached_core_count, b.stage.reached_core_count, "两次运行的漏怪数应一致")
	assert_eq(a.stage.deploy_success_count, b.stage.deploy_success_count,
		"两次运行的成功部署次数应一致")
	assert_eq(a.stage.retreat_count, b.stage.retreat_count, "两次运行的撤退次数应一致")
	assert_eq(a.stage.total_healing_done, b.stage.total_healing_done,
		"两次运行的累计治疗量应一致")
	assert_eq(a.stage.removals.size(), b.stage.removals.size(),
		"两次运行的离场记录条数应一致")
	assert_eq(a.stage.damage_events.size(), b.stage.damage_events.size(),
		"两次运行的伤害事件条数应一致")
	assert_almost_eq(a.stage.elapsed_seconds, b.stage.elapsed_seconds, EPS,
		"两次运行的逻辑用时应一致")

	# 两次运行都确实是完整的一局，而不是双双空转
	assert_eq(a.outcome, BattleTypes.Outcome.VICTORY, "第一次运行应为胜利")
	assert_eq(a.stage.spawned_enemy_count(), DEMO_TIMELINE_SIZE,
		"第一次运行应生成全部 %d 名敌人" % DEMO_TIMELINE_SIZE)


# ============================================================
#  验收点 10：固定逻辑步长、帧率和分辨率独立性
# ============================================================

## 验收点 10：同一战术在 1/60、1/30、1/144 的 tick 粒度下结果完全一致。
func test_result_independent_of_tick_granularity() -> void:
	var ticks: Array[float] = [1.0 / 60.0, 1.0 / 30.0, 1.0 / 144.0]
	var results: Array = []
	for tick: float in ticks:
		var res := _run_demo(TACTIC_B, tick)
		assert_eq((res["rejects"] as Array).size(), 0,
			"tick=%.5f 时战术动作都应被接受：%s" % [tick, str(res["rejects"])])
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
	assert_eq(int((results[0] as Dictionary)["kills"]), DEMO_TIMELINE_SIZE,
		"60fps 粒度下应击杀全部 %d 名敌人" % DEMO_TIMELINE_SIZE)
	assert_eq(int((results[0] as Dictionary)["outcome"]), BattleTypes.Outcome.VICTORY,
		"60fps 粒度下应为胜利")


## 验收点 10（补充）：不同参考分辨率不改变演示关的战斗结果。
##
## 渲染分辨率只影响 tile→px 换算（V2.1.4 LOCKED 度量规则），不得改变任何战斗判定。
func test_result_independent_of_render_resolution() -> void:
	var cfg := _demo_config()
	var results: Array = []
	for size: Array in [[1280, 720], [1920, 1080], [3840, 2160]]:
		var g := BattleGrid.from_layout(DataRegistry.get_layout())
		# 仅改变「参考画布」（模拟不同分辨率下的渲染换算），逻辑参数不变
		g.reference_canvas_width = int(size[0])
		g.reference_canvas_height = int(size[1])
		var rt := StageRuntime.from_config(
			cfg, _enemy_table(), g, _char_table(), _combat())
		assert_true(rt.is_valid(), "%s 分辨率下应无构建错误：%s" % [str(size), str(rt.get_errors())])
		results.append(_run_tactic_with(rt, TACTIC_B))

	assert_eq(results[0], results[1], "720p 与 1080p 的演示关结果必须一致")
	assert_eq(results[1], results[2], "1080p 与 4K 的演示关结果必须一致")
	# 保证比较的是真实战果，而不是三方都在空转
	assert_eq(int((results[0] as Dictionary)["kills"]), DEMO_TIMELINE_SIZE,
		"各分辨率下都应击杀全部 %d 名敌人" % DEMO_TIMELINE_SIZE)

	# 像素换算确实随画布变化（证明逻辑与渲染确已分离）
	var g1 := BattleGrid.from_layout(DataRegistry.get_layout())
	var g2 := BattleGrid.from_layout(DataRegistry.get_layout())
	g2.reference_canvas_width = 3840
	g2.reference_canvas_height = 2160
	assert_ne(g1.centered_board_origin(1920, 1080), g2.centered_board_origin(3840, 2160),
		"像素原点应随画布变化（逻辑/渲染确已分离）")


# ============================================================
#  验收点 11：所有正式数据的角色、敌人、关卡引用均有效
# ============================================================

## 验收点 11：1-1～1-10 与 p1_0_demo 的敌人/角色引用全部可解析，且加载期无错误。
##
## 注意：1-2～1-10 目前是 Phase 0 **占位关卡**（enemySpawnTimeline 与 availableCharacters
## 均为空数组，见各文件的 "_phase0" 字段），因此本用例断言的是
## 「**凡存在的引用都必须可解析**」，而不是「每关都必须有内容」——
## 后者属于关卡内容填充进度，不是 P1.0 的数据完整性要求。
func test_all_stage_references_resolve() -> void:
	var enemies := _enemy_table()
	var characters := _char_table()
	assert_gt(enemies.size(), 0, "enemies.json 应有敌人")
	assert_gt(characters.size(), 0, "characters.json 应有角色")

	var checked_stages := 0
	var checked_enemy_refs := 0
	var checked_char_refs := 0
	var authored_stages: Array[String] = []

	# 正式第一章 1-1～1-10
	for i: int in range(1, 11):
		var sid := "1-%d" % i
		var cfg := DataRegistry.get_entry("stages", sid)
		assert_false(cfg.is_empty(), "应能取到正式关卡 %s" % sid)
		if cfg.is_empty():
			continue
		checked_stages += 1
		var refs := _assert_stage_refs(cfg, sid, enemies, characters)
		checked_enemy_refs += refs["enemies"]
		checked_char_refs += refs["characters"]
		if int(refs["enemies"]) > 0 and int(refs["characters"]) > 0:
			authored_stages.append(sid)

	# Prototype 演示关
	var demo := _demo_config()
	assert_false(demo.is_empty(), "应能取到 Prototype 演示关 %s" % DEMO_STAGE_ID)
	if not demo.is_empty():
		checked_stages += 1
		var refs := _assert_stage_refs(demo, DEMO_STAGE_ID, enemies, characters)
		checked_enemy_refs += refs["enemies"]
		checked_char_refs += refs["characters"]
		if int(refs["enemies"]) > 0 and int(refs["characters"]) > 0:
			authored_stages.append(DEMO_STAGE_ID)

	# 保证本用例确实遍历到了内容（不是空转通过）
	assert_eq(checked_stages, 11, "应检查 1-1～1-10 与演示关共 11 张关卡")
	assert_gt(checked_enemy_refs, 0, "应至少检查到 1 个敌人引用")
	assert_gt(checked_char_refs, 0, "应至少检查到 1 个角色引用")

	# 已填充内容的关卡：正式 1-1 + Prototype 演示关（两者都必须引用可解析）
	assert_true(authored_stages.has("1-1"), "正式 1-1 应是已填充内容的关卡")
	assert_true(authored_stages.has(DEMO_STAGE_ID),
		"Prototype 演示关应是已填充内容的关卡")
	# 演示关的引用必须**全部**可解析（P1.0 交付物）
	assert_eq(checked_enemy_refs >= DEMO_TIMELINE_SIZE, true,
		"检查到的敌人引用数应至少覆盖演示关的 %d 条" % DEMO_TIMELINE_SIZE)

	# 数据加载期不得有任何错误（含引用完整性校验）
	var load_errors := DataRegistry.get_load_errors()
	assert_eq(load_errors.size(), 0, "数据加载不应有任何错误：%s" % str(load_errors))


## 校验一张关卡配置里的敌人/角色引用。
## 返回 {"enemies": 检查到的敌人引用数, "characters": 检查到的角色引用数}。
## 空数组是合法的（Phase 0 占位关卡），但**凡存在的引用都必须可解析**。
func _assert_stage_refs(
	cfg: Dictionary, label: String, enemies: Dictionary, characters: Dictionary
) -> Dictionary:
	var enemy_refs := 0
	var char_refs := 0

	var timeline: Array = cfg.get("enemySpawnTimeline", [])
	for entry: Dictionary in timeline:
		var enemy_id := str(entry.get("enemy", ""))
		assert_true(enemies.has(enemy_id),
			"%s 的 enemySpawnTimeline 引用了不存在的敌人 '%s'" % [label, enemy_id])
		var lane := int(entry.get("lane", -1))
		assert_true(BattleTypes.is_valid_lane(lane),
			"%s 的出怪 lane %d 应在 0～%d" % [label, lane, BattleTypes.LANE_COUNT - 1])
		assert_gte(float(entry.get("time", -1.0)), 0.0,
			"%s 的出怪时间不得为负" % label)
		enemy_refs += 1

	var avail: Array = cfg.get("availableCharacters", [])
	for cid: Variant in avail:
		assert_true(characters.has(str(cid)),
			"%s 的 availableCharacters 引用了不存在的角色 '%s'" % [label, str(cid)])
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


# ============================================================
#  验收点 12：演示关规格一致性
# ============================================================

## 验收点 12：演示关的核心/AP/角色/出怪/波次全部符合 P1.0 规格。
func test_demo_stage_spec_consistency() -> void:
	var cfg := _demo_config()
	assert_false(cfg.is_empty(), "应能取到 Prototype 演示关")
	if cfg.is_empty():
		return

	assert_eq(str(cfg.get("stageId", "")), DEMO_STAGE_ID, "stageId 应为 %s" % DEMO_STAGE_ID)
	assert_eq(int(cfg.get("coreHp", 0)), 5, "演示关核心生命应为 5")
	assert_eq(int(cfg.get("startingAp", 0)), 10, "演示关开局 AP 应为 10")
	assert_eq(float(cfg.get("apRegen", 0.0)), 1.0, "演示关 AP 自然回复应为 1/秒")

	# 可部署角色恰好三人，且与三职业 Prototype 编队一致
	var avail: Array = cfg.get("availableCharacters", [])
	assert_eq(avail.size(), 3, "演示关应恰好解锁 3 名角色（实际 %d）" % avail.size())
	var avail_set := {}
	for cid: Variant in avail:
		avail_set[str(cid)] = true
	for cid: String in TRIPLE:
		assert_true(avail_set.has(cid), "演示关应解锁 %s" % cid)

	# 出怪时间线：20 条、wave 落在 1..6、时间非负且 lane 合法
	var timeline: Array = cfg.get("enemySpawnTimeline", [])
	assert_eq(timeline.size(), DEMO_TIMELINE_SIZE,
		"演示关应有 %d 条出怪计划（实际 %d）" % [DEMO_TIMELINE_SIZE, timeline.size()])
	var composition := {}
	for entry: Dictionary in timeline:
		var wave_no := int(entry.get("wave", 0))
		assert_gte(wave_no, 1, "出怪条目的 wave 应 ≥ 1（实际 %d）" % wave_no)
		assert_lte(wave_no, DEMO_WAVE_COUNT,
			"出怪条目的 wave 应 ≤ %d（实际 %d）" % [DEMO_WAVE_COUNT, wave_no])
		var enemy_id := str(entry.get("enemy", ""))
		composition[enemy_id] = int(composition.get(enemy_id, 0)) + 1

	# 敌人构成与规格一致
	for enemy_id: String in DEMO_COMPOSITION.keys():
		assert_eq(int(composition.get(enemy_id, 0)), int(DEMO_COMPOSITION[enemy_id]),
			"演示关应有 %s × %d" % [enemy_id, int(DEMO_COMPOSITION[enemy_id])])

	# 波次元数据：6 波，编号 1..6，全部 ALL_ENEMIES_DEFEATED
	var waves: Array = cfg.get("waves", [])
	assert_eq(waves.size(), DEMO_WAVE_COUNT, "演示关应有 %d 波" % DEMO_WAVE_COUNT)
	for i: int in range(waves.size()):
		var w: Dictionary = waves[i]
		assert_eq(int(w.get("number", 0)), i + 1, "第 %d 波的编号应为 %d" % [i + 1, i + 1])
		assert_eq(str(w.get("clearCondition", "")), "ALL_ENEMIES_DEFEATED",
			"第 %d 波的完成条件应为 ALL_ENEMIES_DEFEATED" % (i + 1))

	# 总敌人数落在 V2.1.4 D-30 表 33 的建议区间 18～24 内
	assert_gte(timeline.size(), D30_MIN_ENEMIES,
		"总敌人数 %d 应不少于 D-30 建议下限 %d" % [timeline.size(), D30_MIN_ENEMIES])
	assert_lte(timeline.size(), D30_MAX_ENEMIES,
		"总敌人数 %d 应不超过 D-30 建议上限 %d" % [timeline.size(), D30_MAX_ENEMIES])

	# 运行时应能正常构建（规格自洽）
	var rt := _runtime(cfg)
	assert_true(rt.is_valid(), "演示关应无构建错误：%s" % str(rt.get_errors()))
	assert_eq(rt.core_hp_max, 5, "运行时核心上限应为 5")
	assert_eq(rt.ap, 10, "运行时开局 AP 应为 10")
	assert_eq(rt.ap_max, AP_MAX, "AP 上限应来自 balance.combat.maxAp = 30")
	assert_eq(rt.planned_enemy_count(), DEMO_TIMELINE_SIZE, "计划出怪数应与时间线一致")
	assert_eq(rt.total_wave_count(), DEMO_WAVE_COUNT, "运行时波次总数应为 6")


# ============================================================
#  验收点 13：正式主线解锁顺序未被污染（回归）
# ============================================================

## 验收点 13：1-1 仍只解锁雨宫澪、stages 索引仍为 10 条、prototype 索引独立且不重名。
func test_canonical_progression_is_not_polluted() -> void:
	# 1-1 的解锁角色不得被 Prototype 演示关污染
	var cfg_1_1 := _stage_config()
	assert_eq(cfg_1_1["availableCharacters"], [CHAR_MIO],
		"正式 1-1 的 availableCharacters 应仍然只有 amamiya_mio")

	var rt := _runtime(cfg_1_1)
	assert_true(rt.is_valid(), "正式 1-1 应无构建错误：%s" % str(rt.get_errors()))
	assert_eq(rt.available_characters.size(), 1, "正式 1-1 应只有 1 名可部署角色")
	assert_false(rt.available_characters.has(CHAR_YUMA), "正式 1-1 不得解锁神谷悠真")
	assert_false(rt.available_characters.has(CHAR_YUI), "正式 1-1 不得解锁小川结衣")

	# 章节解锁顺序不得为测试方便而改动
	var chars := _char_table()
	assert_eq(str((chars[CHAR_MIO] as Dictionary).get("unlockStage", "")), "1-1",
		"雨宫澪应在 1-1 解锁")
	assert_eq(str((chars[CHAR_YUMA] as Dictionary).get("unlockStage", "")), "1-3",
		"神谷悠真应在 1-3 解锁")
	assert_eq(str((chars[CHAR_YUI] as Dictionary).get("unlockStage", "")), "1-6",
		"小川结衣应在 1-6 解锁")

	# canonical 关卡索引仍恰好 10 条（1-1～1-10）
	var stage_ids := DataRegistry.get_ids("stages")
	assert_eq(stage_ids.size(), 10, "stages 索引应恰好 10 条（实际 %d）" % stage_ids.size())
	for i: int in range(1, 11):
		assert_true(stage_ids.has("1-%d" % i), "stages 索引应含 1-%d" % i)

	# prototype 索引独立：恰好 1 条，且 stageId 不与 ch1 重名
	var proto_ids := DataRegistry.get_prototype_stage_ids()
	assert_eq(proto_ids.size(), 1, "prototype_stages 索引应恰好 1 条（实际 %d）" % proto_ids.size())
	assert_true(proto_ids.has(DEMO_STAGE_ID), "prototype 索引应含 %s" % DEMO_STAGE_ID)
	for sid: Variant in proto_ids:
		assert_false(stage_ids.has(str(sid)),
			"Prototype 关卡 '%s' 不得与 ch1 正式关卡重名" % str(sid))
	assert_false(stage_ids.has(DEMO_STAGE_ID),
		"演示关不得进入 canonical 的 stages 索引")

	# 演示关不得出现在 canonical 的 10 关里，也不得复用正式关卡的 stageId
	var demo := _demo_config()
	assert_eq(str(demo.get("stageId", "")), DEMO_STAGE_ID, "演示关 stageId 应自洽")
	assert_ne(str(demo.get("stageId", "")), str(cfg_1_1.get("stageId", "")),
		"演示关不得复用正式 1-1 的 stageId")


# ============================================================
#  验收点 14：伤害事件是表现层的正确数据源
# ============================================================

## 验收点 14：damage_events 只含实际扣减、字段合法、长度被限制在 200 以内。
func test_damage_events_are_valid_and_bounded() -> void:
	# ---- 小场景：字段与「只记录实际扣减」语义 ----
	var rt := _runtime(_cfg([], [CHAR_MIO], AP_MAX, 0.0, 99))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	_place_enemy(rt, 1, 3.5, "echo_normal")
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_gt(rt.damage_events.size(), 0, "交手后应产生伤害事件")
	var kinds := {}
	for ev: Dictionary in rt.damage_events:
		_assert_damage_event_shape(ev)
		kinds[str(ev["targetKind"])] = true
	assert_true(kinds.has("enemy"), "应记录角色对敌人造成的伤害（targetKind=enemy）")
	assert_true(kinds.has("character"), "应记录敌人对角色造成的伤害（targetKind=character）")
	assert_eq(mio.hp, mio.max_hp - 36, "该逻辑步内敌人应已对澪造成 36 伤害（保证确有交手）")

	# 被完全挡下的伤害（amount ≤ 0）不得入账：对已死目标追加伤害不产生事件
	var before_size := rt.damage_events.size()
	var dead := _place_enemy(rt, 1, 3.5, "echo_runner")
	dead.take_damage(dead.hp_max)
	assert_eq(dead.take_damage(999), 0, "对已死目标造成伤害应返回 0")
	assert_eq(rt.damage_events.size(), before_size,
		"未实际扣减 HP 的伤害不得进入伤害事件")

	# ---- 长局：长度必须被环形裁剪限制在 200 以内 ----
	var res := _run_demo()
	var stage := (res["session"] as BattleSession).stage
	var events := stage.damage_events
	assert_eq(StageRuntime.DAMAGE_EVENT_RETENTION, 200, "伤害事件保留上限应为 200")
	assert_gt(events.size(), 0, "长局应产生伤害事件")
	assert_lte(events.size(), StageRuntime.DAMAGE_EVENT_RETENTION,
		"长局后伤害事件数 %d 不得超过上限 %d"
		% [events.size(), StageRuntime.DAMAGE_EVENT_RETENTION])

	# 裁剪后剩下的每一条仍然合法，且时间戳保持有序（表现层按顺序消费）
	var prev_at := -1.0
	for ev: Dictionary in events:
		_assert_damage_event_shape(ev)
		var at := float(ev["at"])
		assert_gte(at, prev_at - EPS, "伤害事件的时间戳应单调不减（裁剪不得打乱顺序）")
		prev_at = at


## 验收点 14（补充）：在伤害量确实超过 200 笔的长局中，环形裁剪必须**真的生效**。
##
## 演示关一局的伤害事件约 176 笔，尚未触及上限，因此本用例用一张更密集的
## 长局夹具（30 名敌人、10 秒间隔、单线持续交手）把总量推到 200 笔以上，
## 以证明「长度被限制在 200 以内」不是一句空转的断言。
func test_damage_events_cap_engages_in_long_battle() -> void:
	var spawns: Array = []
	for i: int in range(30):
		spawns.append({"time": float(i) * 10.0, "lane": 1, "enemy": "echo_normal"})
	# 前线阻挡 + 治疗续航：保证整局持续交手（核心 HP 充足，即使漏怪也不判负）
	var rt := _runtime(_cfg(spawns, [CHAR_MIO, CHAR_YUI], AP_MAX, 1.0, 99))
	var mio := _deploy_ok(rt, CHAR_MIO, 3, 1)
	_deploy_ok(rt, CHAR_YUI, 2, 1)

	# 跑满整条时间线（末次出怪 290s）+ 收尾
	_advance_until(rt, 340.0, StageRuntime.LOGIC_STEP_SECONDS)

	# 整局确实发生了大量交手（否则下面的裁剪断言没有意义）
	assert_gt(rt.enemies_killed, 0, "长局应产生真实击杀")
	assert_true(mio.hp > 0, "前线应存活（治疗续航成立）")

	# 总量必然超过 200 笔（每名敌人约 5 次被击 + 4 次反击），裁剪因此必须已生效
	assert_eq(rt.damage_events.size(), StageRuntime.DAMAGE_EVENT_RETENTION,
		"伤害量超过上限的长局中，事件数应被精确裁剪到 %d（实际 %d）"
		% [StageRuntime.DAMAGE_EVENT_RETENTION, rt.damage_events.size()])
	for ev: Dictionary in rt.damage_events:
		_assert_damage_event_shape(ev)


## 断言单条伤害事件的字段完整且取值合法。
func _assert_damage_event_shape(ev: Dictionary) -> void:
	for key: String in ["targetKind", "targetId", "amount", "at", "lethal"]:
		assert_true(ev.has(key), "伤害事件应含字段 %s" % key)
	var kind := str(ev.get("targetKind", ""))
	assert_true(kind == "enemy" or kind == "character",
		"targetKind 必须是 enemy 或 character，实际 '%s'" % kind)
	assert_gt(int(ev.get("amount", 0)), 0,
		"伤害事件只应记录实际扣减（amount > 0），实际 %d" % int(ev.get("amount", 0)))
	assert_gte(int(ev.get("targetId", 0)), 1, "targetId 应为正实例 id")
	assert_gte(float(ev.get("at", -1.0)), 0.0, "at 应为非负逻辑时间")
	assert_typeof(ev.get("lethal"), TYPE_BOOL, "lethal 应为布尔值")
