extends CampusScreen

func _ready() -> void:
	super._ready()
	set_background("bg_env_classroom_dusk")
	page_heading("剧情档案", "已读记录  /  回看不会重复改变剧情或发放奖励")
	var ids := DataRegistry.get_ids("story")
	ids.sort()
	var row := 0
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(85,210)
	scroll.size = Vector2(1750,710)
	canvas.add_child(scroll)
	var list := Control.new()
	list.custom_minimum_size = Vector2(1720,0)
	scroll.add_child(list)
	for raw: Variant in ids:
		var sid := str(raw)
		if not CampaignFlow.done(sid):
			continue
		var data := DataRegistry.get_entry("story", sid)
		var col := row % 2
		var y := int(row / 2) * 110
		var entry := button_at(str(data.get("title", sid)), Rect2(15 + col * 855, y, 820, 85), func() -> void:
			CampaignFlow.replay_story_id = sid
			SceneRouter.go_to("story"))
		canvas.remove_child(entry)
		list.add_child(entry)
		row += 1
	list.custom_minimum_size.y = ceilf(float(row)/2)*110
	if row == 0:
		label_at("还没有完成的剧情记录。", Rect2(110, 280, 1400, 70), 32, MUTED)
	button_at("返回校园", Rect2(100, 965, 370, 75), func() -> void: SceneRouter.go_to("home"))
