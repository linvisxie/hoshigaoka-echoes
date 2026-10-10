## Normal Windows battle with no deployments: records real danger and defeat states.
extends Node

var battle: Node
var danger_frame := 0
var break_frame := 0
var next_danger := 0.0
var finishing := false

func _ready() -> void:
	_begin.call_deferred()

func _begin() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	PrototypeEntry.set_pending_stage_id("1-2")
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	add_child(battle)

func _process(_delta: float) -> void:
	if battle == null or battle.session == null or finishing:
		return
	var stage: StageRuntime = battle.session.stage
	if stage.core_hp == 1 and danger_frame < 6 and stage.elapsed_seconds >= next_danger:
		battle._ap_capture("core_danger_%02d" % danger_frame)
		danger_frame += 1
		next_danger = stage.elapsed_seconds + 0.13
	if battle.session.is_decided():
		if break_frame < 8 and battle._result_animation_time >= float(break_frame)*0.10:
			battle._ap_capture("core_break_%02d" % break_frame)
			break_frame += 1
		if battle._result_animation_time >= 1.4:
			finishing = true
			_finish()

func _finish() -> void:
	battle._ap_capture("core_failure_result")
	await RenderingServer.frame_post_draw
	var ok: bool = battle.session.stage.core_hp == 0 and battle.session.outcome == BattleTypes.Outcome.DEFEAT and battle._reward_summary.get("granted",{}).is_empty()
	var f := FileAccess.open("user://core_failure_report.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok":ok,"type":"real Windows normal battle; no deployments, no stat/time overrides","dangerFrames":danger_frame,"breakFrames":break_frame,"summary":battle.session.result_summary(),"rewards":battle._reward_summary},"\t"))
	get_tree().quit(0 if ok else 2)
