## BattleSession — 单场战斗的权威运行时状态（V2.1.4 L3/L4）。
##
## L4 明确要求：BattleSession 按场景实例化，**不得注册为全局 Autoload**。
##
## 职责：
##   P0.1：承载 Victory / Defeat 确定性状态机（V2.1.4 D-40 / D-41），固定逻辑步长驱动
##   P0.2：转发角色部署 / AP 查询等玩家操作到 StageRuntime；胜负一旦确定即冻结
##   P0.3：转发主动撤退 / 暂停；按「全部 Wave 完成且场上无存活敌人」判定胜利
##   P0.4：转发治疗事件；三职业（前线/远程/治疗）共用同一套部署与推进路径
##
## 所有战斗结果均由领域层（StageRuntime / CombatMath）计算，本类不复制规则。
class_name BattleSession
extends Node

## 胜负已确定后发出（outcome: BattleTypes.Outcome）
signal outcome_decided(outcome: int)
## 核心 HP 变化（current, max）
signal core_hp_changed(current: int, max_hp: int)
## 敌人抵达核心（enemy）
signal enemy_reached_core(enemy: EnemyRuntime)
## 部署成功（character）
signal character_deployed(character: CharacterRuntime)
## 部署被拒（character_id, reason）
signal deploy_rejected(character_id: String, reason: int)
## 角色离场（character, kind: StageRuntime.Removal）
signal character_left(character: CharacterRuntime, kind: int)
## 敌人被击败（enemy）
signal enemy_killed(enemy: EnemyRuntime)
## 玩家主动撤退成功（character, refund_granted）
signal character_withdrawn(character: CharacterRuntime, refund: int)
## 当前 Wave 变化（wave_number, total）
signal wave_changed(wave_number: int, total: int)
## 再部署冷却状态变化（character_id, remaining）——离场、到期与每个逻辑步的递减都发
signal redeploy_changed(character_id: String, remaining: float)
## 暂停状态变化（paused）
signal pause_changed(paused: bool)
## 治疗生效（healer, target, amount）——P0.4 三职业框架
signal character_healed(healer: CharacterRuntime, target: CharacterRuntime, amount: int)

var outcome: int = BattleTypes.Outcome.RUNNING
var stage: StageRuntime
var grid: BattleGrid

var _outcome_committed: bool = false
var _frozen: bool = false
var _last_wave_number: int = 0


## 从 StageConfig 与配置表构建会话。
## 返回错误列表（空 = 成功）。
func setup(
	stage_config: Dictionary,
	enemy_table: Dictionary,
	in_grid: BattleGrid,
	character_table: Dictionary = {},
	balance_combat: Dictionary = {}
) -> Array[String]:
	var errs: Array[String] = []
	grid = in_grid
	stage = StageRuntime.from_config(
		stage_config, enemy_table, in_grid, character_table, balance_combat
	)
	errs.append_array(stage.get_errors())
	_last_wave_number = stage.current_wave_number()
	return errs


func is_running() -> bool:
	return outcome == BattleTypes.Outcome.RUNNING


func is_decided() -> bool:
	return outcome != BattleTypes.Outcome.RUNNING


func is_frozen() -> bool:
	return _frozen


# ============================================================
#  玩家操作（转发到领域层；BattleSession 不复制规则）
# ============================================================

## 查询某格能否部署（无副作用，供 UI 悬停反馈）
func query_deploy(character_id: String, column: int, lane: int) -> StageRuntime.DeployResult:
	if _frozen or stage == null:
		var r := StageRuntime.DeployResult.new()
		r.reason = StageRuntime.DeployReject.BATTLE_FINISHED
		return r
	return stage.query_deploy(character_id, column, lane)


## 查询某角色若部署在 (column, lane) 时的攻击覆盖范围（无副作用，供 UI 部署预览）。
##
## 返回结构与 StageRuntime.query_attack_coverage() 一致；UI 不得自行推导射程，
## 必须经本入口读取，以保证「显示的范围」与「真实可打的范围」永远一致。
func query_attack_coverage(
	character_id: String, column: int, lane: int
) -> Array[Dictionary]:
	if stage == null:
		return []
	return stage.query_attack_coverage(character_id, column, lane)


## 执行部署。成功才扣 AP。
func deploy_character(character_id: String, column: int, lane: int) -> StageRuntime.DeployResult:
	if _frozen or stage == null:
		var r := StageRuntime.DeployResult.new()
		r.reason = StageRuntime.DeployReject.BATTLE_FINISHED
		return r
	var res := stage.deploy_character(character_id, column, lane)
	if res.ok and res.character != null:
		character_deployed.emit(res.character)
	else:
		deploy_rejected.emit(character_id, res.reason)
	return res


