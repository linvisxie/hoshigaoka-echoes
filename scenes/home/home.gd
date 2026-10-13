extends CampusScreen

var campus_panel: Panel
var exit_panel: Panel

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
		label_at("那些声音，已被听见。",Rect2(110,465,540,85),40)
		var note := label_at("第一章十次调查已收入学生手册。\n千夏正式加入观测会，可参与后半章重访。\n文化祭的故事，留待下一次放课后。",Rect2(110,600,510,150),28,MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button_at("重温已开放关卡",Rect2(110,790,540,85),func() -> void: SceneRouter.go_to("stage_select"),true).grab_focus()
	panel(Rect2(1260,300,570,625),BLUE)
	label_at("学生手册",Rect2(1300,330,480,60),36,GOLD)
	button_at("角色培养 · 装备",Rect2(1300,430,490,90),func() -> void: SceneRouter.go_to("character"))
	button_at("关卡记录",Rect2(1300,545,490,90),func() -> void: SceneRouter.go_to("stage_select"))
	button_at("剧情档案",Rect2(1300,660,490,90),func() -> void: SceneRouter.go_to("archive"))
	button_at("设置",Rect2(1300,795,230,75),func() -> void: SceneRouter.go_to("settings"))
	button_at("校园菜单",Rect2(1550,795,240,75),_show_menu)
	var unread := CampusHub.unread_count()
	button_at("校园地点与事件" + ("  ·  %d 新" % unread if unread>0 else ""),Rect2(740,915,440,64),_show_campus,true).add_theme_font_size_override("font_size",25)
	label_at("留意那些还没有被听见的声音。",Rect2(85,985,1000,50),26,GOLD)
	fade_in_content()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if campus_panel != null and campus_panel.visible: campus_panel.hide()
		elif is_instance_valid(exit_panel) and exit_panel.visible: exit_panel.hide()
		else: _show_menu()
		get_viewport().set_input_as_handled()

func _in_panel(control: Control, parent: Panel, position: Vector2) -> void:
	control.reparent(parent)
	control.position = position

func _show_campus() -> void:
	if campus_panel != null:
		campus_panel.show()
		return
	campus_panel = modal_panel(Rect2(210,190,1500,730))
	_in_panel(label_at("校园地点 · 放课后的声音",Rect2(0,0,1300,65),36,GOLD),campus_panel,Vector2(45,25))
	_in_panel(label_at("主线与地点共用调查进度；同伴交谈和环境记录可以稍后再读。",Rect2(0,0,1320,40),23,MUTED),campus_panel,Vector2(45,95))
	var entries: Array[Dictionary] = []
	var next := CampaignFlow.next_stage()
	if not next.is_empty():
		var stage := DataRegistry.get_entry("stages",next)
		entries.append({"title":"当前调查  ·  "+next,"subtitle":str(stage.get("stageName",next)),"action":func() -> void: CampaignFlow.open_stage(next)})
	for event: Dictionary in CampusHub.events():
		var sid := str(event.storyId)
		entries.append({"title":str(event.get("hubLocation","校园"))+ ("  ·  已读" if CampaignFlow.done(sid) else "  ·  新记录"),"subtitle":str(event.title),"action":func() -> void: CampusHub.visit(sid)})
	for i: int in range(entries.size()):
		var entry := entries[i]
		var tile := button_at(str(entry.title)+"\n"+str(entry.subtitle),Rect2(0,0,450,103),entry.action,i==0 and not next.is_empty())
		tile.add_theme_font_size_override("font_size",23)
		_in_panel(tile,campus_panel,Vector2(45+(i%3)*480,155+(i/3)*122))
	if entries.is_empty():
		_in_panel(label_at("完成一次调查后，新的校园记录将在这里出现。",Rect2(0,0,1300,80),28,BLUE),campus_panel,Vector2(45,180))
	_in_panel(button_at("返回校园  Esc",Rect2(0,0,300,60),func() -> void: campus_panel.hide()),campus_panel,Vector2(1155,640))

func _show_menu() -> void:
	if is_instance_valid(exit_panel): exit_panel.queue_free()
	exit_panel = modal_panel(Rect2(620,245,680,590))
	_in_panel(label_at("校园菜单",Rect2(0,0,520,60),36,GOLD),exit_panel,Vector2(80,40))
	_in_panel(label_at("进度已自动保存。",Rect2(0,0,520,45),25,MUTED),exit_panel,Vector2(80,110))
	for spec: Array in [["继续留在校园",190,func() -> void: exit_panel.hide()],["返回标题",290,func() -> void: SceneRouter.go_to("title")],["退出游戏…",390,_confirm_exit]]:
		_in_panel(button_at(str(spec[0]),Rect2(0,0,520,75),spec[2]),exit_panel,Vector2(80,int(spec[1])))

func _confirm_exit() -> void:
	exit_panel.hide()
	var confirm := modal_panel(Rect2(620,340,680,390))
	_in_panel(label_at("结束今天的观测？",Rect2(0,0,520,70),34,GOLD),confirm,Vector2(80,45))
	_in_panel(label_at("已保存的调查和培养进度会保留。",Rect2(0,0,560,50),24,MUTED),confirm,Vector2(60,125))
	_in_panel(button_at("取消",Rect2(0,0,250,75),func() -> void: confirm.queue_free()),confirm,Vector2(60,250))
	_in_panel(button_at("退出游戏",Rect2(0,0,250,75),App.request_quit,true),confirm,Vector2(370,250))
	exit_panel = confirm
