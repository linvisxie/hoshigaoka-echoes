## 动画状态机回归测试（本轮指令 第三条 + 第四条）。
##
## 存在的理由：
##   上一轮"角色攻击/受击/死亡动画未接入"是一个**纯运行期**缺口 ——
##   文件都在、GUT 全绿、stderr 为空，但游戏里就是只播 idle。
##   本文件把动画状态机的**行为契约**变成可执行断言，让这类
##   "有资源但不工作"的问题在 CI 阶段暴露。
##
## 覆盖的硬性要求（对应本轮指令 3.1~3.8）：
##   3.1 攻击事件播放攻击动画
##   3.2 受到伤害播放受击动画
##   3.3 失能播放退场/死亡动画
##   3.6 不允许受击反复覆盖死亡动画
##   3.7 动画切换不得改变战斗逻辑（状态机只读、无副作用）
##   3.8 不产生资源泄漏或重复解码
extends GutTest

const FIXTURE_CHAR := "amamiya_mio"


func _make_char() -> CharacterRuntime:
	var c := CharacterRuntime.new()
	c.instance_id = 1
	c.character_id = FIXTURE_CHAR
	c.display_name = "雨宫澪"
	c.column = 2
	c.lane = 1
	c.max_hp = 1000
	c.hp = 1000
	c.attack = 120
	c.defense = 80
	c.block_count_max = 2
	c.behavior = CharacterRuntime.Behavior.FRONTLINE
	c.alive = true
	return c


func _make_enemy() -> EnemyRuntime:
	var e := EnemyRuntime.new()
	e.instance_id = 1
	e.enemy_id = "echo_normal"
	e.display_name = "普通残响体"
	e.lane = 1
	e.logical_x = 3.0
	e.hp = 420
	e.hp_max = 420
	e.attack = 65
	e.defense = 20
	e.total_damage_dealt = 0
	e.total_damage_taken = 0
	return e


# ============================================================ 3.1 攻击

func test_attack_counter_increase_plays_attack_anim() -> void:
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)   # 首次只建立基线
	assert_eq(st.anim, AnimState.IDLE, "开局应为待机")
	# 领域层记账：造成了一次伤害
	c.total_damage_dealt += 120
	st.tick_character(c, 0.1, false)
	assert_eq(st.anim, AnimState.ATTACK, "造成伤害后应播攻击动画")


func test_healer_healing_plays_attack_anim() -> void:
	# 治疗角色没有 total_damage_dealt，靠 total_healing_done 触发"出手"
	var st := AnimState.new()
	var c := _make_char()
	c.behavior = CharacterRuntime.Behavior.HEALER
	st.tick_character(c, 0.0, false)
	c.total_healing_done += 50
	st.tick_character(c, 0.1, false)
	assert_eq(st.anim, AnimState.ATTACK, "治疗出手也应播出手动画")


# ============================================================ 3.2 受击

func test_hit_event_plays_hit_anim() -> void:
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	st.tick_character(c, 0.1, true)    # 本帧有受击事件
	assert_eq(st.anim, AnimState.HIT, "受击应播受击动画")


func test_hit_takes_priority_over_attack() -> void:
	# 同时挨打又出手时，受击优先（被打当然先演受击）
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	c.total_damage_dealt += 120
	st.tick_character(c, 0.1, true)
	assert_eq(st.anim, AnimState.HIT, "受击优先级高于攻击")


# ============================================================ 3.3 失能 / 死亡

func test_incapacitated_plays_death_anim() -> void:
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	assert_eq(st.anim, AnimState.IDLE)
	c.hp = 0
	c.alive = false
	st.tick_character(c, 0.5, false)
	assert_eq(st.anim, AnimState.DEATH, "失能应播死亡动画")
	assert_true(st.dead, "应标记为已进入死亡终态")


func test_enemy_inactive_plays_death_anim() -> void:
	var st := AnimState.new()
	var e := _make_enemy()
	st.tick_enemy(e, 0.0, false)
	e.hp = 0
	st.tick_enemy(e, 0.3, false)
	assert_eq(st.anim, AnimState.DEATH, "敌人 HP 归零应播消散动画")
	assert_true(st.dead, "敌人应标记为已消散")


# ============================================================ 3.6 死亡不可覆盖（关键）

