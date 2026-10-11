## Real Windows scene, earned isolated save, ordinary clock and UI clicks.
extends Node
var battle: Node
var captured := {}
var rin_deployed_at := -1.0
var cast_at := -1.0
var ap_before := 0
var ap_after := 0
var skill_frames := 0
var elite_frames := {}
var finishing := false
var deployment_requested := false
var cast_requested := false
var input_busy := false

func _ready() -> void:
	_begin.call_deferred()

func _begin() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.ensure_loaded()
	if not CampaignFlow.character_unlocked("fujiwara_rin"):
		printerr("An earned completed-five-stage isolated save is required")
		get_tree().quit(3)
		return
	PrototypeEntry.set_pending_stage_id("1-5")
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	add_child(battle)

func _process(_delta: float) -> void:
	if battle == null or battle.session == null or finishing: return
	var stage: StageRuntime = battle.session.stage
	var now := stage.elapsed_seconds
	if not deployment_requested and not input_busy and now > 28 and stage.ap >= stage.deployment_cost("fujiwara_rin"):
		deployment_requested = true
		input_busy = true
		_deploy.call_deferred()
	var unit := stage.get_character_by_id("fujiwara_rin")
	if unit != null:
		if rin_deployed_at >= 0 and now > rin_deployed_at+.8: shot("rin_idle")
		if unit.skill_ready() and not input_busy and not cast_requested and not battle._upgrade_panel_active():
			cast_requested = true
			input_busy = true
			_cast.call_deferred()
		if cast_at >= 0 and skill_frames < 6 and now >= cast_at + skill_frames*.12:
			shot("rin_skill_%02d" % skill_frames)
			skill_frames += 1
	for key: String in ["arrival","time_up","gaze"]:
		if battle._art_drawn.has("elite_event:"+key): shot("elite_"+key)
	if stage.has_pending_offer():
		shot("replay_offer_%d" % stage.pending_offer.get("offerIndex",0))
		if not input_busy:
			input_busy = true
			_choose_offer.call_deferred()
	if not input_busy and not stage.has_pending_offer() and (cast_at < 0 or now > cast_at+1.0):
		for cid: String in ["amamiya_mio","kamiya_yuma"]:
			var hero := stage.get_character_by_id(cid)
			if hero != null and hero.skill_ready():
				input_busy = true
				_hero_cast.call_deferred(cid)
				break
	if battle.session.is_decided() and battle._result_animation_time > 1.8:
		shot("replay_result")
		finishing = true
		_finish.call_deferred()
	if now > 340:
		get_tree().quit(5)

func shot(label: String) -> void:
	if captured.has(label): return
	captured[label] = {"time":battle._now(),"audio":AudioService.playback_status()}
	battle._ap_capture(label)

func _deploy() -> void:
	battle._send_click_at(battle._card_rects[battle._roster.find("fujiwara_rin")].get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	battle._send_click_at(battle._cell_screen_pos(0,2))
	await get_tree().process_frame
	await get_tree().process_frame
	if battle.session.stage.get_character_by_id("fujiwara_rin") == null:
		printerr("Rin deployment through UI failed; selected=",battle._selected_card_id)
		get_tree().quit(4)
		return
	rin_deployed_at = battle._now()
	input_busy = false
	shot("rin_deployment")

func _cast() -> void:
	battle._send_click_at(battle._card_rects[battle._roster.find("fujiwara_rin")].get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	ap_before = battle.session.stage.ap
	battle._send_click_at(battle._skill_rect.get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	ap_after = battle.session.stage.ap
	cast_at = battle._now()
	input_busy = false

func _hero_cast(cid: String) -> void:
	battle._send_click_at(battle._card_rects[battle._roster.find(cid)].get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	battle._send_click_at(battle._skill_rect.get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	input_busy = false

func _choose_offer() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	battle._send_click_at(battle._upgrade_card_rects[0].get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	input_busy = false

func _finish() -> void:
	await RenderingServer.frame_post_draw
	var unit: CharacterRuntime = battle.session.stage.get_character_by_id("fujiwara_rin")
	var ok: bool = battle.session.outcome == BattleTypes.Outcome.VICTORY and unit != null and unit.total_damage_dealt == 0 and skill_frames == 6 and ap_after == mini(30,ap_before+6)
	var f := FileAccess.open("user://rin_replay_report.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok":ok,"evidenceType":"Real Windows renderer, earned save, automated UI clicks; normal AP and time",
		"apBefore":ap_before,"apAfter":ap_after,"rinDamage":unit.total_damage_dealt if unit != null else -1,
		"summary":battle.session.result_summary(),"shots":captured,"ledger":battle._art_drawn},"\t"))
	get_tree().quit(0 if ok else 6)
