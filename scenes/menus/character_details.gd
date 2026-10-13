extends CampusScreen

func _ready() -> void:
	super._ready()
	var cid := CampaignFlow.inspected_character_id
	var cfg := DataRegistry.get_entry("characters", cid)
	set_background("bg_env_corridor_battle")
	page_heading(str(cfg.get("name", "角色")), "%s  /  %s" % [cfg.get("grade", ""), cfg.get("club", "")])
	texture_at(ArtRegistry.character_story(cid), Rect2(80, 170, 730, 780))
	panel(Rect2(850, 210, 990, 710))
	label_at("战斗记录", Rect2(900, 245, 880, 70), 38, GOLD)
	var text := "部署费用 %d AP    /    再部署 %.0f 秒\n" % [int(cfg.get("deployCost", 0)), float(cfg.get("redeployTime", 0))]
	text += "攻击间隔 %.1f 秒    /    阻挡 %d\n" % [float(cfg.get("attackInterval", 0)), int(cfg.get("blockCount", 0))]
	if cid == "fujiwara_rin":
		text = "部署费用 %d AP    /    再部署 %.0f 秒\n全队资源支援 · 无普通攻击、无阻挡\n" % [int(cfg.get("deployCost",0)),float(cfg.get("redeployTime",0))]
	text += "\n主动技能\n"
	for skill: Dictionary in DataRegistry.get_domain("skills").get("skills", []):
		if cfg.get("skillIds", []).has(str(skill.get("id", ""))):
			text += "%s    冷却 %.0f 秒\n%s\n" % [skill.get("name", ""), float(skill.get("cooldownSeconds", 0)), skill.get("description", "")]
	text += "\n天赋\n"
	for talent: Dictionary in DataRegistry.get_domain("skills").get("talents", []):
		if cfg.get("talentIds", []).has(str(talent.get("id", ""))):
			text += "%s\n%s\n" % [talent.get("name", ""), talent.get("description", "")]
	var description := RichTextLabel.new()
	description.text = GameLocale.text(text)
	description.position = Vector2(900,345)
	description.size = Vector2(880,540)
	description.add_theme_font_size_override("normal_font_size",26)
	description.scroll_active = true
	canvas.add_child(description)
	button_at("返回培养", Rect2(90, 965, 360, 75), func() -> void: SceneRouter.go_to("character"))
	button_at("剧情档案", Rect2(1430, 965, 410, 75), func() -> void: SceneRouter.go_to("archive"), true)
