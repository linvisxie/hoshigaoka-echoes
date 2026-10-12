## StageRuntime — 单场战斗的关卡运行时（V2.1.4 L4：场景实例化，不进全局单例）。
##
## 职责（P0.1～P0.3 范围）：
##   P0.1：按 StageConfig.enemySpawnTimeline 生成敌人、固定逻辑步长推进移动、
##         核心 HP 与漏怪结算（同一敌人只结算一次）
##   P0.2：AP 系统（初始化/自然回复/上限/扣费）、角色部署（合法性/占格/唯一性/费用）、
##         阻挡系统（接触线/阻挡名额/释放）、双方攻击与伤害、死亡与失能
##   P0.3：主动撤退与 AP 返还、再部署冷却与失能离场、Wave 调度、暂停冻结
##
## 严格不含任何渲染、输入或 UI；不含技能/天赋/局内强化（属后续阶段）。
##
## 逻辑步长固定为 LOGIC_STEP_SECONDS，因此渲染帧率与分辨率不会改变战斗结果。
##
## P0.3 计时器纪律：再部署冷却、Wave 计时、AP 回复、攻击间隔全部只在**逻辑步**内推进，
## 因此暂停（paused）与胜负确定（running=false）都会让全部计时器停在同一状态。
class_name StageRuntime
extends RefCounted

## 固定逻辑步长（秒）。所有战斗推进只在此步长上发生。
const LOGIC_STEP_SECONDS: float = 1.0 / 60.0

## 单帧最多追赶的逻辑步数，防止长时间卡顿后一次性跑完整关
const MAX_STEPS_PER_ADVANCE: int = 240

var _skill_configs: Dictionary = {}
var _talent_configs: Dictionary = {}
var skill_events: Array[Dictionary] = []
var _deploy_discount: Dictionary = {}
var ap_regen_bonus_cap: float = 0.5
var boss_config: Dictionary = {}
var sequential_waves := false
var _wave_time_delay := 0.0
var boss_state: Dictionary = {}
var boss_events: Array[Dictionary] = []
var boss_warnings: Array[Dictionary] = []
var device_expiry: Dictionary = {}
var device_owner: Dictionary = {}
var rank_cooldowns: Dictionary = {}
var _chapter_rng := RandomNumberGenerator.new()

func configure_skills(domain: Dictionary) -> void:
	_skill_configs.clear()
	_talent_configs.clear()
	for config: Dictionary in domain.get("talents", []):
		_talent_configs[str(config.get("id", ""))] = config.duplicate(true)
	for config: Dictionary in domain.get("skills", []):
		_skill_configs[str(config.get("id", ""))] = config.duplicate(true)
	for character: CharacterRuntime in characters:
		_assign_skill(character)

func field_character_count() -> int:
	var count := 0
	for c: CharacterRuntime in characters:
		if c.character_id != "sara_device": count += 1
	return count

func place_experiment(owner_id: int, column: int, lane: int) -> Dictionary:
	var owner := get_character(owner_id)
	if paused or not running or owner == null or not owner.skill_ready() or owner.skill_config.get("effect", "") != "DEVICE":
		return {"ok":false,"reason":"实验装置尚未就绪"}
	if not BattleTypes.is_valid_column(column) or not BattleTypes.is_valid_lane(lane) or get_character_at(column,lane) != null:
		return {"ok":false,"reason":"请选择合法空部署格"}
	var cfg := owner.skill_config
	# One device per owner; replace only after validating the new cell.
	for iid: Variant in device_owner.keys():
		if int(device_owner[iid]) == owner_id:
			_expire_device(int(iid))
	var device_cfg := {"id":"sara_device","name":"实验装置","behavior":"FRONTLINE","baseStats":{"hp":int(cfg.get("deviceHp",480)),"attack":0,"defense":int(cfg.get("deviceDefense",60))},"attackInterval":1.0,"attackRange":{"rangeTiles":0,"maxLaneDelta":0},"blockCount":int(cfg.get("deviceBlock",1)),"damageType":"SPECIAL"}
	var device := CharacterRuntime.from_config(device_cfg,column,lane,_next_character_instance_id)
	_next_character_instance_id += 1
	characters.append(device)
	character_instances.append(device)
	device_expiry[device.instance_id] = elapsed_seconds+float(cfg.get("durationSeconds",12))
	device_owner[device.instance_id] = owner_id
	owner.skill_cooldown_remaining = float(cfg.get("cooldownSeconds",24))
	skill_events.append({"instanceId":owner_id,"skillId":cfg.id,"at":elapsed_seconds,"column":column,"lane":lane})
	return {"ok":true,"name":cfg.get("name","")}

func _expire_device(iid: int) -> void:
	var device := get_character(iid)
	if device != null:
		device.hp = 0
		# Release relations before removing the occupancy.
		for enemy: EnemyRuntime in enemies:
			if enemy.blocked_by_character_id == iid:
				enemy.blocked_by_character_id = 0
				enemy.state = BattleTypes.EnemyState.MOVING
		_remove_character_instance(iid)
		_append_removal(Removal.RETREATED,"sara_device",iid,device.column,device.lane)
	device_expiry.erase(iid)
	device_owner.erase(iid)

func _apply_area_support(source: CharacterRuntime, cfg: Dictionary, duration: float, prefix: String) -> void:
	for other: CharacterRuntime in characters:
		if other.instance_id == source.instance_id or other.character_id == "sara_device": continue
		var lanes := absi(other.lane-source.lane)
		if lanes > int(cfg.get("maxLaneDelta",1)) or absi(other.column-source.column)+lanes > int(cfg.get("rangeTiles",2)): continue
		for pair: Array in [["ATTACK_SPEED","attackSpeedPct"],["CD_RECOVERY","cdRecoveryPct"]]:
			if float(cfg.get(pair[1],0)) == 0: continue
			other.apply_status_effect_from_config({"effectId":prefix+str(pair[0]),"sourceId":source.character_id,"category":pair[0],"pct":cfg[pair[1]],"durationSeconds":duration},elapsed_seconds)

func chapter_boss() -> EnemyRuntime:
	for enemy: EnemyRuntime in enemies:
		if enemy.mechanic.get("kind", "") == "CHAPTER_BOSS" and enemy.is_active(): return enemy
	return null

func _boss_event(name: String, kind: String = "skill") -> void:
	boss_events.append({"at":elapsed_seconds,"name":name,"kind":kind,"phase":int(boss_state.get("phase",1))})
	if boss_events.size()>128: boss_events.pop_front()

func _tick_chapter_mechanics(step: float) -> void:
	for iid: Variant in device_expiry.keys():
		if elapsed_seconds >= float(device_expiry[iid]) or get_character(int(iid)) == null: _expire_device(int(iid))
	for source: CharacterRuntime in characters:
		if source.talent_config.get("effect","") == "AREA_SPEED": _apply_area_support(source,source.talent_config,.05,"presence")
	for enemy: EnemyRuntime in enemies:
		if not enemy.is_active(): continue
		if enemy.mechanic.get("kind","") == "ANXIETY_AURA":
			for c: CharacterRuntime in characters:
				if absf(enemy.logical_x-c.column)+absi(enemy.lane-c.lane)>float(enemy.mechanic.get("radiusTiles",2)): continue
				for pair: Array in [["ATTACK_SPEED","attackSpeedPct"],["CD_RECOVERY","cdRecoveryPct"]]:
					c.apply_status_effect_from_config({"effectId":"anxiety_"+str(pair[0]),"sourceId":enemy.enemy_id,"category":pair[0],"pct":enemy.mechanic[pair[1]],"durationSeconds":.05},elapsed_seconds)
		elif enemy.mechanic.get("kind","") == "RANK_COMPARE":
			var remaining := float(rank_cooldowns.get(enemy.instance_id,enemy.mechanic.get("intervalSeconds",8)))-step
			if remaining<=0:
				var target: CharacterRuntime=null
				for c: CharacterRuntime in characters:
					if absf(enemy.logical_x-c.column)+absi(enemy.lane-c.lane)>float(enemy.mechanic.get("rangeTiles",3.5)): continue
					if target==null or c.effective_attack()>target.effective_attack(): target=c
				if target!=null:
					target.apply_status_effect_from_config({"effectId":"rank_compare","sourceId":enemy.enemy_id,"category":"ATTACK","pct":enemy.mechanic.get("attackPct",-.15),"durationSeconds":enemy.mechanic.get("durationSeconds",5)},elapsed_seconds)
					remaining=float(enemy.mechanic.get("intervalSeconds",8))
			rank_cooldowns[enemy.instance_id]=remaining
	# Recalculate temporary speed from baseline; expired boosts cannot persist.
	for enemy: EnemyRuntime in enemies:
		var boost := 0.0
		if enemy.time_up_triggered: boost = maxf(boost,float(enemy.time_up_config().get("moveSpeedPct",0)))
		if elapsed_seconds < float(boss_state.get("anxietyUntil",-1)) and enemy.lane == int(boss_state.get("anxietyLane",-1)): boost += float(boss_config.get("anxietySpeedPct",.3))
		enemy.move_speed = enemy.base_move_speed*(1+boost)
	var boss := chapter_boss()
	if boss == null:
		if not boss_state.is_empty(): boss_warnings.clear()
		return
	if boss_state.is_empty():
		boss_state={"born":elapsed_seconds,"phase":1,"standard":elapsed_seconds+float(boss_config.get("standardInterval",12)),"compare":elapsed_seconds+float(boss_config.get("comparisonInterval",15)),"anxiety":elapsed_seconds+float(boss_config.get("anxietyInterval",12)),"mistake":elapsed_seconds+float(boss_config.get("mistakeInterval",18)),"ranking":elapsed_seconds+float(boss_config.get("rankingInterval",15))}
		boss_state.standard=elapsed_seconds+float(boss_config.get("firstStandardSeconds",3))
		boss_state.compare=elapsed_seconds+float(boss_config.get("firstComparisonSeconds",5))
		_boss_event("无名优等生 · 正常考试","entrance")
	var thresholds: Array = boss_config.get("phaseThresholds",[.6,.3])
	var ratio := float(boss.hp)/maxf(1,boss.hp_max)
	var phase := 3 if ratio<float(thresholds[1]) else (2 if ratio<float(thresholds[0]) else 1)
	if phase > int(boss_state.phase):
		boss_state.phase=phase
		boss_warnings.clear()
		boss_state.anxietyUntil=-1
		for c: CharacterRuntime in characters:
			c.status_effects = c.status_effects.filter(func(effect: StatusEffect) -> bool: return not effect.effect_id.begins_with("boss_"))
		var first_cast := elapsed_seconds+float(boss_config.get("phaseFirstCastSeconds",3))
		for timer: String in ["standard","compare","anxiety","mistake","ranking"]: boss_state[timer]=first_cast
		_boss_event("排名焦虑" if phase==2 else "最后五分钟","phase")
	if phase==3:
		boss.move_speed *= 1+float(boss_config.get("finalMovePct",.4))
		boss.attack_interval = float((_enemy_configs[boss.enemy_id] as Dictionary).get("attackInterval",2))/(1+float(boss_config.get("finalAttackSpeedPct",.2)))
	var age := elapsed_seconds-float(boss_state.born)
	if age>float(boss_config.get("enrageSeconds",480)):
		boss.move_speed *= 1+(age-float(boss_config.get("enrageSeconds",480)))/60
	for warning: Dictionary in boss_warnings.duplicate():
		if elapsed_seconds<float(warning.due): continue
		if warning.kind=="standard":
			for i: int in range(2):
				var spawn := EnemyRuntime.from_config(_enemy_configs["echo_normal"],int(warning.lane),_next_enemy_instance_id,boss.wave_number,true,boss.instance_id)
				_next_enemy_instance_id+=1
				spawn.logical_x=BattleGrid.SPAWN_X+float(i)*.25
				enemies.append(spawn)
		else:
			for c: CharacterRuntime in characters:
				if absf(float(c.column)-float(warning.column))+absf(float(c.lane)-float(warning.lane)) <= float(boss_config.get("mistakeRadius",1)):
					var damage := c.take_damage(combat_math.compute_damage(float(boss_config.get("mistakeDamage",220)),c.defense,CombatMath.DamageType.SPECIAL))
					_record_damage_event(false,c.instance_id,damage,c.hp<=0,"enemy",boss.instance_id,Vector2(boss.logical_x,boss.lane),Vector2(c.column,c.lane),CombatMath.DamageType.SPECIAL,true)
		boss_warnings.erase(warning)
	if (phase in [1,3] or bool(boss_config.get("summonAllPhases",false))) and elapsed_seconds >= float(boss_state.standard):
		var lane := _chapter_rng.randi_range(0,2)
		boss_state.standardCount=int(boss_state.get("standardCount",0))+1
		boss_warnings.append({"kind":"standard","lane":lane,"born":elapsed_seconds,"due":elapsed_seconds+float(boss_config.get("warningSeconds",3))})
		if bool(boss_config.get("summonAllPhases",false)):
			boss_warnings.append({"kind":"standard","lane":(lane+1)%3,"born":elapsed_seconds,"due":elapsed_seconds+float(boss_config.get("warningSeconds",3))})
		boss_state.standard=elapsed_seconds+float(boss_config.get("finalSummonInterval",12) if phase==3 else boss_config.get("standardInterval",12))
		_boss_event("最后五分钟 · 残响汇聚" if phase==3 else "标准答案 · 增援预告")
	if phase==1 and elapsed_seconds >= float(boss_state.compare) and not characters.is_empty():
		var ranked: Array[CharacterRuntime]=characters.duplicate()
		ranked.sort_custom(func(a: CharacterRuntime,b: CharacterRuntime) -> bool: return a.effective_attack()>b.effective_attack())
		ranked[0].apply_status_effect_from_config({"effectId":"boss_compare","category":"ATTACK","pct":float(boss_config.get("comparisonPct",-.15)),"durationSeconds":float(boss_config.get("comparisonDuration",5))},elapsed_seconds)
		boss_state.compare=elapsed_seconds+float(boss_config.get("comparisonInterval",15))
		_boss_event("比较 · 最高攻击角色被标记")
	if phase==2 and elapsed_seconds>=float(boss_state.anxiety):
		boss_state.anxietyLane=_chapter_rng.randi_range(0,2)
		boss_state.anxietyUntil=elapsed_seconds+float(boss_config.get("anxietyDuration",6))
		boss_state.anxiety=elapsed_seconds+float(boss_config.get("anxietyInterval",12))
		_boss_event("排名焦虑 · 路线加速")
	if phase==2 and elapsed_seconds>=float(boss_state.mistake) and not characters.is_empty():
		var target: CharacterRuntime=characters[_chapter_rng.randi_range(0,characters.size()-1)]
		boss_state.mistakeCount=int(boss_state.get("mistakeCount",0))+1
		boss_warnings.append({"kind":"mistake","column":target.column,"lane":target.lane,"born":elapsed_seconds,"due":elapsed_seconds+float(boss_config.get("warningSeconds",3))})
		boss_state.mistake=elapsed_seconds+float(boss_config.get("mistakeInterval",18))
		_boss_event("错题 · 3秒后区域爆发")
	if phase==3 and elapsed_seconds>=float(boss_state.ranking):
		var candidates := characters.duplicate()
		for i: int in range(mini(2,characters.size())):
			var index := _chapter_rng.randi_range(0,candidates.size()-1)
			var chosen: CharacterRuntime = candidates.pop_at(index)
			chosen.apply_status_effect_from_config({"effectId":"boss_ranking","category":"ATTACK","pct":float(boss_config.get("rankingPct",-.25)),"durationSeconds":float(boss_config.get("rankingDuration",6))},elapsed_seconds)
		boss_state.rankingCount=int(boss_state.get("rankingCount",0))+1
		boss_state.ranking=elapsed_seconds+float(boss_config.get("rankingInterval",15))
		_boss_event("排名公布 · 两名角色攻击降低")

func _assign_skill(character: CharacterRuntime) -> void:
	var cfg: Dictionary = _character_configs.get(character.character_id, {})
	for raw_id: Variant in cfg.get("talentIds", []):
		if _talent_configs.has(str(raw_id)):
			character.talent_config = _talent_configs[str(raw_id)].duplicate(true)
	for raw_id: Variant in cfg.get("skillIds", []):
		var skill: Dictionary = _skill_configs.get(str(raw_id), {})
		if skill.get("type", "") == "ACTIVE":
			character.skill_config = skill.duplicate(true)
			character.skill_cooldown_remaining = float(skill.get("initialCooldownSeconds", skill.get("cooldownSeconds", 0)))
			return

func cast_skill(instance_id: int) -> Dictionary:
	var character := get_character(instance_id)
	if paused or not running or character == null or character.is_incapacitated():
		return {"ok": false, "reason": "当前无法释放技能"}
	if not character.skill_ready():
		return {"ok": false, "reason": "技能冷却中、已蓄力或受到沉默"}
	var cfg := character.skill_config
	var kind := str(cfg.get("effect", ""))
	if kind == "ATTACK_WINDOW":
		character.skill_active_remaining = float(cfg.get("durationSeconds", 0))
		character.apply_status_effect_from_config({"effectId": str(cfg["id"]), "sourceId": character.character_id,
			"category": StatusEffect.CATEGORY_ATTACK, "pct": float(cfg.get("attackBonusPct", 0)),
			"durationSeconds": character.skill_active_remaining}, elapsed_seconds)
	elif kind == "NEXT_ATTACK":
		character.skill_charged = true
	elif kind == "AP_GAIN":
		add_ap(int(cfg.get("apGain", 0)))
	elif kind == "AREA_HEAL":
		for other: CharacterRuntime in characters:
			if other.character_id == "sara_device" or not _is_in_heal_range(character, other):
				continue
			var amount := other.receive_healing(character.compute_heal_amount(float(cfg.get("healMultiplier", 1))))
			if amount > 0:
				character.total_healing_done += amount
				total_healing_done += amount
				heal_events.append({"healerId":instance_id,"targetId":other.instance_id,"amount":amount,"at":elapsed_seconds})
	elif kind == "AREA_BUFF":
		_apply_area_support(character, cfg, float(cfg.get("durationSeconds", 10)), "beat")
	elif kind == "DEVICE":
		return {"ok":false,"reason":"请选择空部署格放置实验装置","needsCell":true}
	else:
		return {"ok": false, "reason": "技能效果尚未实现"}
	character.skill_cooldown_remaining = float(cfg.get("cooldownSeconds", 0))
	skill_events.append({"instanceId": instance_id, "skillId": cfg["id"], "at": elapsed_seconds})
	if skill_events.size() > 128:
		skill_events.pop_front()
	return {"ok": true, "name": cfg.get("name", ""), "skillId": cfg["id"]}

func _tick_character_skills(step: float) -> void:
	for character: CharacterRuntime in characters:
		var upgrade_rate := upgrades.bonus_pct("CD_RECOVERY", CharacterRuntime.behavior_name(character.behavior)) if upgrades != null else 0.0
		character.skill_cooldown_remaining = maxf(0.0, character.skill_cooldown_remaining - step * character.effective_cd_recovery_factor(upgrade_rate))
		character.skill_active_remaining = maxf(0.0, character.skill_active_remaining - step)

