extends GutTest

func runtime(sequential: bool) -> StageRuntime:
	DataRegistry.load_all()
	var cfg:=DataRegistry.get_entry("stages","1-1").duplicate(true)
	cfg["sequentialWaves"]=sequential
	cfg["enemySpawnTimeline"]=[{"time":1.0,"lane":1,"enemy":"echo_normal","wave":1},{"time":.5 if sequential else 2.0,"lane":0,"enemy":"echo_normal","wave":2}]
	cfg["waves"]=[{"number":1},{"number":2}]
	var enemies: Dictionary={};var chars: Dictionary={}
	for e: Dictionary in DataRegistry.get_domain("enemies").enemies:enemies[e.id]=e
	for c: Dictionary in DataRegistry.get_domain("characters").characters:chars[c.id]=c
	return StageRuntime.from_config(cfg,enemies,BattleGrid.from_layout(DataRegistry.get_layout()),chars,DataRegistry.get_domain("balance").combat)

func advance(rt: StageRuntime,seconds: float) -> void:
	for i: int in range(int(ceil(seconds/.1))):rt.advance(.1)

func test_sequential_wave_with_earlier_timestamp_never_deadlocks_or_spawns_early() -> void:
	var rt:=runtime(true)
	assert_true(rt.is_valid(),str(rt.get_errors()))
	advance(rt,1.2)
	assert_eq(rt.spawned_enemy_count(),1)
	assert_eq(rt.enemies[0].wave_number,1)
	assert_eq(rt.display_wave_number(),1)
	rt.enemies[0].hp=0
	advance(rt,.2)
	assert_eq(rt.current_wave_number(),2)
	advance(rt,1.5)
	assert_eq(rt.spawned_enemy_count(),1,"two-second breathing interval")
	advance(rt,.7)
	assert_eq(rt.spawned_enemy_count(),2,"next wave uses relative delay instead of stale absolute time")
	assert_eq(rt.display_wave_number(),2)

func test_overlapping_tutorial_hud_reports_wave_that_has_actually_arrived() -> void:
	var rt:=runtime(false)
	advance(rt,2.2)
	assert_eq(rt.current_wave_number(),1,"first wave remains uncleared")
	assert_eq(rt.display_wave_number(),2,"incoming wave does not wait for old-wave cleanup in HUD")
	assert_true(rt.incoming_wave_preview().is_empty())
