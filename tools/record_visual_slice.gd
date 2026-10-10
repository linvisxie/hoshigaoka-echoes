## Real Windows renderer, normal scene/domain clock, automated input.
## No battle ticking, stat overrides, save unlocks, or synthetic screenshot compositing.
extends Node

var battle: Node
var captured: Dictionary = {}
var attack_frames := 0
var recording := false
var next_frame := 0.0
var started := 0
var audio_history: Array[Dictionary] = []
var skill_recorded: Dictionary = {}
var active_skill_clip := ""
var skill_frame := 0
var skill_next_frame := 0.0
var victory_frames := 0
var finish_scheduled := false

func _ready() -> void:
	_begin.call_deferred()

func _begin() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		printerr("ISOLATED _testenv APPDATA REQUIRED")
		get_tree().quit(86)
		return
	await get_tree().process_frame
	PrototypeEntry.set_pending_stage_id("1-5")
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	add_child(battle)
	started = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if battle == null or battle.session == null:
		return
	var session: BattleSession = battle.session
	var now := session.stage.elapsed_seconds
	if not session.is_decided() and not session.is_paused() and not battle._upgrade_panel_active():
		for character: CharacterRuntime in session.stage.characters:
			if character.skill_ready() and not skill_recorded.has(character.character_id) and active_skill_clip.is_empty():
				battle._selected_character_id = character.instance_id
				battle._request_skill_selected()
				skill_recorded[character.character_id] = true
				active_skill_clip = character.character_id
				skill_frame = 0
				skill_next_frame = now + 0.02
				break
	if not active_skill_clip.is_empty() and now >= skill_next_frame:
		shot("skill_%s_%02d" % [active_skill_clip, skill_frame])
		skill_frame += 1
		skill_next_frame = now + 0.08
		if skill_frame >= 9:
			active_skill_clip = ""
	if now >= 0.5 and not captured.has("initial"):
		shot("initial")
	if not battle._selected_card_id.is_empty() and not captured.has("deployment_preview"):
		shot("deployment_preview")
	if session.stage.characters.size() >= 2:
		if not captured.has("two_characters"):
			shot("two_characters")
		var mio := session.stage.get_character_by_id("amamiya_mio")
		if mio != null and battle._char_anim.has(mio.instance_id):
			var state: AnimState = battle._char_anim[mio.instance_id]
			if state.anim == AnimState.ATTACK and attack_frames == 0 and not recording:
				recording = true
				next_frame = now
	if recording and now >= next_frame:
		shot("attack_%02d" % attack_frames)
		attack_frames += 1
		next_frame = now + 0.05
		if attack_frames >= 10:
			recording = false
	if battle._upgrade_panel_active() and not captured.has("upgrade_offer"):
		shot("upgrade_offer")
		RenderingServer.frame_post_draw.connect(func() -> void: battle._send_click_at(battle._upgrade_card_rects[0].get_center()), CONNECT_ONE_SHOT)
	if now >= 30 and not captured.has("battle_30s"):
		shot("battle_30s")
	if now >= 60 and not captured.has("battle_60s"):
		shot("battle_60s")
	if session.is_decided():
		if victory_frames < 9 and battle._result_animation_time >= float(victory_frames) * 0.1:
			shot("victory_%02d" % victory_frames)
			victory_frames += 1
		if battle._result_animation_time >= 1.5 and not finish_scheduled:
			finish_scheduled = true
			shot("result")
			_finish.call_deferred()
	if Time.get_ticks_msec() - started > 360000:
		printerr("Visual recording timeout; no completion claim")
		get_tree().quit(2)

func shot(label: String) -> void:
	captured[label] = true
	battle._ap_capture("v3_" + label)
	audio_history.append({"shot": label, "time": battle._now(), "audio": AudioService.playback_status()})

func _finish() -> void:
	await RenderingServer.frame_post_draw
	var file := FileAccess.open("user://visual_slice_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"evidenceType": "Real Windows Godot viewport; automated input, not human play",
		"stage": battle.session.stage.stage_id, "outcome": BattleTypes.outcome_name(battle.session.outcome),
		"time": battle._now(), "shots": captured.keys(), "attackFrames": attack_frames, "victoryFrames": victory_frames,
		"summary": battle.session.result_summary(), "audioHistory": audio_history}, "\t"))
	get_tree().quit()
