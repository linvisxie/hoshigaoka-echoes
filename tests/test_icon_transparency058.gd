extends GutTest

func test_shared_ui_icons_remove_only_the_outer_matte() -> void:
	for size: int in [32,64]:
		for name: String in ["icon_school_coin","icon_study_record","icon_memento","icon_rift_shard","icon_material","icon_heal","icon_attack_up","icon_defense_up","icon_settings"]:
			var path := "res://assets/art/ui/icons/%s_%d.png" % [name,size]
			var source := ArtRegistry.load_texture(path)
			assert_not_null(source,name)
			if source == null: continue
			var original := source.get_image()
			var texture := ArtRegistry.icon(name,size)
			assert_same(texture,ArtRegistry.icon(name,size),"Transparent result is cached")
			var actual := texture.get_image()
			assert_eq(actual.get_size(),original.get_size())
			var corner := int(size/16)
			assert_eq(actual.get_pixel(corner,corner).a,0.0,"Outer opaque export matte removed: "+name)
			var unchanged := true
			for y: int in range(original.get_height()):
				for x: int in range(original.get_width()):
					var before := original.get_pixel(x,y)
					if not (before.r8 == 20 and before.g8 == 18 and before.b8 == 42):
						if actual.get_pixel(x,y) != before: unchanged = false
			assert_true(unchanged,"All non-matte RGBA pixels retained: "+name)

func test_missing_icon_still_returns_null() -> void:
	assert_null(ArtRegistry.icon("missing_icon058",64))
