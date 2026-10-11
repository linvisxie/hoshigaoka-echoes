## Explicit art staging, NOT a normal-clock combat/clear verification.
extends "res://tools/verify_frontend_driver.gd"
func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):get_tree().quit(86);return
	SaveService.ensure_loaded()
	CampaignFlow.open_stage("1-10")
	await wait_ui()
	CampaignFlow.launch_battle()
	await wait_ui()
	var battle:=get_tree().current_scene
	var rt: StageRuntime=battle.session.stage
	var boss:=EnemyRuntime.from_config(rt._enemy_configs.boss_model_student,1,9000,4)
	boss.logical_x=4.1
	rt.enemies.append(boss)
	for phase: int in [1,2,3]:
		boss.hp=[8000,4700,2300][phase-1]
		await wait_ui()
		await shot("STAGED_boss_phase_%d" % phase)
	rt.boss_warnings.append({"kind":"mistake","lane":1,"column":3,"born":rt.elapsed_seconds,"due":rt.elapsed_seconds+3})
	await wait_ui()
	await shot("STAGED_manhattan_warning")
	var labels: Array=[]
	for card: Dictionary in battle._native_hud.cards:
		labels.append({"id":card.id,"label":card.status.text})
	var file:=FileAccess.open("user://staged_ui_labels.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(labels,"\t"))
	get_tree().quit()
