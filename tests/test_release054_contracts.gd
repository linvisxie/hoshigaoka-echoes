extends GutTest

var original: Dictionary

func before_all() -> void:
	DataRegistry.load_all()

func before_each() -> void:
	original = SaveService.snapshot()
	assert_true(TestDataGuard.is_isolated(OS.get_user_data_dir()))
	SaveService.new_game()

func after_each() -> void:
	SaveService.commit(original)

func test_failure_cannot_open_after_story_or_next_stage_from_any_entry() -> void:
	var cfg := DataRegistry.get_entry("stages","1-1")
	var result := StageRewardService.settle(cfg,false,true)
	assert_true(result.ok,"defeat is a valid settlement with no reward")
	assert_false(result.rewarded)
	assert_true(result.granted.is_empty())
	assert_true(CampaignFlow.can_open_stage("1-1"))
	assert_false(CampaignFlow.can_open_stage("1-2"))
	assert_false(CampaignFlow.open_stage("1-2"))
	assert_false(CampaignFlow.story_allowed(str(cfg.storyAfter)))
	assert_false(CampaignFlow.finish_story(str(cfg.storyAfter)))
	assert_false(CampaignFlow.open_story(str(cfg.storyAfter),"1-1","post_battle"))
	CampaignFlow.persist({"pending_stage_id":"1-10"})
	assert_false(CampaignFlow.launch_battle())
	assert_eq(CampaignFlow.next_stage(),"1-1")
	assert_false(CampaignFlow.done(str(cfg.storyAfter)))

func test_unlock_requires_all_predecessors_even_with_corrupt_later_clear() -> void:
	var save := SaveService.snapshot()
	save.stages["1-8"]={"cleared":true,"firstClearClaimed":true}
	SaveService.commit(save)
	assert_false(CampaignFlow.can_open_stage("1-9"))
	assert_false(CampaignFlow.can_open_stage("1-10"))
	assert_true(StageRewardService.settle(DataRegistry.get_entry("stages","1-1"),true,true).ok)
	assert_true(CampaignFlow.can_open_stage("1-2"))
	assert_true(CampaignFlow.story_allowed("ch1_1_1_after"))

func _contact(cid: String) -> StageRuntime:
	var rt := StageRuntime.new()
	rt.combat_math = CombatMath.from_config(DataRegistry.get_domain("balance").combat.damage)
	var c := CharacterRuntime.from_config(DataRegistry.get_entry("characters",cid),2,1,1)
	rt.characters.append(c)
	var e := EnemyRuntime.new()
	e.instance_id=1;e.hp=999;e.hp_max=999;e.attack=200;e.attack_interval=1.6
	e.logical_x=2.3;e.lane=1;e.state=BattleTypes.EnemyState.MOVING
	rt.enemies.append(e)
	return rt

func test_passing_contact_damages_every_role_without_giving_them_block() -> void:
	for cid: String in ["amamiya_mio","kamiya_yuma","ogawa_yui","fujiwara_rin","minase_sara","shiraishi_chinatsu"]:
		var rt := _contact(cid)
		var c := rt.characters[0]
		var before := c.hp
		rt._resolve_enemy_attacks(.1)
		assert_lt(c.hp,before,"contact hurts "+cid)
		assert_eq(rt.enemies[0].state,BattleTypes.EnemyState.MOVING)
		assert_eq(c.blocking_enemy_ids.size(),0)
		var after := c.hp
		rt._resolve_enemy_attacks(.1)
		assert_eq(c.hp,after,"attack interval prevents repeated per-frame hits")

func test_contact_never_hits_other_lane_or_distant_character() -> void:
	var rt := _contact("kamiya_yuma")
	var c := rt.characters[0]
	var before := c.hp
	rt.enemies[0].lane=0
	rt._resolve_enemy_attacks(.1)
	assert_eq(c.hp,before)
	rt.enemies[0].lane=1;rt.enemies[0].logical_x=3.0
	rt._resolve_enemy_attacks(.1)
	assert_eq(c.hp,before)

