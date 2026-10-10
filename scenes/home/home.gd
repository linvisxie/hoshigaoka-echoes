extends CampusScreen

func _ready() -> void:
	super._ready()
	set_background("bg_title_gate")
	AudioService.play_music("after_school")
	var profile: Dictionary = SaveService.get_current().get("profile", {})
	var player := str(profile.get("playerName", "转校生"))
	page_heading("私立星丘高等学校", "第一章 · 新学期的残响     /     放学后     /     %s 的学生手册" % player)
	panel(Rect2(70, 200, 760, 760))
	label_at("放课后观测记录", Rect2(110, 230, 650, 70), 38, GOLD)
	var next := CampaignFlow.next_stage()
	if not next.is_empty():
		var cfg := DataRegistry.get_entry("stages", next)
		label_at("下一主线  %s" % next, Rect2(110, 330, 650, 45), 26, BLUE)
		label_at(str(cfg.get("stageName", next)), Rect2(110, 385, 650, 80), 42)
		var note := label_at(str(cfg.get("briefing", "调查教学楼的异常。")), Rect2(110, 480, 640, 150), 28, MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button_at("继续主线   →", Rect2(110, 720, 640, 86), func() -> void: CampaignFlow.open_stage(next), true).grab_focus()
	else:
		label_at("前五关调查记录已完成", Rect2(110, 350, 660, 80), 38)
		var note := label_at("观测会已经成立。下一步是保健室的调查。\n本构建仅交付前五关，后续关卡尚未完成。", Rect2(110, 470, 640, 170), 28, MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button_at("重温已开放关卡", Rect2(110, 720, 640, 86), func() -> void: SceneRouter.go_to("stage_select"), true)
	label_at("留意那些还没有被听见的声音。", Rect2(110, 855, 650, 45), 24, MUTED)
	panel(Rect2(1080, 570, 750, 390))
	label_at("学生手册", Rect2(1120, 596, 650, 60), 34, GOLD)
	button_at("角色培养 · 装备", Rect2(1120, 680, 650, 72), func() -> void: SceneRouter.go_to("character"))
	button_at("关卡记录", Rect2(1120, 770, 310, 72), func() -> void: SceneRouter.go_to("stage_select"))
	button_at("剧情档案", Rect2(1450, 770, 320, 72), func() -> void: SceneRouter.go_to("archive"))
	button_at("设置", Rect2(1120, 860, 310, 66), func() -> void: SceneRouter.go_to("settings"))
	button_at("返回标题", Rect2(1450, 860, 320, 66), func() -> void: SceneRouter.go_to("title"))
	label_at("✦  教学楼 · 主线调查", Rect2(1100, 240, 700, 65), 32, GOLD)
	if not next.is_empty():
		button_at("前往异常发生地点", Rect2(1120, 330, 590, 76), func() -> void: CampaignFlow.open_stage(next))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneRouter.go_to("title")
