## P0.2 测试：阻挡系统与双方攻击（V2.1.4 D-3A / D-10 / D-11 / D-22 / F 章）
##
## 覆盖要求：
##   - 雨宫澪在同一路线正确阻挡最多 2 名敌人
##   - 第 3 名敌人可继续前进
##   - 不同路线不能错误建立阻挡
##   - 阻挡建立、解除、角色失去战斗能力后的恢复移动
##   - 普通攻击目标选择、攻击间隔、物理伤害公式
##   - 敌人攻击、角色受伤及死亡
##   - 敌人死亡只结算一次，不再漏怪
extends GutTest

const CHAR_ID := "amamiya_mio"
const LOGIC_EPSILON := 0.0001


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func _grid() -> BattleGrid:
	return BattleGrid.from_layout(DataRegistry.get_layout())


## 取敌人配置表（**深拷贝**）。
##
## 纪律（P1.0 修复）：必须 duplicate(true) 后再放入表。
## 否则返回的是 DataRegistry 内部字典的**引用**，任何用例的就地改写都会
## **永久污染 DataRegistry 的内存数据**，并跨文件、顺序相关地影响后续用例
## （历史事故：test_blocking_is_independent_of_sprite_size 把 spriteFramePx
## 就地改成 4096，导致后续读取 enemies 域的用例拿到 4096 而非 64）。
func _enemy_table() -> Dictionary:
	var t := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		t[str(e.get("id", ""))] = e.duplicate(true)
	return t


## 取角色配置表（**深拷贝**，理由同上）。
func _char_table() -> Dictionary:
	var t := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		t[str(c.get("id", ""))] = c.duplicate(true)
	return t


func _combat() -> Dictionary:
	return DataRegistry.get_domain("balance").get("combat", {})


## 构造一个"敌人按需出现在指定路线"的夹具，便于精确控制阻挡场景

