extends GutTest

func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()

func _runtime() -> StageRuntime:
	var cfg := DataRegistry.get_entry("stages", "1-3").duplicate(true)
	cfg["startingAp"] = 30
	var enemies := {}
	var characters := {}
	for entry: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		enemies[str(entry.id)] = entry
	for entry: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		characters[str(entry.id)] = entry
	var rt := StageRuntime.from_config(cfg, enemies, BattleGrid.from_layout(DataRegistry.get_layout()), characters, DataRegistry.get_domain("balance").get("combat", {}))
	rt.configure_skills(DataRegistry.get_domain("skills"))
	return rt

func _enemy(rt: StageRuntime, x: float, lane: int, id: int) -> EnemyRuntime:
	var e := EnemyRuntime.from_config(rt._enemy_configs["echo_normal"], lane, id)
	e.logical_x = x
	e.hp = 10000
	e.hp_max = 10000
	e.state = BattleTypes.EnemyState.MOVING
	rt.enemies.append(e)
	return e

func test_initial_cooldown_and_pause_reject_cast() -> void:
	var rt := _runtime()
	var c := rt.deploy_character("amamiya_mio", 1, 1).character
	assert_almost_eq(c.skill_cooldown_remaining, 12.0, 0.001)
	assert_false(rt.cast_skill(c.instance_id).ok)
	c.skill_cooldown_remaining = 0
	rt.paused = true
	assert_false(rt.cast_skill(c.instance_id).ok)
	assert_eq(rt.skill_events.size(), 0)
	rt.paused = false
	assert_true(rt.cast_skill(c.instance_id).ok)
	assert_almost_eq(c.skill_active_remaining, 6.0, 0.001)
	assert_eq(c.effective_attack(), 180)

func test_mio_three_targets_same_lane_and_range_restore() -> void:
	var rt := _runtime()
	var c := rt.deploy_character("amamiya_mio", 1, 1).character
	for n: int in range(4):
		_enemy(rt, 2.5 + float(n) * 0.2, 1, 100 + n)
	var adjacent := _enemy(rt, 2.0, 0, 110)
	c.skill_cooldown_remaining = 0
	assert_true(rt.cast_skill(c.instance_id).ok)
	rt._resolve_attacker_action(c, 0.0)
	assert_gt(rt.enemies[0].total_damage_taken, 0)
	assert_gt(rt.enemies[2].total_damage_taken, 0)
	assert_eq(rt.enemies[3].total_damage_taken, 0)
	assert_eq(adjacent.total_damage_taken, 0)
	c.skill_active_remaining = 0
	c.attack_cooldown = 0
	var total := c.total_damage_dealt
	rt._resolve_attacker_action(c, 0.0)
	assert_eq(c.total_damage_dealt, total, "normal 1.25 range restores")

func test_yuma_charge_waits_for_own_lane_and_consumes_once() -> void:
	var rt := _runtime()
	var c := rt.deploy_character("kamiya_yuma", 1, 1).character
	c.skill_cooldown_remaining = 0
	var adjacent := _enemy(rt, 2.0, 0, 100)
	assert_true(rt.cast_skill(c.instance_id).ok)
	rt._resolve_attacker_action(c, 0.0)
	assert_true(c.skill_charged)
	assert_eq(adjacent.total_damage_taken, 0)
	var same := _enemy(rt, 3.0, 1, 101)
	rt._resolve_attacker_action(c, 0.0)
	assert_false(c.skill_charged)
	assert_eq(same.total_damage_taken, rt.combat_math.compute_damage(450.0, same.defense, c.damage_type))
	assert_false(rt.cast_skill(c.instance_id).ok)

func test_skill_cooldown_is_frozen_when_stage_paused() -> void:
	var rt := _runtime()
	var c := rt.deploy_character("amamiya_mio", 1, 1).character
	rt.paused = true
	rt.advance(1.0)
	assert_almost_eq(c.skill_cooldown_remaining, 12.0, 0.001)
	rt.paused = false
	rt.advance(1.0)
	assert_almost_eq(c.skill_cooldown_remaining, 12.0 - rt.elapsed_seconds, 0.001, "cooldown follows executed fixed logic steps")

func test_mio_low_hp_defense_recovers_without_stacking() -> void:
	var rt := _runtime()
	var c := rt.deploy_character("amamiya_mio", 1, 1).character
	c.hp = 399
	assert_almost_eq(rt._defense_of_target(c), 108.0, 0.001)
	c.hp = 400
	assert_almost_eq(rt._defense_of_target(c), 80.0, 0.001)
	c.hp = 100
	assert_almost_eq(rt._defense_of_target(c), 108.0, 0.001)

func test_yuma_focus_caps_and_resets_when_target_changes() -> void:
	var rt := _runtime()
	var c := rt.deploy_character("kamiya_yuma", 1, 1).character
	var first := _enemy(rt, 2.0, 1, 100)
	for n: int in range(8):
		c.attack_cooldown = 0
		rt._resolve_attacker_action(c, 0.0)
	var before := first.total_damage_taken
	c.attack_cooldown = 0
	rt._resolve_attacker_action(c, 0.0)
	assert_eq(first.total_damage_taken - before, rt.combat_math.compute_damage(187.5, first.defense, c.damage_type))
	first.logical_x = 6.0
	var second := _enemy(rt, 2.0, 1, 101)
	c.attack_cooldown = 0
	rt._resolve_attacker_action(c, 0.0)
	assert_eq(second.total_damage_taken, rt.combat_math.compute_damage(150.0, second.defense, c.damage_type))
