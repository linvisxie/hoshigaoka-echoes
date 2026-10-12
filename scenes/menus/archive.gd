extends CampusScreen

static var chapter_open := false

func _ready() -> void:
	super._ready()
	set_background("bg_env_classroom_dusk")
	page_heading("剧情档案", "已读记录 / 按调查顺序收藏 · 回看不重复发放奖励")
	var ids := DataRegistry.get_ids("story")
	ids.sort_custom(func(a: Variant,b: Variant) -> bool: return _story_order(str(a)) < _story_order(str(b)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(85,210)
	scroll.size = Vector2(1750,710)
	canvas.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",16)
	scroll.add_child(list)
	for raw: Variant in ids:
		var sid := str(raw)
		if sid.begins_with("prologue") and CampaignFlow.done(sid):
			var title := str(DataRegistry.get_entry("story",sid).get("title","序章 · 转学之日"))
			_entry(list,title if title.begins_with("序章") else "序章 · " + title,func() -> void: _replay(sid))
	var chapter_ids: Array = ids.filter(func(raw: Variant) -> bool: return str(raw).begins_with("ch1_") and CampaignFlow.done(str(raw)))
	_entry(list,("▾ " if chapter_open else "▸ ") + "第一章 · 新学期的残响  /  %d 篇已读" % chapter_ids.size(),func() -> void:
		chapter_open = not chapter_open
		SceneRouter.go_to("archive"))
	if chapter_open:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation",16)
		grid.add_theme_constant_override("v_separation",16)
		list.add_child(grid)
		for raw: Variant in chapter_ids:
			var sid := str(raw)
			var tile := button_at(str(DataRegistry.get_entry("story",sid).get("title",sid)),Rect2(),func() -> void: _replay(sid))
			tile.reparent(grid)
			tile.custom_minimum_size = Vector2(414,100)
			tile.add_theme_font_size_override("font_size",23)
			tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button_at("返回校园",Rect2(100,965,370,75),func() -> void: SceneRouter.go_to("home"))

func _story_order(sid: String) -> int:
	if sid.begins_with("prologue"): return -1
	var parts := sid.split("_")
	if parts.size() < 4: return 9999
	return int(parts[2])*2 + (1 if parts[3] == "after" else 0)

func _entry(list: VBoxContainer,title: String,action: Callable) -> void:
	var button := button_at(title,Rect2(),action)
	button.reparent(list)
	button.custom_minimum_size = Vector2(1690,76)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

func _replay(sid: String) -> void:
	CampaignFlow.replay_story_id = sid
	SceneRouter.go_to("story")
