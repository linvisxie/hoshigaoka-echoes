extends GutTest

func before_all() -> void:
	DataRegistry.load_all()

func test_necklace_keeps_its_gold_art_with_transparent_surroundings() -> void:
	var texture := ArtRegistry.icon("icon_necklace",64)
	assert_not_null(texture)
	var image := texture.get_image()
	assert_eq(image.get_pixel(6,4).a,0.0,"Former background rectangle is transparent")
	assert_gt(image.get_pixel(32,45).a,.9,"Gold pendant remains visible")

func test_resource_description_uses_canonical_use_and_literary_text() -> void:
	for currency_id: String in ["school_coin","equipment_part"]:
		var tip := ResourceDescription.new()
		tip.set_currency(currency_id)
		var canonical := ResourceDescription.definition(currency_id)
		assert_eq(tip.body.text,str(canonical.uiDescription))
		assert_eq(tip.quote.text,str(canonical.flavorText))
		assert_false(tip.quote.text.is_empty())
		assert_lt(tip.quote.get_theme_font_size("font_size"),tip.body.get_theme_font_size("font_size"))
		tip.free()

func test_skin_resources_can_be_released_and_reloaded_without_font_change() -> void:
	var expected := GameSkin.serif().get_string_size("星丘残响",HORIZONTAL_ALIGNMENT_LEFT,-1,28)
	GameSkin.body_font()
	GameSkin.release_resources()
	assert_true(GameSkin._font_cache.is_empty())
	assert_true(GameSkin._glass_cache.is_empty())
	assert_eq(GameSkin.serif().get_string_size("星丘残响",HORIZONTAL_ALIGNMENT_LEFT,-1,28),expected)
