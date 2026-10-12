## Real Windows new-game-to-ending run; normal AP/time and earned growth only.
extends "res://tools/verify_chapter_tail_driver.gd"

var trained_for_boss := false
var trained_for_tail := false
var training_in_progress := false

func _ready() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	started = Time.get_ticks_msec()
	wall_timeout_ms = 2100000
	SceneRouter.go_to("title")

func _process(delta: float) -> void:
	if training_in_progress: return
	if not trained_for_tail and SceneRouter.get_current_key()=="briefing" and str(CampaignFlow.state().get("pending_stage_id",""))=="1-6":
		training_in_progress=true
		_train_before_boss.call_deferred()
		return
	if not trained_for_boss and SceneRouter.get_current_key()=="home" and CampaignFlow.next_stage()=="1-10":
		training_in_progress=true
		_train_before_boss.call_deferred()
		return
	super._process(delta)

func _wait_ui() -> void:
	await get_tree().create_timer(.7).timeout

func _click(pos: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=pos
	get_viewport().push_input(motion,true)
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=pos;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		get_viewport().push_input(event,true)
		await get_tree().process_frame

func _train_before_boss() -> void:
	var before:=SaveService.snapshot()
	var return_to := SceneRouter.get_current_key()
	SceneRouter.go_to("character")
	await _wait_ui()
	var growth:=get_tree().current_scene
	# Spend 4,000 of the 5,000 EXP earned by stage 5, then another 3,600
	# before the Boss. No stage 10 reward, grants, or repeated farming.
	var specs := [["amamiya_mio","study_record_archive",1,9],
		["kamiya_yuma","study_record_note",2,6],["ogawa_yui","study_record_note",2,6]] if not trained_for_tail else [
		["kamiya_yuma","study_record_note",2,9],["ogawa_yui","study_record_note",2,9],
		["minase_sara","study_record_short",16,8]]
	for spec: Array in specs:
		var index: int=growth._card_ids.find(str(spec[0]))
		if index<0:
			finish(false,"Training character has not joined: "+str(spec[0]));return
		var key:=InputEventKey.new();key.keycode=KEY_1+index;key.pressed=true
		Input.parse_input_event(key)
		var release:=InputEventKey.new();release.keycode=key.keycode
		Input.parse_input_event(release)
		await _wait_ui()
		var guard:=0
		while growth._preview_item!=spec[1] and guard<4:
			for item: Dictionary in growth._btn_rects:
				if item.action=="cycle_item":await _click((item.rect as Rect2).get_center());break
			await _wait_ui();guard+=1
		for i: int in range(int(spec[2])):
			for item: Dictionary in growth._btn_rects:
				if item.action=="preview" and int(item.get("arg",0))==1:
					await _click((item.rect as Rect2).get_center());break
			await get_tree().process_frame
			for item: Dictionary in growth._btn_rects:
				if item.action=="levelup":await _click((item.rect as Rect2).get_center());break
			await get_tree().process_frame
		if App.growth.get_progress(str(spec[0])).level!=int(spec[3]):
			finish(false,"Earned first-challenge training failed: "+str(spec[0]));return
		capture("first_challenge_training_"+str(spec[0]))
	var file:=FileAccess.open("user://first_challenge_training_%s.json" % ("tail" if not trained_for_tail else "boss"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"type":"Fresh new game; actual earned stages 1-9 growth UI; no grants or save edits", "before":before,"after":SaveService.snapshot()},"\t"))
	if trained_for_tail:trained_for_boss=true
	else:trained_for_tail=true
	SceneRouter.go_to(return_to)
	await _wait_ui()
	training_in_progress=false

func finish(ok: bool, reason: String) -> void:
	if ok:
		for stage: int in range(1,11):
			if not summaries.has("1-%d" % stage):ok=false
		ok=ok and trained_for_boss
		reason="Fresh new game through ten stages with pre-Boss earned training and ending" if ok else "Fresh ten-stage run incomplete"
	super.finish(ok,reason)
