## Regression for actual scene integration, not only resource existence.
extends GutTest

func _view() -> Node:
	var view: Node = load("res://scenes/battle/battle_scene.gd").new()
	view.grid = BattleGrid.from_layout(DataRegistry.get_layout())
	view.session = BattleSession.new()
	view.session.grid = view.grid
	view.session.stage = StageRuntime.new()
	view.session.stage.grid = view.grid
	return view

func test_scene_and_all_visible_packed_scenes_load() -> void:
	for path: String in ["res://scenes/title/title.tscn", "res://scenes/battle/battle_scene.tscn", "res://scenes/menus/character_screen.tscn"]:
		var packed: PackedScene = load(path)
		assert_not_null(packed, path)
		var node := packed.instantiate()
		assert_not_null(node, "Full script load, not bootstrap headless early exit")
		node.free()

func test_cursor_consumes_450_across_retention_without_duplicates() -> void:
	var stage := StageRuntime.new()
	var cursor := DamageEventCursor.new()
	var consumed := 0
	for i: int in range(450):
		stage._record_damage_event(true, 1, 1, false)
		consumed += cursor.consume(stage.damage_events).size()
	assert_eq(consumed, 450)
	assert_eq(cursor.consume(stage.damage_events).size(), 0)
	assert_eq(cursor.last_sequence, 450)
	assert_eq(cursor.missed_events, 0)
	assert_eq(stage.damage_events.size(), 200, "Retention remains bounded")

func test_cursor_reports_batch_overrun_but_recovers_next_event() -> void:
	var stage := StageRuntime.new()
	var cursor := DamageEventCursor.new()
	for i: int in range(230): stage._record_damage_event(true, 1, 1, false)
	assert_eq(cursor.consume(stage.damage_events).size(), 200)
	assert_eq(cursor.missed_events, 30, "Lost batch must be explicit")
	stage._record_damage_event(true, 1, 1, false)
	assert_eq(cursor.consume(stage.damage_events).size(), 1, "Not permanently stuck at 200")

func test_damage_metadata_is_exact_and_has_no_combat_side_effects() -> void:
	var stage := StageRuntime.new()
	stage.core_hp = 3
	stage.ap = 10
	stage._record_damage_event(true, 9, 125, true, "character", 7,
		Vector2(2, 0), Vector2(4.5, 1), 1)
	var event: Dictionary = stage.damage_events[0]
	assert_eq(event["sourceId"], 7)
	assert_eq(event["targetId"], 9)
	assert_eq(event["sourcePos"], Vector2(2, 0))
	assert_eq(event["targetPos"], Vector2(4.5, 1))
	assert_eq(stage.core_hp, 3)
	assert_eq(stage.ap, 10)
	assert_eq(stage.enemies_killed, 0)

func test_removed_enemy_has_independent_departure_snapshot() -> void:
	var view := _view()
	view.session.stage.removals.append({"entity": "enemy", "entityId": 2,
		"enemyId": "echo_normal", "kind": StageRuntime.Removal.KILLED, "x": 3.5, "lane": 1})
	view._update_animation_states(0.0)
	assert_eq(view._departures.size(), 1, "Drawable after domain cleanup")
	assert_eq(view.session.stage.enemies.size(), 0, "No resurrected domain enemy")
	var ghost: Dictionary = view._departures[0]
	assert_eq(ghost["logical"], Vector2(3.5, 1))
	var state: AnimState = ghost["state"]
	assert_eq(state.anim, "death")
	assert_true(state.is_one_shot())
	view._update_animation_states(0.25)
	assert_eq(view._departures.size(), 1)
	view._update_animation_states(0.51)
	assert_eq(view._departures.size(), 0, "Released after playback")
	view.free()

func test_incapacitated_and_retreat_use_snapshots_not_live_roster() -> void:
	var view := _view()
	for i: int in range(2):
		view.session.stage.removals.append({"entity": "character", "entityId": i+1,
			"characterId": "amamiya_mio", "column": 2, "lane": i,
			"kind": StageRuntime.Removal.INCAPACITATED if i == 0 else StageRuntime.Removal.RETREATED})
	view._update_animation_states(1.0)
	view._update_animation_states(1.0)
	assert_eq(view._departures.size(), 2, "One snapshot per departure, no double consume")
	assert_eq(view.session.stage.characters.size(), 0)
	view.free()

