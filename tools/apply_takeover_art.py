from pathlib import Path
p=Path(__file__).resolve().parents[1]/'scenes/battle/battle_scene.gd'
s=p.read_text(encoding='utf-8')
def rep(old,new):
    global s
    assert s.count(old)==1, (old[:80],s.count(old))
    s=s.replace(old,new,1)
def section(start,end,body):
    global s
    a=s.index(start); b=s.index(end,a)
    s=s[:a]+body+'\n\n'+s[b:]
rep('var _damage_cursor: int = 0','var _damage_events := DamageEventCursor.new()')
rep('var _hit_this_frame: Dictionary = {}','''var _hit_this_frame: Dictionary = {}
var _attack_this_frame: Dictionary = {}
## Immutable logical-position departure snapshots, independent of domain live arrays.
var _departures: Array[Dictionary] = []
var _departures_seen: Dictionary = {}''')
rep('\t_consume_damage_events()\n\t_consume_kills()', '\t_consume_damage_events()\n\t_consume_kills()\n\t_update_animation_states(now)')
rep('''	while _damage_cursor < s.damage_events.size():
		var ev: Dictionary = s.damage_events[_damage_cursor]
		_damage_cursor += 1''','''	for ev: Dictionary in _damage_events.consume(s.damage_events):''')
rep('''		_spawn_vfx("vfx_impact", kind, tid, now, VFX_IMPACT_LIFETIME)''','''		if bool(ev.get("hasPosition", false)):
			_spawn_vfx_at("vfx_impact", _logical_to_screen(ev["targetPos"]), now, VFX_IMPACT_LIFETIME)
		else:
			_spawn_vfx("vfx_impact", kind, tid, now, VFX_IMPACT_LIFETIME)
		var source_key := "%s:%d" % [str(ev.get("sourceKind", "")), int(ev.get("sourceId", 0))]
		_attack_this_frame[source_key] = true''')
# Existing pops keep the resolved target anchor even after the target has left.
rep('''		var lethal := bool(ev.get("lethal", false))''','''		var lethal := bool(ev.get("lethal", false))
		var event_anchor := _logical_to_screen(ev["targetPos"]) if bool(ev.get("hasPosition", false)) else _damage_pop_anchor(kind, tid)''')
# append block location is anchored by text field (checked below by migration)
rep('''			"kind": kind, "targetId": tid,''','''			"kind": kind, "targetId": tid, "anchor": event_anchor,''')
section('func _spawn_attacker_vfx(', 'func _spawn_vfx_at(', '''func _spawn_attacker_vfx(ev: Dictionary, now: float) -> void:
	# Exact source instance supplied by the committed damage event, never nearest-unit guessing.
	if str(ev.get("sourceKind", "")) != "character":
		return
	var cid := int(ev.get("sourceId", 0))
	var attacker: CharacterRuntime = null
	for candidate: CharacterRuntime in session.stage.character_instances:
		if candidate.instance_id == cid:
			attacker = candidate
			break
	if attacker == null or not bool(ev.get("hasPosition", false)):
		return
	var name := "vfx_arrow" if attacker.behavior == CharacterRuntime.Behavior.RANGED else "vfx_slash"
	_spawn_vfx_at(name, _logical_to_screen(ev["sourcePos"]), now, VFX_ATTACK_LIFETIME)
''')
# Actual draw accounting only after the concrete texture draw.
rep('''		draw_texture_rect(tex, dst, false, Color(1.0, 1.0, 1.0, fade))''','''		draw_texture_rect(tex, dst, false, Color(1.0, 1.0, 1.0, fade))
		_mark_drawn("vfx:%s" % str(v["name"]))
		_mark_drawn(ArtRegistry.vfx_strip_path(str(v["name"])))''')
# Remove mutation/counting from end of draw. Startup validation moved to update.
rep('''	_hit_this_frame.clear()
	# 开发/验收模式：检查"有资源但从未触发"的动画与特效（本轮指令 第四条）
	_track_art_reachability()''','''	_draw_departures()''')
rep('''			if frame_tex != null:
				sprite = frame_tex
			_draw_sprite_anchored(sprite, Vector2(px_x, px_y), tile * 0.80, mod, 0.44)''','''			if frame_tex != null:
				sprite = frame_tex
			_draw_sprite_anchored(sprite, Vector2(px_x, px_y), tile * 0.80, mod, 0.44)
			if frame_tex != null:
				_mark_drawn("char_anim:%s" % st.anim)
				_mark_drawn(ArtRegistry.character_strip_path(c.character_id, st.anim))''')
