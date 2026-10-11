extends GutTest

func before_all() -> void:
	if not DataRegistry.is_loaded(): DataRegistry.load_all()

func runtime(sid: String) -> StageRuntime:
	var enemies := {}
	var characters := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies",[]): enemies[e.id]=e
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters",[]): characters[c.id]=c
	var rt := StageRuntime.from_config(DataRegistry.get_entry("stages",sid),enemies,BattleGrid.from_layout(DataRegistry.get_layout()),characters,DataRegistry.get_domain("balance").combat,DataRegistry.get_domain("upgrades"))
	rt.configure_skills(DataRegistry.get_domain("skills"))
	return rt

func test_ten_stages_and_required_story_references() -> void:
	for n: int in range(1,11):
		var cfg := DataRegistry.get_entry("stages","1-%d" % n)
		assert_true(StageRewardService.cfg_has_content(cfg))
		assert_false(DataRegistry.get_entry("story",str(cfg.storyAfter)).is_empty())
		if n>=6:
			assert_eq(runtime("1-%d" % n).get_errors().size(),0)
			assert_false(DataRegistry.get_entry("story",str(cfg.storyBefore)).is_empty())
			assert_false((cfg.availableCharacters as Array).has("shiraishi_chinatsu"),"Chinatsu not required before first clear")

func test_device_occupancy_expiry_no_heal_and_no_character_slot() -> void:
	var rt := runtime("1-8")
	rt.ap=30
	var sara := rt.deploy_character("minase_sara",1,1).character
	sara.skill_cooldown_remaining=0
	assert_true(rt.place_experiment(sara.instance_id,3,0).ok)
	var device := rt.get_character_at(3,0)
	assert_not_null(device)
	assert_eq(device.block_count_max,1)
	assert_eq(rt.field_character_count(),1)
	assert_false(rt.query_deploy("amamiya_mio",3,0).ok)
	assert_false(rt.place_experiment(sara.instance_id,4,0).ok,"cannot bypass cooldown")
	rt.ap=30
	var yui := rt.deploy_character("ogawa_yui",2,0).character
	device.hp=100
	rt._resolve_healer_action(yui,1)
	assert_eq(device.hp,100,"device cannot be healed")
	rt.elapsed_seconds=13
	rt._tick_chapter_mechanics(.1)
	assert_null(rt.get_character_at(3,0),"expired device releases occupancy")

func test_sara_splash_is_same_lane_and_primary_not_double_counted() -> void:
	var rt := runtime("1-8")
	rt.ap=30
	var sara := rt.deploy_character("minase_sara",1,1).character
	for lane: int in [1,1,0]:
		var enemy := EnemyRuntime.from_config(rt._enemy_configs.echo_normal,lane,100+rt.enemies.size())
		enemy.logical_x=2+.2*rt.enemies.size()
		rt.enemies.append(enemy)
	rt._resolve_attacker_action(sara,1)
	assert_gt(rt.enemies[0].total_damage_taken,0)
	assert_gt(rt.enemies[1].total_damage_taken,0)
	assert_lt(rt.enemies[1].total_damage_taken,rt.enemies[0].total_damage_taken)
	assert_eq(rt.enemies[2].total_damage_taken,0)

func test_boss_thresholds_warning_damage_and_pause_clock() -> void:
	var rt := runtime("1-10")
	rt.ap=30
	var mio := rt.deploy_character("amamiya_mio",3,1).character
	var boss := EnemyRuntime.from_config(rt._enemy_configs.boss_model_student,1,100,4)
	rt.enemies.append(boss)
	rt._tick_chapter_mechanics(.1)
	assert_eq(int(rt.boss_state.phase),1)
	rt.elapsed_seconds=5.1
	rt._tick_chapter_mechanics(.1)
	assert_true(mio.has_status_effect("boss_compare"),"phase 1 comparison can happen before a strong team changes phase")
	assert_false(rt.boss_warnings.is_empty(),"phase 1 summon telegraphed")
	boss.hp=4799
	rt.elapsed_seconds=20
	rt._tick_chapter_mechanics(.1)
	assert_eq(int(rt.boss_state.phase),2)
	assert_true(rt.boss_warnings.is_empty(),"phase replace cancels old pending casts")
	rt.elapsed_seconds=23.01
	rt._tick_chapter_mechanics(.1)
	assert_gt(rt.boss_warnings.size(),0)
	var hp := mio.hp
	rt.elapsed_seconds=25.99
	rt._tick_chapter_mechanics(.1)
	assert_eq(mio.hp,hp,"3s warning never deals early damage")
	rt.elapsed_seconds=26.02
	rt._tick_chapter_mechanics(.1)
	assert_lt(mio.hp,hp)
	boss.hp=2399
	rt._tick_chapter_mechanics(.1)
	assert_eq(int(rt.boss_state.phase),3)
	assert_true(rt.boss_warnings.is_empty(),"phase 3 cancels phase 2 hazards")
	assert_gt(boss.move_speed,boss.base_move_speed)
	rt.paused=true
	var clock := rt.elapsed_seconds
	rt.advance(1)
	assert_eq(rt.elapsed_seconds,clock)
	boss.hp=0
	rt._tick_chapter_mechanics(.1)
	assert_true(rt.boss_warnings.is_empty(),"defeated Boss leaves no live hazard")