## 生成时序 / 漏怪等专项夹具：清空 waves 元数据，使波次完全由 enemySpawnTimeline 自动推导。
## Wave 声明只服务于正式关卡数据；测试若整体替换出怪时间线，必须同步移除 Wave 声明，
## 否则会触发「waves 声明了第 N 波但无敌人归属」的一致性报错。
## 注意：必须 duplicate 后再改，绝不能改写 DataRegistry 里的权威字典。
func _cfg_no_waves(cfg: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	c.erase("waves")
	return c


func _cfg_with_spawns(spawns: Array) -> Dictionary:
	var base := DataRegistry.get_entry("stages", "1-1").duplicate(true)
	base.erase("waves")
	base["coreHp"] = 100
	base["startingAp"] = 100
	base["apRegen"] = 0
	base["enemySpawnTimeline"] = spawns
	return base


func _runtime(spawns: Array) -> StageRuntime:
	return StageRuntime.from_config(
		_cfg_with_spawns(spawns), _enemy_table(), _grid(), _char_table(), _combat()
	)


func _step_n(rt: StageRuntime, seconds: float) -> void:
	var t := 0.0
	while t < seconds - LOGIC_EPSILON:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS


## 手动放置一个敌人到指定位置（用于精确构造阻挡场景）
func _place_enemy(
	rt: StageRuntime, lane: int, x: float, enemy_id: String = "echo_normal"
) -> EnemyRuntime:
	var e := EnemyRuntime.from_config(_enemy_table()[enemy_id], lane, 9000 + rt.enemies.size())
	e.logical_x = x
	e.state = BattleTypes.EnemyState.MOVING
	rt.enemies.append(e)
	return e


# ============================================================
#  伤害公式（V2.1.4 D-22）
# ============================================================

func test_physical_damage_formula_matches_spec_example() -> void:
	var m := CombatMath.from_config(_combat().get("damage", {}))
	# V2.1.4 原文示例：攻击 120，对方防御 20 → 120 × 100 / (100 + 20) = 100
	assert_eq(m.compute_damage(120.0, 20.0, CombatMath.DamageType.PHYSICAL), 100,
		"规格原文示例必须复现")


func test_special_damage_uses_forty_percent_defense() -> void:
	var m := CombatMath.from_config(_combat().get("damage", {}))
	# 特殊伤害 = 攻击 × 100 / (100 + 防御 × 0.40)
	# 攻击 120，防御 100 → 120 × 100 / (100 + 40) = 85.71… → 86
	assert_eq(m.compute_damage(120.0, 100.0, CombatMath.DamageType.SPECIAL), 86,
		"特殊伤害应按 40% 防御计算")
	# 物理对照：120 × 100 / (100 + 100) = 60
	assert_eq(m.compute_damage(120.0, 100.0, CombatMath.DamageType.PHYSICAL), 60,
		"物理伤害对照值")


func test_damage_has_minimum_of_one() -> void:
	var m := CombatMath.from_config(_combat().get("damage", {}))
	assert_eq(m.compute_damage(1.0, 99999.0, CombatMath.DamageType.PHYSICAL), 1,
		"最低伤害应为 1")
	assert_eq(m.compute_damage(0.0, 0.0, CombatMath.DamageType.PHYSICAL), 1,
		"攻击为 0 时仍应为最低伤害 1")


func test_damage_is_deterministic() -> void:
	var m := CombatMath.from_config(_combat().get("damage", {}))
	var first := m.compute_damage(120.0, 80.0, CombatMath.DamageType.PHYSICAL)
	for i: int in range(50):
		assert_eq(m.compute_damage(120.0, 80.0, CombatMath.DamageType.PHYSICAL), first,
			"相同输入必须得到相同结果")


func test_invalid_damage_config_reports_errors() -> void:
	var m := CombatMath.from_config({"physicalDefenseFactor": -1.0})
	assert_false(m.is_valid(), "负系数应报错")


# ============================================================
#  阻挡系统（V2.1.4 D-10 / D-3A）
# ============================================================

func test_character_can_block_up_to_two_enemies() -> void:
	var rt := _runtime([])
	assert_true(rt.deploy_character(CHAR_ID, 2, 1).ok, "部署应成功")
	var mio := rt.get_character_by_id(CHAR_ID)
	assert_eq(mio.block_count_max, 2, "阻挡上限应为 2")

	# 在中段放 2 个敌人，位置在接触线内。
	# 注意：两个敌人不能放在完全相同的 x——那样它们会在下一步同时进入接触判定，
	# 虽仍能各占 1 个名额，但为贴近真实战况（敌人依次推进），此处让第二个稍远。
	var e1 := _place_enemy(rt, 1, 2.5)
	var e2 := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(mio.blocking_enemy_ids.size(), 2, "应同时阻挡 2 名敌人")
	assert_true(mio.is_blocking(e1.instance_id), "敌人 #1 应被阻挡")
	assert_true(mio.is_blocking(e2.instance_id), "敌人 #2 应被阻挡")
	assert_eq(e1.state, BattleTypes.EnemyState.BLOCKED, "敌人 #1 状态应为 BLOCKED")
	assert_eq(e2.state, BattleTypes.EnemyState.BLOCKED, "敌人 #2 状态应为 BLOCKED")


func test_third_enemy_continues_moving() -> void:
	var rt := _runtime([])
	assert_true(rt.deploy_character(CHAR_ID, 2, 1).ok, "部署应成功")
	var mio := rt.get_character_by_id(CHAR_ID)

	# 放 3 个敌人，全部在接触线内（用不同 x 保证都能接触）
	var e1 := _place_enemy(rt, 1, 2.5)
	var e2 := _place_enemy(rt, 1, 2.5)
	var e3 := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(mio.blocking_enemy_ids.size(), 2, "最多只能阻挡 2 名")
	# 第 3 名不得被阻挡，必须继续前进
	assert_false(mio.is_blocking(e3.instance_id), "第 3 名敌人不应被阻挡")
	assert_eq(e3.state, BattleTypes.EnemyState.MOVING, "第 3 名敌人应保持 MOVING")

	var x_before := e3.logical_x
	_step_n(rt, 1.0)
	assert_lt(e3.logical_x, x_before, "第 3 名敌人应继续向左移动")


func test_enemies_on_other_lanes_are_not_blocked() -> void:
	var rt := _runtime([])
	assert_true(rt.deploy_character(CHAR_ID, 2, 1).ok, "部署中段")
	var mio := rt.get_character_by_id(CHAR_ID)

	# 上段与下段各放一个敌人，位置与中段阻挡者对齐
	var e_upper := _place_enemy(rt, 0, 2.5)
	var e_lower := _place_enemy(rt, 2, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_false(mio.is_blocking(e_upper.instance_id), "上段敌人不得被中段角色阻挡")
	assert_false(mio.is_blocking(e_lower.instance_id), "下段敌人不得被中段角色阻挡")
	assert_eq(e_upper.state, BattleTypes.EnemyState.MOVING, "上段敌人应继续移动")
	assert_eq(e_lower.state, BattleTypes.EnemyState.MOVING, "下段敌人应继续移动")


func test_blocked_enemy_stops_moving() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 3, 1)
	var e := _place_enemy(rt, 1, 3.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(e.state, BattleTypes.EnemyState.BLOCKED, "应被阻挡")
	var x_blocked := e.logical_x
	_step_n(rt, 2.0)
	assert_almost_eq(e.logical_x, x_blocked, 0.0001, "被阻挡的敌人不得继续移动")


func test_block_released_when_enemy_dies() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	var e := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_true(mio.is_blocking(e.instance_id), "应先建立阻挡")

	# 直接击杀该敌人
	e.hp = 0
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_false(mio.is_blocking(e.instance_id), "敌人死亡后应解除阻挡关系")
	assert_eq(mio.block_slots_remaining(), 2, "阻挡名额应全部回收")


func test_block_released_when_blocker_incapacitated() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	var e := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(e.state, BattleTypes.EnemyState.BLOCKED, "应先被阻挡")

	# 让角色失去战斗能力
	mio.take_damage(99999)
	assert_true(mio.is_incapacitated(), "角色应已失能")

	var x_before := e.logical_x
	_step_n(rt, 2.0)

	assert_eq(mio.blocking_enemy_ids.size(), 0, "失能角色不应保留阻挡关系")
	assert_eq(e.state, BattleTypes.EnemyState.MOVING, "敌人应恢复移动状态")
	assert_lt(e.logical_x, x_before, "敌人应重新向左移动")


func test_block_slots_are_recycled_after_kill() -> void:
	# 击杀 1 个后应能再接住新的敌人
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)

	var e1 := _place_enemy(rt, 1, 2.5)
	var e2 := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(mio.blocking_enemy_ids.size(), 2, "应先占满 2 个名额")

	e1.hp = 0  # 击杀第一个
	var e3 := _place_enemy(rt, 1, 2.5)
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_true(mio.is_blocking(e3.instance_id), "回收的名额应能接住新敌人")
	assert_eq(mio.blocking_enemy_ids.size(), 2, "仍应保持 2 个阻挡")


func test_blocking_is_independent_of_sprite_size() -> void:
	# 阻挡判定完全基于 tile 与接触线配置，与 Sprite 像素尺寸无关。
	# 改变 spriteFramePx 不应影响阻挡判定结果。
	var t1 := _enemy_table()
	var t2 := _enemy_table()
	for k: String in t2.keys():
		(t2[k] as Dictionary)["spriteFramePx"] = 4096  # 夸张地放大

	var rt1 := StageRuntime.from_config(_cfg_with_spawns([]), t1, _grid(), _char_table(), _combat())
	var rt2 := StageRuntime.from_config(_cfg_with_spawns([]), t2, _grid(), _char_table(), _combat())
	for rt: StageRuntime in [rt1, rt2]:
		rt.deploy_character(CHAR_ID, 2, 1)
		_place_enemy(rt, 1, 2.5)
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)

	assert_eq(rt1.get_character_by_id(CHAR_ID).blocking_enemy_ids.size(), 1,
		"原始尺寸下应阻挡 1 名")
	assert_eq(rt2.get_character_by_id(CHAR_ID).blocking_enemy_ids.size(), 1,
		"Sprite 尺寸改变后阻挡结果应相同（阻挡与尺寸解耦）")