func _active_skill_targets(character: CharacterRuntime) -> Array[EnemyRuntime]:
	var targets: Array[EnemyRuntime] = []
	var cfg := character.skill_config
	var reach := float(cfg.get("rangeTiles", 0))
	for enemy: EnemyRuntime in enemies:
		if not enemy.is_active() or absi(enemy.lane-character.lane) > int(cfg.get("maxLaneDelta",0)):
			continue
		var distance := enemy.logical_x - float(character.column)
		if character.is_blocking(enemy.instance_id) or (distance >= -0.00001 and distance <= reach + 0.00001):
			targets.append(enemy)
	targets.sort_custom(func(a: EnemyRuntime, b: EnemyRuntime) -> bool:
		return a.instance_id < b.instance_id if is_equal_approx(a.logical_x, b.logical_x) else a.logical_x < b.logical_x)
	return targets.slice(0, mini(targets.size(), int(cfg.get("targetLimit", 1))))

## 撤退与再部署的默认参数（仅当权威配置缺失时兜底；正常路径一律读取配置）
const DEFAULT_RETREAT_REFUND_RATE: float = 0.5
const DEFAULT_REDEPLOY_SECONDS: float = 20.0

## 敌人/角色离场原因（供测试与日志断言；表现层据此播放不同反馈）
enum Removal {
	KILLED = 0,        ## HP ≤ 0 被击败
	REACHED_CORE = 1,  ## 抵达残响锚点并完成漏怪结算
	RETREATED = 2,     ## 玩家主动撤退
	INCAPACITATED = 3, ## 因 HP 耗尽而失能离场
}

## Wave 运行状态
enum WaveStatus {
	PENDING = 0,   ## 尚未开始
	ACTIVE = 1,    ## 进行中（正在出怪或清场）
	CLEARED = 2,   ## 已完成（计划敌人全部生成且全部离场）
}

const WAVE_PENDING := WaveStatus.PENDING
const WAVE_ACTIVE := WaveStatus.ACTIVE
const WAVE_CLEARED := WaveStatus.CLEARED

var grid: BattleGrid
var combat_math: CombatMath

var stage_id: String = ""
var core_hp_max: int = 0
var core_hp: int = 0

## AP 系统（V2.1.4 D-7）
var ap: int = 0
var ap_max: int = 0
var ap_regen_per_second: float = 0.0
## AP 回复的浮点累积（保证按逻辑步长精确增长，而非按帧）
var _ap_accumulator: float = 0.0

## 场上敌人与已部署角色
var enemies: Array[EnemyRuntime] = []
var characters: Array[CharacterRuntime] = []

## 离场记录（击杀 / 漏怪 / 主动撤退 / 失能）。供测试与结算摘要使用。
var removals: Array[Dictionary] = []

## 治疗事件记录（P0.4）：{healerId, targetId, amount, at}。
## 供测试断言与表现层播放治疗反馈；只记录**实际生效**的治疗。
var heal_events: Array[Dictionary] = []

## 伤害事件记录（P1.0）：{targetKind, targetId, amount, at, damageType, lethal}。
## 供表现层播放「伤害数字 / 受击闪白」等基础反馈（V2.1.4 D-38：每次攻击至少包含
## 攻击动画、命中特效、受击闪白、伤害数字、音效；不能只修改血量）。
##
## 纪律：
##   - 只记录**实际扣减**的 HP（amount > 0），被完全挡下或对已死目标的溢出伤害不入账；
##   - 本数组是**表现层数据源**，不参与任何战斗判定；
##   - 与 heal_events 一样按逻辑步累积，因此帧率与分辨率不影响其内容。
var damage_events: Array[Dictionary] = []
## Presentation-only monotonic sequence; array retention must not reset consumers.
var _damage_event_sequence: int = 0

## 表现层读取伤害事件时的游标（表现层自己维护；领域层不关心）
const DAMAGE_EVENT_RETENTION := 200

## 本关允许部署的角色 id（来自 StageConfig.availableCharacters）
var available_characters: Array[String] = []

## 阻挡接触线（tile，来自 balance.json combat.blocking）
var block_contact_line_tiles: float = 0.5

## 暂停开关（V2.1.4 D-35：暂停后游戏逻辑、动画、CD 与敌人移动全部停止）。
## 表现层只置位，不复制任何规则。
var paused: bool = false

## 战斗是否仍在推进。由 BattleSession 在胜负确定时置 false，
## 从领域层保证「胜负确定后所有计时器停止推进」。
var running: bool = true

## 撤退退款配置（V2.1.4 D-9 / 表 24）
var retreat_refund_rate: float = DEFAULT_RETREAT_REFUND_RATE
var retreat_refund_on_incapacitated: float = 0.0
## 再部署默认冷却（角色级 redeployTime 优先）
var redeploy_default_seconds: float = DEFAULT_REDEPLOY_SECONDS

## 减益下限（V2.1.4 L556～557 LOCKED：有效攻击力/攻击频率/CD 恢复速度不得低于
## 各自基础值的 40%）。权威值来自 balance.json 的 combat.debuffFloor；
## 部署角色时注入到 CharacterRuntime，代码内不复制第二份数值。
var debuff_floor_pct: float = CharacterRuntime.DEFAULT_DEBUFF_FLOOR

## 增益上限（V2.1.4 表 81 L2108「攻击速度加成 局内总增益原则上不超过 +80%」）。
## 权威值来自 balance.json 的 combat.buffCeiling；L2113 明标该表为测试基线，
## 故上限可配置、非 LOCKED。部署角色时注入 CharacterRuntime。
var buff_ceiling_pct: float = CharacterRuntime.DEFAULT_BUFF_CEILING

## 场上同时部署上限（V2.1.4 L614/L631/L937/L1811/L2113 LOCKED：单场最多同时部署 5 名）。
## 权威值来自 balance.json 的 combat.fieldDeployLimit（规格 L614「底层参数可配置，
## v1.1+ 角色池扩大后可提高到 8」）；配置缺失时用规格 LOCKED 默认 5。
## 仅在启用 AP/编队系统（balance_combat 非空）时施加限制——P0.1 类专项测试
## 传空 combat 字典，不受此规则约束。
## 注意：水濑纱良「临时实验装置」按 L860 不计入本上限——装置系统属 A0.6+，未实现。
const FIELD_DEPLOY_LIMIT_DEFAULT := 5
var field_deploy_limit: int = 0

## 计划中的出怪条目（来自 StageConfig，禁止写死在代码）
var _spawn_plan: Array[Dictionary] = []
var _spawn_cursor: int = 0

## Wave 元数据与运行状态
var waves: Array[Dictionary] = []
var _wave_states: Array[Dictionary] = []
var _current_wave_index: int = 0

## 累计逻辑时间（秒）
var elapsed_seconds: float = 0.0
var _accumulator: float = 0.0

var _next_enemy_instance_id: int = 1
var _next_character_instance_id: int = 1

## 敌人配置表 / 角色配置表（由 from_config 填入）
var _enemy_configs: Dictionary = {}
var _character_configs: Dictionary = {}

## Alpha A0.1：角色 id -> 成长面板（{hp, attack, defense, healPower}）。
##
## 为空表示**不启用成长**（Prototype 固定 Lv.1 行为，与 P0.4 完全一致）。
## 由调用方通过 set_character_level_stats() 注入；领域层不自行读取成长数据文件，
## 从而保持「战斗领域不依赖存档/成长系统」的分层纪律（L3）。
var _character_level_stats: Dictionary = {}

## 已部署角色的实例历史（含已离场者）。用于「撤退/死亡/重新部署不得复制实体」的断言。
var character_instances: Array[CharacterRuntime] = []

## 构建或运行期的错误（空 = 无错）
var _errors: Array[String] = []

## 统计
var core_damage_events: int = 0
var reached_core_count: int = 0
var enemies_killed: int = 0
var characters_lost: int = 0
var deploy_success_count: int = 0
var deploy_reject_count: int = 0
var retreat_count: int = 0
var retreat_refunded_ap_total: int = 0
## 全队累计实际治疗量（P0.4）
var total_healing_done: int = 0
## 战斗时长上限（秒）。超过后不再生成敌人，避免「敌人被永久阻挡」导致对局永不结束。
var _max_battle_seconds: float = 0.0


## 从 StageConfig 与配置表构建 StageRuntime。
## enemy_table:    { enemyId -> EnemyConfig }
## character_table:{ characterId -> CharacterConfig }
## upgrades_domain: data/upgrades.json 的内容（Alpha A0.6）。
##   与 enemy_table/character_table 同一套路：**由调用方注入**，
##   域层不直接读 DataRegistry（保持「领域不依赖存档/全局单例」的分层纪律）。
##   不传（空字典）= 本局不启用局内强化，所有倍率恒为 1.0。
static func from_config(
	stage_config: Dictionary,
	enemy_table: Dictionary,
	grid: BattleGrid,
	character_table: Dictionary = {},
	balance_combat: Dictionary = {},
	upgrades_domain: Dictionary = {}
) -> StageRuntime:
	var rt := StageRuntime.new()
	rt.grid = grid
	rt._enemy_configs = enemy_table
	rt._character_configs = character_table
	rt.ap_regen_bonus_cap = float(balance_combat.get("apRegenBonusCap", 0.5))

	if grid == null or not grid.is_valid():
		rt._errors.append("BattleGrid 无效，无法构建 StageRuntime")

	var sid := str(stage_config.get("stageId", ""))
	if sid.is_empty():
		rt._errors.append("StageConfig 缺少 stageId")
	rt.stage_id = sid
	rt._chapter_rng.seed = sid.hash()
	rt.boss_config = stage_config.get("bossConfig", {}).duplicate(true)
	rt.sequential_waves = bool(stage_config.get("sequentialWaves", false))

	# ---- 核心 HP ----
	var core_hp_raw: Variant = stage_config.get("coreHp", null)
	if core_hp_raw == null:
		rt._errors.append("StageConfig 缺少 coreHp")
	elif int(core_hp_raw) <= 0:
		rt._errors.append("StageConfig.coreHp 必须为正整数，实际 %s" % core_hp_raw)
	else:
		rt.core_hp_max = int(core_hp_raw)
		rt.core_hp = int(core_hp_raw)

	# ---- AP（V2.1.4 D-7：开局 10 / 上限 30 / 自然恢复 1 每秒）----
	# 设计说明：balance_combat 为空表示本次运行未启用 AP 系统（例如 P0.1 的
	# 移动/漏怪专项测试只关心战场推进）。此时 AP 保持 0 且不报错；
	# 一旦提供了 balance.combat（正式战斗必然提供），则严格执行必填校验。
	if balance_combat.is_empty():
		rt.ap = 0
		rt.ap_max = 0
		rt.ap_regen_per_second = 0.0
	else:
		var starting_ap: Variant = stage_config.get("startingAp", null)
		if starting_ap == null:
			rt._errors.append("StageConfig 缺少 startingAp")
		elif int(starting_ap) < 0:
			rt._errors.append("StageConfig.startingAp 不能为负，实际 %s" % starting_ap)

		var max_ap_raw: Variant = balance_combat.get("maxAp", null)
		if max_ap_raw == null:
			rt._errors.append("balance.combat 缺少 maxAp")
		elif int(max_ap_raw) <= 0:
			rt._errors.append("balance.combat.maxAp 必须为正整数，实际 %s" % max_ap_raw)

		var regen_raw: Variant = stage_config.get("apRegen", null)
		if regen_raw == null:
			rt._errors.append("StageConfig 缺少 apRegen")
		elif float(regen_raw) < 0.0:
			rt._errors.append("StageConfig.apRegen 不能为负，实际 %s" % regen_raw)

		if starting_ap != null and max_ap_raw != null and regen_raw != null \
			and int(max_ap_raw) > 0 and int(starting_ap) >= 0 and float(regen_raw) >= 0.0:
			rt.ap = mini(int(starting_ap), int(max_ap_raw))
			rt.ap_max = int(max_ap_raw)
			rt.ap_regen_per_second = float(regen_raw)

	# ---- 伤害公式参数（V2.1.4 D-22）----
	rt.combat_math = CombatMath.from_config(balance_combat.get("damage", {}))
	# 同上：未启用战斗数值时，使用代码默认参数而不报错
	if not balance_combat.is_empty():
		rt._errors.append_array(rt.combat_math.get_errors())

	# ---- 阻挡接触线 ----
	var blocking_cfg: Dictionary = balance_combat.get("blocking", {})
	if balance_combat.is_empty():
		rt.block_contact_line_tiles = 0.5
	elif blocking_cfg.has("contactLineTiles"):
		rt.block_contact_line_tiles = float(blocking_cfg["contactLineTiles"])
	else:
		rt._errors.append("balance.combat.blocking 缺少 contactLineTiles")

	# ---- 撤退退款与再部署冷却（V2.1.4 D-9 / 表 24）----
	var retreat_cfg: Dictionary = balance_combat.get("retreat", {})
	if retreat_cfg.has("refundRate"):
		var rate := float(retreat_cfg["refundRate"])
		if rate < 0.0 or rate > 1.0:
			rt._errors.append("balance.combat.retreat.refundRate 必须落在 0.0～1.0，实际 %s" % rate)
		else:
			rt.retreat_refund_rate = rate
	elif not balance_combat.is_empty():
		rt._errors.append("balance.combat.retreat 缺少 refundRate")
	rt.retreat_refund_on_incapacitated = float(
		retreat_cfg.get("refundOnIncapacitated", 0.0)
	)

	var redeploy_cfg: Dictionary = balance_combat.get("redeploy", {})
	if redeploy_cfg.has("defaultSeconds"):
		var secs := float(redeploy_cfg["defaultSeconds"])
		if secs < 0.0:
			rt._errors.append("balance.combat.redeploy.defaultSeconds 不能为负，实际 %s" % secs)
		else:
			rt.redeploy_default_seconds = secs
	elif not balance_combat.is_empty():
		rt._errors.append("balance.combat.redeploy 缺少 defaultSeconds")

	# ---- 减益下限（V2.1.4 L556～557 LOCKED：「有效攻击力、有效攻击频率、有效技能冷却
	#      恢复速度均不得低于各自基础值的 40%（首轮可配置下限）。上述减益下限首章
	#      统一存于 balance.json」）----
	# 权威值只来自 balance.json；缺段时用规格值 0.4 兜底但**不静默通过**（报错），
	# 以便「规格要求承载于 balance.json」这条纪律可被验证。
	var floor_cfg: Dictionary = balance_combat.get("debuffFloor", {})
	if floor_cfg.is_empty():
		if not balance_combat.is_empty():
			rt._errors.append("balance.combat 缺少 debuffFloor（V2.1.4 L557 要求减益下限存于 balance.json）")
	else:
		var floor_pct := float(floor_cfg.get("attackSpeedPct", CharacterRuntime.DEFAULT_DEBUFF_FLOOR))
		if floor_pct <= 0.0 or floor_pct > 1.0:
			rt._errors.append(
				"balance.combat.debuffFloor.attackSpeedPct 必须落在 (0, 1]，实际 %s" % floor_pct)
		else:
			rt.debuff_floor_pct = floor_pct
		# 三项下限当前均为同一规格值 40%，若配置被拆成不同值则显式报错，
		# 避免「配置改了一项、代码只读了一项」这种静默不一致。
		for key: String in ["attackPct", "cdRecoveryPct"]:
			if floor_cfg.has(key) and not is_equal_approx(float(floor_cfg[key]), floor_pct):
				rt._errors.append(
					"balance.combat.debuffFloor.%s（%s）与 attackSpeedPct（%s）不一致；"
					% [key, str(floor_cfg[key]), str(floor_pct)]
					+ "当前构建只实现单一统一下限，拆分需先补实现")

	# ---- 增益上限（V2.1.4 表 81 L2108：攻击速度加成局内总增益不超过 +80%）----
	# 与下限不同，表 81 被规格 L2113 明标为「测试基线，不是最终数值」，
	# 因此上限可配置、非 LOCKED；缺失时用代码兜底值而不报错。
	var ceiling_cfg: Dictionary = balance_combat.get("buffCeiling", {})
	if not ceiling_cfg.is_empty():
		var ceiling := float(ceiling_cfg.get("attackSpeedPct", CharacterRuntime.DEFAULT_BUFF_CEILING))
		if ceiling < 1.0:
			rt._errors.append(
				"balance.combat.buffCeiling.attackSpeedPct 必须 ≥ 1.0（基础值 1.0 加上正增益），实际 %s"
				% ceiling)
		else:
			rt.buff_ceiling_pct = ceiling

	# ---- 场上同时部署上限（V2.1.4 L614/L631/L937/L1811/L2113 LOCKED）----
	# 仅在启用 AP/编队系统（balance_combat 非空）时生效；配置缺失时用规格默认 5。
	# 此前该值只存在于 balance.json 而**无任何代码读取**，等于 LOCKED 规则未实现；
	# 首章最多 3 名可部署角色，故启用后对现有关卡行为零影响，但它是 A0.6 六人编队的前置。
	if not balance_combat.is_empty():
		var raw_limit: Variant = balance_combat.get("fieldDeployLimit", FIELD_DEPLOY_LIMIT_DEFAULT)
		# Godot 的 JSON 解析把所有数字给 float（5 -> 5.0），因此接受
		# INT/FLOAT 两种类型，但必须是正整数值。
		var limit_ok := (typeof(raw_limit) == TYPE_INT or typeof(raw_limit) == TYPE_FLOAT) \
			and int(raw_limit) > 0 and is_equal_approx(float(raw_limit), float(int(raw_limit)))
		if not limit_ok:
			rt._errors.append(
				"balance.combat.fieldDeployLimit 必须为正整数，实际 %s" % str(raw_limit))
		else:
			rt.field_deploy_limit = int(raw_limit)

	# ---- 局内强化开放（Alpha A0.6，L2129～2138）----
	# 只有 upgrades.json 的 openByStage 显式声明 opens > 0 的关卡才创建实例；
	# 其余关卡保持 null ⇒ 所有倍率短路为 1.0，与接入前逐位一致。
	rt._configure_upgrades(upgrades_domain)

	# ---- 可部署角色列表 ----
	if stage_config.has("availableCharacters"):
		var ac: Variant = stage_config["availableCharacters"]
		if typeof(ac) == TYPE_ARRAY:
			for cid: Variant in ac:
				rt.available_characters.append(str(cid))
		else:
			rt._errors.append("availableCharacters 必须是数组")
	else:
		rt._errors.append("StageConfig 缺少 availableCharacters")

	# ---- 角色行为分类与治疗参数校验（P0.4 三职业统一框架）----
	rt._validate_character_behaviors()

	# ---- 出怪时间线（唯一数据源）----
	rt._spawn_plan = rt._validate_spawn_timeline(stage_config, enemy_table)
	if rt.sequential_waves:
		rt._spawn_plan.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			return float(a.time)<float(b.time) if int(a.get("wave",1))==int(b.get("wave",1)) else int(a.get("wave",1))<int(b.get("wave",1)))
	rt._max_battle_seconds = rt._compute_max_battle_seconds()

	# ---- Wave 元数据与运行状态 ----
	rt._build_waves(stage_config)
	return rt


