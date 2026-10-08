## BattleSession — 单场战斗的权威运行时状态（V2.1.4 L3/L4）。
##
## L4 明确要求：BattleSession 按场景实例化，**不得注册为全局 Autoload**。
## 该类为 Node，由战斗场景实例化并持有 StageRuntime。
##
## P0.1 职责：
##   - 承载 Victory / Defeat 确定性状态机（V2.1.4 D-40 / D-41）
##   - 以固定逻辑步长驱动 StageRuntime
##   - 胜负一旦确定即冻结：不再生成新敌人、不再重复结算
##
## 不含攻击/阻挡/技能/AP 消耗（属 P0.2+）。
class_name BattleSession
extends Node

## 胜负已确定后发出（outcome: BattleTypes.Outcome）
signal outcome_decided(outcome: int)
## 核心 HP 变化（current, max）
signal core_hp_changed(current: int, max_hp: int)
## 敌人抵达核心（enemy）
signal enemy_reached_core(enemy: EnemyRuntime)

var outcome: int = BattleTypes.Outcome.RUNNING
var stage: StageRuntime
var grid: BattleGrid

## 胜负结算次数保护（确保只触发一次）
var _outcome_committed: bool = false
## 状态机是否已冻结（确定胜负后不再推进逻辑）
var _frozen: bool = false


## 从 StageConfig 与敌人表构建会话。
## 返回错误列表（空 = 成功）。
func setup(stage_config: Dictionary, enemy_table: Dictionary, in_grid: BattleGrid) -> Array[String]:
	var errs: Array[String] = []
	grid = in_grid
	stage = StageRuntime.from_config(stage_config, enemy_table, in_grid)
	errs.append_array(stage.get_errors())
	return errs


func is_running() -> bool:
	return outcome == BattleTypes.Outcome.RUNNING


func is_decided() -> bool:
	return outcome != BattleTypes.Outcome.RUNNING


## 按渲染帧时间推进。内部转交固定逻辑步长驱动（帧率无关）。
func tick(delta_seconds: float) -> void:
	if _frozen or stage == null:
		return

	var reached: Array[EnemyRuntime] = stage.advance(delta_seconds)

	# 逐一结算漏怪伤害（apply_core_damage 自带幂等保护）
	for e: EnemyRuntime in reached:
		var applied := stage.apply_core_damage(e)
		if applied > 0:
			enemy_reached_core.emit(e)
			core_hp_changed.emit(stage.core_hp, stage.core_hp_max)

	# 抵达核心者结算完即从场上移除
	if not reached.is_empty():
		stage.remove_reached_core()

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
	if stage.all_planned_spawned() and not stage.has_living_enemies():
		_commit_outcome(BattleTypes.Outcome.VICTORY)


## 提交胜负结果（只执行一次，之后冻结逻辑）。
func _commit_outcome(new_outcome: int) -> void:
	if _outcome_committed:
		return
	_outcome_committed = true
	_frozen = true
	outcome = new_outcome
	GameLog.info("BattleSession", "胜负确定：%s（核心 HP %d/%d，生成 %d/%d，抵达核心 %d）"
		% [
			BattleTypes.outcome_name(outcome),
			stage.core_hp, stage.core_hp_max,
			stage.spawned_enemy_count(), stage.planned_enemy_count(),
			stage.reached_core_count,
		])
	outcome_decided.emit(outcome)


## 是否已冻结（确定胜负后为 true）
func is_frozen() -> bool:
	return _frozen


func to_debug_dict() -> Dictionary:
	var base := stage.to_debug_dict() if stage != null else {}
	base["outcome"] = BattleTypes.outcome_name(outcome)
	base["frozen"] = _frozen
	return base