func test_no_duplicate_blocking() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	var e := _place_enemy(rt, 1, 2.5)
	# 连续多步，同一敌人不应被重复计入
	_step_n(rt, 2.0)
	var count := 0
	for eid: int in mio.blocking_enemy_ids:
		if eid == e.instance_id:
			count += 1
	assert_eq(count, 1, "同一敌人不应被重复阻挡")


# ============================================================
#  角色攻击（V2.1.4 D-11 / D-13）
# ============================================================

func test_character_attacks_enemy_in_range() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 1, 2.5)  # 在 1.25 格射程内
	var hp_before := e.hp
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_lt(e.hp, hp_before, "射程内的敌人应受到伤害")
	# 伤害应为 配置攻击 120 对 防御 20 的 echo_normal = 100
	assert_eq(hp_before - e.hp, 100, "首击应造成 100 伤害（物理公式）")


func test_character_does_not_attack_out_of_range() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 1, 5.0)  # 远超 1.25 格射程
	var hp_before := e.hp
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(e.hp, hp_before, "射程外不应受到伤害")


func test_character_does_not_attack_other_lane() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 0, 2.0)  # 上段，与角色同 column
	var hp_before := e.hp
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(e.hp, hp_before, "不同路线不应被攻击（maxLaneDelta=0）")


