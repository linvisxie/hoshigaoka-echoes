from pathlib import Path
p=Path(__file__).resolve().parents[1]/'scenes/battle/battle_scene.gd'
s=p.read_text(encoding='utf-8')
a=s.index('func _drive_autoplay()'); b=s.index('## 本关第一位已部署角色',a)
s=s[:a]+'''## Confirmed-input deployment driver. It never changes AP/cooldowns/level or bypasses query_deploy.
var _autoplay_deploy_idx: int = 0
var _autoplay_deploy_at: float = 0.0
var _autoplay_wall_started: int = -1
var _autoplay_attempts: int = 0

func _drive_autoplay() -> void:
	# Outcome handling must precede AP waits (the domain clock freezes at outcome).
	if session.is_decided():
		if not _autoplay_result_captured:
			_autoplay_result_captured = true
			_ap_capture("result")
			GameLog.info(TAG, "[autoplay] 已确认结果：%s" % BattleTypes.outcome_name(session.outcome))
		return
	if _autoplay_wall_started < 0:
		_autoplay_wall_started = Time.get_ticks_msec()
	if Time.get_ticks_msec() - _autoplay_wall_started > 600000:
		_autoplay = false
		GameLog.warn(TAG, "[autoplay] 墙钟超时，停止输入；未宣称完成")
		return
	if session.is_paused() or _autoplay_deploy_idx >= _roster.size():
		return
	var now := elapsed_since_start()
	if now < 1.0 or now < _autoplay_deploy_at:
		return
	var cid: String = _roster[_autoplay_deploy_idx]
	var existing := session.stage.get_character_by_id(cid)
	if existing != null:
		GameLog.info(TAG, "[autoplay] 部署已确认 %s id=%d" % [cid, existing.instance_id])
		_ap_capture("deployed_%s" % cid)
		_autoplay_deploy_idx += 1
		_autoplay_attempts = 0
		return
	var col := 2 if _autoplay_deploy_idx == 0 else 1
	var lane := 1 if _autoplay_deploy_idx < 2 else 0
	# For larger rosters, select a legal free slot rather than overlap the three cells.
	var admission := session.query_deploy(cid, col, lane)
	if not admission.ok:
		_autoplay_deploy_at = now + 0.5
		return
	if _autoplay_attempts >= 8:
		_autoplay = false
		GameLog.warn(TAG, "[autoplay] 多次输入未确认 %s；停止并保留诊断" % cid)
		return
	# One input action per update; only advance after observing domain deployment.
	if _selected_card_id != cid:
		if _card_rects.size() <= _autoplay_deploy_idx:
			return
		_send_click_at(_card_rects[_autoplay_deploy_idx].get_center())
	else:
		_click_cell(col, lane)
		_autoplay_attempts += 1
	_autoplay_deploy_at = now + 0.2


''' + s[b:]
a=s.index('var _pending_capture:'); b=s.index('func _do_capture(',a)
s=s[:a]+'''func _ap_capture(shot_name: String) -> void:
	# Bound name per callback: a second request cannot overwrite the first.
	RenderingServer.frame_post_draw.connect(func() -> void: _do_capture(shot_name), CONNECT_ONE_SHOT)


'''+s[b:]
s=s.replace('expected.append(ArtRegistry.character_strip_path(cid, "idle"))','expected.append("%s/characters/%s/%s_base.png" % [ArtRegistry.ART_ROOT, cid, cid])',1)
s=s.replace('if not ResourceLoader.exists(p):\n\t\t\tmissing.append(p)','if ArtRegistry.load_texture(p) == null:\n\t\t\tmissing.append(p)',1)
# Legacy nearest-source description is no longer accurate.
a=s.index('## 攻击者出手特效（斩击 / 箭矢）。'); b=s.index('func _spawn_attacker_vfx',a)
s=s[:a]+'''## Exact source from committed damage event. Unknown sources do not spawn guessed attacks.
'''+s[b:]
p.write_text(s,encoding='utf-8')
print('Confirmed-input autoplay and load validation applied')