## 校验并规范化出怪时间线，返回按时间升序的条目数组。
## 校验角色配置中的行为分类与治疗参数（P0.4 三职业统一框架）。
## 设计纪律：行为必须由数据显式声明，**禁止按 classType 字符串猜**；
## 声明非法时在构建期报错，而不是静默退化成默认行为。
func _validate_character_behaviors() -> void:
	for cid: String in _character_configs.keys():
		var cfg: Dictionary = _character_configs[cid]
		if not cfg.has("behavior"):
			_errors.append("角色 %s 缺少 behavior（P0.4 起必填：FRONTLINE / RANGED / HEALER）" % cid)
			continue
		var text := str(cfg["behavior"])
		var behavior := CharacterRuntime.parse_behavior(text)
		if behavior < 0:
			_errors.append("角色 %s 的 behavior 非法（'%s'），必须是 FRONTLINE / RANGED / HEALER"
				% [cid, text])
			continue

		var range_cfg: Dictionary = cfg.get("attackRange", {})
		if range_cfg.is_empty():
			_errors.append("角色 %s 缺少 attackRange（射程与治疗范围必须由数据声明）" % cid)
			continue

		if behavior == CharacterRuntime.Behavior.HEALER:
			if int(cfg.get("healPower", 0)) <= 0:
				_errors.append("治疗角色 %s 缺少正的 healPower" % cid)
			if str(range_cfg.get("shape", "")) != "manhattan":
				_errors.append("治疗角色 %s 的 attackRange.shape 必须是 manhattan（V2.1.4 表 30）" % cid)
			if not range_cfg.has("maxLaneDelta"):
				_errors.append("治疗角色 %s 必须显式声明 maxLaneDelta（跨线不得由几何距离推导）" % cid)
		else:
			# 输出角色不得携带治疗力，避免出现第二套治疗来源
			if int(cfg.get("healPower", 0)) > 0:
				_errors.append("非治疗角色 %s 不应声明 healPower" % cid)

		# 阻挡能力必须与规格一致：远程 / 治疗为 0（表 25 / 28 / 30）
		if behavior != CharacterRuntime.Behavior.FRONTLINE and int(cfg.get("blockCount", 0)) > 0:
			_errors.append("非前线角色 %s 的 blockCount 必须为 0（V2.1.4 表 25 / 表 28 / 表 30）" % cid)

		# ---- 裁决 DEC-C-0003：跨线攻击声明的一致性校验 ----
		# 纪律：跨线能力必须由角色数据显式声明，禁止按 behavior 推导；
		# 声明自相矛盾时在构建期报错，而不是静默退化成某一种行为。
		rt_validate_cross_lane(cid, behavior, range_cfg)


## 校验单个角色的跨线攻击声明（裁决 DEC-C-0003）。
##
## 规则：
##   ① 治疗角色不得声明跨线攻击（治疗走 manhattan + maxLaneDelta 的既有路径）；
##   ② allowCrossLane=true 必须同时满足 maxLaneDelta ≥ 1（否则声明自相矛盾）；
##   ③ maxLaneDelta ≥ 1 但 allowCrossLane 缺失/false → 报错（防止「配了跨线却没生效」）；
##   ④ adjacentLaneRangeTiles 不得大于本路线 rangeTiles（相邻路线不应比本路线更远）；
##   ⑤ targetLimit 必须为 1（DEC-C-0003：每次普通攻击只选择一个目标）。
func rt_validate_cross_lane(cid: String, behavior: int, range_cfg: Dictionary) -> void:
	var allow := bool(range_cfg.get("allowCrossLane", false))
	var delta := int(range_cfg.get("maxLaneDelta", 0))

	if behavior == CharacterRuntime.Behavior.HEALER:
		if allow:
			_errors.append("治疗角色 %s 不得声明 allowCrossLane（治疗范围走 manhattan + maxLaneDelta）" % cid)
		return

	if allow and delta < 1:
		_errors.append(
			"角色 %s 声明 allowCrossLane=true 但 maxLaneDelta=%d；跨线必须同时给出 ≥1 的 maxLaneDelta"
			% [cid, delta])
	elif not allow and delta >= 1:
		_errors.append(
			"角色 %s 的 maxLaneDelta=%d 但未声明 allowCrossLane=true；"
			% [cid, delta]
			+ "DEC-C-0003 要求跨线能力显式声明，不得只改 maxLaneDelta 就期待生效")

	if allow:
		var own_range := float(range_cfg.get("rangeTiles", 0.0))
		var adj_range := float(range_cfg.get("adjacentLaneRangeTiles", 0.0))
		if adj_range <= 0.0:
			_errors.append("角色 %s 声明跨线但缺少正的 adjacentLaneRangeTiles" % cid)
		elif adj_range > own_range + 0.0001:
			_errors.append(
				"角色 %s 的 adjacentLaneRangeTiles（%s）不得大于本路线 rangeTiles（%s）"
				% [cid, adj_range, own_range])
		if int(range_cfg.get("targetLimit", 1)) != 1:
			_errors.append(
				"角色 %s 的 targetLimit 必须为 1（DEC-C-0003：每次普通攻击只选择一个目标），实际 %s"
				% [cid, str(range_cfg.get("targetLimit", 1))])


func _validate_spawn_timeline(
	stage_config: Dictionary,
	enemy_table: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if not stage_config.has("enemySpawnTimeline"):
		_errors.append("StageConfig 缺少 enemySpawnTimeline")
		return out

	var raw: Variant = stage_config["enemySpawnTimeline"]
	if typeof(raw) != TYPE_ARRAY:
		_errors.append("enemySpawnTimeline 必须是数组")
		return out

	var timeline: Array = raw
	for i: int in range(timeline.size()):
		var entry: Variant = timeline[i]
		if typeof(entry) != TYPE_DICTIONARY:
			_errors.append("enemySpawnTimeline[%d] 必须是对象" % i)
			continue
		var e: Dictionary = entry

		if not e.has("time"):
			_errors.append("enemySpawnTimeline[%d] 缺少 time" % i)
			continue
		var t := float(e["time"])
		if t < 0.0:
			_errors.append("enemySpawnTimeline[%d].time 不能为负（%s）" % [i, t])
			continue

		if not e.has("lane"):
			_errors.append("enemySpawnTimeline[%d] 缺少 lane" % i)
			continue
		var lane := int(e["lane"])
		if not BattleTypes.is_valid_lane(lane):
			_errors.append(
				"enemySpawnTimeline[%d].lane 非法（%d），必须为 0～%d"
				% [i, lane, BattleTypes.LANE_COUNT - 1]
			)
			continue

		if not e.has("enemy"):
			_errors.append("enemySpawnTimeline[%d] 缺少 enemy" % i)
			continue
		var enemy_id := str(e["enemy"])
		if enemy_id.is_empty():
			_errors.append("enemySpawnTimeline[%d].enemy 为空" % i)
			continue
		if not enemy_table.has(enemy_id):
			_errors.append(
				"enemySpawnTimeline[%d].enemy 引用了不存在的敌人 ID：'%s'"
				% [i, enemy_id]
			)
			continue

		# wave 为可选字段：缺省时归入第 1 波，保持旧配置可用。
		var wave_no := 0
		if e.has("wave"):
			wave_no = int(e["wave"])
			if wave_no < 1:
				_errors.append("enemySpawnTimeline[%d].wave 必须 ≥ 1，实际 %d" % [i, wave_no])
				continue

		out.append({
			"time": t, "lane": lane, "enemy": enemy_id,
			"index": i, "wave": wave_no,
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["time"]), float(b["time"])):
			return float(a["time"]) < float(b["time"])
		return int(a["index"]) < int(b["index"])
	)
	return out


## 战斗时长上限：最后一个计划出怪时间 + 敌人从入口走到核心所需时间 + 余量。
## 超过后不再生成敌人，保证「敌人被永久阻挡」时对局仍能收敛到胜负。
func _compute_max_battle_seconds() -> float:
	if _spawn_plan.is_empty():
		return 0.0
	var last_time := 0.0
	for e: Dictionary in _spawn_plan:
		last_time = maxf(last_time, float(e["time"]))
	return last_time + 40.0


## 构建 Wave 元数据与运行状态。
##
## 数据单一来源纪律（V2.1.4 B6 + 本轮要求）：
##   enemySpawnTimeline 是**出怪时间/路线/敌人种类的唯一数据源**；
##   StageConfig.waves 只承载波次**元数据**（编号、显示名、完成条件），
##   不得重复保存敌人安排。两者通过 timeline 条目的 wave 字段关联。
func _build_waves(stage_config: Dictionary) -> void:
	waves.clear()
	_wave_states.clear()
	_current_wave_index = 0

	# 1) 元数据：优先取配置，缺失时自动推导
	var meta_by_number := {}
	var ordered_numbers: Array[int] = []
	if stage_config.has("waves"):
		var raw: Variant = stage_config["waves"]
		if typeof(raw) != TYPE_ARRAY:
			_errors.append("StageConfig.waves 必须是数组")
		else:
			for i: int in range((raw as Array).size()):
				var wv: Variant = (raw as Array)[i]
				if typeof(wv) != TYPE_DICTIONARY:
					_errors.append("waves[%d] 必须是对象" % i)
					continue
				var w: Dictionary = wv
				var num := int(w.get("number", 0))
				if num < 1:
					_errors.append("waves[%d].number 必须 ≥ 1" % i)
					continue
				if meta_by_number.has(num):
					_errors.append("waves 出现重复编号 %d" % num)
					continue
				var cond := str(w.get("clearCondition", "ALL_ENEMIES_DEFEATED"))
				if cond != "ALL_ENEMIES_DEFEATED":
					_errors.append(
						"waves[%d].clearCondition 暂只支持 ALL_ENEMIES_DEFEATED，实际 '%s'"
						% [i, cond]
					)
				meta_by_number[num] = {
					"number": num,
					"label": str(w.get("label", "Wave %d" % num)),
					"clearCondition": cond,
				}
				ordered_numbers.append(num)

	# 2) 依据 timeline 的实际引用决定真实波次集合（timeline 是唯一出怪来源）
	var referenced: Array[int] = []
	var counts := {}
	var last_time := {}
	var lanes_by_wave := {}
	for e: Dictionary in _spawn_plan:
		var n := int(e["wave"])
		if n <= 0:
			# 未标注 wave 的条目归入第 1 波，保证旧配置向后兼容
			n = 1
		if not referenced.has(n):
			referenced.append(n)
		counts[n] = int(counts.get(n, 0)) + 1
		last_time[n] = maxf(float(last_time.get(n, 0.0)), float(e["time"]))
		var lanes: Array = lanes_by_wave.get(n, [])
		var lane := int(e["lane"])
		if not lanes.has(lane):
			lanes.append(lane)
		lanes_by_wave[n] = lanes
	referenced.sort()

	# 配置声明了波次却没有任何出怪 → 数据自相矛盾，必须报错而不是静默通过
	if not meta_by_number.is_empty():
		for n: int in ordered_numbers:
			if not referenced.has(n):
				_errors.append(
					"waves 声明了第 %d 波，但 enemySpawnTimeline 中没有任何敌人归属该波" % n
				)
		# 出怪引用了未声明的波次 → 同样报错，避免出现「影子波次」
		for n: int in referenced:
			if not meta_by_number.has(n):
				_errors.append("enemySpawnTimeline 引用了未在 waves 中声明的第 %d 波" % n)

	for idx: int in range(referenced.size()):
		var num: int = referenced[idx]
		var meta: Dictionary = meta_by_number.get(num, {})
		waves.append({
			"number": num,
			"label": str(meta.get("label", "Wave %d" % num)),
			"clearCondition": str(meta.get("clearCondition", "ALL_ENEMIES_DEFEATED")),
			"enemyCount": int(counts.get(num, 0)),
			"lanes": lanes_by_wave.get(num, []),
		})

	if waves.is_empty():
		# 没有任何出怪的关卡（例如调试用空关卡）不视为错误，但胜负门槛仍需可判定
		_current_wave_index = 0
		return

	# 3) 运行状态
	for i: int in range(waves.size()):
		_wave_states.append({
			"index": i,
			"number": int(waves[i]["number"]),
			"status": WAVE_PENDING,
			"spawnIndexFirst": -1,
			"spawnIndexLast": -1,
			"spawned": 0,
			"killed": 0,
			"leaked": 0,
			# A0.2：衍生体（复制体）的击杀/漏怪子计数。
			# 它们照常计入 killed/leaked（供复盘显示「本波共处理 N 个敌人」），
			# 但**不构成波次完成门槛**——门槛只数计划内本体（见 _update_wave_progress）。
			"killedDerived": 0,
			"leakedDerived": 0,
		})
	# 建立 timeline 游标区间（按规范化后的顺序，与 _spawn_cursor 一一对应）
	for i: int in range(_spawn_plan.size()):
		var n := int(_spawn_plan[i]["wave"])
		if n <= 0:
			n = 1
		for wi: int in range(waves.size()):
			if int(waves[wi]["number"]) == n:
				if int(_wave_states[wi]["spawnIndexFirst"]) < 0:
					_wave_states[wi]["spawnIndexFirst"] = i
				_wave_states[wi]["spawnIndexLast"] = i
				break

	_wave_states[0]["status"] = WAVE_ACTIVE
	_current_wave_index = 0


func get_errors() -> Array[String]:
	return _errors


## 注入角色成长面板（Alpha A0.1）。
##
## stats_by_character: { characterId -> {hp, attack, defense, healPower?} }
## 传入空字典即回到「不启用成长」（Prototype 固定 Lv.1）。
## 纪律：本方法**只存引用数据**，不校验、不计算；面板由 CharacterProgress 负责。
func set_character_level_stats(stats_by_character: Dictionary) -> void:
	_character_level_stats = stats_by_character.duplicate(true)


## 当前是否启用了成长面板
func has_level_stats() -> bool:
	return not _character_level_stats.is_empty()


func is_valid() -> bool:
	return _errors.is_empty()


func planned_enemy_count() -> int:
	return _spawn_plan.size()


func spawned_enemy_count() -> int:
	return _spawn_cursor


func all_planned_spawned() -> bool:
	return _spawn_cursor >= _spawn_plan.size()


func has_living_enemies() -> bool:
	for e: EnemyRuntime in enemies:
		if e.is_active():
			return true
	return false


## 场上尚能作战的角色数量
func living_character_count() -> int:
	var n := 0
	for c: CharacterRuntime in characters:
		if not c.is_incapacitated() and c.character_id != "sara_device":
			n += 1
	return n


# ============================================================
#  AP 系统（V2.1.4 D-7）
# ============================================================

## AP 是否足以支付某费用
func can_afford(cost: int) -> bool:
	return ap >= cost


