extends CampusScreen

func _ready() -> void:
	super._ready()
	set_background("bg_title_gate")
	AudioService.play_music("observation_club")
	var profile: Dictionary = SaveService.get_current().get("profile", {})
	var player := str(profile.get("playerName", "转校生"))
	page_heading("私立星丘高等学校", "第一章 · 新学期的残响     /     %s 的学生手册" % player)
	resource_chip("school_coin","icon_school_coin",Rect2(1230,190,280,64))
	resource_chip("equipment_part","icon_material",Rect2(1540,190,280,64))
	texture_at(ArtRegistry.load_texture("res://assets/art/characters/amamiya_mio/amamiya_mio_story.png"),Rect2(640,190,650,845))
	panel(Rect2(70,260,620,665),GOLD)
	label_at("放课后观测记录",Rect2(110,295,540,60),36,GOLD)
	label_at("MAIN STORY  /  第一章",Rect2(112,362,520,40),22,MUTED)
	var next := CampaignFlow.next_stage()
	if not next.is_empty():
		var cfg := DataRegistry.get_entry("stages",next)
		label_at("调查地点  %s" % next,Rect2(110,440,520,45),26,BLUE)
		label_at(str(cfg.get("stageName",next)),Rect2(110,493,520,80),44)
		var note := label_at(str(cfg.get("briefing","调查教学楼的异常。")),Rect2(110,600,510,150),28,MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button_at("继续主线   →",Rect2(110,790,540,85),func() -> void: CampaignFlow.open_stage(next),true).grab_focus()
	else:
		label_at("观测会，成立。",Rect2(110,465,540,85),44)
		var note := label_at("前五次调查已收入学生手册。\n凛已加入重访阵容，协助调度 AP。\n可在 1-3～1-5 重访时与她并肩调查。",Rect2(110,600,510,150),28,MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button_at("重温已开放关卡",Rect2(110,790,540,85),func() -> void: SceneRouter.go_to("stage_select"),true).grab_focus()
	panel(Rect2(1260,300,570,625),BLUE)
	label_at("学生手册",Rect2(1300,330,480,60),36,GOLD)
	button_at("角色培养 · 装备",Rect2(1300,430,490,90),func() -> void: SceneRouter.go_to("character"))
	button_at("关卡记录",Rect2(1300,545,490,90),func() -> void: SceneRouter.go_to("stage_select"))
	button_at("剧情档案",Rect2(1300,660,490,90),func() -> void: SceneRouter.go_to("archive"))
	button_at("设置",Rect2(1300,795,230,75),func() -> void: SceneRouter.go_to("settings"))
	button_at("返回标题",Rect2(1550,795,240,75),func() -> void: SceneRouter.go_to("title"))
	label_at("留意那些还没有被听见的声音。",Rect2(85,985,1000,50),26,GOLD)
	fade_in_content()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneRouter.go_to("title")
