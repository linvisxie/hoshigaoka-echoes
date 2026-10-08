## BattleSession — 单场战斗的权威运行时状态（V2.1.4 L3/L4）。
##
## L4 明确要求：BattleSession 按场景实例化，**不得注册为全局 Autoload**。
##
## 职责：
##   P0.1：承载 Victory / Defeat 确定性状态机（V2.1.4 D-40 / D-41），固定逻辑步长驱动
##   P0.2：转发角色部署 / AP 查询等玩家操作到 StageRuntime；胜负一旦确定即冻结
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
## 角色失能（character）
signal character_lost(character: CharacterRuntime)
## 敌人被击败（enemy）
signal enemy_killed(enemy: EnemyRuntime)

var outcome: int = BattleTypes.Outcome.RUNNING
var stage: StageRuntime
var grid: BattleGrid

var _outcome_committed: bool = false
var _frozen: bool = false


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


# ============================================================
#  主循环
# ============================================================

## 按渲染帧时间推进。内部转交固定逻辑步长驱动（帧率无关）。
func tick(delta_seconds: float) -> void:
	if _frozen or stage == null:
		return

	var enemies_before := stage.enemies.duplicate()
	var chars_alive_before := {}
	for c: CharacterRuntime in stage.characters:
		chars_alive_before[c.instance_id] = not c.is_incapacitated()

	var reached: Array[EnemyRuntime] = stage.advance(delta_seconds)

	# 漏怪结算（apply_core_damage 自带幂等保护）
	for e: EnemyRuntime in reached:
		var applied := stage.apply_core_damage(e)
		if applied > 0:
			enemy_reached_core.emit(e)
			core_hp_changed.emit(stage.core_hp, stage.core_hp_max)
	if not reached.is_empty():
		stage.remove_reached_core()

	# 事件派发：击杀与失能
	for e: EnemyRuntime in enemies_before:
		if e.hp <= 0 and e.state == BattleTypes.EnemyState.DEAD:
			enemy_killed.emit(e)
	for c: CharacterRuntime in stage.characters:
		if chars_alive_before.get(c.instance_id, true) and c.is_incapacitated():
			character_lost.emit(c)

	_evaluate_outcome()


## 判定胜负（V2.1.4 D-40 胜利 / D-41 失败）。
func _evaluate_outcome() -> void:
	if _outcome_committed:
		return

	# 失败优先：核心生命 <= 0
	if stage.core_hp <= 0:
		_commit_outcome(BattleTypes.Outcome.DEFEAT)
		return

	# 胜利：全部计划出怪已生成 + 场上无存活敌人 + 核心仍有 HP
	# （P0.2 起"无存活敌人"可由真实击杀达成，无需夹具）
	if stage.all_planned_spawned() and not stage.has_living_enemies():
		_commit_outcome(BattleTypes.Outcome.VICTORY)


func _commit_outcome(new_outcome: int) -> void:
	if _outcome_committed:
		return
	_outcome_committed = true
	_frozen = true
	outcome = new_outcome
	GameLog.info("BattleSession", "胜负确定：%s（核心 %d/%d，生成 %d/%d，击杀 %d，漏怪 %d，失能 %d）"
		% [
			BattleTypes.outcome_name(outcome),
			stage.core_hp, stage.core_hp_max,
			stage.spawned_enemy_count(), stage.planned_enemy_count(),
			stage.enemies_killed, stage.reached_core_count, stage.characters_lost,
		])
	outcome_decided.emit(outcome)


func to_debug_dict() -> Dictionary:
	var base := stage.to_debug_dict() if stage != null else {}
	base["outcome"] = BattleTypes.outcome_name(outcome)
	base["frozen"] = _frozen
	return base
