extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.ensure_loaded()
	SceneRouter.go_to("character")
	await wait_ui()
	var growth := get_tree().current_scene
	var key := InputEventKey.new()
	key.keycode = KEY_6
	key.pressed = true
	get_viewport().push_input(key,true)
	await wait_ui()
	var cid: String = growth._selected_id
	check(growth._list_page==1,"select second-page character")
	await shot("growth_page2")
	var level_rect: Rect2
	var break_rect: Rect2
	var cycle_rect: Rect2
	var quick: Array[Rect2]=[]
	for b: Dictionary in growth._btn_rects:
		if b.action=="levelup":level_rect=b.rect
		if b.action=="breakthrough":break_rect=b.rect
		if b.action=="cycle_item":cycle_rect=b.rect
		if b.action=="preview":quick.append(b.rect)
	check(level_rect.size.is_equal_approx(growth._navigation[1].size),"upgrade matches skills button dimensions")
	check(break_rect.size.is_equal_approx(growth._navigation[2].size),"breakthrough matches equipment dimensions")
	check(is_equal_approx(cycle_rect.position.x,level_rect.position.x) and is_equal_approx(cycle_rect.end.x,level_rect.end.x),"study type aligns with upgrade edges")
	check(is_equal_approx(quick[0].position.x,break_rect.position.x) and is_equal_approx(quick[-1].end.x,break_rect.end.x),"quantity group aligns with breakthrough edges")
	check(find_button(growth,"装备背包")!=null,"backpack remains beside campus return")
	check(growth._page_previous.position.y-growth._card_rects[5].end.y>=20*growth._scale,"pager has breathing space below character cards")
	await button("技能与天赋")
	await shot("skills_fullbody")
	await button("返回培养")
	growth=get_tree().current_scene
	check(growth._list_page==1 and growth._selected_id==cid,"return restores character and page")
	await click(growth._info_rect.position+Vector2(100,160)*growth._scale)
	await wait_ui()
	check(growth._preview_item=="study_record_note","inventory directly selects study record")
	check(growth._btn_rects.any(func(b:Dictionary)->bool:return bool(b.get("all",false))),"third quantity offers all")
	await click(growth._info_rect.position+Vector2(100,100)*growth._scale)
	await wait_ui()
	var held: int=App.growth.get_currency("study_record_short")
	var affordable: int=growth._max_affordable()
	for b: Dictionary in growth._btn_rects:
		if bool(b.get("all",false)): await click((b.rect as Rect2).get_center());break
	await wait_ui()
	check(growth._preview_count==affordable and affordable>1,"all selects actual available records within level cap")
	var level_before: int=App.growth.get_progress(cid).level
	for b: Dictionary in growth._btn_rects:
		if b.action=="levelup": await click((b.rect as Rect2).get_center());break
	await wait_ui()
	check(App.growth.get_currency("study_record_short")==held-affordable and App.growth.get_progress(cid).level>level_before,"all investment consumes records and raises level")
	await button("角色装备")
	await shot("character_equipment")
	await button("装备背包")
	var claim := find_button(get_tree().current_scene,"领取全部装备奖励")
	if claim != null and not claim.disabled: await button("领取全部装备奖励")
	await shot("backpack_weapon")
	await button("▸ 饰品")
	await button("整理过的错题集  +0")
	await shot("backpack_accessory")
	await button("返回角色")
	check(get_tree().current_scene._list_page==1 and get_tree().current_scene._selected_id==cid,"backpack return restores second-page character")
	for spec: Array in [["ogawa_yui","ch1_1_6_before"],["minase_sara","ch1_1_8_before"],["shiraishi_chinatsu","ch1_1_10_after"]]:
		CampaignFlow.replay_story_id=str(spec[1])
		SceneRouter.go_to("story")
		await wait_ui()
		var story:=get_tree().current_scene
		for i:int in range(story.nodes.size()):
			if str(story.nodes[story.index].get("character",""))==str(spec[0]): break
			await click(story.next_button.get_global_rect().get_center())
			await click(story.next_button.get_global_rect().get_center())
			await wait_ui()
		check(story.figure.texture!=null and str((story.figure.texture as AtlasTexture).atlas.resource_path).contains(str(spec[0])+"_story.png"),"story correctly framed source: "+str(spec[0]))
		await shot("story_"+str(spec[0]))
	SceneRouter.go_to("archive")
	await wait_ui()
	await shot("archive_chapters")
	get_tree().current_scene.chapter_open=true
	SceneRouter.go_to("archive")
	await wait_ui()
	await shot("archive_chronological")
	var archive:=get_tree().current_scene
	check(archive._story_order("ch1_1_9_after")<archive._story_order("ch1_1_10_before") and archive._story_order("ch1_1_10_before")<archive._story_order("ch1_1_10_after"),"archive numeric stage and before-after chronology")
	check(find_grid(archive)!=null and find_grid(archive).columns==4,"archive chapter uses four columns")
	for cid2: String in ["amamiya_mio","kamiya_yuma","fujiwara_rin","ogawa_yui","minase_sara","shiraishi_chinatsu"]:
		CampaignFlow.inspected_character_id=cid2
		SceneRouter.go_to("character_details")
		await wait_ui()
		await shot("details_"+cid2)
		await escape_to("character")
	SceneRouter.go_to("home")
	await wait_ui()
	await shot("campus_glass")
	await verify_campus_events()
	SceneRouter.go_to("settings")
	await wait_ui()
	await shot("settings_glass")
	await escape_to("home")
	SceneRouter.go_to("stage_select")
	await wait_ui()
	await shot("stages_glass")
	await escape_to("home")
	SceneRouter.go_to("archive")
	await wait_ui()
	await escape_to("home")
	SceneRouter.go_to("character")
	await wait_ui()
	check(get_tree().current_scene._list_page==0,"leaving cultivation for campus clears transient page memory")
	CampaignFlow.persist({"pending_stage_id":"1-10"})
	SceneRouter.go_to("briefing")
	await wait_ui()
	var briefing := get_tree().current_scene
	var first: String=briefing.party[0]
	var pos: Vector2=briefing.cards[first].get_global_rect().get_center()
	await click(pos)
	await wait_ui()
	check(not briefing.selected.has(first),"click deselects participation")
	await click(pos)
	await wait_ui()
	check(briefing.selected.has(first),"click selects participation")
	await shot("briefing_selected")
	var target:Vector2=briefing.cards[str(briefing.party[1])].get_global_rect().get_center()
	for step:int in range(12):
		if step==0:
			var press:=InputEventMouseButton.new();press.position=pos;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
			get_viewport().push_input(press,true)
		var move:=InputEventMouseMotion.new();move.position=pos.lerp(target,float(step)/11);get_viewport().push_input(move,true)
		await get_tree().process_frame
	var release:=InputEventMouseButton.new();release.position=target;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	get_viewport().push_input(release,true)
	await wait_ui()
	check(briefing.party[1]==first and briefing.selected.has(first),"drag changes order without deselecting")
	await shot("briefing_reordered")
	await click(briefing.cards[first].get_global_rect().get_center())
	await button("开始战斗   →")
	check(not get_tree().current_scene._roster.has(first),"deselected character excluded from actual battle roster")
	await wait_ui()
	var file:=FileAccess.open("user://glass_ui_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"ok":checks.all(func(c:Dictionary)->bool:return c.ok)},"\t"))
	if checks.all(func(c:Dictionary)->bool:return c.ok):App.request_quit()
	else:get_tree().quit(1)

func find_grid(node: Node) -> GridContainer:
	if node is GridContainer:return node
	for child: Node in node.get_children():
		var result:=find_grid(child)
		if result!=null:return result
	return null

func verify_campus_events() -> void:
	var home := get_tree().current_scene
	check(CampusHub.events().size()==9,"completed chapter offers six conversations and three environment records")
	home._show_campus()
	await wait_ui()
	await shot("campus_locations")
	var before := SaveService.snapshot()
	await button("保健室  ·  新记录\n留给自己的绷带")
	check(SceneRouter.get_current_key()=="story" and not get_tree().current_scene.replay,"campus starts unlocked optional story")
	await shot("campus_conversation")
	await finish_current_story()
	check(SceneRouter.get_current_key()=="home","optional story returns to campus")
	check(CampaignFlow.done("hub_ch1_yui"),"optional encounter completion persists")
	check(SaveService.snapshot().currencies==before.currencies and SaveService.snapshot().stages==before.stages,"optional encounter grants no resources or stage unlocks")
	check(SaveService.load_game() and CampaignFlow.done("hub_ch1_yui"),"encounter remains read after reload")
	var replay_before := SaveService.snapshot()
	CampusHub.visit("hub_ch1_yui")
	await wait_ui()
	check(get_tree().current_scene.replay,"read encounter uses side-effect-free replay")
	await finish_current_story()
	check(SceneRouter.get_current_key()=="home" and SaveService.snapshot()==replay_before,"campus replay returns home without save mutations")
	home=get_tree().current_scene
	home._show_menu()
	await wait_ui()
	await shot("campus_menu")
	home._confirm_exit()
	await wait_ui()
	await shot("campus_exit_confirmation")
	await button("取消")
	check(SceneRouter.get_current_key()=="home","exit confirmation cancel stays in campus")

func finish_current_story() -> void:
	for i: int in range(40):
		if SceneRouter.get_current_key()!="story":break
		var story := get_tree().current_scene
		await click(story.next_button.get_global_rect().get_center())
		await wait_ui()

func escape_to(expected: String) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true
	get_viewport().push_input(event,true)
	var release:=InputEventKey.new();release.keycode=KEY_ESCAPE
	get_viewport().push_input(release,true)
	await wait_ui()
	check(SceneRouter.get_current_key()==expected,"Esc returns to "+expected)
