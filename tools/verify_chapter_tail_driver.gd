## Real Windows continuation from the previously earned five-stage test save.
## Normal domain clock/AP/stats, production flow, automated input (not human play).
extends "res://tools/verify_campaign_driver.gd"

var input_after := 0
var boss_samples := 0
var last_boss_sample := -1.0

func _ready() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	started=Time.get_ticks_msec()
	visited_character=true
	CampaignFlow.resume()

func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != null and SceneRouter.get_current_key()=="battle" and scene.session!=null:
		var rt: StageRuntime=scene.session.stage
		if not scene.session.is_decided() and not scene.session.is_paused() and not scene._upgrade_panel_active() and Time.get_ticks_msec()>input_after:
			# No healer before stage 6: use the actual retreat input before the
			# frontline collapses, then redeploy through the ordinary AP/cooldown.
			var frontline := rt.get_character_by_id("amamiya_mio")
			if int(rt.stage_id.get_slice("-",1))<6 and frontline != null and frontline.hp_ratio()<.30:
				scene._selected_character_id=frontline.instance_id
				var retreat:=InputEventKey.new();retreat.keycode=KEY_R;retreat.pressed=true
				get_viewport().push_input(retreat,true)
				var release:=InputEventKey.new();release.keycode=KEY_R
				get_viewport().push_input(release,true)
				input_after=Time.get_ticks_msec()+300
			if scene._device_select_owner!=0:
				var threat: EnemyRuntime=null
				for e: EnemyRuntime in rt.enemies:
					if e.is_active() and e.lane!=1 and (threat==null or e.logical_x<threat.logical_x):threat=e
				if threat!=null:
					var column:=clampi(int(floor(threat.logical_x)),0,3)
					if rt.get_character_at(column,threat.lane)==null:
						scene._send_click_at(scene._cell_screen_pos(column,threat.lane))
						input_after=Time.get_ticks_msec()+300
						capture("experiment_"+rt.stage_id)
			else:
				var order: Array[String]=["amamiya_mio","kamiya_yuma","ogawa_yui","fujiwara_rin","minase_sara","shiraishi_chinatsu"]
				var slots: Array[Vector2i]=[Vector2i(3,1),Vector2i(1,1),Vector2i(2,0),Vector2i(0,0),Vector2i(2,1),Vector2i(1,0)]
				if int(rt.stage_id.get_slice("-",1)) < 6: slots[1] = Vector2i(1,1)
				for i: int in range(order.size()):
					var cid := order[i]
					if not rt.available_characters.has(cid) or rt.get_character_by_id(cid)!=null: continue
					if not rt.query_deploy(cid,slots[i].x,slots[i].y).ok: break
					var card_index: int=scene._roster.find(cid)
					if card_index<0 or card_index>=scene._card_rects.size(): break
					if scene._selected_card_id==cid: scene._send_click_at(scene._cell_screen_pos(slots[i].x,slots[i].y))
					else: scene._send_click_at(scene._card_rects[card_index].get_center())
					input_after=Time.get_ticks_msec()+200
					break
		var boss := rt.chapter_boss()
		if boss!=null:
			capture("boss_phase_%d" % int(rt.boss_state.get("phase",1)))
			if not rt.boss_warnings.is_empty():
				capture("boss_warning_phase_%d" % int(rt.boss_state.get("phase",1)))
			if boss_samples<40 and rt.elapsed_seconds-last_boss_sample>.2 and int(rt.boss_state.get("phase",1))>=2:
				last_boss_sample=rt.elapsed_seconds
				capture("boss_motion_%02d" % boss_samples)
				boss_samples+=1
		if scene.session.is_decided() and not summaries.has(rt.stage_id):
			summaries["mechanics_"+rt.stage_id]={"bossEvents":rt.boss_events.duplicate(true),"healedTotal":rt.total_healing_done,"healEvents":rt.heal_events.duplicate(true),"skillEvents":rt.skill_events.duplicate(true)}
	super._process(delta)

func should_cast(rt: StageRuntime,c: CharacterRuntime) -> bool:
	if int(rt.stage_id.get_slice("-",1))<6:return true
	var targets:=rt._active_skill_targets(c)
	if c.character_id=="kamiya_yuma":
		for e: EnemyRuntime in targets:
			if e.lane!=c.lane:return true
		return targets.size()>=2
	if c.character_id=="amamiya_mio":return not targets.is_empty()
	if c.character_id=="ogawa_yui":
		for ally: CharacterRuntime in rt.characters:
			if ally.hp_ratio()<.7:return true
		return false
	if c.character_id=="minase_sara":
		for e: EnemyRuntime in rt.enemies:
			if e.is_active() and e.lane!=1 and e.logical_x<5:return true
		return false
	return true

func finish(ok: bool, reason: String) -> void:
	if ok:
		ok=CampaignFlow.done("ch1_1_10_after") and CampaignFlow.character_unlocked("shiraishi_chinatsu")
		reason="Five tail stages completed through normal campaign flow; ending and Chinatsu unlock verified" if ok else "Ending/unlock incomplete"
	super.finish(ok,reason)