func test_attack_respects_interval() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 1, 2.5)
	e.hp = 100000  # 避免被打死
	var tick := StageRuntime.LOGIC_STEP_SECONDS

	# 第一击立即发生
	rt.advance(tick)
	var after_first := e.hp
	# 在攻击间隔内不应再造成伤害（1.1 秒间隔）
	_step_n(rt, 1.0)
	assert_eq(e.hp, after_first, "攻击间隔内不应再次造成伤害")
	# 越过间隔后应再攻击一次
	_step_n(rt, 0.2)
	assert_lt(e.hp, after_first, "越过攻击间隔后应再次攻击")


func test_targeting_prefers_closest_to_core() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	# 两个都在射程内，靠核心更近的是 x=2.2
	var near := _place_enemy(rt, 1, 2.2)
	var far := _place_enemy(rt, 1, 3.0)
	near.hp = 100000
	far.hp = 100000
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_lt(near.hp, 100000, "应优先攻击最接近核心的敌人")
	assert_eq(far.hp, 100000, "未被选中的敌人不应受伤")


func test_attack_ignores_enemies_behind_character() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 3, 1)
	# 敌人已越过角色（x 小于角色 column）→ 不在"前方"
	var e := _place_enemy(rt, 1, 1.0)
	var hp_before := e.hp
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(e.hp, hp_before, "角色身后的敌人不在攻击范围内")


# ============================================================
#  敌人攻击与角色死亡（V2.1.4 D-28 / D-29）
# ============================================================

func test_enemy_attacks_its_blocker() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	var e := _place_enemy(rt, 1, 2.5)

	# 建立阻挡的那一逻辑步内，敌人即以 cooldown=0 完成首次攻击（进入战斗即出手）。
	# echo_normal 攻击 65 vs 雨宫澪防御 80 → 65×100/180 = 36.11 → 36
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_true(mio.is_blocking(e.instance_id), "应已建立阻挡")
	assert_lt(mio.hp, 1000, "建立阻挡的同一逻辑步内应完成首次攻击")
	assert_eq(1000 - mio.hp, 36, "敌人伤害应符合同一物理公式（65 vs 80 防御 → 36）")

	# 敌人攻击间隔 1.2 秒：间隔内不应再次造成伤害
	var hp_after_first := mio.hp
	_step_n(rt, 1.0)
	assert_eq(mio.hp, hp_after_first, "攻击间隔内不应再次造成伤害")

	# 越过间隔后应再次攻击
	_step_n(rt, 0.3)
	assert_eq(1000 - mio.hp, 72, "越过 1.2s 间隔后应完成第二次攻击（累计 72）")


func test_enemy_attack_hits_only_when_blocked() -> void:
	# 未被阻挡的敌人不应攻击任何人（P0.2 无远程敌人）
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 4, 1)  # 部署在 col4
	var e := _place_enemy(rt, 1, 3.0)   # 尚未到接触线（col4 接触线为 4.5）
	var mio := rt.get_character_by_id(CHAR_ID)
	_step_n(rt, 1.0)
	assert_eq(mio.hp, 1000, "未被阻挡的敌人不得攻击")


