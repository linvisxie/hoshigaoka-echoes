extends GutTest

func before_all() -> void:
	DataRegistry.load_all()

func before_each() -> void:
	assert_true(TestDataGuard.is_isolated(OS.get_user_data_dir()))
	SaveService.new_game("重试流程回归")
	CampaignFlow.persist({"campaign_active":true,"mode":"pre_battle","pending_stage_id":"1-1"})

func test_failure_after_settled_victory_preserves_unread_story_and_paid_rewards() -> void:
	assert_true(StageRewardService.settle(DataRegistry.get_entry("stages","1-1"),true).ok)
	var paid: Dictionary = JSON.parse_string(JSON.stringify(SaveService.snapshot()))
	assert_true(StageRewardService.settle(DataRegistry.get_entry("stages","1-1"),false).ok)
	assert_true(CampaignFlow.record_failed_attempt_return())
	assert_true(SaveService.load_game())
	assert_eq(str(CampaignFlow.state().pending_story_after),"ch1_1_1_after")
	assert_eq(str(CampaignFlow.state().mode),"post_battle")
	assert_eq(SaveService.snapshot().currencies,paid.currencies)
	assert_eq(SaveService.snapshot().stages,paid.stages)

func test_first_failure_does_not_unlock_story_or_next_stage() -> void:
	var before := SaveService.snapshot()
	assert_true(CampaignFlow.record_failed_attempt_return())
	assert_eq(str(CampaignFlow.state().pending_story_after),"")
	assert_eq(str(CampaignFlow.state().mode),"hub")
	assert_false(CampaignFlow.can_open_stage("1-2"))
	assert_eq(SaveService.snapshot().currencies,before.currencies)
	assert_eq(SaveService.snapshot().stages,before.stages)

func test_finished_or_unearned_story_is_not_rescheduled_by_failure() -> void:
	for finished: bool in [true,false]:
		var save := SaveService.snapshot()
		save.flow_state["pending_story_after"] = "ch1_1_1_after"
		save.flow_state["current_story_id"] = "ch1_1_1_after"
		save.story.flags["done:ch1_1_1_after"] = finished
		assert_true(SaveService.commit(save))
		assert_true(CampaignFlow.record_failed_attempt_return())
		assert_eq(str(CampaignFlow.state().pending_story_after),"")