func test_anxiety_expires_and_ranking_targets_highest_legal_attack() -> void:
	var rt := runtime("1-9")
	rt.ap=30
	var mio := rt.deploy_character("amamiya_mio",3,1).character
	rt.ap=30
	var yuma := rt.deploy_character("kamiya_yuma",2,1).character
	var anxiety := EnemyRuntime.from_config(rt._enemy_configs.echo_anxiety,1,100)
	anxiety.logical_x=3.5
	var ranking := EnemyRuntime.from_config(rt._enemy_configs.echo_rank,1,101)
	ranking.logical_x=3.5
	rt.enemies.append(anxiety)
	rt.enemies.append(ranking)
	var interval := yuma.effective_attack_interval()
	var recovery := yuma.effective_cd_recovery_factor()
	rt.rank_cooldowns[101]=0
	rt._tick_chapter_mechanics(.1)
	assert_gt(yuma.effective_attack_interval(),interval)
	assert_lt(yuma.effective_cd_recovery_factor(),recovery)
	var highest: CharacterRuntime = mio if mio.attack>=yuma.attack else yuma
	var other: CharacterRuntime = yuma if highest==mio else mio
	assert_lt(highest.effective_attack(),highest.attack,"ranking debuffs highest legal attack")
	assert_eq(other.effective_attack(),other.attack,"ranking is not a global attack debuff")
	anxiety.logical_x=9
	rt.elapsed_seconds=6
	for c: CharacterRuntime in rt.characters: c.tick_status_effects(6)
	assert_almost_eq(yuma.effective_attack_interval(),interval,.0001)
	assert_almost_eq(yuma.effective_cd_recovery_factor(),recovery,.0001)

func test_chinatsu_support_excludes_self_and_distant_lane_and_stacks_with_active() -> void:
	var rt := runtime("1-10")
	rt.available_characters.append("shiraishi_chinatsu")
	rt.ap=30
	var chinatsu := rt.deploy_character("shiraishi_chinatsu",1,0).character
	rt.ap=30
	var near := rt.deploy_character("kamiya_yuma",2,0).character
	rt.ap=30
	var far := rt.deploy_character("amamiya_mio",1,2).character
	var near_interval := near.effective_attack_interval()
	var self_interval := chinatsu.effective_attack_interval()
	var far_interval := far.effective_attack_interval()
	rt._tick_chapter_mechanics(.1)
	assert_lt(near.effective_attack_interval(),near_interval)
	assert_eq(chinatsu.effective_attack_interval(),self_interval)
	assert_eq(far.effective_attack_interval(),far_interval)
	var passive_interval := near.effective_attack_interval()
	chinatsu.skill_cooldown_remaining=0
	assert_true(rt.cast_skill(chinatsu.instance_id).ok)
	assert_lt(near.effective_attack_interval(),passive_interval)
	assert_gt(near.effective_cd_recovery_factor(),1.0)

func test_tail_normal_ap_clear_paths() -> void:
	for n: int in range(6,11):
		var rt := runtime("1-%d" % n)
		if n==10:
			# V2.1.4 recommends Lv.9-12 for the Boss. Four Lv.9 members
			# cost 8,000 EXP, within the actual chapter reward budget.
			var stats: Dictionary={}
			for cid: String in ["amamiya_mio","kamiya_yuma","ogawa_yui","minase_sara"]:
				var cfg: Dictionary=rt._character_configs[cid]
				var progress:=CharacterProgress.from_growth_config(cid,DataRegistry.get_domain("character_growth"),cfg.baseStats,str(cfg.growthProfileId))
				progress.add_exp(2000)
				assert_eq(progress.level,9)
				stats[cid]=progress.compute_stats()
			rt.set_character_level_stats(stats)
		var order: Array[String]=["amamiya_mio","kamiya_yuma","ogawa_yui","fujiwara_rin"]
		if n>=8: order.append("minase_sara")
		var slots: Array[Vector2i]=[Vector2i(3,1),Vector2i(2,1),Vector2i(2,0),Vector2i(0,0),Vector2i(1,1)]
		var index := 0
		for tick: int in range(600*60):
			if index<order.size() and rt.query_deploy(order[index],slots[index].x,slots[index].y).ok:
				rt.deploy_character(order[index],slots[index].x,slots[index].y)
				index+=1
			for c: CharacterRuntime in rt.characters.duplicate():
				if not c.skill_ready(): continue
				if c.skill_config.get("effect","")=="DEVICE":
					var threat: EnemyRuntime=null
					for e: EnemyRuntime in rt.enemies:
						if e.lane!=1 and e.is_active() and (threat==null or e.logical_x<threat.logical_x): threat=e
					if threat!=null:
						var column:=clampi(int(floor(threat.logical_x)),0,3)
						rt.place_experiment(c.instance_id,column,threat.lane)
				else: rt.cast_skill(c.instance_id)
			if rt.pending_offer_active_guard(): rt.resolve_offer(str(rt.pending_offer.candidates[0]))
			rt.advance(1.0/60)
			if rt.core_hp<=0 or rt.all_waves_cleared(): break
		assert_gt(rt.core_hp,0,"1-%d legal normal-AP solution at the specified challenge level; t=%.1f kills=%d" % [n,rt.elapsed_seconds,rt.enemies_killed])
		assert_true(rt.all_waves_cleared(),"1-%d clears all waves" % n)