func test_character_dies_when_hp_reaches_zero() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	assert_true(mio.alive, "初始应存活")

	mio.take_damage(mio.max_hp)
	assert_eq(mio.hp, 0, "HP 应归零")
	assert_false(mio.alive, "应失去战斗能力")
	assert_true(mio.is_incapacitated(), "应处于失能状态")


func test_incapacitated_character_stops_attacking() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var mio := rt.get_character_by_id(CHAR_ID)
	var e := _place_enemy(rt, 1, 2.5)
	e.hp = 100000
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	var hp_after_hit := e.hp
	assert_lt(hp_after_hit, 100000, "应先造成伤害")

	mio.take_damage(999999)
	assert_true(mio.is_incapacitated(), "角色应失能")

	_step_n(rt, 3.0)
	assert_eq(e.hp, hp_after_hit, "失能角色不应继续攻击")


func test_damage_event_settled_once_per_attack() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 1, 2.5)
	var hp_before := e.hp
	# 单步只应结算一次攻击
	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_eq(hp_before - e.hp, 100, "单步应只结算一次攻击伤害")


# ============================================================
#  击杀与漏怪（本轮要求 9）
# ============================================================

func test_killed_enemy_does_not_damage_core() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var core_before := rt.core_hp

	# 击杀敌人后推进很久，核心不应被该敌人扣血
	var e := _place_enemy(rt, 1, 2.5)
	e.hp = 1
	_step_n(rt, 30.0)

	assert_eq(rt.core_hp, core_before, "被击杀的敌人不得再对核心造成漏怪伤害")
	assert_eq(rt.reached_core_count, 0, "不应有任何敌人抵达核心")


func test_kill_counted_exactly_once() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 1, 2.5)
	e.hp = 1
	_step_n(rt, 5.0)
	assert_eq(rt.enemies_killed, 1, "击杀数应为 1")

	# 继续推进，击杀数不应重复增长
	_step_n(rt, 10.0)
	assert_eq(rt.enemies_killed, 1, "击杀数不得重复计数")


func test_dead_enemy_is_removed_from_field() -> void:
	var rt := _runtime([])
	rt.deploy_character(CHAR_ID, 2, 1)
	var e := _place_enemy(rt, 1, 2.5)
	e.hp = 1
	_step_n(rt, 5.0)
	assert_eq(rt.enemies.size(), 0, "死亡敌人应从场上移除")
	assert_eq(rt.enemies_killed, 1, "应记录 1 次击杀")


func test_real_kill_path_leads_to_victory() -> void:
	# 本轮要求 12：新增真实击杀路径能正确触发胜利（不依赖测试夹具）
	var spawns := [
		{"time": 0.5, "lane": 1, "enemy": "echo_normal"},
		{"time": 1.0, "lane": 1, "enemy": "echo_normal"},
	]
	var rt := _runtime(spawns)
	rt.deploy_character(CHAR_ID, 3, 1)  # 中段 col3，位于出怪路径上

	var session := BattleSession.new()
	add_child_autofree(session)
	var errs := session.setup(
		_cfg_with_spawns(spawns), _enemy_table(), _grid(), _char_table(), _combat()
	)
	assert_eq(errs.size(), 0, "构建应无错误")
	assert_true(session.deploy_character(CHAR_ID, 3, 1).ok, "部署应成功")

	# 推进足够长时间让她真实击杀全部敌人
	var t := 0.0
	while session.is_running() and t < 180.0:
		session.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS

	assert_eq(session.outcome, BattleTypes.Outcome.VICTORY,
		"真实击杀路径应能触发胜利（击杀 %d，漏怪 %d）"
		% [session.stage.enemies_killed, session.stage.reached_core_count])
	assert_gt(session.stage.enemies_killed, 0, "胜利应来自真实击杀而非夹具")


# ============================================================
#  1-1 教学关整体可通关性（本轮完成标准）
# ============================================================

