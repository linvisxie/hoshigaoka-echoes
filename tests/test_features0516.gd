extends GutTest

const Story = preload("res://scenes/story/story.gd")
const BOW := "equip_ch1_1_2_fine_weapon"
const ACCESSORY := "equip_ch1_1_6_heal_accessory"
var saved: Dictionary
var locale: String
var motion_level: int

func before_each() -> void:
	saved = SaveService._current.duplicate(true)
	locale = GameLocale.language
	motion_level = GameSkin.motion_level
	SaveService._current = SaveService.build_default_save()

func after_each() -> void:
	SaveService._current = saved
	GameLocale.set_language(locale)
	GameSkin.motion_level = motion_level

func _item(id: String,instance_id: String,owner: String = "",level: int = 0) -> Dictionary:
	var item := EquipmentService.build_instance(id,instance_id)
	item.boundCharacterId = owner
	item.enhanceLevel = level
	return item

func _seed(items: Array,characters: Dictionary) -> Dictionary:
	var save := SaveService.build_default_save()
	save.inventory[EquipmentService.ITEMS_KEY] = items
	save.characters = characters
	save.currencies = {"school_coin":5000,"equipment_part":50}
	return save

func test_swap_preview_matches_real_equip_and_preserves_original() -> void:
	var save := _seed([_item(BOW,"new"),_item(BOW,"old","kamiya_yuma",3)],{"kamiya_yuma":{"equipment":{"WEAPON":"old"}}})
	SaveService._current = save
	var before := save.duplicate(true)
	var preview := EquipmentService.preview_operation(save,"new","equip","kamiya_yuma")
	assert_eq(save,before,"Preview must not mutate the original save")
	assert_lt(preview.changes.kamiya_yuma.after.attack,preview.changes.kamiya_yuma.before.attack,"Replacing an enhanced bow exposes the loss")
	assert_true(EquipmentService.equip("kamiya_yuma","new").ok)
	assert_eq(preview.changes.kamiya_yuma.after,EquipmentService.bonuses_for_character(SaveService.get_current(),"kamiya_yuma"),"Preview matches domain operation")

func test_transfer_preview_exposes_both_characters() -> void:
	var save := _seed([_item(ACCESSORY,"transfer","amamiya_mio",2)],{"amamiya_mio":{"equipment":{"ACCESSORY":"transfer"}}})
	var original := save.duplicate(true)
	var preview := EquipmentService.preview_operation(save,"transfer","equip","kamiya_yuma")
	assert_true(preview.changes.has("amamiya_mio"))
	assert_true(preview.changes.has("kamiya_yuma"))
	assert_eq(preview.changes.amamiya_mio.after,{})
	assert_eq(save,original)

func test_enhancement_preview_matches_actual_cost_and_stats() -> void:
	var save := _seed([_item(BOW,"bow","kamiya_yuma")],{"kamiya_yuma":{"equipment":{"WEAPON":"bow"}}})
	SaveService._current = save
	var before := save.duplicate(true)
	var preview := EquipmentService.preview_operation(save,"bow","enhance")
	assert_eq(save,before)
	assert_true(preview.affordable)
	assert_true(EquipmentService.enhance("bow").ok)
	for currency: String in preview.remaining: assert_eq(int(SaveService.get_current().currencies[currency]),int(preview.remaining[currency]))
	assert_eq(preview.changes.kamiya_yuma.after,EquipmentService.bonuses_for_character(SaveService.get_current(),"kamiya_yuma"))

func test_insufficient_cost_and_invalid_operations_are_not_actionable() -> void:
	var save := _seed([_item(BOW,"bow")],{})
	save.currencies = {}
	assert_false(EquipmentService.preview_operation(save,"bow","enhance").affordable)
	assert_eq(EquipmentService.preview_operation(save,"bow","equip","amamiya_mio"),{})
	assert_eq(EquipmentService.preview_operation(save,"bow","unequip"),{})
	assert_eq(EquipmentService.preview_operation(save,"missing","enhance"),{})

