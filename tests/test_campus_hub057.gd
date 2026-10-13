extends GutTest
var original: Dictionary

func before_each() -> void:
	assert_true(TestDataGuard.is_isolated(OS.get_user_data_dir()))
	DataRegistry.load_all()
	original=SaveService.snapshot()
	SaveService.new_game()

func after_each() -> void:
	SaveService.restore(original)
	SaveService.commit(original)

func test_locations_do_not_expose_locked_character_stories() -> void:
	var home=load("res://scenes/home/home.gd").new()
	autofree(home)
	assert_true(home._location_events("观测会活动室").is_empty())
	assert_true(home._location_events("弓道场").is_empty())
	assert_true(home._location_events("保健室").is_empty())
	assert_true(home._roaming_locations().is_empty(),"No duplicate main-campus places in new-save roam")
	StageRewardService.settle(DataRegistry.get_entry("stages","1-1"),true,true)
	assert_eq(home._location_events("观测会活动室").size(),1)
	assert_true(home._has_unread("观测会活动室"))
	assert_true(home._location_events("保健室").is_empty())

func test_read_badges_and_extra_locations_follow_saved_story_progress() -> void:
	for i: int in range(1,11):
		StageRewardService.settle(DataRegistry.get_entry("stages","1-%d"%i),true,true)
	var save:=SaveService.snapshot()
	save.story.flags["done:ch1_1_5_after"]=true
	save.story.flags["done:ch1_1_10_after"]=true
	SaveService.commit(save)
	var home=load("res://scenes/home/home.gd").new()
	autofree(home)
	assert_eq(home._location_events("科学部").size(),1)
	assert_eq(home._location_events("轻音部").size(),1)
	assert_eq(home._roaming_locations(),["科学部","轻音部","旧校舍"],"Only unlocked places absent from the main courtyard appear in roam")
	assert_true(home._has_unread("保健室"))
	save=SaveService.snapshot()
	save.story.flags["done:hub_ch1_yui"]=true
	SaveService.commit(save)
	var before:=SaveService.snapshot()
	assert_false(home._has_unread("保健室"))
	assert_eq(home._location_events("保健室").size(),1,"Read story remains replayable")
	assert_eq(SaveService.snapshot(),before,"Queries never grant currency or change stage progress")
