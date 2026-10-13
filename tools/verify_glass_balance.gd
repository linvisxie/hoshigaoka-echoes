## Deterministic domain simulation, NOT a real-time Windows playthrough.
extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	DataRegistry.load_all()
	var reports: Array = []
	for level: int in [5,7,9]:
		for n: int in range(6,11):
			for active: bool in [false,true]:
				reports.append(simulate("1-%d" % n,level,active))
	var f := FileAccess.open("user://balance_comparison.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"type":"deterministic domain simulation; fixed formation; no upgrade bonuses; no player save mutation","runs":reports},"\t"))
	get_tree().quit()

func simulate(sid: String,level: int,active: bool) -> Dictionary:
	var enemies := {};var chars := {};var stats := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").enemies:enemies[e.id]=e
	for c: Dictionary in DataRegistry.get_domain("characters").characters:
		chars[c.id]=c
		var p := CharacterProgress.from_growth_config(c.id,DataRegistry.get_domain("character_growth"),c.baseStats,c.growthProfileId)
		p.level=level;stats[c.id]=p.compute_stats()
	var session := BattleSession.new()
	session.setup(DataRegistry.get_entry("stages",sid),enemies,BattleGrid.from_layout(DataRegistry.get_layout()),chars,DataRegistry.get_domain("balance").combat,{})
	var rt := session.stage
	rt.set_character_level_stats(stats)
	rt.configure_skills(DataRegistry.get_domain("skills"))
	var order := ["amamiya_mio","kamiya_yuma","ogawa_yui","fujiwara_rin","minase_sara"]
	var slots := [Vector2i(3,1),Vector2i(1,1),Vector2i(2,0),Vector2i(0,0),Vector2i(2,1)]
	var peak := 0;var lane_seen := {};var count := 0;var wave_consistent := true
	while session.is_running() and rt.elapsed_seconds<700:
		for i: int in range(order.size()):
			var cid: String=order[i]
			if not rt.available_characters.has(cid) or rt.get_character_by_id(cid)!=null:continue
			if rt.query_deploy(cid,slots[i].x,slots[i].y).ok:rt.deploy_character(cid,slots[i].x,slots[i].y)
			else:break
		if active:
			for c: CharacterRuntime in rt.characters.duplicate():
				if not c.skill_ready():continue
				var targets := rt._active_skill_targets(c)
				if c.character_id=="kamiya_yuma":
					var side := false
					for e: EnemyRuntime in targets:side=side or e.lane!=c.lane
					if not side and targets.size()<2:continue
				if c.character_id=="amamiya_mio" and targets.is_empty():continue
				if c.character_id=="ogawa_yui":
					var injured := false
					for ally: CharacterRuntime in rt.characters:injured=injured or ally.hp_ratio()<.7
					if not injured:continue
				if c.character_id=="minase_sara":
					var threat: EnemyRuntime=null
					for e: EnemyRuntime in rt.enemies:
						if e.is_active() and e.lane!=1 and (threat==null or e.logical_x<threat.logical_x):threat=e
					if threat!=null:
						var column:=clampi(int(floor(threat.logical_x)),0,3)
						if rt.get_character_at(column,threat.lane)==null and rt.place_experiment(c.instance_id,column,threat.lane).ok:count+=1
				elif rt.cast_skill(c.instance_id).get("ok",false):count+=1
		session.tick(.1)
		peak=maxi(peak,rt.enemies.size())
		for e: EnemyRuntime in rt.enemies:
			lane_seen[e.lane]=true
			if not e.is_derived and e.wave_number>rt.current_wave_number():wave_consistent=false
	var summary := session.result_summary()
	summary.merge({"stage":sid,"level":level,"skillsEnabled":active,"skillCasts":count,"peakLiving":peak,"lanes":lane_seen.keys(),"waveConsistent":wave_consistent,"seconds":rt.elapsed_seconds},true)
	print("BALANCE ",JSON.stringify(summary))
	session.free()
	return summary