## 主动撤退（V2.1.4 D-9 / 表 24）。
## 幂等：领域层以「角色是否仍在场」为准，重复调用不会二次返还 AP。
func withdraw_character(instance_id: int) -> StageRuntime.RetreatResult:
	if _frozen or stage == null:
		var r := StageRuntime.RetreatResult.new()
		r.reason = StageRuntime.RetreatReject.BATTLE_FINISHED
		return r
	var before := stage.get_character(instance_id)
	var res := stage.withdraw_character(instance_id)
	if res.ok:
		if before != null:
			character_left.emit(before, StageRuntime.Removal.RETREATED)
			character_withdrawn.emit(before, res.refund_granted)
	return res


## 主动撤退便捷入口：按角色 id 撤退其当前在场的实例。
func withdraw_character_by_id(character_id: String) -> StageRuntime.RetreatResult:
	if _frozen or stage == null:
		var r := StageRuntime.RetreatResult.new()
		r.reason = StageRuntime.RetreatReject.BATTLE_FINISHED
		return r
	var inst := stage.get_character_by_id(character_id)
	if inst == null:
		var r := StageRuntime.RetreatResult.new()
		r.reason = StageRuntime.RetreatReject.CHARACTER_NOT_DEPLOYED
		return r
	return withdraw_character(inst.instance_id)


## 某角色当前的再部署剩余秒数（0 = 可部署）
func get_redeploy_remaining(character_id: String) -> float:
	if stage == null:
		return 0.0
	return stage.get_redeploy_remaining(character_id)


## 暂停 / 继续（V2.1.4 D-35：游戏逻辑、动画、CD 与敌人移动全部停止）
func set_paused(value: bool) -> void:
	if stage == null or _frozen:
		return
	if stage.is_paused() == value:
		return
	stage.set_paused(value)
	pause_changed.emit(value)


func is_paused() -> bool:
	return stage != null and stage.is_paused()


func toggle_pause() -> bool:
	if stage == null or _frozen:
		return false
	set_paused(not stage.is_paused())
	return stage.is_paused()


# ============================================================
#  主循环
# ============================================================

## 按渲染帧时间推进。内部转交固定逻辑步长驱动（帧率无关）。
## 暂停与胜负已定时，StageRuntime.advance 不推进任何计时器。
func tick(delta_seconds: float) -> void:
	if _frozen or stage == null:
		return

	var enemies_before := stage.enemies.duplicate()
	# 角色快照同样要在推进前取：失能角色会在同一逻辑步内被领域层移出 characters，
	# 若推进后再遍历 characters 就永远看不到它，character_lost 类事件会静默丢失。
	var chars_before := stage.characters.duplicate()
	var chars_alive_before := {}
	for c: CharacterRuntime in chars_before:
		chars_alive_before[c.instance_id] = not c.is_incapacitated()
	# 再部署冷却在推进前的快照（用于找出本步内发生变化 / 归零的角色）
	var cd_before := {}
	for c: CharacterRuntime in stage.character_instances:
		if c.redeploy_cooldown_remaining > 0.0:
			cd_before[c.character_id] = c.redeploy_cooldown_remaining

	var heals_before := stage.heal_events.size()
	var reached: Array[EnemyRuntime] = stage.advance(delta_seconds)

	# 治疗事件派发（P0.4）：只派发本次推进内**新产生**的实际治疗
	if stage.heal_events.size() > heals_before:
		for i: int in range(heals_before, stage.heal_events.size()):
			var ev: Dictionary = stage.heal_events[i]
			var healer := stage.get_character(int(ev["healerId"]))
			var tgt := stage.get_character(int(ev["targetId"]))
			if healer != null and tgt != null:
				character_healed.emit(healer, tgt, int(ev["amount"]))

	# 漏怪结算：领域层已在同一逻辑步内结算核心伤害（core_hp 已是真值），
	# 此处再调一次 apply_core_damage 仅作幂等兜底，并负责派发信号。
	# 信号按 reached 列表派发——列表中每个敌人都是**本步首次**抵达核心，天然恰好一次。
	for e: EnemyRuntime in reached:
		stage.apply_core_damage(e)
		enemy_reached_core.emit(e)
	if not reached.is_empty():
		core_hp_changed.emit(stage.core_hp, stage.core_hp_max)
		stage.remove_reached_core()

	# 事件派发：击杀（状态由领域层清理阶段统一置 DEAD）
	for e: EnemyRuntime in enemies_before:
		if e.hp <= 0 and e.state == BattleTypes.EnemyState.DEAD:
			enemy_killed.emit(e)
	# 事件派发：本逻辑步内新失能的角色（用推进前的快照比对）
	for c: CharacterRuntime in chars_before:
		if chars_alive_before.get(c.instance_id, true) and c.is_incapacitated():
			character_left.emit(c, StageRuntime.Removal.INCAPACITATED)

	# 再部署冷却变化（UI 据此刷新倒计时；启动、递减与归零都应通知）
	for c: CharacterRuntime in stage.character_instances:
		var before := float(cd_before.get(c.character_id, 0.0))
		var now := c.redeploy_cooldown_remaining
		if absf(now - before) > 0.0001:
			redeploy_changed.emit(c.character_id, now)

	# Wave 变化
	var wn := stage.current_wave_number()
	if wn != _last_wave_number:
		_last_wave_number = wn
		wave_changed.emit(wn, stage.total_wave_count())

	_evaluate_outcome()


