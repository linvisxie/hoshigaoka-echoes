## Phase 0 验收测试：DataRegistry 加载与校验（V2.1.4 B6）
##
## 验证：canonical + 目录型数据域可全部加载、ID 索引可用、引用校验生效。
extends GutTest

var _reg: Node


func before_each() -> void:
	_reg = load("res://scripts/data/data_registry.gd").new()
	add_child_autofree(_reg)


func test_load_all_succeeds_on_phase0_data() -> void:
	var ok: bool = _reg.load_all()
	if not ok:
		for e: String in _reg.get_load_errors():
			gut.p("加载问题: %s" % e)
	assert_true(ok, "Phase 0 数据应无错误加载")


func test_all_canonical_domains_are_registered() -> void:
	_reg.load_all()
	var expected := [
		"terms", "balance", "characters", "skills", "enemies", "currencies",
		"character_growth", "upgrade_costs", "upgrades", "equipment",
		"equipment_affixes", "mementos", "stage_rewards",
	]
	for domain: String in expected:
		assert_false(
			_reg.get_domain(domain).is_empty(),
			"数据域应已注册: %s" % domain
		)


func test_stage_index_contains_ten_stages() -> void:
	_reg.load_all()
	var ids: Array = _reg.get_ids("stages")
	assert_eq(ids.size(), 10, "应索引到 10 个关卡")


func test_stage_index_lookup_by_id() -> void:
	_reg.load_all()
	var st: Dictionary = _reg.get_entry("stages", "1-1")
	assert_false(st.is_empty(), "应能按 stageId 取到 1-1")
	assert_eq(int(st.get("chapter", 0)), 1, "1-1 应属第 1 章")


func test_story_index_available() -> void:
	_reg.load_all()
	var ids: Array = _reg.get_ids("story")
	assert_gt(ids.size(), 0, "应索引到至少 1 个剧情")


func test_layout_params_readable() -> void:
	_reg.load_all()
	var layout: Dictionary = _reg.get_layout()
	assert_eq(int(layout.get("tileSizePx", 0)), 192, "应能读到 tileSizePx")
	assert_eq(int(layout.get("laneSpacingPx", 0)), 192, "应能读到 laneSpacingPx")


func test_reload_is_idempotent() -> void:
	assert_true(_reg.load_all(), "首次加载应成功")
	assert_true(_reg.load_all(), "重复加载应仍成功且无重复索引")
	assert_eq(_reg.get_ids("stages").size(), 10, "重复加载后关卡数不应翻倍")