func test_auto_reading_dwell_adapts_to_length_and_setting() -> void:
	assert_almost_eq(Story.reading_delay("短句",2.5,false),2.5,.01)
	assert_gt(Story.reading_delay("长".repeat(100),2.5,false),2.5)
	assert_gt(Story.reading_delay("a ".repeat(60),2.5,true),2.5)
	assert_gt(Story.reading_delay("短句",5,false),Story.reading_delay("短句",1,false))
	assert_lte(Story.reading_delay("a ".repeat(10000),6,true),12.0)

func test_motion_strength_options_do_not_change_transition_code() -> void:
	GameSkin.motion_level = 0
	assert_eq(GameSkin.motion_factor(),0.0)
	GameSkin.motion_level = 1
	assert_eq(GameSkin.motion_factor(),0.5)
	GameSkin.motion_level = 2
	assert_eq(GameSkin.motion_factor(),1.0)

func test_insufficient_enhancement_shows_shortfall_without_negative_balances() -> void:
	var save := _seed([_item(BOW,"bow","kamiya_yuma",4)],{"kamiya_yuma":{"equipment":{"WEAPON":"bow"}}})
	save.currencies = {"school_coin":1340,"equipment_part":0}
	var original := save.duplicate(true)
	var preview := EquipmentService.preview_operation(save,"bow","enhance")
	assert_false(preview.affordable)
	assert_eq(preview.available,{"school_coin":1340,"equipment_part":0})
	assert_eq(preview.remaining,preview.available,"A rejected operation spends neither currency")
	assert_eq(preview.shortfall,{"school_coin":0,"equipment_part":2})
	assert_eq(save,original)
	SaveService._current = save
	assert_false(EquipmentService.enhance("bow").ok)
	assert_eq(SaveService.get_current(),original,"Domain refusal preserves all resources")

func test_result_equipment_cards_follow_this_settlement_only() -> void:
	var cfg := DataRegistry.get_entry("stages","1-2")
	var first := StageRewardService.settle(cfg,true,false)
	assert_true(first.ok)
	var summary := {"ok":first.ok,"pendingRegistered":first.pending_registered}
	var before := SaveService.snapshot()
	var items := BattleOverlays.equipment_rewards(summary)
	assert_eq(items.size(),1)
	assert_eq(items[0].id,BOW)
	assert_eq(items[0].count,1)
	assert_eq(items[0].icon,EquipmentService.slot_icon("WEAPON"))
	assert_eq(SaveService.snapshot(),before,"Rendering must not fulfill or duplicate equipment")
	var repeat := StageRewardService.settle(cfg,true,false)
	assert_true(repeat.ok)
	assert_eq(BattleOverlays.equipment_rewards({"ok":true,"pendingRegistered":repeat.pending_registered}),[],"A repeat victory must not repeat the pending first-clear item")
	assert_eq(BattleOverlays.equipment_rewards({"ok":false,"pendingRegistered":first.pending_registered}),[],"A failed transaction must not announce an award")
	assert_eq(BattleOverlays.equipment_rewards({"ok":true}),[],"Old pending items are not rewards from this run")

func test_result_memento_card_uses_the_actual_template() -> void:
	var cfg := DataRegistry.get_entry("stages","1-10")
	var result := StageRewardService.settle(cfg,true,false)
	assert_true(result.ok)
	var summary := {"ok":true,"pendingRegistered":result.pending_registered}
	var items := BattleOverlays.equipment_rewards(summary)
	assert_eq(items.size(),1)
	assert_eq(items[0].id,"memento_ch1_boss_cleared")
	assert_eq(items[0].icon,EquipmentService.slot_icon("MEMENTO"))
	summary.pendingRegistered.append(result.pending_registered[0])
	assert_eq(BattleOverlays.equipment_rewards(summary)[0].count,1,"Duplicate tokens must not duplicate a visible reward")