func test_hit_cannot_override_death() -> void:
	# 这是本轮指令 3.6 的明文要求：死亡后不得被受击反复覆盖
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	c.hp = 0
	c.alive = false
	st.tick_character(c, 0.5, false)
	assert_eq(st.anim, AnimState.DEATH)
	# 死后连续来 10 次受击事件
	for i: int in range(10):
		st.tick_character(c, 0.6 + float(i) * 0.1, true)
		assert_eq(st.anim, AnimState.DEATH,
			"死亡后第 %d 次受击不得覆盖死亡动画" % (i + 1))


func test_attack_cannot_override_death() -> void:
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	c.hp = 0
	c.alive = false
	st.tick_character(c, 0.5, false)
	c.total_damage_dealt += 500
	st.tick_character(c, 0.6, false)
	assert_eq(st.anim, AnimState.DEATH, "死亡后攻击计数器增长也不得覆盖死亡")


func test_enemy_death_not_overridden_by_hit() -> void:
	var st := AnimState.new()
	var e := _make_enemy()
	st.tick_enemy(e, 0.0, false)
	e.hp = 0
	st.tick_enemy(e, 0.3, false)
	for i: int in range(5):
		st.tick_enemy(e, 0.4 + float(i) * 0.1, true)
		assert_eq(st.anim, AnimState.DEATH, "敌人消散后不得被受击覆盖")


# ============================================================ 3.5 回落待机

func test_attack_falls_back_to_idle_after_duration() -> void:
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	c.total_damage_dealt += 120
	st.tick_character(c, 0.1, false)
	assert_eq(st.anim, AnimState.ATTACK)
	# 攻击动画时长 + 余量之后应回落
	st.tick_character(c, 0.1 + AnimState.ATTACK_SECONDS + 0.05, false)
	assert_eq(st.anim, AnimState.IDLE, "攻击动画播完应回落待机")


func test_hit_falls_back_to_idle_after_duration() -> void:
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	st.tick_character(c, 0.1, true)
	assert_eq(st.anim, AnimState.HIT)
	st.tick_character(c, 0.1 + AnimState.HIT_SECONDS + 0.05, false)
	assert_eq(st.anim, AnimState.IDLE, "受击动画播完应回落待机")


func test_no_event_keeps_idle() -> void:
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	for i: int in range(20):
		st.tick_character(c, 1.0 + float(i) * 0.1, false)
		assert_eq(st.anim, AnimState.IDLE, "无事件应始终保持待机")


func test_enemy_defaults_to_move() -> void:
	var st := AnimState.new()
	var e := _make_enemy()
	st.tick_enemy(e, 0.0, false)
	st.tick_enemy(e, 0.1, false)
	assert_eq(st.anim, AnimState.MOVE, "活跃敌人默认播移动")


# ============================================================ 3.7 无副作用（关键）

func test_state_machine_does_not_mutate_combat_state() -> void:
	# 本轮指令 3.7：动画切换**不得**改变攻击次数或战斗逻辑。
	# 断言：跑完整套状态迁移后，角色的全部战斗字段一字未改。
	var st := AnimState.new()
	var c := _make_char()
	var snap := {
		"hp": c.hp, "max_hp": c.max_hp, "attack": c.attack, "defense": c.defense,
		"total_damage_dealt": c.total_damage_dealt,
		"total_healing_done": c.total_healing_done,
		"total_damage_taken": c.total_damage_taken,
		"attack_cooldown": c.attack_cooldown,
		"alive": c.alive, "column": c.column, "lane": c.lane,
	}
	st.tick_character(c, 0.0, false)
	c.total_damage_dealt += 120
	st.tick_character(c, 0.1, false)
	st.tick_character(c, 0.2, true)
	st.tick_character(c, 0.5, false)
	c.hp = 0
	c.alive = false
	st.tick_character(c, 0.9, false)
	# 除测试自己改的两个字段外，其余必须完全不变
	assert_eq(c.total_damage_dealt, snap["total_damage_dealt"] + 120,
		"状态机不得额外增加攻击计数")
	assert_eq(c.total_healing_done, snap["total_healing_done"], "状态机不得改治疗计数")
	assert_eq(c.total_damage_taken, snap["total_damage_taken"], "状态机不得改承伤计数")
	assert_eq(c.max_hp, snap["max_hp"], "状态机不得改最大生命")
	assert_eq(c.attack, snap["attack"], "状态机不得改攻击")
	assert_eq(c.defense, snap["defense"], "状态机不得改防御")
	assert_eq(c.attack_cooldown, snap["attack_cooldown"], "状态机不得改冷却")
	assert_eq(c.column, snap["column"], "状态机不得改位置")
	assert_eq(c.lane, snap["lane"], "状态机不得改路线")