## 判定胜负（V2.1.4 D-40 胜利 / D-41 失败）。
func _evaluate_outcome() -> void:
	if _outcome_committed:
		return

	# 失败优先：核心生命 ≤ 0（D-41，立即失败，不得继续出怪）
	if stage.core_hp <= 0:
		_commit_outcome(BattleTypes.Outcome.DEFEAT)
		return

	# 胜利：全部计划 Wave 完成（计划敌人全部生成且全部离场）+ 场上无存活敌人 + 核心仍有 HP
	# （P0.2 起「无存活敌人」可由真实击杀达成，无需夹具）
	if stage.all_waves_cleared() and not stage.has_living_enemies():
		_commit_outcome(BattleTypes.Outcome.VICTORY)


func _commit_outcome(new_outcome: int) -> void:
	if _outcome_committed:
		return
	_outcome_committed = true
	_frozen = true
	outcome = new_outcome
	# 领域层同步停表：胜负确定后敌人移动、AP 回复、攻击、
	# 再部署冷却与 Wave 计时全部不再推进（本轮要求）。
	stage.running = false
	stage.paused = false
	GameLog.info("BattleSession", "胜负确定：%s（核心 %d/%d，Wave %d/%d，生成 %d/%d，击杀 %d，漏怪 %d，失能 %d，撤退 %d）"
		% [
			BattleTypes.outcome_name(outcome),
			stage.core_hp, stage.core_hp_max,
			stage.current_wave_number(), stage.total_wave_count(),
			stage.spawned_enemy_count(), stage.planned_enemy_count(),
			stage.enemies_killed, stage.reached_core_count,
			stage.characters_lost, stage.retreat_count,
		])
	outcome_decided.emit(outcome)


## 战斗结算摘要（结果界面显示；全部数字来自领域层，表现层不自行统计）
func result_summary() -> Dictionary:
	if stage == null:
		return {}
	return {
		"outcome": outcome,
		"outcomeName": BattleTypes.outcome_name(outcome),
		"victory": outcome == BattleTypes.Outcome.VICTORY,
		"coreHp": stage.core_hp,
		"coreHpMax": stage.core_hp_max,
		"kills": stage.enemies_killed,
		"leaked": stage.reached_core_count,
		"lost": stage.characters_lost,
		"retreats": stage.retreat_count,
		"retreatAp": stage.retreat_refunded_ap_total,
		"heals": stage.heal_events.size(),
		"healedTotal": stage.total_healing_done,
		"wave": stage.current_wave_number(),
		"waveTotal": stage.total_wave_count(),
		"planned": stage.planned_enemy_count(),
		"spawned": stage.spawned_enemy_count(),
		"elapsed": snappedf(stage.elapsed_seconds, 0.01),
		# V2.1.4 G-八 失败与复盘设计：突破核心的敌人类型 / 最多承压路线 /
		# 角色死亡次数 / AP 最大溢出与短缺。全部由领域层统计，表现层只显示。
		"leakedByType": stage.leaked_by_enemy_type(),
		"killsByType": stage.kills_by_enemy_type(),
		"pressureByLane": stage.pressure_by_lane(),
		"busiestLane": stage.busiest_lane(),
		"apMax": stage.ap_max,
		"apFinal": stage.ap,
	}


func to_debug_dict() -> Dictionary:
	var base := stage.to_debug_dict() if stage != null else {}
	base["outcome"] = BattleTypes.outcome_name(outcome)
	base["frozen"] = _frozen
	return base
