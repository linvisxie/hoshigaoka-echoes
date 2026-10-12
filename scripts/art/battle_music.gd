## Single read-only policy: boss phase > monitor encounter > stage score.
class_name BattleMusic
extends RefCounted

static func base_track(stage_id: String) -> String:
	return {"1-4":"corridor_pressure","1-5":"corridor_pressure","1-6":"infirmary_light","1-7":"ranking_pressure","1-8":"science_resonance","1-9":"archive_convergence","1-10":"archive_convergence"}.get(stage_id,"echo_frontline")

static func select(stage_id: String, runtime: StageRuntime) -> String:
	if runtime.chapter_boss() != null:
		return "boss_exam_%d" % clampi(int(runtime.boss_state.get("phase",1)),1,3)
	for enemy: EnemyRuntime in runtime.enemies:
		if enemy.enemy_id == "echo_invigilator" and enemy.is_active():return "invigilator_exam"
	return base_track(stage_id)
