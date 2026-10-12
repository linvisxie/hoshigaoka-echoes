## Real Windows renderer, ordinary domain clock and production flow APIs.
## Automated traversal, explicitly not human play. No stat/AP/time overrides.
extends Node

var scene_instance := 0
var entered := 0
var last_action := 0
var started := 0
var captured: Dictionary = {}
var summaries: Dictionary = {}
var actions: Array[Dictionary] = []
var visited_character := false
var success := false
var wall_timeout_ms := 1500000
var capture_hold_until := 0

func _ready() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		printerr("Campaign evidence requires isolated _testenv APPDATA")
		get_tree().quit(86)
		return
	started = Time.get_ticks_msec()
	SceneRouter.go_to("title")

func _process(_delta: float) -> void:
	if success:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var now := Time.get_ticks_msec()
	if now < capture_hold_until:
		return
	if scene_instance != scene.get_instance_id():
		scene_instance = scene.get_instance_id()
		entered = now
		last_action = now
	var dwell := now - entered
	if now - started > wall_timeout_ms:
		finish(false, "Wall-clock timeout")
		return
	var key := SceneRouter.get_current_key()
	match key:
		"title":
			if dwell > 1200:
				if not captured.has("title"):
					capture("title")
					return
				scene._activate(1)
		"new_game":
			if dwell > 1000:
				if not captured.has("name_input"):
					capture("name_input")
					return
				scene.name_input.text = "观测记录"
				scene._start()
		"story":
			if dwell > 500:
				var sid := str(scene.story_id)
				if int(scene.index) == 6 and not captured.has(sid + "_dialogue"):
					scene.dialogue.visible_ratio = 1.0
					capture(sid + "_dialogue")
					return
				if now - last_action > 180:
					last_action = now
					scene.dialogue.visible_ratio = 1.0
					var event := InputEventKey.new()
					event.keycode = KEY_ENTER
					event.pressed = true
					Input.parse_input_event(event)
					var release := InputEventKey.new()
					release.keycode = KEY_ENTER
					Input.parse_input_event(release)
		"briefing":
			if dwell > 1200:
				var label := "briefing_" + str(CampaignFlow.state().get("pending_stage_id", ""))
				if not captured.has(label):
					capture(label)
					return
				CampaignFlow.launch_battle()
		"battle":
			if scene.session == null:
				return
			var session: BattleSession = scene.session
			var sid := session.stage.stage_id
			if not summaries.has("metrics_"+sid):
				summaries["metrics_"+sid] = {"peakLivingEnemies":0,"attackLanes":[],"plannedEnemies":session.stage.planned_enemy_count()}
			var metrics: Dictionary = summaries["metrics_"+sid]
			metrics["peakLivingEnemies"] = maxi(int(metrics["peakLivingEnemies"]),session.stage.enemies.size())
			for ev: Dictionary in session.stage.damage_events:
				if str(ev.get("sourceKind","")) == "character" and bool(ev.get("hasPosition",false)):
					var lane := int((ev["targetPos"] as Vector2).y)
					if not (metrics["attackLanes"] as Array).has(lane): metrics["attackLanes"].append(lane)
			if not session.is_decided() and not session.is_paused() and not scene._upgrade_panel_active():
				for character: CharacterRuntime in session.stage.characters:
					if character.skill_ready() and should_cast(session.stage,character):
						scene._selected_character_id = character.instance_id
						var event := InputEventKey.new()
						event.keycode = KEY_Q
						event.pressed = true
						Input.parse_input_event(event)
						var release := InputEventKey.new()
						release.keycode = KEY_Q
						Input.parse_input_event(release)
						capture("skill_" + sid + "_" + character.character_id)
						break
			if session.stage.elapsed_seconds >= 35:
				capture("battle_" + sid)
			if scene._upgrade_panel_active():
				capture("upgrade_" + sid)
				if now - last_action > 1200:
					scene._choose_upgrade_index(0)
					last_action = now
			if session.is_decided():
				if not summaries.has(sid):
					summaries[sid] = session.result_summary()
					summaries[sid]["skillEvents"] = session.stage.skill_events.duplicate(true)
					capture("victory_pose_" + sid)
					last_action = now
					if session.outcome != BattleTypes.Outcome.VICTORY:
						finish(false, "Battle failed: " + sid)
						return
				if now - last_action > 1800:
					if not captured.has("result_" + sid):
						capture("result_" + sid)
						return
					scene._send_click_at(scene._quit_rect.get_center())
		"home":
			if dwell < 1200:
				return
			var completed := 0
			for sid: String in summaries.keys():
				if not sid.begins_with("metrics_"): completed += 1
			var label := "campus_after_%d" % completed
			if not captured.has(label):
				capture(label)
				return
			if not visited_character:
				visited_character = true
				SceneRouter.go_to("character")
				return
			var next := CampaignFlow.next_stage()
			if next.is_empty():
				finish(true, "Five stages completed through normal campaign flow")
			else:
				CampaignFlow.open_stage(next)
		"character":
			if dwell > 1600:
				if not captured.has("character_after_1_1"):
					capture("character_after_1_1")
					return
				SceneRouter.go_to("home")

func should_cast(_rt: StageRuntime,_character: CharacterRuntime) -> bool:
	return true

func capture(label: String) -> void:
	if captured.has(label):
		return
	captured[label] = true
	capture_hold_until = Time.get_ticks_msec() + 400
	actions.append({"capture": label, "wallMs": Time.get_ticks_msec() - started,
		"flow": CampaignFlow.state().duplicate(true), "audio": AudioService.playback_status()})
	await RenderingServer.frame_post_draw
	var dir := "user://campaign_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var error := get_viewport().get_texture().get_image().save_png(dir + "/" + label + ".png")
	GameLog.info("CampaignEvidence", "Captured %s err=%d" % [label, error])

func finish(ok: bool, reason: String) -> void:
	success = true
	var report := {"evidenceType": "Real Windows viewport, automated traversal and input; not human play",
		"ok": ok, "reason": reason, "summaries": summaries, "actions": actions,
		"wallSeconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"save": SaveService.get_current().duplicate(true)}
	var file := FileAccess.open("user://campaign_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	GameLog.info("CampaignEvidence", "Finished: %s %s" % [ok, reason])
	get_tree().quit(0 if ok else 2)
