extends GutTest

func before_all() -> void:
	if not DataRegistry.is_loaded(): DataRegistry.load_all()

func after_each() -> void:
	SaveService._current = {}

func test_bow_rejects_sword_user_without_mutating_save() -> void:
	var save := SaveService.build_default_save()
	save.inventory = {"equipmentInstances":[EquipmentService.build_instance("equip_ch1_1_2_fine_weapon","bow")]}
	SaveService._current = save
	var before := SaveService.snapshot()
	assert_false(EquipmentService.can_equip("equip_ch1_1_2_fine_weapon","amamiya_mio"))
	assert_false(EquipmentService.can_equip("equip_ch1_1_2_fine_weapon","fujiwara_rin"))
	assert_true(EquipmentService.can_equip("equip_ch1_1_2_fine_weapon","kamiya_yuma"))
	assert_false(EquipmentService.equip("amamiya_mio","bow").ok)
	assert_eq(SaveService.get_current(),before)
	assert_true(EquipmentService.equip("kamiya_yuma","bow").ok)
	assert_true(EquipmentService.bonuses_for_character(SaveService.get_current(),"kamiya_yuma").has("attack"))

func test_legacy_wrong_weapon_returns_intact_and_accessories_stay() -> void:
	var save := SaveService.build_default_save()
	var bow := EquipmentService.build_instance("equip_ch1_1_2_fine_weapon","bow")
	bow.enhanceLevel=10
	bow.boundCharacterId="amamiya_mio"
	var accessory := EquipmentService.build_instance("equip_ch1_1_9_rare_accessory","accessory")
	accessory.boundCharacterId="amamiya_mio"
	save.inventory={"equipmentInstances":[bow,accessory]}
	save.characters={"amamiya_mio":{"equipment":{"WEAPON":"bow","ACCESSORY":"accessory"}}}
	assert_false(EquipmentService.bonuses_for_character(save,"amamiya_mio").has("attack"),"legacy illegal gear never grants combat stats")
	assert_eq(EquipmentService.return_incompatible_to_inventory(save),1)
	assert_eq(EquipmentService.return_incompatible_to_inventory(save),0,"idempotent")
	assert_eq(bow.enhanceLevel,10)
	assert_eq(bow.boundCharacterId,"")
	assert_eq(EquipmentService._instances_of(save).size(),2)
	assert_eq(EquipmentService.equipped_of(save,"amamiya_mio"),{"ACCESSORY":"accessory"})
	assert_eq(accessory.boundCharacterId,"amamiya_mio")

func test_three_routes_are_horizontal_and_cells_keep_depth_shear() -> void:
	var board: Node2D=load("res://scenes/battle/battle_scene.tscn").instantiate()
	board.grid=BattleGrid.from_layout(DataRegistry.get_layout())
	board._viewport_size=Vector2(1920,1080)
	board._update_render_scale()
	board._update_layout()
	for lane: int in range(3):
		var first: Vector2=board._cell_screen_pos(0,lane)
		for col: int in range(6):
			var p: Vector2=board._cell_screen_pos(col,lane)
			assert_almost_eq(p.y,first.y,.001)
			assert_eq(board._screen_to_cell(p),{"column":col,"lane":lane})
		var corners: PackedVector2Array=board._cell_polygon(2,lane)
		assert_almost_eq(corners[0].y,corners[1].y,.001)
		assert_lt(corners[3].x,corners[0].x)
	board.free()
