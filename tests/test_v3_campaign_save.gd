extends GutTest

func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()

func before_each() -> void:
	assert_true(TestDataGuard.is_isolated(OS.get_user_data_dir()))
	SaveService.new_game("流程回归")
	CampaignFlow.persist({"campaign_active": true, "mode": "pre_battle", "pending_stage_id": "1-1"})

func test_reward_and_required_story_survive_reload_together() -> void:
	var cfg := DataRegistry.get_entry("stages", "1-1")
	var result := StageRewardService.settle(cfg, true)
	assert_true(result.ok)
	var coins := int(SaveService.get_current().currencies.school_coin)
	assert_true(SaveService.load_game())
	assert_eq(str(CampaignFlow.state().pending_story_after), "ch1_1_1_after")
	assert_eq(str(CampaignFlow.state().mode), "post_battle")
	assert_eq(int(SaveService.get_current().currencies.school_coin), coins)
	assert_true(StageRewardService.is_first_cleared("1-1"))

func test_failed_battle_does_not_schedule_after_story_or_rewards() -> void:
	var before := SaveService.snapshot()
	assert_true(StageRewardService.settle(DataRegistry.get_entry("stages", "1-1"), false).ok)
	assert_eq(SaveService.get_current(), before)

func test_read_node_is_idempotent_and_resume_node_persists() -> void:
	CampaignFlow.persist({"mode": "story", "current_story_id": "prologue_transfer"})
	assert_true(CampaignFlow.record_node("prologue_transfer", 4))
	assert_true(CampaignFlow.record_node("prologue_transfer", 4))
	assert_true(SaveService.load_game())
	assert_eq(str(CampaignFlow.state().current_story_node), "4")
	var reads: Array = SaveService.get_current().story.readNodes
	assert_eq(reads.count("prologue_transfer:4"), 1)

func test_completed_after_story_is_not_scheduled_on_replay() -> void:
	var save := SaveService.snapshot()
	save.story.flags["done:ch1_1_1_after"] = true
	assert_true(SaveService.commit(save))
	assert_true(StageRewardService.settle(DataRegistry.get_entry("stages", "1-1"), true).ok)
	assert_eq(str(CampaignFlow.state().get("pending_story_after", "")), "")