## 增加 AP（不超过上限）。返回实际入账量。
## 预留 AP 加成扩展点（后续角色/装备可调用）。
func add_ap(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := ap
	ap = mini(ap_max, ap + amount)
	return ap - before


## 尝试扣除 AP。不足则返回 false 且不改变 AP。
func try_spend_ap(cost: int) -> bool:
	if cost < 0:
		return false
	if ap < cost:
		return false
	ap -= cost
	return true


# ============================================================
#  角色部署（V2.1.4 D-6 / E 章）
# ============================================================

## 部署被拒绝的原因（用于 UI 与测试断言）
enum DeployReject {
	OK = 0,
	INVALID_CELL = 1,
	CELL_OCCUPIED = 2,
	CHARACTER_NOT_AVAILABLE = 3,
	CHARACTER_ALREADY_DEPLOYED = 4,
	INSUFFICIENT_AP = 5,
	BATTLE_FINISHED = 6,
	REDEPLOY_COOLDOWN = 7,
	FIELD_LIMIT_REACHED = 8,
}

## 部署请求结果
class DeployResult:
	extends RefCounted
	var ok: bool = false
	var reason: int = DeployReject.OK
	var character: CharacterRuntime = null
	var cost: int = 0
	## 被拒时若与再部署冷却有关，携带剩余秒数（供 UI 显示倒计时）
	var cooldown_remaining: float = 0.0
	## 被拒原因=场上人数上限时携带该上限（内嵌类不访问外层字段，显式传递）
	var field_limit: int = 0

	func reason_text() -> String:
		match reason:
			DeployReject.OK:
				return "可部署"
			DeployReject.INVALID_CELL:
				return "非法部署格"
			DeployReject.CELL_OCCUPIED:
				return "该格已被占用"
			DeployReject.CHARACTER_NOT_AVAILABLE:
				return "本关不可使用该角色"
			DeployReject.CHARACTER_ALREADY_DEPLOYED:
				return "该角色已在场"
			DeployReject.INSUFFICIENT_AP:
				return "AP 不足"
			DeployReject.BATTLE_FINISHED:
				return "战斗已结束"
			DeployReject.REDEPLOY_COOLDOWN:
				return "再部署冷却中（剩余 %.1f 秒）" % cooldown_remaining
			DeployReject.FIELD_LIMIT_REACHED:
				return "场上已达同时部署上限（%d 名）" % field_limit
			_:
				return "未知原因(%d)" % reason


## 查询某格能否部署指定角色（**不产生副作用**，供 UI 悬停反馈使用）。
## 这是部署合法性的唯一判定入口，UI 不得复制规则。
func query_deploy(character_id: String, column: int, lane: int) -> DeployResult:
	var r := DeployResult.new()
	r.character = null

	if not running:
		r.reason = DeployReject.BATTLE_FINISHED
		return r

	if not BattleTypes.is_valid_column(column) or not BattleTypes.is_valid_lane(lane):
		r.reason = DeployReject.INVALID_CELL
		return r

	if not available_characters.has(character_id):
		r.reason = DeployReject.CHARACTER_NOT_AVAILABLE
		return r

	if not _character_configs.has(character_id):
		r.reason = DeployReject.CHARACTER_NOT_AVAILABLE
		return r

	# 再部署冷却优先于占用/AP 判定：冷却期间角色卡必须显示剩余时间（V2.1.4 J 章）
	var cooldown := get_redeploy_remaining(character_id)
	if cooldown > 0.0:
		r.reason = DeployReject.REDEPLOY_COOLDOWN
		r.cooldown_remaining = cooldown
		r.cost = _deploy_cost(character_id)
		return r

	if get_character_by_id(character_id) != null:
		r.reason = DeployReject.CHARACTER_ALREADY_DEPLOYED
		return r

	if get_character_at(column, lane) != null:
		r.reason = DeployReject.CELL_OCCUPIED
		return r

	# 场上同时部署上限（V2.1.4 LOCKED，L614/L1811/L2113）。置于 AP 判定之前：
	# 满员时 AP 再够也放不了，先报"上限"比"AP 不足"更准确（AP 会自然回复，
	# 空位不会自己出现）。启用条件：field_deploy_limit > 0（见字段注释）。
	if field_deploy_limit > 0 and field_character_count() >= field_deploy_limit:
		r.reason = DeployReject.FIELD_LIMIT_REACHED
		r.field_limit = field_deploy_limit
		r.cost = int(_character_configs[character_id].get("deployCost", 0))
		return r

	var cfg: Dictionary = _character_configs[character_id]
	var cost := deployment_cost(character_id)
	r.cost = cost
	if not can_afford(cost):
		r.reason = DeployReject.INSUFFICIENT_AP
		return r

	r.ok = true
	r.reason = DeployReject.OK
	return r


## 执行部署。成功才扣 AP（失败不得扣费）。
func deploy_character(character_id: String, column: int, lane: int) -> DeployResult:
	var r := query_deploy(character_id, column, lane)
	if not r.ok:
		deploy_reject_count += 1
		GameLog.debug("StageRuntime", "部署被拒：%s（%s @ col%d lane%d）"
			% [r.reason_text(), character_id, column, lane])
		return r

	var cfg: Dictionary = _character_configs[character_id]
	# 先扣费（此时已确保可支付）
	if not try_spend_ap(r.cost):
		# 理论上不可达；保守起见按 AP 不足处理
		r.ok = false
		r.reason = DeployReject.INSUFFICIENT_AP
		deploy_reject_count += 1
		return r

	# 重新部署一律创建**全新的运行时实例**（HP 满、攻击冷却就绪）；
	# 旧实例留在 character_instances 里作为离场历史，不再出现在 characters 中。
	# Alpha A0.1：若调用方注入了成长面板（level_stats），用它覆盖 baseStats 的
	# hp/attack/defense/healPower —— 等级因此影响战斗，而无需复制第二份角色面板。
	var growth_stats: Dictionary = _character_level_stats.get(character_id, {})
	var inst := CharacterRuntime.from_config(
		cfg, column, lane, _next_character_instance_id, growth_stats)
	inst.paid_deploy_cost = r.cost
	if not _deploy_discount.is_empty() and elapsed_seconds <= float(_deploy_discount.get("until", -1)) and character_id != str(_deploy_discount.get("source", "")):
		_deploy_discount.clear()
	_next_character_instance_id += 1
	inst.redeploy_time = _redeploy_seconds(character_id)
	# A0.2：注入减益下限（权威值来自 balance.json 的 combat.debuffFloor）。
	# 新实例不带任何状态效果（旧实例的减益不继承）。
	inst.debuff_floor_pct = debuff_floor_pct
	# DEC-C-0004：注入增益上限（权威值来自 balance.json 的 combat.buffCeiling）。
	inst.buff_ceiling_pct = buff_ceiling_pct
	_assign_skill(inst)
	if inst.talent_config.get("effect", "") == "NEXT_DEPLOY_DISCOUNT":
		_deploy_discount = {"source": character_id, "until": elapsed_seconds + float(inst.talent_config.get("durationSeconds", 0)), "amount": int(inst.talent_config.get("apDiscount", 0))}
	characters.append(inst)
	character_instances.append(inst)
	r.character = inst
	deploy_success_count += 1
	GameLog.info("StageRuntime", "部署 %s 到 (col%d, lane%d)，费用 %d AP，剩余 %d AP"
		% [inst.display_name, column, lane, r.cost, ap])
	return r


## 取指定 id 已部署的角色（未部署返回 null）
func get_character_by_id(character_id: String) -> CharacterRuntime:
	for c: CharacterRuntime in characters:
		if c.character_id == character_id:
			return c
	return null


## 取指定 id 最近一次生成的实例（含已离场者；从未部署返回 null）。
## 再部署冷却即挂在该实例上。
func get_character_instance(character_id: String) -> CharacterRuntime:
	for i: int in range(character_instances.size() - 1, -1, -1):
		if character_instances[i].character_id == character_id:
			return character_instances[i]
	return null


## 取某格上的角色（空返回 null）
func get_character_at(column: int, lane: int) -> CharacterRuntime:
	for c: CharacterRuntime in characters:
		if c.column == column and c.lane == lane:
			return c
	return null


# ============================================================
#  部署预览（裁决 DEC-C-0003 / 第四阶段：射程提示）
# ============================================================

## 查询某角色若部署在 (column, lane) 时的**攻击覆盖范围**（供 UI 部署预览使用）。
##
## 返回 [{lane, rangeTiles, isAdjacent, cells:[{column, lane}]}, ...]，按 lane 升序。
## 「cells」是该路线内被覆盖的**部署格**集合（仅用于可视化高亮；敌人不占格，
## 因此真实可打范围是连续区间，格集合是面向玩家的近似提示）。
##
## 纪律：
##   - 本方法**无副作用**，不部署、不扣 AP；
##   - 覆盖范围与真实攻击判定共用同一套数据（attack_range_for_lane），
##     因此 UI 不可能显示出一个实际打不到的范围；
##   - 治疗角色返回其治疗覆盖（曼哈顿 + maxLaneDelta），语义与输出角色一致。
func query_attack_coverage(character_id: String, column: int, lane: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _character_configs.has(character_id):
		return out
	if not BattleTypes.is_valid_column(column) or not BattleTypes.is_valid_lane(lane):
		return out

	var cfg: Dictionary = _character_configs[character_id]
	var behavior := CharacterRuntime.parse_behavior(str(cfg.get("behavior", "")))
	var range_cfg: Dictionary = cfg.get("attackRange", {})
	if range_cfg.is_empty():
		return out

	# 构造一个**临时探针实例**复用 CharacterRuntime 的射程判定，避免复制第二份规则。
	# 该实例不进入 characters，不参与任何战斗结算。
	var probe := CharacterRuntime.from_config(cfg, column, lane, 0, {})
	var max_delta := 0
	if behavior == CharacterRuntime.Behavior.HEALER:
		# 治疗角色：跨线仍受 maxLaneDelta 约束，且无「前方」方向性
		max_delta = probe.max_lane_delta
	else:
		max_delta = probe.max_lane_delta if probe.allow_cross_lane else 0

	for d: int in range(-max_delta, max_delta + 1):
		var target_lane := lane + d
		if not BattleTypes.is_valid_lane(target_lane):
			continue
		var eff_range := probe.attack_range_for_lane(target_lane)
		if eff_range <= 0.0:
			continue
		var covered: Array[Dictionary] = []
		for col: int in range(BattleTypes.COLUMN_COUNT):
			var in_range := false
			if behavior == CharacterRuntime.Behavior.HEALER:
				# 治疗覆盖：以治疗者所在格为圆心，按曼哈顿距离近似到格中心
				var manhattan := absi(col - column) + absi(target_lane - lane)
				in_range = float(manhattan) <= eff_range + 0.0001
			else:
				# 输出覆盖：目标格中心落在「前方 0 ~ 射程」区间内
				var delta_x := float(col) - float(column)
				in_range = delta_x >= -0.0001 and delta_x <= eff_range + 0.0001
			if in_range:
				covered.append({"column": col, "lane": target_lane})
		out.append({
			"lane": target_lane,
			"rangeTiles": eff_range,
			"isAdjacent": d != 0,
			"cells": covered,
		})
	return out


## 某角色当前的再部署剩余秒数（0 = 可部署）
func get_redeploy_remaining(character_id: String) -> float:
	var inst := get_character_instance(character_id)
	if inst == null:
		return 0.0
	# 仍在场上（未离场）时冷却无意义
	if get_character_by_id(character_id) != null:
		return 0.0
	return maxf(0.0, inst.redeploy_cooldown_remaining)


## 该角色是否处于再部署冷却
func is_redeploy_cooling(character_id: String) -> bool:
	return get_redeploy_remaining(character_id) > 0.0


func _deploy_cost(character_id: String) -> int:
	if not _character_configs.has(character_id):
		return 0
	return int((_character_configs[character_id] as Dictionary).get("deployCost", 0))

## Display and admission share the actual cost; hover never consumes the voucher.
func deployment_cost(character_id: String) -> int:
	var cost := _deploy_cost(character_id)
	if elapsed_seconds <= float(_deploy_discount.get("until", -1)) and character_id != str(_deploy_discount.get("source", "")):
		cost = maxi(1, cost - int(_deploy_discount.get("amount", 0)))
	return cost


## 角色级再部署时长（characters.json 的 redeployTime）；缺省回落到 balance 默认值。
func _redeploy_seconds(character_id: String) -> float:
	if _character_configs.has(character_id):
		var cfg: Dictionary = _character_configs[character_id]
		if cfg.has("redeployTime"):
			var v := float(cfg["redeployTime"])
			if v >= 0.0:
				return v
	return redeploy_default_seconds


# ============================================================
#  主动撤退（V2.1.4 D-9 / 表 24）
# ============================================================

## 撤退被拒绝的原因
enum RetreatReject {
	OK = 0,
	CHARACTER_NOT_DEPLOYED = 1,
	CHARACTER_INCAPACITATED = 2,
	BATTLE_FINISHED = 3,
}

class RetreatResult:
	extends RefCounted
	var ok: bool = false
	var reason: int = RetreatReject.OK
	var character_id: String = ""
	## 按比例算出的应返还额度（未受 AP 上限截断）
	var refund: int = 0
	## 实际入账的 AP（受 ap_max 截断）
	var refund_granted: int = 0
	## 撤退后该角色剩余的再部署冷却（秒）
	var cooldown: float = 0.0
	## 本次撤退解除的阻挡关系数量
	var released_blocks: int = 0

	func reason_text() -> String:
		match reason:
			RetreatReject.OK:
				return "已撤退"
			RetreatReject.CHARACTER_NOT_DEPLOYED:
				return "该角色不在场上"
			RetreatReject.CHARACTER_INCAPACITATED:
				return "该角色已无法战斗"
			RetreatReject.BATTLE_FINISHED:
				return "战斗已结束"
			_:
				return "未知原因(%d)" % reason


## 计算某角色的撤退返还 AP（V2.1.4 表 24：部署费用的 50%）。
## 比例来自 balance.combat.retreat.refundRate，不写死在代码里，
## 以便后续角色天赋 / 局内强化「快速换防」按来源覆写。
## 返回值已按 FLOOR 取整，保证不会超过「费用 × 比例」这一规格上限。
func compute_retreat_refund(deploy_cost: int, rate: float = -1.0) -> int:
	var effective := retreat_refund_rate if rate < 0.0 else rate
	# A0.6：「快速换防」提高默认返还比例；调用方显式传入 rate 时以传入值为准
	# （供未来角色天赋/局内强化按来源覆写，见 L2040 撤退比例的覆写设计）。
	if upgrades != null and rate < 0.0:
		effective = upgrades.retreat_refund_rate(retreat_refund_rate)
	if deploy_cost <= 0 or effective <= 0.0:
		return 0
	var raw := float(deploy_cost) * effective
	var floored := int(floor(raw + 0.000001))
	return clampi(floored, 0, deploy_cost)


## 主动撤退：角色离场、原格立即释放、阻挡关系解除、按比例返还 AP，
## 并进入该角色自身的再部署冷却。
##
## 幂等纪律：角色一旦离场就不再出现在 characters 中，
## 因此重复调用只会得到 CHARACTER_NOT_DEPLOYED，不可能二次返还 AP。
func withdraw_character(instance_id: int) -> RetreatResult:
	var r := RetreatResult.new()
	if not running:
		r.reason = RetreatReject.BATTLE_FINISHED
		return r

	var char := get_character(instance_id)
	if char == null:
		r.reason = RetreatReject.CHARACTER_NOT_DEPLOYED
		return r

	r.character_id = char.character_id

	# HP 耗尽的角色不归主动撤退管辖：走 _cleanup_dead 的失能路径（表 24「死亡返还 0 AP」）
	if char.is_incapacitated():
		r.reason = RetreatReject.CHARACTER_INCAPACITATED
		return r

	var cost := char.paid_deploy_cost if char.paid_deploy_cost >= 0 else _deploy_cost(char.character_id)
	r.refund = compute_retreat_refund(cost)
	r.refund_granted = add_ap(r.refund)

	# ① 解除该角色挂接的全部阻挡关系，被阻挡的敌人立即恢复行动
	for e: EnemyRuntime in enemies:
		if e.blocked_by_character_id == char.instance_id:
			e.blocked_by_character_id = 0
			e.state = BattleTypes.EnemyState.MOVING
			e.attack_cooldown = 0.0
			r.released_blocks += 1
	char.blocking_enemy_ids.clear()

	# ② 离场（原格随 get_character_at 立即变为空）
	_remove_character_instance(char.instance_id)
	_append_removal(Removal.RETREATED, char.character_id, char.instance_id, char.column, char.lane)

	# ③ 进入再部署冷却
	char.redeploy_cooldown_remaining = char.redeploy_time
	r.cooldown = char.redeploy_cooldown_remaining

	retreat_count += 1
	retreat_refunded_ap_total += r.refund_granted
	r.ok = true
	r.reason = RetreatReject.OK

	GameLog.info("StageRuntime",
		"主动撤退 %s：解除阻挡 %d 名，返还 %d AP（费用 %d × %.0f%%，实际入账 %d），剩余 %d/%d AP，再部署冷却 %.1f 秒"
		% [char.display_name, r.released_blocks, r.refund, cost,
			retreat_refund_rate * 100.0, r.refund_granted, ap, ap_max,
			char.redeploy_cooldown_remaining])
	return r


## 便捷重载：按角色 id 主动撤退该角色当前在场的实例。
func withdraw_character_by_id(character_id: String) -> RetreatResult:
	var inst := get_character_by_id(character_id)
	if inst == null:
		var r := RetreatResult.new()
		r.character_id = character_id
		r.reason = RetreatReject.CHARACTER_NOT_DEPLOYED
		return r
	return withdraw_character(inst.instance_id)


## 从场上移除角色实例（保留在 character_instances 历史中）。
func _remove_character_instance(instance_id: int) -> bool:
	for i: int in range(characters.size()):
		if characters[i].instance_id == instance_id:
			characters.remove_at(i)
			return true
	return false


func _append_removal(kind: int, character_id: String, instance_id: int, column: int, lane: int) -> void:
	removals.append({
		"kind": kind,
		"entity": "character",
		"characterId": character_id,
		"entityId": instance_id,
		"column": column,
		"lane": lane,
		"at": snappedf(elapsed_seconds, 0.001),
	})


## 某类离场事件的发生次数
func removal_count(kind: int) -> int:
	var n := 0
	for r: Dictionary in removals:
		if int(r["kind"]) == kind:
			n += 1
	return n


# ============================================================
#  Wave 调度（V2.1.4 D-33 / D-34 / D-40）
# ============================================================

## 总波数
func total_wave_count() -> int:
	return waves.size()


## 当前波次序号（1 起；无波次时返回 0）。
## 全部波次已完成时返回**最后一波的编号**，而不是 0——
## 否则结算摘要与 HUD 会显示成「Wave 0/3」这种自相矛盾的读数。
## Latest wave that has actually spawned. Early tutorials intentionally allow
## overlapping waves; the HUD must not lag behind their incoming wave number.
func display_wave_number() -> int:
	var number := current_wave_number()
	for state: Dictionary in _wave_states:
		if int(state.get("spawned",0))>0:number=maxi(number,int(state["number"]))
	return number

func incoming_wave_preview() -> Dictionary:
	for wave: Dictionary in waves:
		if int(wave["number"])>display_wave_number():return wave
	return {}

func current_wave_number() -> int:
	if waves.is_empty():
		return 0
	if _current_wave_index >= waves.size():
		return int(waves[waves.size() - 1]["number"])
	if _current_wave_index < 0:
		return 0
	return int(waves[_current_wave_index]["number"])


## 当前波次的运行状态字典（无波次时返回空字典）
func current_wave_state() -> Dictionary:
	if _current_wave_index < 0 or _current_wave_index >= _wave_states.size():
		return {}
	return _wave_states[_current_wave_index]


## 当前波次尚未生成的数量
func current_wave_remaining() -> int:
	if _current_wave_index < 0 or _current_wave_index >= waves.size():
		return 0
	var first := int(_wave_states[_current_wave_index]["spawnIndexFirst"])
	var last := int(_wave_states[_current_wave_index]["spawnIndexLast"])
	if first < 0:
		return 0
	var total := last - first + 1
	var spawned_in_wave := clampi(_spawn_cursor - first, 0, total)
	return total - spawned_in_wave


## 第 index 波（0 起）的运行状态
func wave_state_at(index: int) -> Dictionary:
	if index < 0 or index >= _wave_states.size():
		return {}
	return _wave_states[index]


## 全部波次是否已完成（当前波索引已越过最后一波）
func all_waves_cleared() -> bool:
	if waves.is_empty():
		return all_planned_spawned() and not has_living_enemies()
	return _current_wave_index >= waves.size()


## 下一波预告（供 HUD 显示「下一波」），无下一波时返回空字典
func next_wave_preview() -> Dictionary:
	var nxt := _current_wave_index + 1
	if nxt < 0 or nxt >= waves.size():
		return {}
	var w: Dictionary = waves[nxt]
	return {
		"number": int(w["number"]),
		"label": str(w["label"]),
		"enemyCount": int(w["enemyCount"]),
		"lanes": (w["lanes"] as Array).duplicate(),
	}


## 关闭当前波次并开启下一波。
func _complete_current_wave() -> void:
	if _current_wave_index < 0 or _current_wave_index >= _wave_states.size():
		return
	if int(_wave_states[_current_wave_index]["status"]) == WAVE_CLEARED:
		return
	var completed_wave := int(waves[_current_wave_index]["number"])
	_wave_states[_current_wave_index]["status"] = WAVE_CLEARED
	GameLog.info("StageRuntime", "Wave %d 完成（生成 %d，击杀 %d，漏怪 %d）"
		% [
			completed_wave,
			int(_wave_states[_current_wave_index]["spawned"]),
			int(_wave_states[_current_wave_index]["killed"]),
			int(_wave_states[_current_wave_index]["leaked"]),
		])
	_current_wave_index += 1
	if sequential_waves and _current_wave_index < _wave_states.size():
		var first := int(_wave_states[_current_wave_index]["spawnIndexFirst"])
		if first >= 0:
			_wave_time_delay = elapsed_seconds + 2.0 - float(_spawn_plan[first]["time"])
	if _current_wave_index < _wave_states.size():
		_wave_states[_current_wave_index]["status"] = WAVE_ACTIVE
		GameLog.info("StageRuntime", "Wave %d 开始（%d 名敌人，路线 %s）"
			% [
				int(waves[_current_wave_index]["number"]),
				int(waves[_current_wave_index]["enemyCount"]),
				str(waves[_current_wave_index]["lanes"]),
			])
	# A0.6（契约「触发时机」）：波次清空后判定是否建立三选一面板。
	# 放在**本函数末尾**（已完成波号已知、下一波已开启）而不是调用方 _step：
	# 这样「核心归零失败时不得触发」由 _update_wave_progress 的既有早退天然保证，
	# 不会出现"败北瞬间弹强化面板"的荒谬状态。
	_maybe_open_offer(completed_wave)


## A0.6：波次完成点判定是否建立三选一请求。
##
## 触发条件（全部满足才建立，契约第 1 节）：
##   ① 本关启用了强化系统（upgrades != null，由 openByStage 显式 opens>0 决定）；
##   ② 当前完成波号 ∈ 数据的 triggerWaves；
##   ③ 已用开放次数（含跳过）< total_opens；
##   ④ 战斗未结束（running 且核心仍有 HP）；
##   ⑤ 不在玩家暂停态（paused 是另一套状态，暂停中不应弹出要求玩家操作的面板）。
##
## 候选为空（池耗尽 / 无可选教学项且随机池也空）→ **不建立** pending、不消耗开放次数，
## 只记警告——否则会弹出一个"点了也没用"的空面板，并白白吃掉一次开放。
func _maybe_open_offer(completed_wave: int) -> void:
	if upgrades == null:
		return
	if _offer_battle_finished():
		return
	# 玩家暂停中不建立面板：paused 是"玩家主动停表"，面板则要求玩家立刻做选择——
	# 两者混用会让「继续」按钮同时承担两种语义（契约明令两者不可混用）。
	if paused:
		return
	if pending_offer_active_guard():
		return
	if not upgrades.trigger_waves.has(completed_wave):
		return
	# 次数用尽（含跳过）后不再开放：避免"空面板"与"跳过后仍能再刷"。
	if upgrades.is_exhausted():
		return
	# 本波清空后已无任何可打的目标（全部波次完成 + 场上无存活敌人）⇒ 下一 tick
	# 上层就会判定胜利。此时**不得**再建立请求：契约「战斗未结束才触发」，
	# 且胜负已定后 resolve/reroll/skip 一律返回 false，弹出面板等于给玩家一个
	# 点不动的死面板（结算界面还会被它盖住）。
	if all_waves_cleared() and not has_living_enemies():
		return
	var candidates := _roll_offer_candidates()
	if candidates.is_empty():
		GameLog.warn("StageRuntime",
			"Wave %d 完成但强化候选为空（池已耗尽或教学项不可用），本次不建立面板、不消耗开放次数"
			% completed_wave)
		return
	pending_offer = {
		"candidates": candidates,
		"isTutorial": _offer_is_tutorial(),
		"offerIndex": upgrades.selections_used + 1,
		"rerollsRemaining": upgrades.rerolls_remaining,
	}
	GameLog.info("StageRuntime", "局内强化面板已建立：第 %d 次开放（Wave %d 完成，教学=%s，候选 %s，剩余重掷 %d）"
		% [int(pending_offer["offerIndex"]), completed_wave,
			str(pending_offer["isTutorial"]), str(candidates),
			int(pending_offer["rerollsRemaining"])])


## 契约里 pending 非空即"已有待处理请求"，此处做一次显式自检（含字典被外部置空键的情况）。
func pending_offer_active_guard() -> bool:
	if pending_offer.is_empty():
		return false
	var c: Variant = pending_offer.get("candidates", [])
	return typeof(c) == TYPE_ARRAY and not (c as Array).is_empty()


## 本次是否走固定教学三选一（L2132）：开关已开 **且** 教学三项当前都仍可选。
## 任一项不可用（缺失 / 已满叠）→ 整体回落随机候选（不硬凑"缺一个"的教学）。
func _offer_is_tutorial() -> bool:
	if not _tutorial_offer_enabled:
		return false
	return not tutorial_upgrade_choices(_upgrades_domain).is_empty()


## 当前候选：教学优先，其次随机抽取。**不写死任何 id**（教学项来自数据）。
func _roll_offer_candidates() -> Array[String]:
	if upgrades == null:
		return []
	if _offer_is_tutorial():
		return tutorial_upgrade_choices(_upgrades_domain)
	var profile := _party_profile()
	return UpgradeCandidateRoller.roll(
		upgrades, profile["behaviors"], profile["tags"], _upgrade_seed())


## 每逻辑步的 Wave 完成判定。
## 完成条件（ALL_ENEMIES_DEFEATED）：本波计划敌人已全部生成，
## 且本波敌人已全部「击杀 + 漏怪」结算完毕。
func _update_wave_progress() -> void:
	if _current_wave_index < 0 or _current_wave_index >= _wave_states.size():
		return
	var st: Dictionary = _wave_states[_current_wave_index]
	if int(st["status"]) != WAVE_ACTIVE:
		return
	# 让位给「核心 HP 耗尽立即失败」：核心归零后不得再把波次判为完成，
	# 也不得开启下一波（由 BattleSession 负责判定失败）。
	if core_hp <= 0:
		return
	var last := int(st["spawnIndexLast"])
	if last < 0:
		# 本波没有任何敌人（数据异常已在构建期报错）→ 直接关闭
		_complete_current_wave()
		return
	# 完成条件：本波计划敌人全部已生成（按计数判定，而不是用生成游标）——
	# 这样「本波已生成完且已全部离场」必然隐含「后续波次的敌人尚未生成」，
	# 不会出现跨波提前完成。
	var total := int(waves[_current_wave_index]["enemyCount"])
	if int(st["spawned"]) < total:
		# 本波仍有敌人未生成
		return
	# A0.2（C-8 解决）：完成判定只数**计划内本体**（derived = 0）。
	# 作弊纸偶的复制体是运行中新增的衍生体，它们同样会击杀/漏怪并被计入本波，
	# 若把衍生体也计入分母（或用总数比较），本波将永远无法判为完成。
	# 复制体仍占用阻挡名额、仍会漏怪扣核心，其击杀/漏怪照常记入本波统计（供复盘显示），
	# 只是不构成「本波是否清空」的门槛。
	if int(st["killed"]) + int(st["leaked"]) - int(st["killedDerived"]) - int(st["leakedDerived"]) < total:
		# 本波仍有**本体**留在场上（未被击杀也未漏怪）
		return
	# 本体已清空：若衍生体仍在场，战斗不能判胜（has_living_enemies 为 true），
	# 此时不关闭本波，等衍生体也被处理完；若衍生体已全部离场，则与旧行为完全一致。
	if _has_living_derived_in_wave(int(st["number"])):
		return
	_complete_current_wave()


## 本波是否仍有存活的衍生体（复制体）。
##
## 用途：区分「本体已清空」与「场上彻底干净」。若无此判定，本波会在复制体仍在场时
## 就被关闭并开启下一波，导致两波敌人同时在场的非预期局面。
func _has_living_derived_in_wave(wave_no: int) -> bool:
	for e: EnemyRuntime in enemies:
		if not e.is_active():
			continue
		if e.is_derived and e.wave_number == wave_no:
			return true
	return false


# ============================================================
#  主循环
# ============================================================

## 按固定逻辑步长推进战斗。
## 返回本次推进中抵达核心的敌人列表。
func advance(delta_seconds: float) -> Array[EnemyRuntime]:
	var reached: Array[EnemyRuntime] = []
	if delta_seconds <= 0.0 or not is_valid():
		return reached
	# 暂停或胜负已定时不推进任何计时器（V2.1.4 D-35 / D-40）
	if paused or not running:
		return reached
	# A0.6（契约「冻结战斗」）：pending_offer 非空期间不推进任何计时器，返回空数组。
	# 这里**不设置 paused** —— 玩家暂停与强化冻结必须保持为两套独立状态。
	# 同时清空累积器：解冻后不得补跑选择期间的时间（L1972）。
	if has_pending_offer():
		_accumulator = 0.0
		return reached

	_accumulator += delta_seconds
	var steps := 0
	while _accumulator >= LOGIC_STEP_SECONDS and steps < MAX_STEPS_PER_ADVANCE:
		# 核心 HP 耗尽 → 立即停止全部推进（V2.1.4 D-41），不得在同一帧的后续逻辑步继续出怪
		if core_hp <= 0:
			_accumulator = 0.0
			break
		_accumulator -= LOGIC_STEP_SECONDS
		steps += 1
		elapsed_seconds += LOGIC_STEP_SECONDS
		_step(LOGIC_STEP_SECONDS, reached)
		# A0.6（L1972）：本逻辑步内建立了强化面板 ⇒ 立即停止推进，并**丢弃**本次调用
		# 剩余的时间累积。丢弃而不是结转是必需的：若把剩余时间留在累积器里，
		# 解冻后的第一帧就会补跑「选择期间」的时长，L1972
		# 「选择界面不计入技能 CD 或敌人移动时间」立刻不成立。
		if has_pending_offer():
			_accumulator = 0.0
			break
	return reached


## 单个逻辑步的完整推进顺序（确定性）：
##   1. AP 自然回复
##   2. 生成到期敌人
##   3. 推进再部署冷却
##   3.5 A0.2 推进角色状态效果（沉默 / 攻速减益按逻辑步到期移除）
##   4. 释放无效阻挡关系（阻挡者离场/失能，敌人已亡）
##   5. 清理死亡实体（HP≤0 → DEAD，释放阻挡名额）+ 失能角色离场
##   5.5 A0.2 敌人机制结算（时间到 / 复制 / 注视）
##   6. 敌人移动（仅 MOVING）
##   7. 建立阻挡（接触线 + 剩余名额）
##   7.5 A0.2 沉默触发判定（触发条件依赖本步刚建立的阻挡关系）
##   8. 判定抵达核心
##   9. 双方攻击结算（含 A0.2 远程敌人的停驻与射击）
##  10. Wave 完成判定
##
## 注意：清理放在「建立阻挡」之前，保证上一逻辑步内被击杀的敌人
## 立即释放阻挡名额，新敌人在同一逻辑步就能接上（V2.1.4 D-10）。
##
## A0.2 新增阶段的插入位置依据：
##   - 状态效果在**攻击结算之前**推进，保证「3 秒沉默」按逻辑步精确到期（设计稿 §2.2.5 T4）；
##   - 敌人机制在**清理之后、移动之前**结算：本体若已在上一逻辑步被打死，
##     不会生成复制体（设计稿 §2.3.5 M5「已死亡不构成『低于 50% 但存活』」）；
##   - 沉默放在**建立阻挡之后**：其触发条件正是「本步刚与角色建立阻挡关系」。
func _step(step: float, reached: Array[EnemyRuntime]) -> void:
	# 0. 核心已耗尽：本逻辑步不再推进任何内容（V2.1.4 D-41「立即失败」）
	if core_hp <= 0:
		return

	# 1. AP 自然回复（按步长精确累积，不按帧）
	if ap_regen_per_second > 0.0 and ap < ap_max:
		# A0.6：局内强化只乘在回复**速率**上，累积器与取整逻辑完全不变
		_ap_accumulator += ap_regen_per_second * _ap_regen_mult() * step
		while _ap_accumulator >= 1.0 and ap < ap_max:
			_ap_accumulator -= 1.0
			ap += 1
		if ap >= ap_max:
			_ap_accumulator = 0.0

	# 2. 生成
	_spawn_due()

	# 3. 再部署冷却（与渲染帧率完全解耦，只在逻辑步内递减）
	_tick_redeploy_cooldowns(step)

	# 3.5 A0.2：角色状态效果按逻辑步推进（到期移除）
	_tick_character_status_effects()

	# 4. 释放无效阻挡
	_release_invalid_blocks()

	# 5. 清理死亡实体（提前于建立阻挡，及时释放名额）
	_cleanup_dead()

	# 5.5 A0.2：敌人机制结算（时间到 / 复制 / 注视）
	_process_enemy_mechanics(step)
	_tick_chapter_mechanics(step)

	# 6. 移动
	_move_enemies(step)

	# 7. 建立阻挡
	_establish_blocks()

	# 7.5 A0.2：沉默触发判定（依赖本步刚建立的阻挡关系）
	_process_silence_triggers(step)

	# 8. 抵达核心（仅未被阻挡的敌人可能到达）
	#    在领域层内**立即结算**核心伤害，而不是留给上层在同一帧末尾补算：
	#    这样 core_hp 在「Wave 完成判定」之前就已经是真实值，
	#    核心归零时本波不会被误判为完成，也不会误开启下一波。
	for e: EnemyRuntime in enemies:
		if e.state == BattleTypes.EnemyState.MOVING and e.has_reached_core():
			e.state = BattleTypes.EnemyState.REACHED_CORE
			reached_core_count += 1
			_note_wave_leak(e)
			reached.append(e)
			apply_core_damage(e)

	# 9. 角色行动（三职业统一分派：输出走攻击路径，治疗走治疗路径）
	_tick_character_skills(step)
	_resolve_character_actions(step)
	_resolve_enemy_attacks(step)
	# 9.5 A0.2：远程敌人（试卷飞灵）的停驻与射击结算
	_resolve_ranged_enemy_actions(step)

	# 10. Wave 推进
	_update_wave_progress()


# ============================================================
#  A0.2：敌人机制结算（数据驱动；参数全部来自 enemies.json 的 mechanic 段）
# ============================================================

## 每逻辑步推进全部敌人的一次性机制与周期机制。
##
## 纪律：本函数**不包含任何敌人专属数值**，全部参数从 e.mechanic 读出；
## 按 mechanic.kind / 子对象是否存在分派，而不是按 enemy_id 硬编码分支。
func _process_enemy_mechanics(step: float) -> void:
	# 快照：复制机制会向 enemies 追加新实例，直接遍历会边遍历边改数组。
	var snapshot: Array[EnemyRuntime] = enemies.duplicate()
	for e: EnemyRuntime in snapshot:
		if not e.is_active():
			continue
		_process_time_up(e)
		_process_copy_split(e)
		_process_gaze(e, step)


## 「时间到」（SELF_BUFF_ON_HP_THRESHOLD）：生命**低于**阈值后移速按配置百分比永久提高。
##
## 规格（LOCKED，v214_ordered.txt L1150）：「生命低于 40% 后移动速度提高 30%。」
## 「低于」按严格小于处理（设计稿 C-7 的临时口径 STRICTLY_LESS_THAN）；
## HP 恰好等于阈值时**不触发**。
func _process_time_up(e: EnemyRuntime) -> void:
	if e.time_up_triggered:
		return
	var cfg := e.time_up_config()
	if cfg.is_empty():
		return
	if e.hp_max <= 0 or e.hp <= 0:
		return
	var threshold := float(cfg.get("triggerHpRatio", 0.0))
	var pct := float(cfg.get("moveSpeedPct", 0.0))
	# 严格小于：不使用 <=
	if float(e.hp) < float(e.hp_max) * threshold:
		e.time_up_triggered = true
		# 以**配置基准速度**计算，避免多次触发时叠乘（triggerOnce 语义）
		e.move_speed = e.base_move_speed * (1.0 + pct)
		GameLog.info("StageRuntime", "%s 触发「%s」：移速 %.3f → %.3f tile/s"
			% [e.display_name, str(cfg.get("effectId", "timeUp")),
				e.base_move_speed, e.move_speed])


## 「复制」（SPLIT_ON_HP_THRESHOLD）：生命**首次低于**阈值时生成 N 个低生命复制体。
##
## 规格（LOCKED，L1135）：「生命首次低于 50% 时生成 1 个低生命复制体。
## 复制体拥有原敌人 35% HP，并且不能再次复制。」
## 防递归三重保证（设计稿 §2.3.5 M2）：
##   ① 配置层：复制体的 mechanic.canCopy 被强制为 false（make_derived_copy）；
##   ② 实例层：copy_triggered 一生只触发一次；
##   ③ 断言层：测试断言「本体数 × 2 == 实例总数」。
func _process_copy_split(e: EnemyRuntime) -> void:
	if e.copy_triggered:
		return
	if not e.can_copy():
		return
	if e.hp <= 0:
		# 已死亡不构成「低于 50% 但存活」——不生成复制体
		return
	var cfg := e.split_config()
	if cfg.is_empty():
		return
	var threshold := float(cfg.get("triggerHpRatio", 0.0))
	if float(e.hp) >= float(e.hp_max) * threshold:
		return
	e.copy_triggered = true
	var count := int(cfg.get("spawnCount", 1))
	var offset := float(cfg.get("copySpawnOffsetTiles", 0.0))
	for i: int in range(count):
		var copy := EnemyRuntime.make_derived_copy(e, _next_enemy_instance_id, offset)
		_next_enemy_instance_id += 1
		enemies.append(copy)
		GameLog.info("StageRuntime", "%s 触发复制：生成复制体 #%d（HP %d/%d，wave %d，继承本体波次）"
			% [e.display_name, copy.instance_id, copy.hp, copy.hp_max, copy.wave_number])


## 「注视」（PERIODIC_DEBUFF）：每 intervalSeconds 标记最近一名玩家角色，
## 施加持续 durationSeconds 的攻速减益。
##
## 规格（LOCKED，L1148）：「每隔 10 秒标记最近一个玩家角色，持续 5 秒；
## 被标记角色攻击速度 -25%。」
## 无合法目标时**不重置冷却**（继续累积），与 _resolve_healer_action 的既有纪律一致
## （设计稿 §2.4.5 M1）。
func _process_gaze(e: EnemyRuntime, step: float) -> void:
	var cfg := e.gaze_config()
	if cfg.is_empty():
		return
	e.gaze_cooldown -= step
	if e.gaze_cooldown > 0.0:
		return
	var target := _select_nearest_character_for_enemy(e)
	if target == null:
		# 无目标：冷却保持 ≤ 0，下一逻辑步继续尝试（不重置）
		return
	var effect_cfg := {
		"effectId": str(cfg.get("effectId", "")),
		"sourceId": e.enemy_id,
		"category": str(cfg.get("category", "")),
		"pct": float(cfg.get("attackSpeedPct", 0.0)),
		"durationSeconds": float(cfg.get("durationSeconds", 0.0)),
		"stackPolicy": str(cfg.get("stackPolicy", "REFRESH_DURATION")),
	}
	var applied := target.apply_status_effect_from_config(effect_cfg, elapsed_seconds)
	e.gaze_cooldown = float(cfg.get("intervalSeconds", 0.0))
	GameLog.info("StageRuntime", "%s 施加「注视」于 %s（%s，攻速 %+.0f%%，持续 %.1fs）"
		% [e.display_name, target.display_name,
			"新增" if applied else "刷新",
			float(effect_cfg["pct"]) * 100.0, float(effect_cfg["durationSeconds"])])


## 「沉默」（SILENCE_ON_FIRST_CONTACT）：首次接触玩家防线后，
## 使最近一名角色 durationSeconds 内无法主动释放技能。
##
## 规格（LOCKED，L1129）：「首次接触玩家防线后，使最近一名角色 3 秒内无法主动释放技能；
## 技能冷却 12 秒。」
## 规格（LOCKED，L557）：「控制类沉默仅禁止主动技能，**不改变普通攻击频率**。」
##   ⇒ 该效果 category = SILENCE、pct = 0，**不进**攻速百分数求和，**不受** 40% 下限夹取。
##
## 触发口径（设计稿 §2.2.5 M1 方案 A，CANDIDATE）：该敌人**首次与任一玩家角色建立
## 阻挡关系**（blocked_by_character_id != 0）的那一逻辑步。
## 目标口径（设计稿 §2.2.5 M2）：取触发时阻挡自己的那名角色（该解释是对 L1129
## 「最近一名角色」的窄化，属需人裁决项 C-6）。
func _process_silence_triggers(step: float) -> void:
	for e: EnemyRuntime in enemies:
		if not e.is_active():
			continue
		var cfg := e.silence_config()
		if cfg.is_empty():
			continue
		# 冷却推进（repeatable=true 时可重复触发；默认 false 时该冷却不参与判定）
		if e.silence_cooldown > 0.0:
			e.silence_cooldown = maxf(0.0, e.silence_cooldown - step)
		var repeatable := bool(cfg.get("repeatable", false))
		if e.silence_triggered and not repeatable:
			continue
		if repeatable and e.silence_cooldown > 0.0:
			continue
		# 触发条件：首次与角色建立阻挡关系（方案 A）
		if e.blocked_by_character_id == 0:
			continue
		var target := get_character(e.blocked_by_character_id)
		if target == null or target.is_incapacitated():
			continue
		var effect_cfg := {
			"effectId": str(cfg.get("effectId", "")),
			"sourceId": e.enemy_id,
			"category": str(cfg.get("category", "SILENCE")),
			# L557：控制类沉默不改变任何数值，pct 恒为 0
			"pct": 0.0,
			"durationSeconds": float(cfg.get("durationSeconds", 0.0)),
			"stackPolicy": str(cfg.get("stackPolicy", "REFRESH_DURATION")),
		}
		target.apply_status_effect_from_config(effect_cfg, elapsed_seconds)
		e.silence_triggered = true
		e.silence_cooldown = float(cfg.get("cooldownSeconds", 0.0))
		GameLog.info("StageRuntime", "%s 触发「无声」：%s 在 %.1f 秒内无法主动释放技能"
			% [e.display_name, target.display_name, float(effect_cfg["durationSeconds"])])


## 远程敌人（试卷飞灵）的停驻与射击结算。
##
## 规格（LOCKED，L1102）：「达到攻击距离后停下，远程攻击前排。」
## 规格（LOCKED，L1098）：攻击距离 3 格。
## 规格（LOCKED，L1164，F-十七）：「远程敌人默认攻击**距离自己最近的合法目标**」。
##
## 纪律：
##   - 停驻态使用新增的 EnemyState.RANGED_ATTACK，**不置为 BLOCKED**，
##     因此不占用角色的阻挡名额（设计稿 §2.1.5 M3）；
##   - 若角色主动贴近至接触线，沿用通用阻挡规则（_establish_blocks 已处理），
##     此时该敌人进入 BLOCKED 并由 _resolve_enemy_attacks 结算，本函数跳过它；
##   - 参数（rangeTiles / maxLaneDelta / 是否停驻 / 是否恢复移动）全部来自 mechanic 段。
func _resolve_ranged_enemy_actions(step: float) -> void:
	for e: EnemyRuntime in enemies:
		if not e.is_active():
			continue
		if not e.is_ranged_attacker():
			continue
		# 已被通用阻挡规则接管的敌人走 _resolve_enemy_attacks 的 BLOCKED 分支
		if e.state == BattleTypes.EnemyState.BLOCKED \
			or e.state == BattleTypes.EnemyState.ATTACKING:
			continue
		# 仅 MOVING 与 RANGED_ATTACK 参与本分支（CASTING/DEAD/REACHED_CORE 不参与）
		if e.state != BattleTypes.EnemyState.MOVING \
			and e.state != BattleTypes.EnemyState.RANGED_ATTACK:
			continue

		var target := _select_ranged_target(e)
		if target == null:
			# 无合法目标：若配置允许则恢复移动（设计稿 §2.1.5 M5）
			if e.state == BattleTypes.EnemyState.RANGED_ATTACK and e.resumes_when_no_target():
				e.state = BattleTypes.EnemyState.MOVING
				e.attack_cooldown = 0.0
			continue

		# 有目标：判断是否已达射程（一维 tile 距离，maxLaneDelta=0 时无需二维度量）
		var dist := absf(float(target.column) - e.logical_x)
		var in_range := dist <= e.ranged_range_tiles() + 0.0001
		if not in_range:
			# 未达射程：保持/恢复移动，本步不出手
			if e.state == BattleTypes.EnemyState.RANGED_ATTACK:
				e.state = BattleTypes.EnemyState.MOVING
			continue

		# 已达射程：停驻（不移动、不占阻挡名额）
		if e.stops_when_target_in_range():
			if e.state != BattleTypes.EnemyState.RANGED_ATTACK:
				e.state = BattleTypes.EnemyState.RANGED_ATTACK
				e.attack_cooldown = 0.0
		# 攻击间隔推进与出手结算
		e.attack_cooldown = maxf(0.0, e.attack_cooldown - step)
		if e.attack_cooldown > 0.0:
			continue
		var dmg := combat_math.compute_damage(e.attack, _defense_of_target(target), e.damage_type)
		var applied := target.take_damage(dmg)
		e.total_damage_dealt += applied
		e.attack_cooldown = e.attack_interval
		_record_damage_event(false, target.instance_id, applied, target.is_incapacitated(),
			"enemy", e.instance_id, Vector2(e.logical_x, e.lane),
			Vector2(target.column, target.lane), e.damage_type)
		GameLog.debug("StageRuntime", "%s 远程攻击 %s 造成 %d 伤害（剩余 HP %d）"
			% [e.display_name, target.display_name, applied, target.hp])


## 远程敌人的选敌（LOCKED，L1164「距离自己最近的合法目标」）。
##
## 与角色侧选敌（D-11「最接近防守核心的敌人」）方向相反，两者不可混用。
## 「合法目标」= 仍在场、非失能、且跨线数不超过 mechanic.maxLaneDelta 的角色。
## 「最近」= 同路线内的一维 tile 距离 |character.column − enemy.logical_x|。
## 并列裁决（CANDIDATE，规格未给）：① column 更小者（更靠核心）优先 → ② instance_id 更小者。
func _select_ranged_target(e: EnemyRuntime) -> CharacterRuntime:
	var best: CharacterRuntime = null
	var best_dist := INF
	for c: CharacterRuntime in characters:
		if c.is_incapacitated():
			continue
		if absi(c.lane - e.lane) > e.ranged_max_lane_delta():
			continue
		var dist := absf(float(c.column) - e.logical_x)
		if dist < best_dist - 0.000001:
			best_dist = dist
			best = c
		elif best != null and absf(dist - best_dist) <= 0.000001:
			if c.column < best.column:
				best = c
			elif c.column == best.column and c.instance_id < best.instance_id:
				best = c
	return best


## 敌人侧「最近一名玩家角色」选敌（用于注视 / 沉默等标记类能力）。
##
## 与远程攻击选敌的差别：标记类能力**不限同路线**（设计稿 §2.4.5 M1 / C-10，CANDIDATE，
## 规格未规定标记是否受 maxLaneDelta 约束）。口径：全局最近，距离度量用
## |character.column − enemy.logical_x|，并列时取 column 更小者、再取 instance_id 更小者。
func _select_nearest_character_for_enemy(e: EnemyRuntime) -> CharacterRuntime:
	var best: CharacterRuntime = null
	var best_dist := INF
	for c: CharacterRuntime in characters:
		if c.is_incapacitated():
			continue
		var dist := absf(float(c.column) - e.logical_x)
		if dist < best_dist - 0.000001:
			best_dist = dist
			best = c
		elif best != null and absf(dist - best_dist) <= 0.000001:
			if c.column < best.column:
				best = c
			elif c.column == best.column and c.instance_id < best.instance_id:
				best = c
	return best


## 推进全部在场角色的状态效果（V2.1.4 L556～557：持续时间按逻辑步计）。
##
## 到期移除与「已失能角色不保留效果」两条都在此处理：角色离场后其运行时对象
## 不再出现在 characters 中，效果自然不再参与结算。
func _tick_character_status_effects() -> void:
	for c: CharacterRuntime in characters:
		if c.status_effects.is_empty():
			continue
		var expired := c.tick_status_effects(elapsed_seconds)
		for eid: String in expired:
			GameLog.debug("StageRuntime", "%s 的状态效果 %s 已到期" % [c.display_name, eid])


## 推进全部已离场实例的再部署冷却。
func _tick_redeploy_cooldowns(step: float) -> void:
	for c: CharacterRuntime in character_instances:
		if c.redeploy_cooldown_remaining <= 0.0:
			continue
		# 仍在场上的实例不消耗冷却
		if get_character(c.instance_id) != null:
			continue
		c.redeploy_cooldown_remaining = maxf(0.0, c.redeploy_cooldown_remaining - step)
		if c.redeploy_cooldown_remaining <= 0.0:
			GameLog.info("StageRuntime", "%s 的再部署冷却结束" % c.display_name)


## 生成所有到达时间的敌人。
func _spawn_due() -> void:
	while _spawn_cursor < _spawn_plan.size():
		var entry: Dictionary = _spawn_plan[_spawn_cursor]
		if sequential_waves and int(entry.get("wave",1)) > current_wave_number():
			break
		if float(entry["time"]) + _wave_time_delay > elapsed_seconds:
			break
		# 敌人被无限阻挡时也要保证对局收敛：超过战斗时长上限后不再生成
		if _max_battle_seconds > 0.0 and elapsed_seconds > _max_battle_seconds:
			GameLog.warn("StageRuntime", "已超过战斗时长上限 %.1fs，停止生成剩余敌人" % _max_battle_seconds)
			return
		var enemy_id: String = str(entry["enemy"])
		var lane: int = int(entry["lane"])
		var cfg: Dictionary = _enemy_configs[enemy_id]
		# A0.2（C-8 解决）：把该出怪条目所属的 Wave 显式写进实例。
		# 未标注 wave 的旧条目按 _build_waves 的口径归入第 1 波。
		var wave_no := int(entry.get("wave", 0))
		if wave_no <= 0:
			wave_no = 1
		var inst := EnemyRuntime.from_config(cfg, lane, _next_enemy_instance_id, wave_no)
		_next_enemy_instance_id += 1
		enemies.append(inst)
		_spawn_cursor += 1
		_note_wave_spawn(_spawn_cursor - 1)
		GameLog.debug("StageRuntime", "生成敌人 %s（lane=%d, t=%.2fs, wave=%d）"
			% [enemy_id, lane, elapsed_seconds, wave_no])


func _note_wave_spawn(spawn_index: int) -> void:
	for st: Dictionary in _wave_states:
		var first := int(st["spawnIndexFirst"])
		var last := int(st["spawnIndexLast"])
		if first >= 0 and spawn_index >= first and spawn_index <= last:
			st["spawned"] = int(st["spawned"]) + 1
			return


func _note_wave_kill(enemy: EnemyRuntime) -> void:
	for st: Dictionary in _wave_states:
		if _enemy_in_wave(enemy, st):
			st["killed"] = int(st["killed"]) + 1
			if enemy.is_derived:
				st["killedDerived"] = int(st["killedDerived"]) + 1
			return


func _note_wave_leak(enemy: EnemyRuntime) -> void:
	for st: Dictionary in _wave_states:
		if _enemy_in_wave(enemy, st):
			st["leaked"] = int(st["leaked"]) + 1
			if enemy.is_derived:
				st["leakedDerived"] = int(st["leakedDerived"]) + 1
			return


## 敌人所属波次的判定（A0.2 重写，解决设计稿冲突 C-8）。
##
## 旧实现用 `instance_id - 1` 落在 spawnIndex 区间来归属波次。该口径对**计划内**的敌人
## 成立（实例 id 与生成序号同序），但对**运行中新增的衍生体**（作弊纸偶的复制体）失效：
## 复制体不在 spawnPlan 中，其 instance_id 必然落在任何区间之外 → 击杀与漏怪都不计入
## 任何波次 → 本波 `killed + leaked` 永远差 1 → 波次无法完成、战斗无法判定胜负（卡死）。
##
## 现口径：
##   ① 优先用实例上的 wave_number 显式归属（本体在 _spawn_due 时带入，
##      衍生体在 make_derived_copy 时继承本体）——衍生体因此归入生成它的本体所在波次；
##   ② wave_number ≤ 0 时（测试夹具手工放置的敌人）退回旧的 instance_id 区间判定，
##      保持既有夹具语义不变。
func _enemy_in_wave(enemy: EnemyRuntime, st: Dictionary) -> bool:
	if enemy.wave_number > 0:
		return int(st["number"]) == enemy.wave_number
	var first := int(st["spawnIndexFirst"])
	var last := int(st["spawnIndexLast"])
	if first < 0:
		return false
	var idx := enemy.instance_id - 1
	return idx >= first and idx <= last


## 敌人移动（仅 MOVING 状态）。BLOCKED / ATTACKING / RANGED_ATTACK 不移动。
##
## A0.2：RANGED_ATTACK 是试卷飞灵「达到攻击距离后停下」的驻留态（LOCKED，L1102），
## 因此该状态下的敌人**不推进位置**——这正是本机制的全部意义。
func _move_enemies(step: float) -> void:
	for e: EnemyRuntime in enemies:
		if e.state == BattleTypes.EnemyState.MOVING:
			e.advance(step)


## 释放无效阻挡关系：
##   - 阻挡者已离场（撤退/失能移除）或已失能 → 其挂接的敌人恢复移动（BLOCKED → MOVING）
##   - 敌人已死亡/已消失 → 从阻挡者列表移除
##
## 注意：判定以**敌人侧**的 blocked_by_character_id 为准，而不是只依赖角色侧的
## blocking_enemy_ids。因为角色一旦离场或失能，其阻挡列表可能已被清空，
## 若此处只看该列表就会漏掉「敌人仍停在原地」的情况。
func _release_invalid_blocks() -> void:
	# 1) 敌人侧：阻挡者已离场/失能 → 恢复移动
	for e: EnemyRuntime in enemies:
		if e.state != BattleTypes.EnemyState.BLOCKED \
			and e.state != BattleTypes.EnemyState.ATTACKING:
			continue
		var blocker := get_character(e.blocked_by_character_id)
		if blocker == null or blocker.is_incapacitated():
			e.blocked_by_character_id = 0
			e.state = BattleTypes.EnemyState.MOVING
			e.attack_cooldown = 0.0
			GameLog.debug("StageRuntime", "敌人 %s 的阻挡者已失效，恢复移动" % e.enemy_id)

	# 2) 角色侧：清理指向已消失敌人的引用
	for c: CharacterRuntime in characters:
		if c.blocking_enemy_ids.is_empty():
			continue
		var kept: Array[int] = []
		for eid: int in c.blocking_enemy_ids:
			var e := get_enemy(eid)
			if e == null or not e.is_active():
				continue
			# 敌人已不再被本角色阻挡（例如已被释放）→ 同步移除
			if e.blocked_by_character_id != c.instance_id:
				continue
			kept.append(eid)
		c.blocking_enemy_ids = kept


## 建立阻挡：敌人推进到阻挡者前方接触线且该单位仍有剩余阻挡名额时停止移动。
## 名额已满 → 不建立阻挡，敌人继续前进（V2.1.4 D-10 明确要求）。
##
## A0.2：处于 RANGED_ATTACK（试卷飞灵的停驻射击态）的敌人同样参与本判定——
## 设计稿 §2.1.5 M3 明确「若角色主动贴近至接触线，沿用通用阻挡规则」，
## F 章未给远程敌人豁免阻挡，不应自行新增例外。
func _establish_blocks() -> void:
	for e: EnemyRuntime in enemies:
		if e.state != BattleTypes.EnemyState.MOVING \
			and e.state != BattleTypes.EnemyState.RANGED_ATTACK:
			continue
		var blocker := _find_available_blocker(e)
		if blocker == null:
			continue
		if not blocker.add_blocking(e.instance_id):
			continue
		e.blocked_by_character_id = blocker.instance_id
		e.state = BattleTypes.EnemyState.BLOCKED
		e.attack_cooldown = 0.0
		# 停在接触线外侧（不越过阻挡者所在格）
		var contact_x := float(blocker.column) + block_contact_line_tiles
		if e.logical_x < contact_x:
			e.logical_x = contact_x


## 寻找可阻挡该敌人的角色：
##   同路线、存活、仍有阻挡名额、且敌人在其接触线范围内。
func _find_available_blocker(e: EnemyRuntime) -> CharacterRuntime:
	var best: CharacterRuntime = null
	for c: CharacterRuntime in characters:
		if c.is_incapacitated():
			continue
		if c.lane != e.lane:
			continue
		if not c.can_block_more():
			continue
		# 敌人已越过该角色所在格 → 不再受其阻挡
		if e.logical_x < float(c.column) - 0.0001:
			continue
		# 接触判定：敌人中心与角色所在格中心的距离 ≤ 接触线
		if e.logical_x - float(c.column) > block_contact_line_tiles:
			continue
		# 多个候选时取「更靠近核心」的那名（column 更小）
		if best == null or c.column < best.column:
			best = c
	return best


## 角色自动攻击（V2.1.4 D-11 目标优先级）
## 角色行动统一入口（P0.4 三职业框架）。
## 前线与远程共用同一条攻击路径（二者差别只在数据：射程与阻挡数）；
## 治疗型走治疗路径。**不为任何单个角色写专属分支。**
func _resolve_character_actions(step: float) -> void:
	for c: CharacterRuntime in characters:
		if c.is_incapacitated():
			continue
		if c.is_healer():
			_resolve_healer_action(c, step)
		else:
			_resolve_attacker_action(c, step)


## 输出型（前线 / 远程）的单次行动结算。
## 射程、阻挡能力、伤害类型全部来自配置，行为本身不携带任何数值。
func _resolve_attacker_action(c: CharacterRuntime, step: float) -> void:
	if c.effective_attack() <= 0 or not bool((_character_configs.get(c.character_id, {}) as Dictionary).get("normalAttackEnabled", true)):
		return
	c.attack_cooldown = maxf(0.0, c.attack_cooldown - step)
	if c.attack_cooldown > 0.0:
		return
	var targets: Array[EnemyRuntime] = []
	var skill_attack := c.skill_charged or c.skill_active_remaining > 0.0
	if skill_attack:
		targets = _active_skill_targets(c)
	# A charged piercing arrow waits for its own-lane geometry without silencing
	# ordinary adjacent-lane support. Only a real skill hit consumes the charge.
	if targets.is_empty():
		skill_attack = false
		var target := _select_target_for(c)
		if target != null:
			targets.append(target)
	if targets.is_empty():
		return
	# Active-skill geometry is separate from normal attack geometry. No changes
	# to ordinary target choice, interval, damage formula or cross-lane rules.
	var multiplier := float(c.skill_config.get("damageMultiplier", 1.0)) if c.skill_charged and skill_attack else 1.0
	if c.talent_config.get("effect", "") == "SAME_TARGET_DAMAGE":
		var primary := targets[0].instance_id
		c.talent_same_target_hits = c.talent_same_target_hits + 1 if primary == c.talent_last_target else 0
		c.talent_last_target = primary
		multiplier *= 1.0 + minf(float(c.talent_same_target_hits) * float(c.talent_config.get("bonusPerHitPct", 0.0)), float(c.talent_config.get("maxBonusPct", 0.0)))
	var atk := float(c.effective_attack()) * _atk_mult(c) * multiplier
	for target: EnemyRuntime in targets:
		var effective_atk := atk
		if c.talent_config.get("effect", "") == "ARMORED_SPECIAL" and target.defense >= int(c.talent_config.get("defenseThreshold", 80)):
			effective_atk *= 1.0 + float(c.talent_config.get("damageBonusPct", 0.15))
		var dmg := combat_math.compute_damage(effective_atk, target.defense, c.damage_type)
		var applied := target.take_damage(dmg)
		c.total_damage_dealt += applied
		_record_damage_event(true, target.instance_id, applied, target.hp <= 0,
			"character", c.instance_id, Vector2(c.column, c.lane),
			Vector2(target.logical_x, target.lane), c.damage_type, skill_attack)
		GameLog.debug("StageRuntime", "%s 攻击 %s 造成 %d 伤害（剩余 HP %d）"
			% [c.display_name, target.enemy_id, applied, target.hp])
		if c.talent_config.get("effect", "") == "ARMORED_SPECIAL":
			for other: EnemyRuntime in enemies:
				if other.instance_id == target.instance_id or not other.is_active() or other.lane != target.lane:
					continue
				if absf(other.logical_x-target.logical_x) > float(c.talent_config.get("splashRange", .75)):
					continue
				var splash_atk := atk * float(c.talent_config.get("splashMultiplier", .7))
				if other.defense >= int(c.talent_config.get("defenseThreshold",80)):
					splash_atk *= 1.0 + float(c.talent_config.get("damageBonusPct",.15))
				var splash := other.take_damage(combat_math.compute_damage(splash_atk,other.defense,c.damage_type))
				c.total_damage_dealt += splash
				_record_damage_event(true,other.instance_id,splash,other.hp<=0,"character",c.instance_id,Vector2(c.column,c.lane),Vector2(other.logical_x,other.lane),c.damage_type)
	if skill_attack:
		c.skill_charged = false
	c.attack_cooldown = c.effective_attack_interval()


## 治疗型的单次行动结算（V2.1.4 D 章二十三 治疗公式 / 表 30 范围与间隔）。
## 纪律：
##   ① 只治疗**仍在场**的友军（已离场者不在 characters 中，天然排除）；
##   ② 实际治疗 = 治疗力 × 技能倍率，且不得超过目标最大 HP（由 receive_healing 夹取）；
##   ③ 全部满血时不执行治疗，且**不消耗间隔**（否则会出现「空转掉一次治疗」）；
##   ④ 冷却与间隔同样只在固定逻辑步内推进。
func _resolve_healer_action(c: CharacterRuntime, step: float) -> void:
	c.attack_cooldown = maxf(0.0, c.attack_cooldown - step)
	if c.attack_cooldown > 0.0:
		return
	var target := _select_heal_target_for(c)
	if target == null:
		# 无可治疗目标（全部满血 / 范围内无人）→ 不进入冷却，等下一次逻辑步再试
		return
	var amount := int(round(float(c.compute_heal_amount()) * _heal_mult(c)))
	var healed := target.receive_healing(amount)
	if healed <= 0:
		return
	c.total_healing_done += healed
	total_healing_done += healed
	c.last_heal_at = elapsed_seconds
	c.attack_cooldown = c.heal_interval
	heal_events.append({
		"healerId": c.instance_id,
		"targetId": target.instance_id,
		"amount": healed,
		"at": snappedf(elapsed_seconds, 0.001),
	})
	GameLog.debug("StageRuntime", "%s 治疗 %s %d HP（剩余 HP %d/%d）"
		% [c.display_name, target.display_name, healed, target.hp, target.max_hp])


## 记录一次**实际生效**的伤害（P1.0 基础反馈的表现层数据源）。
##
## target_is_enemy: true = 敌人被打（角色输出），false = 角色被打（敌人输出）。
## 只记录 applied > 0 的事件；表现层据此播伤害数字与受击闪白。
## 本方法**不参与任何战斗判定**，也不改变调用点的返回值。
func _record_damage_event(
	target_is_enemy: bool,
	target_instance_id: int,
	applied: int,
	lethal: bool,
	source_kind: String = "",
	source_id: int = 0,
	source_pos: Vector2 = Vector2.ZERO,
	target_pos: Vector2 = Vector2.ZERO,
	damage_type: int = 0,
	skill_attack: bool = false
) -> void:
	if applied <= 0:
		return
	_damage_event_sequence += 1
	damage_events.append({
		"seq": _damage_event_sequence,
		"targetKind": "enemy" if target_is_enemy else "character",
		"targetId": target_instance_id,
		"amount": applied,
		"at": snappedf(elapsed_seconds, 0.001),
		"lethal": lethal,
		"sourceKind": source_kind, "sourceId": source_id,
		"sourcePos": source_pos, "targetPos": target_pos,
		"hasPosition": not source_kind.is_empty(), "damageType": damage_type,
		# Capture before NEXT_ATTACK consumes its charge; presentation must not
		# infer this from mutable character state after the committed hit.
		"skillAttack": skill_attack,
	})
	# 环形裁剪：只保留最近若干条，避免长局内存无上限增长。
	# 表现层每个逻辑步都会消费新事件，因此裁剪不影响可见反馈。
	if damage_events.size() > DAMAGE_EVENT_RETENTION:
		damage_events = damage_events.slice(damage_events.size() - DAMAGE_EVENT_RETENTION)


## 治疗目标选择（V2.1.4 表 30 / 表 31）：
##   范围：曼哈顿距离 ≤ rangeTiles；跨线数 ≤ maxLaneDelta（独立于几何距离判定）；
##   优先级：当前**生命百分比最低**的受伤友军；
##   并列时按 instance_id 升序，保证确定性。
func _select_heal_target_for(c: CharacterRuntime) -> CharacterRuntime:
	var best: CharacterRuntime = null
	var best_ratio := 2.0
	for other: CharacterRuntime in characters:
		if other.character_id == "sara_device":
			continue
		if other.instance_id == c.instance_id:
			continue
		if not other.is_wounded():
			continue
		if not _is_in_heal_range(c, other):
			continue
		var ratio := other.hp_ratio()
		if ratio < best_ratio - 0.000001:
			best_ratio = ratio
			best = other
		elif best != null and absf(ratio - best_ratio) <= 0.000001 				and other.instance_id < best.instance_id:
			best = other
	return best


## 目标是否落在治疗范围内。
## 先判跨线（maxLaneDelta，规格要求作为独立规则显式限制），再判曼哈顿距离。
func _is_in_heal_range(c: CharacterRuntime, other: CharacterRuntime) -> bool:
	var lane_delta := absi(c.lane - other.lane)
	if lane_delta > c.max_lane_delta:
		return false
	if c.heal_uses_manhattan:
		var manhattan := absi(c.column - other.column) + lane_delta
		return float(manhattan) <= c.attack_range_tiles + 0.0001
	# 非曼哈顿形状（P0.4 未使用）：退化为同路直线距离，避免出现未定义的判定
	if lane_delta != 0:
		return false
	return float(absi(c.column - other.column)) <= c.attack_range_tiles + 0.0001


## 兼容旧调用点：仅执行输出型角色的攻击结算。
## （保留名称以免破坏 P0.2/P0.3 既有测试语义；新代码应使用 _resolve_character_actions）
func _resolve_character_attacks(step: float) -> void:
	for c: CharacterRuntime in characters:
		if c.is_incapacitated():
			continue
		if c.is_healer():
			continue
		_resolve_attacker_action(c, step)


## 目标选择（V2.1.4 D-11 目标优先级 + 裁决 DEC-C-0003 跨路线攻击）。
##
## 优先级（保持原有规则不变）：
##   ① 最接近防守核心的敌人（logicalX 最小）
##   ② 当前正在阻挡的敌人
##   ③ 更早进入攻击范围的敌人（以 instance_id 升序近似「更早」，保证确定性）
##
## 攻击范围（裁决 DEC-C-0003）：
##   - 本路线：前方 rangeTiles 以内（如悠真 4.0 格）；
##   - 相邻路线：仅当角色数据显式声明 allowCrossLane 且 |laneDelta| ≤ maxLaneDelta 时，
##     前方 adjacentLaneRangeTiles 以内（如悠真 3.0 格）；
##   - **绝不允许上路直接打下路**（laneDelta=2 被 can_attack_lane 拒绝）。
##
## 例外：当前被该角色阻挡的敌人**始终可攻击**（阻挡目标必然同路线）。
##
## 每次普通攻击仍只选择一个目标（DEC-C-0003 明文：跨线不增加攻击频率、不复制攻击次数）。
func _select_target_for(c: CharacterRuntime) -> EnemyRuntime:
	var candidates: Array[EnemyRuntime] = []
	for e: EnemyRuntime in enemies:
		if not e.is_active():
			continue
		# 路线闸门：同路线恒定合法；跨线须由数据显式授权且不超过 maxLaneDelta
		if not c.can_attack_lane(e.lane):
			continue
		var blocked_by_me := c.is_blocking(e.instance_id)
		if not blocked_by_me:
			# 射程判定：按目标所在路线取有效射程（本路 vs 相邻路），全部以逻辑格计算
			if not c.is_target_in_attack_range(e.lane, e.logical_x):
				continue
		candidates.append(e)

	if candidates.is_empty():
		return null

	candidates.sort_custom(func(a: EnemyRuntime, b: EnemyRuntime) -> bool:
		# ① 最接近核心（logicalX 最小）优先
		if not is_equal_approx(a.logical_x, b.logical_x):
			return a.logical_x < b.logical_x
		# ② 当前被本角色阻挡者优先
		var a_blocked := c.is_blocking(a.instance_id)
		var b_blocked := c.is_blocking(b.instance_id)
		if a_blocked != b_blocked:
			return a_blocked
		# ③ 更早进入战场者优先（instance_id 升序）
		return a.instance_id < b.instance_id
	)
	# 单次攻击只取一个目标（DEC-C-0003：targetLimit 当前恒为 1）
	return candidates[0]


## 敌人攻击（被阻挡时攻击阻挡者）
## 状态说明：敌人一旦被阻挡即保持 BLOCKED（V2.1.4 F-四十五 状态机中 ATTACKING 表示
## 「正在出手」的瞬间态）。为保持逻辑简单且确定，攻击结算不切换主状态，
## 仅通过 attack_cooldown 控制出手节奏；BLOCKED 期间持续攻击其阻挡者。
func _resolve_enemy_attacks(step: float) -> void:
	for e: EnemyRuntime in enemies:
		if not e.is_active():
			continue
		if e.state != BattleTypes.EnemyState.BLOCKED:
			continue
		e.attack_cooldown = maxf(0.0, e.attack_cooldown - step)
		if e.attack_cooldown > 0.0:
			continue
		var blocker := get_character(e.blocked_by_character_id)
		if blocker == null or blocker.is_incapacitated():
			# 阻挡者已失能/已撤退：本帧不结算，状态在 _release_invalid_blocks 中被释放
			continue
		var dmg := combat_math.compute_damage(e.attack, _defense_of_target(blocker), e.damage_type)
		var applied := blocker.take_damage(dmg)
		e.total_damage_dealt += applied
		e.attack_cooldown = e.attack_interval
		_record_damage_event(false, blocker.instance_id, applied, blocker.is_incapacitated(),
			"enemy", e.instance_id, Vector2(e.logical_x, e.lane),
			Vector2(blocker.column, blocker.lane), e.damage_type)


## 清理死亡实体与失能角色
func _cleanup_dead() -> void:
	# 敌人死亡：HP 耗尽者统一置为 DEAD 并计数（击杀统计的唯一入口）
	var still_alive: Array[EnemyRuntime] = []
	for e: EnemyRuntime in enemies:
		if e.hp <= 0:
			if e.state != BattleTypes.EnemyState.DEAD:
				e.state = BattleTypes.EnemyState.DEAD
				enemies_killed += 1
				_note_wave_kill(e)
				# 记录击杀离场（P1.0 修复）：
				# removals 的契约是记录「击杀 / 漏怪 / 主动撤退 / 失能」四类离场，
				# 但此前只有**测试夹具**会写 KILLED，真实击杀路径漏了这一步，
				# 导致表现层无法据 removals 回放「敌人是怎么没的」（死亡粒子永远不触发）。
				# 漏怪路径（apply_core_damage）一直是正常写入的，此处补齐以保持一致。
				# 幂等：状态一旦置 DEAD 就不会再进入本分支。
				_append_enemy_removal(Removal.KILLED, e)
				GameLog.debug("StageRuntime", "敌人 %s 被击败" % e.enemy_id)
			continue
		if e.is_active():
			still_alive.append(e)
	enemies = still_alive

	# 角色侧同步清理：移除指向已消失敌人的引用
	for c: CharacterRuntime in characters:
		if c.blocking_enemy_ids.is_empty():
			continue
		var kept_ids: Array[int] = []
		for eid: int in c.blocking_enemy_ids:
			if get_enemy(eid) != null:
				kept_ids.append(eid)
		c.blocking_enemy_ids = kept_ids

	# 角色因 HP 耗尽而失能 → 离场并进入再部署冷却（V2.1.4 D-27 / 表 24「死亡返还 0 AP」）
	var still_standing: Array[CharacterRuntime] = []
	for c: CharacterRuntime in characters:
		if c.is_incapacitated():
			c.blocking_enemy_ids.clear()
			characters_lost += 1
			# 失能离场同样按规格进入再部署冷却（规格未区分该计时的长度，
			# 故与主动撤退统一按角色的 redeployTime 计时）。
			c.redeploy_cooldown_remaining = c.redeploy_time
			_append_removal(Removal.INCAPACITATED, c.character_id, c.instance_id, c.column, c.lane)
			GameLog.info("StageRuntime", "%s 失去战斗能力，离场并进入 %.1f 秒再部署冷却（不返还 AP）"
				% [c.display_name, c.redeploy_cooldown_remaining])
			continue
		still_standing.append(c)
	characters = still_standing


## 局内强化（Alpha A0.6）。null = 本关未开放强化系统。
##
## 关键不变量（有回归测试逐条钉死）：
##   ① 本字段为 null 时，**所有倍率入口恒等于 1.0 / 基础比例**，
##      伤害、AP 回复、撤退返还与接入前逐位一致 —— 即对 1-1～1-4 与既有测试零影响。
##   ② 倍率只在既有结算公式的**输入端**乘一次，不新增任何判定分支、
##      不改伤害公式本身（D-22 公式 LOCKED）。
##   ③ 离开关卡即随本对象销毁（L2118「局内强化离开关卡后清空」），不落盘。
var upgrades: InBattleUpgrades = null


# ============================================================
#  A0.6 局内强化：三选一面板的领域层状态（契约 docs/a0_6_ui_contract.md 第 1 节）
# ============================================================
#
# 分层纪律（L3，同 upgrades 字段）：
#   * 本区块只做**纯逻辑**：建立/清空 pending、校验玩家请求、冻结推进。
#     不读存档、不碰 UI、不依赖场景节点。
#   * 表现层（battle_scene.gd）只读 pending_offer 并**转发**玩家操作，
#     合法性裁决全部在本区块。

## 当前待处理的三选一请求。{} = 无请求。
##
## 非空时字段（契约冻结）：
##   candidates: Array[String]   当前候选（1~3 项）
##   isTutorial: bool            是否为 1-5 首次固定教学三选一
##   offerIndex: int             本次是第几次开放（1 起）
##   rerollsRemaining: int       剩余免费重掷次数
##
## **冻结语义**：非空期间 advance() 不推进任何计时器（返回空数组），
## 且**不得**把 paused 置为 true（玩家暂停与强化冻结是两套状态，混用会让
## 暂停按钮语义错乱：玩家点「继续」会误跳到下一波）。依据 L1972。
var pending_offer: Dictionary = {}

## 本关注入的 upgrades 数据域（仅在校验通过、且本关开放时保留）。
## 用途：教学固定三选一的 id 列表在数据里，reroll 时要能重新读出它。
var _upgrades_domain: Dictionary = {}

## 1-5 首次通关前为 true：本次走固定教学三选一（L2132）。
## 「是否首次」由表现/存档层判定后注入（域层不读存档，L3）。
var _tutorial_offer_enabled: bool = false

## 本场已消耗的开放次数（**含跳过**，见 skip_offer）。
## 为什么跳过也计入：L2051 允许跳过，但若不计入库，玩家就能靠"跳过→面板再来"
## 无限刷候选，等于取消 L2045「重掷不能反复刷到满意为止」的限制。
func _offer_battle_finished() -> bool:
	# 「战斗已结束」的域层口径：上层停表（running=false，BattleSession 在
	# 胜负确定时设置）或核心 HP 耗尽（D-41 立即失败）。
	return (not running) or core_hp <= 0


## 当前是否有待处理的三选一请求
func has_pending_offer() -> bool:
	return not pending_offer.is_empty()


## 本局已获得强化（按获得顺序）。未开放本系统时返回空数组。
## 条目：{id, name, description, stacks, maxStacks, tier, category, icon}
## 数据全部来自数据层（本函数不写死任何中文名/数值）。
func upgrade_summary() -> Array[Dictionary]:
	if upgrades == null:
		return []
	return upgrades.upgrade_summary()


## 启用/关闭固定教学三选一（L2132「首次」由表现/存档层判定后注入）。
func set_tutorial_offer_enabled(value: bool) -> void:
	if _tutorial_offer_enabled == value:
		return
	_tutorial_offer_enabled = value
	GameLog.info("StageRuntime", "教学强化模式：%s" % ("启用（固定三选一）" if value else "关闭（走随机候选）"))


func is_tutorial_offer_enabled() -> bool:
	return _tutorial_offer_enabled


## 取某单位的攻击倍率（无强化系统时恒为 1.0）。
func _atk_mult(c: CharacterRuntime) -> float:
	if upgrades == null:
		return 1.0
	return upgrades.attack_multiplier(CharacterRuntime.behavior_name(c.behavior))


## 取某目标的防御有效值（前线防御类强化只作用于角色，敌人不受玩家强化影响）。
func _defense_of_target(c: CharacterRuntime) -> float:
	var base := float(c.defense)
	if c.talent_config.get("effect", "") == "LOW_HP_DEFENSE" and c.hp_ratio() < float(c.talent_config.get("hpThreshold", 0.0)):
		base *= 1.0 + float(c.talent_config.get("defenseBonusPct", 0.0))
	if upgrades == null:
		return base
	return base * upgrades.defense_multiplier(
		CharacterRuntime.behavior_name(c.behavior))


## 取治疗者的治疗倍率（无强化系统时恒为 1.0）。
func _heal_mult(c: CharacterRuntime) -> float:
	if upgrades == null:
		return 1.0
	return upgrades.heal_multiplier(CharacterRuntime.behavior_name(c.behavior))


## 部署或重建角色后调用：把已选强化的持续型增益挂到该实例上。
## 当前实现走"结算时读取"路径（见 _atk_mult 等），不注入 StatusEffect，
## 因此本函数暂为空实现占位——留注释说明，避免误以为漏了接线。
func _apply_upgrades_to_instance(_c: CharacterRuntime) -> void:
	pass


## AP 自然回复倍率（阶段级；无强化系统时恒为 1.0）。
func _ap_regen_mult() -> float:
	var bonus := upgrades.ap_regen_bonus_pct() if upgrades != null else 0.0
	for character: CharacterRuntime in characters:
		if not character.is_incapacitated():
			bonus += float((_character_configs.get(character.character_id, {}) as Dictionary).get("apRegenBonusPct", 0.0))
	return 1.0 + minf(ap_regen_bonus_cap, bonus)


# ============================================================
#  查询
# ============================================================

## 按 upgrades.json 的 openByStage 决定是否启用局内强化系统。
##
## 纪律：
##   * 数据未注入（tools/ 模拟器、未升级的调用方）→ 不启用，倍率恒 1.0；
##   * 关卡未在 openByStage 中**显式**列出 → 不启用（不拿 default 当开放依据），
##     避免"忘了配就自动开"这种静默改变既有关卡体验的行为；
##   * 数据校验有错 → 不启用并把错误并入 _errors（宁可不开，也不带坏数据跑）；
##   * triggerWaves（A0.6）在**同一处**读入并做同样纪律的校验：
##     缺失 / 非数组 / 含非法波号 → 不启用 + 报错。
##     **绝不静默兜底成"每波都能触发"**——那会让所有开放关卡每波弹一次面板。
func _configure_upgrades(upgrades_domain: Dictionary) -> void:
	if upgrades_domain.is_empty():
		return
	var plan: Variant = upgrades_domain.get("openByStage", {})
	if typeof(plan) != TYPE_DICTIONARY:
		_errors.append("upgrades.openByStage 必须是对象")
		return
	var entry: Variant = (plan as Dictionary).get(stage_id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return
	var opens := int((entry as Dictionary).get("opens", 0))
	if opens <= 0:
		return
	# ---- triggerWaves：与 opens 同一处的严格校验 ----
	var trigger_waves: Array[int] = []
	var raw_waves: Variant = (entry as Dictionary).get("triggerWaves", null)
	if raw_waves == null:
		_errors.append("upgrades.openByStage.%s 缺少 triggerWaves（A0.6 契约要求显式声明触发波号）" % stage_id)
		return
	if typeof(raw_waves) != TYPE_ARRAY:
		_errors.append("upgrades.openByStage.%s.triggerWaves 必须是数组" % stage_id)
		return
	for v: Variant in (raw_waves as Array):
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			_errors.append("upgrades.openByStage.%s.triggerWaves 含非数字项：%s" % [stage_id, str(v)])
			return
		var wn := int(v)
		if wn < 1:
			_errors.append("upgrades.openByStage.%s.triggerWaves 波号必须 ≥ 1，实际 %d" % [stage_id, wn])
			return
		if not trigger_waves.has(wn):
			trigger_waves.append(wn)
	var u := InBattleUpgrades.from_data(upgrades_domain)
	if not u.get_errors().is_empty():
		for e: String in u.get_errors():
			_errors.append("upgrades 数据错误：%s" % e)
		return
	# 教学固定项：与 triggerWaves 同一纪律——声明了就必须自洽；不自洽只是
	# "教学不可用"（回落随机），但 id 列表本身非法（非数组）要报错。
	var tutorial_ids: Array[String] = []
	var fixed: Variant = upgrades_domain.get("tutorialFixedChoices_1_5", null)
	if typeof(fixed) == TYPE_DICTIONARY:
		var raw_ids: Variant = (fixed as Dictionary).get("upgradeIds", [])
		if typeof(raw_ids) != TYPE_ARRAY:
			_errors.append("upgrades.tutorialFixedChoices_1_5.upgradeIds 必须是数组")
			return
		for v: Variant in (raw_ids as Array):
			tutorial_ids.append(str(v))
	elif fixed != null:
		_errors.append("upgrades.tutorialFixedChoices_1_5 必须是对象")
		return
	u.total_opens = opens
	u.rerolls_remaining = int(upgrades_domain.get("rerollsPerBattle", 0))
	u.trigger_waves = trigger_waves
	u.tutorial_fixed_ids = tutorial_ids
	upgrades = u
	_upgrades_domain = upgrades_domain
	GameLog.info("StageRuntime", "局内强化已启用：%s（开放 %d 次，免费重掷 %d 次，触发波 %s）"
		% [stage_id, opens, u.rerolls_remaining, str(trigger_waves)])


## 本关可用队伍的「行为集合」与「标签并集」——候选算法的输入（L2051 第 1 步）。
## 用 availableCharacters（本关可上阵的全部角色）而非当前在场角色：
## 构筑价值应看"这支队伍能不能用"，而不是"此刻恰好站了几个人"。
func _party_profile() -> Dictionary:
	var behaviors: Array[String] = []
	var tags: Array[String] = []
	for cid: String in available_characters:
		var cfg: Dictionary = _character_configs.get(cid, {})
		var beh := str(cfg.get("behavior", ""))
		if not beh.is_empty() and not behaviors.has(beh):
			behaviors.append(beh)
		var t: Variant = cfg.get("roleTags", [])
		if typeof(t) == TYPE_ARRAY:
			for v: Variant in (t as Array):
				if not tags.has(str(v)):
					tags.append(str(v))
	return {"behaviors": behaviors, "tags": tags}


## 取当前三选一候选。未启用强化系统时返回空数组。
func upgrade_choices() -> Array[String]:
	if upgrades == null:
		return []
	# 选择次数已用尽时不再提供候选：否则 UI 会弹出一个"点了也没用"的面板。
	if upgrades.selections_used >= upgrades.total_opens:
		return []
	var profile := _party_profile()
	return UpgradeCandidateRoller.roll(
		upgrades, profile["behaviors"], profile["tags"], _upgrade_seed())


## 1-5 首次为**固定**教学三选一（L2132），不走随机抽取。
## 返回按 upgrades.json 声明顺序、且当前仍可选择的条目；不足 3 项时返回空，
## 由调用方回落到随机候选（不硬凑，也不假装教学成功）。
func tutorial_upgrade_choices(upgrades_domain: Dictionary) -> Array[String]:
	if upgrades == null:
		return []
	# id 列表优先取本关注入的数据域；调用方另传一份（测试夹具）时以传入者为准。
	var ids: Array = []
	var fixed: Variant = upgrades_domain.get("tutorialFixedChoices_1_5", null)
	if typeof(fixed) == TYPE_DICTIONARY:
		var raw_ids: Variant = (fixed as Dictionary).get("upgradeIds", [])
		if typeof(raw_ids) == TYPE_ARRAY:
			ids = raw_ids
	if ids.is_empty():
		# 数据域未随本次调用传入（例如表现层只传了自身缓存）→ 用启用时读入的副本，
		# 避免"数据明明配了却拿不到教学项"。
		ids = upgrades.tutorial_fixed_ids
	if ids.size() != 3:
		return []
	var out: Array[String] = []
	for v: Variant in ids:
		var id := str(v)
		if not upgrades.has_definition(id) or not upgrades.can_select(id):
			return []   # 有一项不可用就整体回落，不给"缺一个"的教学
		out.append(id)
	return out


## 玩家选定一项强化。未启用 / 非法 / 已满叠返回 false（不静默生效）。
func choose_upgrade(upgrade_id: String) -> bool:
	if upgrades == null:
		GameLog.warn("StageRuntime", "本关未开放局内强化，忽略选择请求：%s" % upgrade_id)
		return false
	if upgrades.selections_used >= upgrades.total_opens:
		GameLog.warn("StageRuntime", "本场强化选择次数已用尽（%d/%d）"
			% [upgrades.selections_used, upgrades.total_opens])
		return false
	if not upgrades.apply(upgrade_id):
		return false
	upgrades.selections_used += 1
	GameLog.info("StageRuntime", "局内强化已选择：%s（%d/%d 次）"
		% [upgrade_id, upgrades.selections_used, upgrades.total_opens])
	return true


## 消耗一次免费重掷（L2117）。**不重建 pending 候选**（老入口，保留兼容）。
func reroll_upgrades() -> bool:
	if upgrades == null or upgrades.rerolls_remaining <= 0:
		return false
	upgrades.rerolls_remaining -= 1
	upgrades.reroll_count += 1
	_sync_offer_rerolls()
	GameLog.info("StageRuntime", "使用免费重掷，剩余 %d 次" % upgrades.rerolls_remaining)
	return true


# ============================================================
#  A0.6 三选一面板：玩家操作入口（契约 docs/a0_6_ui_contract.md 第 1 节）
# ============================================================

## 玩家选定一项。
##
## 成功：应用效果 + 计入 selections_used + 清空 pending + 战斗恢复（由 advance 解冻）。
## 失败返回 false 且**不清空** pending（可重试）：无 pending / id 非法 /
## **id 不在当前候选内**（越权防护）/ 次数用尽 / 战斗已结束。
##
## 「id 必须属于当前候选」是本函数的**关键防线**：表现层拿到的只是卡面快照，
## 若不校验，任何调用方都能凭 id 直接注入任意强化（UI 越权 = 绕过三选一规则）。
func resolve_offer(upgrade_id: String) -> bool:
	if upgrades == null:
		GameLog.warn("StageRuntime", "本关未开放局内强化，忽略选择请求：%s" % upgrade_id)
		return false
	if not has_pending_offer():
		GameLog.warn("StageRuntime", "当前没有待处理的强化选择，忽略：%s" % upgrade_id)
		return false
	if _offer_battle_finished():
		GameLog.warn("StageRuntime", "战斗已结束，拒绝强化选择：%s" % upgrade_id)
		return false
	if upgrades.is_exhausted():
		GameLog.warn("StageRuntime", "本场强化选择次数已用尽（%d/%d），拒绝：%s"
			% [upgrades.selections_used, upgrades.total_opens, upgrade_id])
		return false
	var candidates: Array = pending_offer.get("candidates", [])
	if not candidates.has(upgrade_id):
		GameLog.warn("StageRuntime", "强化 %s 不在本次候选中（%s），拒绝（防越权注入）"
			% [upgrade_id, str(candidates)])
		return false
	if not upgrades.apply(upgrade_id):
		# 未知 id 或已达叠加上限：同样不清空 pending，让玩家改选别的
		return false
	upgrades.selections_used += 1
	GameLog.info("StageRuntime", "局内强化已选择：%s（第 %d 次开放，累计选择 %d/%d，层数 %d）"
		% [upgrade_id, int(pending_offer.get("offerIndex", 0)),
			upgrades.selections_used, upgrades.total_opens,
			upgrades.stacks_of(upgrade_id)])
	pending_offer = {}
	_sync_offer_rerolls()
	return true


## 消耗 1 次免费重掷并就地重建候选（保持 pending）。无 pending / 无次数返回 false。
##
## 重掷确定性（契约）：候选仍由 _upgrade_seed() 派生，**重掷次数参与种子**
## （UpgradeCandidateRoller 抽取前 reroll_count 已 +1），因此
## 「同一状态 ⇒ 同一候选」在重掷后依然成立，帧率无关性不受破坏
## （种子刻意不含 elapsed_seconds）。
##
## 教学态取舍（L2132）：1-5 首次是**固定**三选一，重掷后候选项仍是教学三项，
## 但**照常消耗**那 1 次重掷（保持 L2117「每场默认 1 次免费重掷」与既有
## test_reroll_is_single_use 的语义）。理由：第一次见到强化系统就被告知
## "选项是随机的"才是错误的教学。
func reroll_offer() -> bool:
	if upgrades == null or not has_pending_offer():
		return false
	if _offer_battle_finished():
		GameLog.warn("StageRuntime", "战斗已结束，拒绝重掷")
		return false
	if upgrades.rerolls_remaining <= 0:
		GameLog.warn("StageRuntime", "没有剩余的重掷次数（已用 %d 次）" % upgrades.reroll_count)
		return false
	var was_tutorial := bool(pending_offer.get("isTutorial", false))
	upgrades.rerolls_remaining -= 1
	upgrades.reroll_count += 1
	var rebuilt := _roll_offer_candidates()
	if rebuilt.is_empty():
		# 池耗尽（极端情形）：候选整体清空 ⇒ 面板已无内容可选。
		# 这里**不**顺势消耗开放次数：本次开放作废，玩家可继续重掷（若有次数）。
		GameLog.warn("StageRuntime", "重掷后候选为空（池耗尽），本次开放作废、不消耗开放次数")
		pending_offer = {}
		return false
	pending_offer["candidates"] = rebuilt
	pending_offer["isTutorial"] = _offer_is_tutorial()
	pending_offer["rerollsRemaining"] = upgrades.rerolls_remaining
	if was_tutorial:
		GameLog.info("StageRuntime",
			"教学态重掷：候选保持固定 %s（L2132 首次固定三选一，不切换为随机）；剩余重掷 %d 次"
			% [str(rebuilt), upgrades.rerolls_remaining])
	else:
		GameLog.info("StageRuntime", "重掷完成：新候选 %s（第 %d 次重掷，剩余 %d 次）"
			% [str(rebuilt), upgrades.reroll_count, upgrades.rerolls_remaining])
	return true


## 跳过本次强化（L2051：V2.1 允许玩家「跳过强化」，普通情况下**没有额外奖励**；
## 该功能用于极端构筑需求和测试）。
##
## 跳过**计入已用开放次数**：若不计入，玩家可用"跳过 → 面板再开"无限刷候选，
## 等于取消 L2045「重掷不能反复刷到满意为止」的限制。跳过不应用任何效果，
## 也不进入 upgrade_summary()（跳过 ≠ 获得）。
func skip_offer() -> bool:
	if upgrades == null or not has_pending_offer():
		return false
	if _offer_battle_finished():
		GameLog.warn("StageRuntime", "战斗已结束，拒绝跳过")
		return false
	if upgrades.is_exhausted():
		return false
	upgrades.selections_used += 1
	GameLog.info("StageRuntime", "玩家跳过本次强化（L2051，无额外奖励）：第 %d 次开放，累计 %d/%d"
		% [int(pending_offer.get("offerIndex", 0)),
			upgrades.selections_used, upgrades.total_opens])
	pending_offer = {}
	_sync_offer_rerolls()
	return true


## 把 rebase 后的重掷剩余同步进 pending 快照（表现层读 pending 显示「剩余重掷：N」）。
func _sync_offer_rerolls() -> void:
	if upgrades == null or pending_offer.is_empty():
		return
	pending_offer["rerollsRemaining"] = upgrades.rerolls_remaining


## 探针/测试用：pending 状态的只读快照（契约第 3 节 upgradeOffer 的域层对应物）。
func offer_debug_dict() -> Dictionary:
	var ids: Array = []
	var it_tut := false
	var offer_index := 0
	var rerolls := 0
	if upgrades != null:
		rerolls = upgrades.rerolls_remaining
	if not pending_offer.is_empty():
		var c: Variant = pending_offer.get("candidates", [])
		if typeof(c) == TYPE_ARRAY:
			for v: Variant in (c as Array):
				ids.append(str(v))
		it_tut = bool(pending_offer.get("isTutorial", false))
		offer_index = int(pending_offer.get("offerIndex", 0))
		rerolls = int(pending_offer.get("rerollsRemaining", rerolls))
	return {
		"active": has_pending_offer(),
		"ids": ids,
		"isTutorial": it_tut,
		"offerIndex": offer_index,
		"rerollsRemaining": rerolls,
	}


## 派生抽取种子。
##
## 只由「关卡 id + 已选次数 + 已重掷次数」构成 —— **刻意不含 elapsed_seconds**：
## 若把逻辑时刻混进种子，不同帧率/不同暂停时机就会摇出不同候选，
## 破坏既有的「不同分辨率与渲染帧率不改变战斗结果」LOCKED 保证
## （tests/test_p0_4_three_class.gd 第 16 项钉着这条）。
func _upgrade_seed() -> int:
	var h := 2166136261
	for b: int in stage_id.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0x7FFFFFFF
	h = (h ^ (upgrades.selections_used * 2654435761)) & 0x7FFFFFFF
	h = (h ^ (upgrades.reroll_count * 40503)) & 0x7FFFFFFF
	return h


func get_enemy(instance_id: int) -> EnemyRuntime:
	for e: EnemyRuntime in enemies:
		if e.instance_id == instance_id:
			return e
	return null


func get_character(instance_id: int) -> CharacterRuntime:
	for c: CharacterRuntime in characters:
		if c.instance_id == instance_id:
			return c
	return null


## 对指定敌人结算核心伤害（幂等：同一敌人只结算一次）。
func apply_core_damage(enemy: EnemyRuntime) -> int:
	if enemy == null:
		return 0
	if enemy.core_damage_applied:
		return 0
	enemy.core_damage_applied = true
	var dmg := maxi(0, enemy.core_damage)
	core_hp = maxi(0, core_hp - dmg)
	core_damage_events += 1
	_append_enemy_removal(Removal.REACHED_CORE, enemy)
	GameLog.info("StageRuntime", "敌人 %s 抵达核心，核心 HP -%d -> %d"
		% [enemy.enemy_id, dmg, core_hp])
	return dmg


## 清除全部已抵达核心的敌人（结算后从场上移除）。
func remove_reached_core() -> void:
	var kept: Array[EnemyRuntime] = []
	for e: EnemyRuntime in enemies:
		if e.state != BattleTypes.EnemyState.REACHED_CORE:
			kept.append(e)
	enemies = kept


func _append_enemy_removal(kind: int, enemy: EnemyRuntime) -> void:
	for r: Dictionary in removals:
		if str(r.get("entity", "")) == "enemy" \
			and int(r.get("kind", -1)) == kind \
			and int(r.get("entityId", -1)) == enemy.instance_id:
			return
	removals.append({
		"kind": kind,
		"entity": "enemy",
		"entityId": enemy.instance_id,
		"enemyId": enemy.enemy_id,
		"lane": enemy.lane,
		"x": snappedf(enemy.logical_x, 0.001),
		"at": snappedf(elapsed_seconds, 0.001),
	})


# ============================================================
#  复盘统计（V2.1.4 G-八 失败与复盘设计）
# ============================================================

## 突破核心的敌人种类 → 次数。
## V2.1.4 G-八 要求失败结算显示「突破核心的敌人类型」。
func leaked_by_enemy_type() -> Dictionary:
	var out := {}
	for r: Dictionary in removals:
		if str(r.get("entity", "")) != "enemy":
			continue
		if int(r.get("kind", -1)) != Removal.REACHED_CORE:
			continue
		var eid := str(r.get("enemyId", "?"))
		out[eid] = int(out.get(eid, 0)) + 1
	return out


## 各路线累计承受的压力（按该路线生成的敌人**总 HP** 计）。
##
## 为什么用总 HP 而不是「敌人个数」：V2.1.4 明确「关卡难度主要来自敌人组合与出怪时机，
## 不靠单纯堆血」，但一条路上出现 2 只装甲（1600 HP）与出现 2 只普通（840 HP）
## 对玩家的实际压力完全不同。用总 HP 更接近「该路线需要多少输出量」。
## 返回 {lane: totalHp}，lane 0/1/2。
func pressure_by_lane() -> Dictionary:
	var out := {0: 0, 1: 0, 2: 0}
	for e: Dictionary in _spawn_plan:
		var lane := int(e["lane"])
		var eid := str(e["enemy"])
		var hp := 0
		if _enemy_configs.has(eid):
			hp = int((_enemy_configs[eid] as Dictionary).get("hp", 0))
		out[lane] = int(out.get(lane, 0)) + hp
	return out


## 承受压力最大的路线（V2.1.4 G-八「最多承压路线」）。压力并列时取编号较小的路线。
## 无出怪时返回 -1。
func busiest_lane() -> int:
	if _spawn_plan.is_empty():
		return -1
	var p := pressure_by_lane()
	var best_lane := -1
	var best := -1
	for lane: int in [0, 1, 2]:
		var v := int(p.get(lane, 0))
		if v > best:
			best = v
			best_lane = lane
	return best_lane


## 各敌人种类的击杀数（结算摘要用）
func kills_by_enemy_type() -> Dictionary:
	var out := {}
	for r: Dictionary in removals:
		if str(r.get("entity", "")) != "enemy":
			continue
		if int(r.get("kind", -1)) != Removal.KILLED:
			continue
		var eid := str(r.get("enemyId", "?"))
		out[eid] = int(out.get(eid, 0)) + 1
	return out


# ============================================================
#  暂停（V2.1.4 D-35）
# ============================================================

## 暂停 / 继续。暂停后敌人移动、AP 回复、攻击、再部署冷却与 Wave 计时全部冻结；
## 恢复后从同一状态继续推进（不补跑暂停期间的时间）。
func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	GameLog.info("StageRuntime", "战斗%s" % ("已暂停" if paused else "已继续"))


func is_paused() -> bool:
	return paused


# ============================================================
#  测试夹具（P0.1 引入；明确标注仅供测试，不得出现在正式游戏流程）
# ============================================================

## 供测试使用：按 instance_id 移除一个敌人（模拟「被清除」）。
## P0.2 起已有真实击杀路径，本夹具仅保留以维持 P0.1 测试
## （禁止在正式游戏流程中调用）。
func despawn_for_test(instance_id: int) -> bool:
	for i: int in range(enemies.size()):
		if enemies[i].instance_id == instance_id:
			enemies[i].state = BattleTypes.EnemyState.DEAD
			_append_enemy_removal(Removal.KILLED, enemies[i])
			_note_wave_kill(enemies[i])
			enemies.remove_at(i)
			return true
	return false


## 供测试使用：清除场上全部敌人。
## 语义上等价于「这些敌人已被处理完毕」，因此同样计入所属 Wave 的击杀数，
## 否则「清场后应判胜」这类 P0.1 用例会因为 Wave 未完成而永远不判胜。
func despawn_all_for_test() -> int:
	var n := enemies.size()
	for e: EnemyRuntime in enemies:
		e.state = BattleTypes.EnemyState.DEAD
		_append_enemy_removal(Removal.KILLED, e)
		_note_wave_kill(e)
	enemies.clear()
	return n


func to_debug_dict() -> Dictionary:
	var enemies_dbg: Array[Dictionary] = []
	for e: EnemyRuntime in enemies:
		enemies_dbg.append(e.to_debug_dict())
	var chars_dbg: Array[Dictionary] = []
	for c: CharacterRuntime in characters:
		chars_dbg.append(c.to_debug_dict())
	return {
		"stageId": stage_id,
		"elapsed": snappedf(elapsed_seconds, 0.001),
		"coreHp": core_hp,
		"coreHpMax": core_hp_max,
		"ap": ap,
		"apMax": ap_max,
		"spawned": _spawn_cursor,
		"planned": _spawn_plan.size(),
		"living": enemies.size(),
		"reachedCore": reached_core_count,
		"coreDamageEvents": core_damage_events,
		"enemiesKilled": enemies_killed,
		"charactersLost": characters_lost,
		"retreatCount": retreat_count,
		"retreatRefundedAp": retreat_refunded_ap_total,
		"healCount": heal_events.size(),
		"healedTotal": total_healing_done,
		"deployed": characters.size(),
		"deployedTotal": character_instances.size(),
		"paused": paused,
		"wave": current_wave_number(),
		"waveTotal": total_wave_count(),
		# A0.6：强化面板域层状态（探针/测试读取；表现层另有自己的画布坐标快照）。
		"upgradeOffer": offer_debug_dict(),
		"gainedUpgrades": upgrade_summary(),
		"enemies": enemies_dbg,
		"characters": chars_dbg,
	}