func test_blocked_enemy_keeps_blocker_priority() -> void:
	var rt := _contact("amamiya_mio")
	var ranged := CharacterRuntime.from_config(DataRegistry.get_entry("characters","kamiya_yuma"),2,1,2)
	rt.characters.append(ranged)
	var e := rt.enemies[0]
	e.state=BattleTypes.EnemyState.BLOCKED;e.blocked_by_character_id=1
	var before := ranged.hp
	rt._resolve_enemy_attacks(.1)
	assert_lt(rt.characters[0].hp,rt.characters[0].max_hp)
	assert_eq(ranged.hp,before)

func test_music_mapping_priority_and_restoration() -> void:
	var expected := ["echo_frontline","echo_frontline","echo_frontline","corridor_pressure","corridor_pressure","infirmary_light","ranking_pressure","science_resonance","archive_convergence","archive_convergence"]
	for i: int in range(10):assert_eq(BattleMusic.base_track("1-%d" % (i+1)),expected[i])
	var rt := _contact("kamiya_yuma")
	assert_eq(BattleMusic.select("1-10",rt),"archive_convergence")
	rt.enemies[0].enemy_id="echo_invigilator"
	assert_eq(BattleMusic.select("1-10",rt),"invigilator_exam")
	var boss := EnemyRuntime.new()
	boss.hp=9000;boss.state=BattleTypes.EnemyState.MOVING;boss.mechanic={"kind":"CHAPTER_BOSS"}
	rt.enemies.append(boss)
	for phase: int in range(1,4):
		rt.boss_state.phase=phase
		assert_eq(BattleMusic.select("1-10",rt),"boss_exam_%d" % phase)
	rt.enemies.clear()
	assert_eq(BattleMusic.select("1-10",rt),"archive_convergence")

func test_campus_optional_events_unlock_and_grant_no_resources() -> void:
	assert_eq(CampusHub.events().size(),0)
	assert_false(CampaignFlow.story_allowed("hub_ch1_yui"))
	StageRewardService.settle(DataRegistry.get_entry("stages","1-1"),true,true)
	assert_eq(CampusHub.events().size(),1)
	assert_eq(CampusHub.unread_count(),1)
	var coins: Dictionary = SaveService.snapshot().currencies.duplicate(true)
	assert_true(CampaignFlow.story_allowed("hub_ch1_mio"))
	# No scene change needed to verify optional content is free of reward metadata.
	for event: Dictionary in CampusHub.events():
		assert_false(event.has("rewards"))
		assert_true(event.has("completionFlags"))
	assert_eq(SaveService.snapshot().currencies,coins)
	assert_eq(CampaignFlow.next_stage(),"1-2")

func test_all_glass_palettes_load_imported_texture_with_hud_corner_size() -> void:
	for accent: Color in [GameSkin.BLUE,GameSkin.GOLD,GameSkin.GREEN,GameSkin.RED,GameSkin.MUTED]:
		var style := GameSkin.glass(accent) as StyleBoxTexture
		assert_not_null(style)
		assert_not_null(style.texture)
		assert_gt(style.texture.get_width(),0)
		assert_eq(style.get_texture_margin(SIDE_LEFT),18.0)

func test_repeated_music_policy_does_not_cancel_pending_retry_fade() -> void:
	AudioService.stop_music()
	AudioService.play_music("echo_frontline")
	var transition: Tween=AudioService._music_tween
	for i: int in range(40):AudioService.play_music("echo_frontline")
	assert_eq(AudioService._music_tween,transition,"same pending cue keeps original transition")
	await get_tree().create_timer(.95).timeout
	assert_true(AudioService.playback_status().musicPlaying,"stopped retry music actually starts")
	assert_gt(float(AudioService.playback_status().musicPosition),.1)
	AudioService.stop_music()

func test_new_priority_cue_can_replace_a_pending_music_transition() -> void:
	AudioService.stop_music()
	AudioService.play_music("archive_convergence")
	var previous: Tween=AudioService._music_tween
	AudioService.play_music("boss_exam_1")
	assert_ne(AudioService._music_tween,previous)
	for i: int in range(40):AudioService.play_music("boss_exam_1")
	await get_tree().create_timer(.95).timeout
	assert_eq(AudioService.playback_status().track,"boss_exam_1")
	assert_true(AudioService.playback_status().musicPlaying)
	AudioService.stop_music()
