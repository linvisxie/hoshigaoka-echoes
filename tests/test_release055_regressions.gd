extends GutTest

class RejectingSave extends "res://scripts/save/save_service.gd":
	var reject_main := false
	func _write_json(path: String, data: Variant) -> bool:
		if reject_main and path == SAVE_PATH:
			return false
		return super._write_json(path, data)

func test_failed_new_save_preserves_old_progress_and_generation() -> void:
	var svc := RejectingSave.new()
	add_child_autofree(svc)
	assert_true(svc.new_game("旧同学"))
	var before: Dictionary = svc.snapshot()
	var generation: int = svc.save_generation()
	svc.reject_main = true
	assert_false(svc.new_game("新同学"))
	assert_push_error("主存档写入失败")
	assert_eq(svc.snapshot(), before)
	assert_eq(svc.save_generation(), generation)
	assert_eq(svc.get_last_persisted(), before)

func before_each() -> void:
	assert_true(TestDataGuard.is_isolated(OS.get_user_data_dir()))
	DataRegistry.load_all()
	SaveService.new_game()

func test_new_game_invalidates_cached_growth_and_combat_stats() -> void:
	App.ensure_growth()
	App.growth.grant({"study_record_archive": 5})
	assert_true(App.growth.level_up_with_records("amamiya_mio", "study_record_archive", 2).ok)
	assert_true(App.growth.commit())
	var generation := SaveService.save_generation()
	assert_true(SaveService.new_game("新同学"))
	assert_gt(SaveService.save_generation(), generation)
	assert_true(App.ensure_growth())
	assert_eq(App.growth.get_progress("amamiya_mio").level, 1)
	assert_eq(App.growth.get_progress("amamiya_mio").exp, 0)
	assert_eq(App.growth.get_progress("amamiya_mio").breakthrough, 0)
	assert_eq(int(App.level_stats_table()["amamiya_mio"].attack), int(DataRegistry.get_entry("characters", "amamiya_mio").baseStats.attack))
	assert_true(App.growth.commit())
	assert_true(SaveService.load_game())
	App.ensure_growth()
	assert_eq(App.growth.get_progress("amamiya_mio").level, 1)
	assert_eq(App.growth.get_currency("study_record_archive"), 0)

func test_old_service_reference_cannot_restore_old_levels() -> void:
	var old := CharacterGrowthService.new()
	old.setup()
	old.grant({"study_record_archive": 5})
	old.level_up_with_records("amamiya_mio", "study_record_archive", 2)
	assert_true(old.commit())
	assert_true(SaveService.new_game())
	assert_true(old.commit())
	assert_eq(int(SaveService.get_current().progression.characters.amamiya_mio.level), 1)
	assert_eq(old.get_progress("amamiya_mio").level, 1)

func test_unused_whole_records_are_retained_exactly_once() -> void:
	var svc := CharacterGrowthService.new()
	svc.setup()
	svc.grant({"study_record_archive": 10})
	var result := svc.level_up_with_records("amamiya_mio", "study_record_archive", 10)
	assert_true(result.ok)
	assert_eq(int(result.levelAfter), 10)
	assert_eq(svc.get_currency("study_record_archive"), 8, "Only two books are needed; unused eight must not be added twice")
	assert_true(svc.commit())
	assert_true(SaveService.load_game())
	svc.setup()
	assert_eq(svc.get_currency("study_record_archive"), 8)
