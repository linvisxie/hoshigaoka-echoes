extends CampusScreen

var party: Array = []
var party_labels: Array[Label] = []

func _ready() -> void:
	super._ready()
	var sid := str(CampaignFlow.state().get("pending_stage_id", "1-1"))
	var cfg := DataRegistry.get_entry("stages", sid)
	set_background(ArtRegistry.STAGE_ENV.get(sid, ArtRegistry.DEFAULT_ENV))
	page_heading("%s  ·  %s" % [sid, cfg.get("stageName", "关卡情报")], "残响时刻即将开始  /  部署确认")
	panel(Rect2(80, 210, 850, 720))
	label_at("观测记录", Rect2(120, 245, 740, 65), 36, GOLD)
	var note := label_at(str(cfg.get("briefing", "守住核心，清除所有残响体。")), Rect2(120, 340, 740, 140), 30)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var names: Array[String] = []
	for spawn: Dictionary in cfg.get("enemySpawnTimeline", []):
		var enemy := DataRegistry.get_entry("enemies", str(spawn.get("enemy", "")))
		var enemy_name := str(enemy.get("name", spawn.get("enemy", "")))
		if not names.has(enemy_name):
			names.append(enemy_name)
	var enemy_label := label_at("残响体\n%s" % " · ".join(names), Rect2(120, 540, 740, 145), 28, MUTED)
	enemy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_at("防线 %d   /   初始 AP %d   /   3 条路线" % [int(cfg.get("coreHp", 3)), int(cfg.get("startingAp", 10))], Rect2(120, 760, 740, 60), 27, BLUE)
	panel(Rect2(990, 210, 850, 720))
	label_at("本关出战角色", Rect2(1030, 245, 760, 65), 36, GOLD)
	var roster: Array = cfg.get("availableCharacters", [])
	party = roster.duplicate()
	var saved: Array = CampaignFlow.state().get("party_order", [])
	var unique_saved: Dictionary = {}
	for cid: Variant in saved:
		unique_saved[cid] = true
	if saved.size() == party.size() and unique_saved.size() == party.size() and saved.all(func(cid: Variant) -> bool: return party.has(cid)):
		party = saved.duplicate()
	for i: int in range(roster.size()):
		var cid := str(roster[i])
		var char_cfg := DataRegistry.get_entry("characters", cid)
		texture_at(ArtRegistry.character_portrait(cid, 256), Rect2(1040 + i * 240, 365, 210, 250))
		label_at(str(char_cfg.get("name", cid)), Rect2(1040 + i * 240, 645, 230, 60), 30)
	label_at("出战顺序  ·  点击名字调整角色卡位置", Rect2(1030, 745, 760, 50), 25, MUTED)
	for i: int in range(party.size()):
		button_at(str(DataRegistry.get_entry("characters", str(party[i])).get("name", party[i])), Rect2(1040 + i * 240, 815, 210, 65), _rotate_party, false)
	button_at("返回校园", Rect2(90, 970, 380, 75), func() -> void: SceneRouter.go_to("home"))
	button_at("开始战斗   →", Rect2(1390, 970, 450, 75), func() -> void: CampaignFlow.launch_battle(), true).grab_focus()

func _rotate_party() -> void:
	if party.size() < 2:
		return
	party.append(party.pop_front())
	if CampaignFlow.persist({"party_order": party}):
		SceneRouter.go_to("briefing")
	else:
		show_error("阵容顺序保存失败。")