rep('''		_draw_sprite_anchored(esprite, Vector2(px_x, px_y), eh, emod, 0.42)''','''		_draw_sprite_anchored(esprite, Vector2(px_x, px_y), eh, emod, 0.42)
		if ef != null:
			_mark_drawn("enemy_anim:%s" % est.anim)
			_mark_drawn(ArtRegistry.enemy_strip_path(e.enemy_id, est.anim))''')
rep('''	var hit := _hit_this_frame.has("character:%d" % c.instance_id)
	st.tick_character(c, now, hit)
	return st''','''	return st''')
rep('''	var hit := _hit_this_frame.has("enemy:%d" % e.instance_id)
	st.tick_enemy(e, now, hit)
	return st''','''	return st''')
section('func _track_art_reachability()', '## 导出美术可达性报告', '''func _track_art_reachability() -> void:
	# Compatibility hook: selections and queued instances are NOT draw evidence.
	if not _art_checked:
		_verify_art_available()
''')
rep('''		var pos := _damage_pop_anchor(str(p["kind"]), int(p["targetId"]))''','''		var pos: Vector2 = p.get("anchor", _damage_pop_anchor(str(p["kind"]), int(p["targetId"])))''')
# Report after the last feedback consumption/draw instead of inside domain tick signal.
rep('''	report_unreachable_art()
	queue_redraw()''','''	call_deferred("_report_after_last_draw")
	queue_redraw()''')
s+='''

## Resolve logical tiles/lane at render time; no battle geometry is changed.
func _logical_to_screen(pos: Vector2) -> Vector2:
	return Vector2(_origin.x + _px(grid.tile_size_px) * pos.x,
		_origin.y + _px(grid.lane_spacing_px) * pos.y)

func _update_animation_states(now: float) -> void:
	if not _art_checked:
		_verify_art_available()
	for c: CharacterRuntime in session.stage.characters:
		var state := _char_anim_state(c, now)
		state.tick_character(c, now, _hit_this_frame.has("character:%d" % c.instance_id),
			_attack_this_frame.has("character:%d" % c.instance_id))
	for e: EnemyRuntime in session.stage.enemies:
		var state := _enemy_anim_state(e, now)
		state.tick_enemy(e, now, _hit_this_frame.has("enemy:%d" % e.instance_id),
			_attack_this_frame.has("enemy:%d" % e.instance_id))
	_hit_this_frame.clear()
	_attack_this_frame.clear()
	for removal: Dictionary in session.stage.removals:
		var kind := str(removal.get("entity", ""))
		var id := int(removal.get("entityId", 0))
		var key := "%s:%d" % [kind, id]
		if _departures_seen.has(key):
			continue
		_departures_seen[key] = true
		var reason := int(removal.get("kind", -1))
		if reason == StageRuntime.Removal.REACHED_CORE:
			_enemy_anim.erase(id)
			continue
		var state := AnimState.new()
		state.begin_death(now)
		var code := str(removal.get("characterId", "")) if kind == "character" else str(removal.get("enemyId", ""))
		var x := float(removal.get("column", 0)) if kind == "character" else float(removal.get("x", 0))
		_departures.append({"kind": kind, "id": id, "code": code, "state": state,
			"logical": Vector2(x, float(removal.get("lane", 0))), "born": now})
		if kind == "character": _char_anim.erase(id)
		else: _enemy_anim.erase(id)
	for i: int in range(_departures.size() - 1, -1, -1):
		var state: AnimState = _departures[i]["state"]
		if state.finished(now):
			_departures.remove_at(i)
	while _departures.size() > 64:
		_departures.remove_at(0)

func _draw_departures() -> void:
	for ghost: Dictionary in _departures:
		var state: AnimState = ghost["state"]
		var progress := state.progress(_now())
		var kind := str(ghost["kind"])
		var code := str(ghost["code"])
		var texture: Texture2D
		if kind == "character":
			texture = ArtRegistry.character_frame_progress(code, "death", progress)
		else:
			texture = ArtRegistry.enemy_frame_progress(code, "death", progress)
		if texture == null:
			continue
		var height := _px(grid.tile_size_px) * (0.80 if kind == "character" else 0.72)
		_draw_sprite_anchored(texture, _logical_to_screen(ghost["logical"]), height,
			Color(1, 1, 1, 1.0 - progress), 0.44 if kind == "character" else 0.42)
		if progress < 1.0:
			_mark_drawn("%s_anim:death" % ("char" if kind == "character" else "enemy"))
			var path := ArtRegistry.character_strip_path(code, "death") if kind == "character" else ArtRegistry.enemy_strip_path(code, "death")
			_mark_drawn(path)

func _report_after_last_draw() -> void:
	await RenderingServer.frame_post_draw
	report_unreachable_art()
'''
p.write_text(s,encoding='utf-8')
print('Battle scene migration applied')
