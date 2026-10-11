## Consume only records earned by the isolated real campaign, through growth UI clicks.
extends "res://tools/verify_frontend_driver.gd"
func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()): get_tree().quit(86); return
	SaveService.ensure_loaded()
	var before:=SaveService.snapshot()
	SceneRouter.go_to("character")
	await wait_ui()
	var growth:=get_tree().current_scene
	for spec: Array in [["amamiya_mio","study_record_short",20],["kamiya_yuma","study_record_archive",1],["ogawa_yui","study_record_note",4],["minase_sara","study_record_note",4]]:
		var index: int=growth._card_ids.find(str(spec[0]))
		var key:=InputEventKey.new();key.keycode=KEY_1+index;key.pressed=true;Input.parse_input_event(key)
		await wait_ui()
		var guard:=0
		while growth._preview_item!=spec[1] and guard<4:
			for item: Dictionary in growth._btn_rects:
				if item.action=="cycle_item": await click((item.rect as Rect2).get_center());break
			await wait_ui();guard+=1
		# Use the one-record preview and commit controls for every actual record.
		for i: int in range(int(spec[2])):
			for item: Dictionary in growth._btn_rects:
				if item.action=="preview" and int(item.get("arg",0))==1:
					await click((item.rect as Rect2).get_center());break
			await get_tree().process_frame
			for item: Dictionary in growth._btn_rects:
				if item.action=="levelup": await click((item.rect as Rect2).get_center());break
			await get_tree().process_frame
		check(App.growth.get_progress(str(spec[0])).level==9,"earned records train "+str(spec[0])+" to Lv.9")
		await shot("trained_"+str(spec[0]))
	var file:=FileAccess.open("user://training_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"type":"Actual growth UI clicks; earned campaign records only; no currency grants", "checks":checks,"before":before,"after":SaveService.snapshot()},"\t"))
	SceneRouter.go_to("home")
	await wait_ui()
	get_tree().quit(0 if checks.all(func(item: Dictionary)->bool:return item.ok) else 2)