func test_death_clamps_to_last_frame_does_not_repeat() -> void:
	var state := AnimState.new()
	state.begin_death(1.0)
	assert_eq(state.progress(5.0), 1.0)
	assert_true(state.finished(5.0))
	var final := ArtRegistry.enemy_frame_progress("echo_normal", "death", state.progress(5.0))
	var later := ArtRegistry.enemy_frame_progress("echo_normal", "death", state.progress(7.0))
	assert_eq(final, later)
	assert_eq(final.region.position.x, 3.0 * final.region.size.x)

func test_hit_queues_attack_once_then_returns_idle() -> void:
	var state := AnimState.new()
	var c := CharacterRuntime.new()
	c.alive = true
	c.hp = 100
	state.tick_character(c, 0.0, false)
	c.total_damage_dealt = 120
	state.tick_character(c, 0.1, true)
	assert_eq(state.anim, "hit")
	state.tick_character(c, 0.3, false)
	assert_eq(state.anim, "attack", "Attack no longer swallowed by concurrent hit")
	state.tick_character(c, 0.7, false)
	assert_eq(state.anim, "idle")

func test_first_hit_and_exact_attack_event_not_discarded() -> void:
	var c := CharacterRuntime.new()
	c.alive = true
	c.hp = 100
	var state := AnimState.new()
	state.tick_character(c, 1.0, true, true)
	assert_eq(state.anim, "hit")
	state.tick_character(c, 1.3, false)
	assert_eq(state.anim, "attack")

func test_selection_queue_is_not_draw_evidence() -> void:
	var view := _view()
	var state := AnimState.new()
	state.begin_death(0)
	view._char_anim[1] = state
	view._vfx.append({"name": "vfx_slash", "born": 0, "life": 1})
	view._track_art_reachability()
	assert_eq(view.art_reachability_report()["drawnCount"], 0,
		"No actual draw happened; old state/queue counting is forbidden")
	view.free()

func test_lethal_impact_survives_absent_target() -> void:
	var view := _view()
	view.session.stage._record_damage_event(true, 4, 100, true,
		"character", 1, Vector2(2, 1), Vector2(3.2, 1))
	view._consume_damage_events()
	assert_eq(view._vfx.size(), 1, "Impact exists even after target removal")
	assert_eq(view._damage_pops.size(), 1)
	assert_true(view._damage_pops[0].has("anchor"))
	view.free()

func test_actual_cross_lane_damage_event_preserves_attacker() -> void:
	var enemies := {}
	for cfg: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		enemies[str(cfg["id"])] = cfg
	var characters := {}
	for cfg: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		characters[str(cfg["id"])] = cfg
	var stage := StageRuntime.from_config(DataRegistry.get_entry("stages", "1-3"), enemies,
		BattleGrid.from_layout(DataRegistry.get_layout()), characters,
		DataRegistry.get_domain("balance").get("combat", {}))
	stage.add_ap(30)
	var result := stage.deploy_character("kamiya_yuma", 1, 0)
	assert_true(result.ok)
	for frame: int in range(720):
		stage.advance(1.0 / 60.0)
	# Real character action path chooses the middle-lane enemy from an adjacent lane.
	assert_gt(stage.damage_events.size(), 0)
	if stage.damage_events.is_empty():
		return
	var event: Dictionary = stage.damage_events[0]
	assert_eq(event["sourceKind"], "character")
	assert_eq(event["sourceId"], result.character.instance_id)
	assert_eq(event["sourcePos"], Vector2(1, 0))
	var position: Vector2 = event["targetPos"]
	assert_eq(position.y, 1.0)

func test_no_attack_vfx_guessed_for_unknown_source() -> void:
	var view := _view()
	view._spawn_attacker_vfx({"targetKind": "enemy", "targetId": 1}, 0.0)
	assert_eq(view._vfx.size(), 0, "Unknown source cannot be attributed to a nearest unit")
	view.free()

func test_isolation_predicate_and_gut_invocation() -> void:
	assert_false(TestDataGuard.is_isolated("C:/Users/test/AppData/Roaming/HoshigaokaEchoes"))
	assert_false(TestDataGuard.is_isolated("relative/_testenv/HoshigaokaEchoes"))
	assert_true(TestDataGuard.is_isolated("D:/星丘残响/_testenv/run/appdata/HoshigaokaEchoes"))
	assert_true(TestDataGuard.is_gut_invocation(PackedStringArray(["-s", "addons/gut/gut_cmdln.gd"])))
	assert_false(TestDataGuard.is_gut_invocation(PackedStringArray(["--scene=battle"])))