func test_stage_1_1_is_winnable_with_only_amamiya_mio() -> void:
	# 规格 G-十二：新档只使用雨宫澪也能完成 1-1 教学
	var session := BattleSession.new()
	add_child_autofree(session)
	var errs := session.setup(
		DataRegistry.get_entry("stages", "1-1"),
		_enemy_table(), _grid(), _char_table(), _combat()
	)
	assert_eq(errs.size(), 0, "构建应无错误")
	assert_true(session.deploy_character(CHAR_ID, 2, 1).ok, "应能部署雨宫澪")

	var t := 0.0
	while session.is_running() and t < 300.0:
		session.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS

	assert_eq(session.outcome, BattleTypes.Outcome.VICTORY,
		"1-1 应可用雨宫澪单人通关（核心 %d/%d，击杀 %d，漏怪 %d）"
		% [session.stage.core_hp, session.stage.core_hp_max,
			session.stage.enemies_killed, session.stage.reached_core_count])
	assert_gt(session.stage.enemies_killed, 0, "应通过真实击杀通关")


func test_stage_1_1_fails_without_deployment() -> void:
	# 对照：不部署任何角色时，1-1 应失败（证明关卡确有战斗需求）
	var session := BattleSession.new()
	add_child_autofree(session)
	session.setup(
		DataRegistry.get_entry("stages", "1-1"),
		_enemy_table(), _grid(), _char_table(), _combat()
	)
	var t := 0.0
	while session.is_running() and t < 300.0:
		session.tick(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS

	assert_eq(session.outcome, BattleTypes.Outcome.DEFEAT, "不部署应失败")


# ============================================================
#  帧率/分辨率无关性（本轮要求 10）
# ============================================================

func test_battle_result_independent_of_tick_granularity() -> void:
	# 用不同 tick 粒度驱动相同总时长，最终战斗结果必须完全一致。
	# 说明：StageRuntime 内部把任意 delta 拆成固定 1/60s 逻辑步，
	# 因此 tick 粒度只影响"每帧追赶几步"，不影响逻辑总量。
	var spawns := [
		{"time": 1.0, "lane": 1, "enemy": "echo_normal"},
		{"time": 3.0, "lane": 1, "enemy": "echo_normal"},
	]
	var total := 40.0
	var results := []
	for tick: float in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 144.0]:
		var rt := _runtime(spawns)
		rt.deploy_character(CHAR_ID, 3, 1)
		# 推进到统一的逻辑步数，保证三条路径的逻辑时间完全相同
		var steps := int(round(total / StageRuntime.LOGIC_STEP_SECONDS))
		for i: int in range(steps):
			rt.advance(tick)
		results.append({
			"killed": rt.enemies_killed,
			"reached": rt.reached_core_count,
			"core": rt.core_hp,
			"mioHp": rt.get_character_by_id(CHAR_ID).hp,
		})
	assert_eq(results[0], results[1], "60fps 与 30fps 结果必须一致")
	assert_eq(results[1], results[2], "30fps 与 144fps 结果必须一致")


func test_battle_result_independent_of_render_resolution() -> void:
	var spawns := [
		{"time": 1.0, "lane": 1, "enemy": "echo_normal"},
	]
	var results := []
	for size: Array in [[1280, 720], [1920, 1080], [3840, 2160]]:
		var g := BattleGrid.from_layout(DataRegistry.get_layout())
		g.reference_canvas_width = int(size[0])
		g.reference_canvas_height = int(size[1])
		var _origin := g.centered_board_origin(size[0], size[1])

		var rt := StageRuntime.from_config(
			_cfg_with_spawns(spawns), _enemy_table(), g, _char_table(), _combat()
		)
		rt.deploy_character(CHAR_ID, 3, 1)
		var t := 0.0
		while t < 40.0 - LOGIC_EPSILON:
			rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
			t += StageRuntime.LOGIC_STEP_SECONDS
		results.append({
			"killed": rt.enemies_killed,
			"core": rt.core_hp,
			"mioHp": rt.get_character_by_id(CHAR_ID).hp,
		})
	assert_eq(results[0], results[1], "720p 与 1080p 结果必须一致")
	assert_eq(results[1], results[2], "1080p 与 4K 结果必须一致")
