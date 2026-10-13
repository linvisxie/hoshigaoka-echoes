extends GutTest

var original := "zh"

func before_each() -> void:
	original = GameLocale.language
	GameLocale.set_language("en")

func after_each() -> void:
	GameLocale.set_language(original)

func test_templates_keep_numbers_names_and_percentages() -> void:
	assert_eq(GameLocale.text("雨宫澪 升至 Lv.12，提升 3 级"),"Mio Amamiya reached Lv.12, gained 3 levels")
	assert_eq(GameLocale.text("防御 +20%"),"DEF +20%")
	assert_eq(GameLocale.text("下一波 03 · 上段 / 中段"),"Next wave 03 · Upper / Middle")
	assert_eq(GameLocale.text("生命  120 / 1000"),"HP  120 / 1000")
	assert_eq(GameLocale.text("study_record_small"),"study_record_small")
	assert_eq(GameLocale.text("▸ 第一章 · 新学期的残响  /  0 篇已读"),"▸ Chapter One · Echoes of a New Term / 0 read")
	assert_eq(GameLocale.text("· 需要等级 Lv.10（当前 Lv.1）"),"· Requires Lv.10 (current Lv.1)")
	var composed := "部署费用 10 AP    /    再部署 8 秒\n攻击间隔 1.1 秒    /    阻挡 2\n\n主动技能\n夕凪一闪    冷却 12 秒\n6秒内攻击 +50%，攻击同路线前方3格内最多3名敌人。\n"
	assert_null(RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]").search(GameLocale.text(composed)))

func test_all_story_titles_speakers_and_lines_have_english() -> void:
	var cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
	for sid: String in DataRegistry.get_ids("story"):
		var story := DataRegistry.get_entry("story",sid)
		assert_null(cjk.search(GameLocale.text(str(story.get("title","")))),sid+" title")
		for node: Dictionary in story.get("nodes",[]):
			for field: String in ["speaker","text"]:
				var source := str(node.get(field,""))
				var translated := GameLocale.text(source)
				assert_null(cjk.search(translated),sid+" node "+str(node.id)+" "+field)
				assert_eq(translated.count("{player}"),source.count("{player}"),"player placeholder preserved")

func test_translation_never_mutates_registry_or_player_save() -> void:
	var config := DataRegistry.get_entry("characters","amamiya_mio").duplicate(true)
	var snapshot := SaveService.snapshot()
	assert_eq(GameLocale.text(str(config.name)),"Mio Amamiya")
	assert_eq(DataRegistry.get_entry("characters","amamiya_mio"),config)
	assert_eq(SaveService.snapshot(),snapshot)
	GameLocale.set_language("zh")
	assert_eq(GameLocale.text("角色培养"),"角色培养")
	GameLocale.set_language("invalid")
	assert_eq(GameLocale.language,"zh")

func test_skills_resources_stages_and_equipment_have_english() -> void:
	var cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
	for domain: String in ["skills","characters","currencies","equipment","mementos","upgrades","stages","enemies"]:
		for id: String in DataRegistry.get_ids(domain):
			var entry := DataRegistry.get_entry(domain,id)
			for field: String in ["name","description","uiDescription","flavorText","stageName","briefing"]:
				assert_null(cjk.search(GameLocale.text(str(entry.get(field,"")))),domain+"/"+id+"/"+field)