func test_enemy_state_machine_does_not_mutate() -> void:
	var st := AnimState.new()
	var e := _make_enemy()
	var hp := e.hp
	var x := e.logical_x
	var dealt := e.total_damage_dealt
	st.tick_enemy(e, 0.0, false)
	e.total_damage_dealt += 60
	st.tick_enemy(e, 0.1, false)
	st.tick_enemy(e, 0.2, true)
	st.tick_enemy(e, 0.4, false)
	assert_eq(e.hp, hp, "状态机不得改敌人 HP")
	assert_eq(e.logical_x, x, "状态机不得改敌人逻辑坐标（会影响移动/阻挡判定）")
	assert_eq(e.total_damage_dealt, dealt + 60, "状态机不得额外增加敌人攻击计数")


# ============================================================ 3.8 无资源泄漏

func test_frame_lookup_is_cached_not_redecoded() -> void:
	# 本轮指令 3.8：动画帧更新不得产生资源泄漏或大量重复解码。
	# ArtRegistry 用 static 缓存，同一帧多次取用必须返回**同一个对象**。
	ArtRegistry.clear_cache()
	var a := ArtRegistry.character_frame_progress(FIXTURE_CHAR, "attack", 0.5)
	var b := ArtRegistry.character_frame_progress(FIXTURE_CHAR, "attack", 0.5)
	assert_not_null(a, "攻击帧应可取得")
	assert_eq(a, b, "同一帧重复取用必须命中缓存（同一对象）")
	var strip1 := ArtRegistry.load_texture(ArtRegistry.character_strip_path(FIXTURE_CHAR, "attack"))
	var strip2 := ArtRegistry.load_texture(ArtRegistry.character_strip_path(FIXTURE_CHAR, "attack"))
	assert_eq(strip1, strip2, "帧条贴图只应解码一次")


func test_one_shot_progress_maps_monotonically() -> void:
	# 一次性动画的帧号必须随进度单调推进（不能来回跳）
	var st := AnimState.new()
	var c := _make_char()
	st.tick_character(c, 0.0, false)
	c.total_damage_dealt += 120
	st.tick_character(c, 1.0, false)
	assert_true(st.is_one_shot(), "攻击应被标记为一次性动画")
	var p0 := st.progress(1.0)
	var p1 := st.progress(1.0 + AnimState.ATTACK_SECONDS * 0.5)
	var p2 := st.progress(1.0 + AnimState.ATTACK_SECONDS * 0.9)
	assert_lt(p0, p1, "进度应递增")
	assert_lt(p1, p2, "进度应持续递增")
	assert_lte(p2, 1.0, "进度不得超过 1")


# ============================================================ 3.4 资源齐备

func test_all_anim_strips_exist_for_state_machine() -> void:
	# 状态机可能选中的每条动画都必须有真实帧条，否则会静默回退
	for cid: String in ["amamiya_mio", "kamiya_yuma", "ogawa_yui"]:
		for a: String in [AnimState.IDLE, AnimState.MOVE, AnimState.ATTACK,
				AnimState.HIT, AnimState.DEATH]:
			var tex := ArtRegistry.character_frame_progress(cid, a, 0.5)
			assert_not_null(tex, "角色 %s 的 %s 动画帧必须存在" % [cid, a])
	for eid: String in ["echo_normal", "echo_runner", "echo_armored",
			"echo_exam_sheet", "echo_silent", "echo_copy", "echo_invigilator"]:
		for a: String in [AnimState.IDLE, AnimState.MOVE, AnimState.ATTACK,
				AnimState.HIT, AnimState.DEATH]:
			var tex := ArtRegistry.enemy_frame_progress(eid, a, 0.5)
			assert_not_null(tex, "敌人 %s 的 %s 动画帧必须存在" % [eid, a])
