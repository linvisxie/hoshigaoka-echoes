extends GutTest

func before_all() -> void:
	if not DataRegistry.is_loaded(): DataRegistry.load_all()

func _runtime() -> StageRuntime:
	var cfg := DataRegistry.get_entry("stages","1-5").duplicate(true)
	cfg["startingAp"] = 30
	cfg["availableCharacters"].append("fujiwara_rin")
	var enemies := {}
	var characters := {}
	for entry: Dictionary in DataRegistry.get_domain("enemies").get("enemies",[]): enemies[str(entry.id)] = entry
	for entry: Dictionary in DataRegistry.get_domain("characters").get("characters",[]): characters[str(entry.id)] = entry
	var rt := StageRuntime.from_config(cfg,enemies,BattleGrid.from_layout(DataRegistry.get_layout()),characters,DataRegistry.get_domain("balance").get("combat",{}),DataRegistry.get_domain("upgrades"))
	rt.configure_skills(DataRegistry.get_domain("skills"))
	return rt

func test_rin_has_no_normal_attack_and_passive_ends_on_withdrawal() -> void:
	var rt := _runtime()
	var rin := rt.deploy_character("fujiwara_rin",1,1).character
	assert_not_null(rin)
	assert_eq(rin.block_count_max,0)
	assert_almost_eq(rt._ap_regen_mult(),1.15,.0001)
	var enemy := EnemyRuntime.from_config(rt._enemy_configs["echo_normal"],1,100)
	enemy.logical_x = 1.0
	enemy.state = BattleTypes.EnemyState.MOVING
	rt.enemies.append(enemy)
	rt._resolve_attacker_action(rin,1.0)
	assert_eq(enemy.total_damage_taken,0,"resource support must never deal minimum-one fake damage")
	rin.apply_status_effect_from_config({"effectId":"test_attack", "category":"ATTACK", "pct":10.0, "durationSeconds":5},0)
	rt._resolve_attacker_action(rin,1.0)
	assert_eq(enemy.total_damage_taken,0,"attack buffs cannot enable a support's forbidden normal attack")
	rt.withdraw_character(rin.instance_id)
	assert_almost_eq(rt._ap_regen_mult(),1.0,.0001)

func test_dispatch_respects_cap_cooldown_and_pause() -> void:
	var rt := _runtime()
	var rin := rt.deploy_character("fujiwara_rin",0,0).character
	assert_false(rt.cast_skill(rin.instance_id).ok)
	rin.skill_cooldown_remaining = 0
	rt.ap = 28
	rt.paused = true
	assert_false(rt.cast_skill(rin.instance_id).ok)
	assert_eq(rt.ap,28)
	rt.paused = false
	assert_true(rt.cast_skill(rin.instance_id).ok)
	assert_eq(rt.ap,30)
	assert_almost_eq(rin.skill_cooldown_remaining,24.0,.001)
	assert_false(rt.cast_skill(rin.instance_id).ok)

func test_discount_hover_rejection_and_single_consumption() -> void:
	var rt := _runtime()
	rt.deploy_character("fujiwara_rin",0,0)
	for i: int in range(4): assert_eq(rt.query_deploy("amamiya_mio",1,1).cost,8)
	assert_false(rt.deploy_character("amamiya_mio",0,0).ok)
	assert_eq(rt.deployment_cost("amamiya_mio"),8,"occupied-cell rejection cannot consume discount")
	var result := rt.deploy_character("amamiya_mio",1,1)
	assert_true(result.ok)
	assert_eq(result.cost,8)
	assert_eq(rt.ap,6)
	assert_eq(rt.deployment_cost("kamiya_yuma"),12,"voucher consumed exactly once")
	var withdrawn := rt.withdraw_character(result.character.instance_id)
	assert_true(withdrawn.ok)
	assert_eq(rt.ap,10,"refund uses actual paid 8 AP, not undiscounted 10")

func test_discount_expires_and_ap_support_shares_soft_cap() -> void:
	var rt := _runtime()
	rt.deploy_character("fujiwara_rin",0,0)
	rt.elapsed_seconds = 10.01
	assert_eq(rt.deployment_cost("amamiya_mio"),10)
	for i: int in range(4): rt.upgrades.apply("upgrade_ap_regen")
	assert_almost_eq(rt._ap_regen_mult(),1.5,.0001,"Rin and upgrades share +50% AP cap")

func test_skill_build_changes_real_clock_and_retains_debuff_floor() -> void:
	var rt := _runtime()
	var mio := rt.deploy_character("amamiya_mio",1,1).character
	assert_true(rt.upgrades.apply("upgrade_cd_recovery"))
	var before := mio.skill_cooldown_remaining
	rt._tick_character_skills(1.0)
	assert_almost_eq(before-mio.skill_cooldown_remaining,1.15,.0001)
	mio.apply_status_effect_from_config({"effectId":"test_cd_debuff", "category":"CD_RECOVERY", "pct":-2.0, "durationSeconds":5},0)
	before = mio.skill_cooldown_remaining
	rt._tick_character_skills(1.0)
	assert_almost_eq(before-mio.skill_cooldown_remaining,mio.debuff_floor_pct,.0001,"floor applies after summing upgrades and debuffs")

func _board(size: Vector2) -> Node2D:
	var board: Node2D = load("res://scenes/battle/battle_scene.tscn").instantiate()
	board.grid = BattleGrid.from_layout(DataRegistry.get_layout())
	board._viewport_size = size
	board._update_render_scale()
	board._update_layout()
	return board

func test_projection_roundtrip_and_all_eighteen_centers_at_three_resolutions() -> void:
	for size: Vector2 in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1440)]:
		var board := _board(size)
		for lane: int in range(3):
			for col: int in range(6):
				var center: Vector2 = board._cell_screen_pos(col,lane)
				var hit: Dictionary = board._screen_to_cell(center)
				assert_eq(hit.get("column",-1),col)
				assert_eq(hit.get("lane",-1),lane)
				var logical: Vector2 = Vector2(col+.37,lane-.26)
				var recovered: Vector2 = board._screen_to_logical(board._logical_to_screen(logical))
				assert_lt(recovered.distance_to(logical),.0001)
		board.free()

func test_slanted_cell_boundaries_do_not_claim_gaps_or_neighboring_lanes() -> void:
	var board := _board(Vector2(1920,1080))
	for logical: Vector2 in [Vector2(2.49,1),Vector2(2,1.49),Vector2(-.6,0),Vector2(5.6,2)]:
		assert_true(board._screen_to_cell(board._logical_to_screen(logical)).is_empty())
	var upper: Vector2 = board._cell_screen_pos(0,0)
	var lower: Vector2 = board._cell_screen_pos(0,2)
	assert_lt(lower.x,upper.x,"nearer route shifts left, as the concept ground plane")
	assert_gt(lower.y,upper.y)
	assert_almost_eq((board._cell_screen_pos(5,0) as Vector2).y,upper.y,.001,"route remains horizontal")
	board.free()
