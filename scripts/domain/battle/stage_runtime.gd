## StageRuntime — 单场战斗的关卡运行时（V2.1.4 L4：场景实例化，不进全局单例）。
##
## 职责（P0.1 + P0.2 范围）：
##   P0.1：按 StageConfig.enemySpawnTimeline 生成敌人、固定逻辑步长推进移动、
##         核心 HP 与漏怪结算（同一敌人只结算一次）
##   P0.2：AP 系统（初始化/自然回复/上限/扣费）、角色部署（合法性/占格/唯一性/费用）、
##         阻挡系统（接触线/阻挡名额/释放）、双方攻击与伤害、死亡与失能
##
## 严格不含任何渲染、输入或 UI；不含技能/天赋/局内强化（属后续阶段）。
##
## 逻辑步长固定为 LOGIC_STEP_SECONDS，因此渲染帧率与分辨率不会改变战斗结果。
class_name StageRuntime
extends RefCounted

## 固定逻辑步长（秒）。所有战斗推进只在此步长上发生。
const LOGIC_STEP_SECONDS: float = 1.0 / 60.0

## 单帧最多追赶的逻辑步数，防止长时间卡顿后一次性跑完整关
const MAX_STEPS_PER_ADVANCE: int = 240

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

## 本关允许部署的角色 id（来自 StageConfig.availableCharacters）
var available_characters: Array[String] = []

## 阻挡接触线（tile，来自 balance.json combat.blocking）
var block_contact_line_tiles: float = 0.5

## 计划中的出怪条目（来自 StageConfig，禁止写死在代码）
var _spawn_plan: Array[Dictionary] = []
var _spawn_cursor: int = 0

## 累计逻辑时间（秒）
var elapsed_seconds: float = 0.0
var _accumulator: float = 0.0

var _next_enemy_instance_id: int = 1
var _next_character_instance_id: int = 1

## 敌人配置表 / 角色配置表（由 from_config 填入）
var _enemy_configs: Dictionary = {}
var _character_configs: Dictionary = {}

## 构建或运行期的错误（空 = 无错）
var _errors: Array[String] = []

## 统计
var core_damage_events: int = 0
var reached_core_count: int = 0
var enemies_killed: int = 0
var characters_lost: int = 0
var deploy_success_count: int = 0
var deploy_reject_count: int = 0


## 从 StageConfig 与配置表构建 StageRuntime。
## enemy_table:    { enemyId -> EnemyConfig }
## character_table:{ characterId -> CharacterConfig }
static func from_config(
	stage_config: Dictionary,
	enemy_table: Dictionary,
	grid: BattleGrid,
	character_table: Dictionary = {},
	balance_combat: Dictionary = {}
) -> StageRuntime:
	var rt := StageRuntime.new()
	rt.grid = grid
	rt._enemy_configs = enemy_table
	rt._character_configs = character_table

	if grid == null or not grid.is_valid():
		rt._errors.append("BattleGrid 无效，无法构建 StageRuntime")

	var sid := str(stage_config.get("stageId", ""))
	if sid.is_empty():
		rt._errors.append("StageConfig 缺少 stageId")
	rt.stage_id = sid

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
	# 设计说明：balance_combat 为空表示"本次运行未启用 AP 系统"（例如 P0.1 的
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

	# ---- 可部署角色列表 ----
	if stage_config.has("availableCharacters"):
		var ac: Variant = stage_config["availableCharacters"]
		if typeof(ac) == TYPE_ARRAY:
			for cid: Variant in ac:
				rt.available_characters.append(str(cid))
		else:
			rt._errors.append("availableCharacters 必须是数组")

	# ---- 出怪时间线 ----
	rt._spawn_plan = rt._validate_spawn_timeline(stage_config, enemy_table)
	return rt


## 校验并规范化出怪时间线，返回按时间升序的条目数组。
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

		out.append({"time": t, "lane": lane, "enemy": enemy_id, "index": i})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["time"]), float(b["time"])):
			return float(a["time"]) < float(b["time"])
		return int(a["index"]) < int(b["index"])
	)
	return out


func get_errors() -> Array[String]:
	return _errors


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
		if not c.is_incapacitated():
			n += 1
	return n


# ============================================================
#  AP 系统（V2.1.4 D-7）
# ============================================================

## AP 是否足以支付某费用
func can_afford(cost: int) -> bool:
	return ap >= cost


## 增加 AP（不超过上限）。返回实际增加量。
## 预留 AP 加成扩展点（后续角色/装备可调用，P0.2 不实现具体加成）。
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
#  角色部署（V2.1.4 D-6 / E 章 / 本轮要求）
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
}

## 部署请求结果
class DeployResult:
	extends RefCounted
	var ok: bool = false
	var reason: int = DeployReject.OK
	var character: CharacterRuntime = null
	var cost: int = 0

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
			_:
				return "未知原因(%d)" % reason


## 查询某格能否部署指定角色（**不产生副作用**，供 UI 悬停反馈使用）。
## 这是部署合法性的唯一判定入口，UI 不得复制规则。
func query_deploy(character_id: String, column: int, lane: int) -> DeployResult:
	var r := DeployResult.new()
	r.character = null

	if not BattleTypes.is_valid_column(column) or not BattleTypes.is_valid_lane(lane):
		r.reason = DeployReject.INVALID_CELL
		return r

	if not available_characters.has(character_id):
		r.reason = DeployReject.CHARACTER_NOT_AVAILABLE
		return r

	if not _character_configs.has(character_id):
		r.reason = DeployReject.CHARACTER_NOT_AVAILABLE
		return r

	if get_character_by_id(character_id) != null:
		r.reason = DeployReject.CHARACTER_ALREADY_DEPLOYED
		return r

	if get_character_at(column, lane) != null:
		r.reason = DeployReject.CELL_OCCUPIED
		return r

	var cfg: Dictionary = _character_configs[character_id]
	var cost := int(cfg.get("deployCost", 0))
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

	var inst := CharacterRuntime.from_config(cfg, column, lane, _next_character_instance_id)
	_next_character_instance_id += 1
	characters.append(inst)
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


## 取某格上的角色（空返回 null）
func get_character_at(column: int, lane: int) -> CharacterRuntime:
	for c: CharacterRuntime in characters:
		if c.column == column and c.lane == lane:
			return c
	return null


# ============================================================
#  主循环
# ============================================================

## 按固定逻辑步长推进战斗。
## 返回本次推进中抵达核心的敌人列表。
func advance(delta_seconds: float) -> Array[EnemyRuntime]:
	var reached: Array[EnemyRuntime] = []
	if delta_seconds <= 0.0 or not is_valid():
		return reached

	_accumulator += delta_seconds
	var steps := 0
	while _accumulator >= LOGIC_STEP_SECONDS and steps < MAX_STEPS_PER_ADVANCE:
		_accumulator -= LOGIC_STEP_SECONDS
		steps += 1
		elapsed_seconds += LOGIC_STEP_SECONDS
		_step(LOGIC_STEP_SECONDS, reached)
	return reached


## 单个逻辑步的完整推进顺序（确定性）：
##   1. AP 自然回复
##   2. 生成到期敌人
##   3. 释放无效阻挡关系（阻挡者失能/敌人已亡）
##   4. 清理死亡实体（HP≤0 → DEAD，释放阻挡名额）
##   5. 敌人移动（仅 MOVING）
##   6. 建立阻挡（接触线 + 剩余名额）
##   7. 判定抵达核心
##   8. 双方攻击结算
##
## 注意：清理放在"建立阻挡"之前，保证上一逻辑步内被击杀的敌人
## 立即释放阻挡名额，新敌人在同一逻辑步就能接上（V2.1.4 D-10）。
func _step(step: float, reached: Array[EnemyRuntime]) -> void:
	# 1. AP 自然回复（按步长精确累积，不按帧）
	if ap_regen_per_second > 0.0 and ap < ap_max:
		_ap_accumulator += ap_regen_per_second * step
		while _ap_accumulator >= 1.0 and ap < ap_max:
			_ap_accumulator -= 1.0
			ap += 1
		if ap >= ap_max:
			_ap_accumulator = 0.0

	# 2. 生成
	_spawn_due()

	# 3. 释放无效阻挡
	_release_invalid_blocks()

	# 4. 清理死亡实体（提前于建立阻挡，及时释放名额）
	_cleanup_dead()

	# 5. 移动
	_move_enemies(step)

	# 6. 建立阻挡
	_establish_blocks()

	# 7. 抵达核心（仅未被阻挡的敌人可能到达）
	for e: EnemyRuntime in enemies:
		if e.state == BattleTypes.EnemyState.MOVING and e.has_reached_core():
			e.state = BattleTypes.EnemyState.REACHED_CORE
			reached_core_count += 1
			reached.append(e)

	# 8. 攻击
	_resolve_character_attacks(step)
	_resolve_enemy_attacks(step)


## 生成所有到达时间的敌人。
func _spawn_due() -> void:
	while _spawn_cursor < _spawn_plan.size():
		var entry: Dictionary = _spawn_plan[_spawn_cursor]
		if float(entry["time"]) > elapsed_seconds:
			break
		var enemy_id: String = str(entry["enemy"])
		var lane: int = int(entry["lane"])
		var cfg: Dictionary = _enemy_configs[enemy_id]
		var inst := EnemyRuntime.from_config(cfg, lane, _next_enemy_instance_id)
		_next_enemy_instance_id += 1
		enemies.append(inst)
		_spawn_cursor += 1
		GameLog.debug("StageRuntime", "生成敌人 %s（lane=%d, t=%.2fs）"
			% [enemy_id, lane, elapsed_seconds])


## 敌人移动（仅 MOVING 状态）。BLOCKED / ATTACKING 不移动。
func _move_enemies(step: float) -> void:
	for e: EnemyRuntime in enemies:
		if e.state == BattleTypes.EnemyState.MOVING:
			e.advance(step)


## 释放无效阻挡关系：
##   - 阻挡者已失能/已不存在 → 其挂接的敌人恢复移动（BLOCKED → MOVING）
##   - 敌人已死亡/已消失 → 从阻挡者列表移除
##
## 注意：判定以**敌人侧**的 blocked_by_character_id 为准，而不是只依赖角色侧的
## blocking_enemy_ids。因为 CharacterRuntime.take_damage() 在失能时会立即清空
## 自己的阻挡列表，若此处只看该列表就会漏掉"敌人仍停在原地"的情况。
func _release_invalid_blocks() -> void:
	# 1) 敌人侧：阻挡者已失能或不存在 → 恢复移动
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
func _establish_blocks() -> void:
	for e: EnemyRuntime in enemies:
		if e.state != BattleTypes.EnemyState.MOVING:
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
		# 多个候选时取"更靠近核心"的那名（column 更小）
		if best == null or c.column < best.column:
			best = c
	return best


## 角色自动攻击（V2.1.4 D-11 目标优先级）
func _resolve_character_attacks(step: float) -> void:
	for c: CharacterRuntime in characters:
		if c.is_incapacitated():
			continue
		c.attack_cooldown = maxf(0.0, c.attack_cooldown - step)
		if c.attack_cooldown > 0.0:
			continue
		var target := _select_target_for(c)
		if target == null:
			continue
		var dmg := combat_math.compute_damage(c.attack, target.defense, c.damage_type)
		var applied := target.take_damage(dmg)
		c.total_damage_dealt += applied
		c.attack_cooldown = c.attack_interval
		GameLog.debug("StageRuntime", "%s 攻击 %s 造成 %d 伤害（剩余 HP %d）"
			% [c.display_name, target.enemy_id, applied, target.hp])


## 目标选择（V2.1.4 D-11）：
##   ① 最接近防守核心的敌人（logicalX 最小）
##   ② 当前正在阻挡的敌人
##   ③ 更早进入攻击范围的敌人（以 instance_id 升序近似"更早"，保证确定性）
## 攻击范围：同路线"前方" rangeTiles 以内（V2.1.4 D-13：同路线前方 1.25 格以内）。
## 例外：当前被该角色阻挡的敌人**始终可攻击**。
func _select_target_for(c: CharacterRuntime) -> EnemyRuntime:
	var candidates: Array[EnemyRuntime] = []
	for e: EnemyRuntime in enemies:
		if not e.is_active():
			continue
		if e.lane != c.lane:
			continue
		var blocked_by_me := c.is_blocking(e.instance_id)
		if not blocked_by_me:
			# 范围判定：敌人须在角色前方且不超出射程
			var delta := e.logical_x - float(c.column)
			if delta < -0.0001 or delta > c.attack_range_tiles:
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
	return candidates[0]


## 敌人攻击（被阻挡时攻击阻挡者）
## 状态说明：敌人一旦被阻挡即保持 BLOCKED（V2.1.4 F-四十五 状态机中 ATTACKING 表示
## "正在出手"的瞬间态）。为保持 P0.2 逻辑简单且确定，攻击结算不切换主状态，
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
			# 阻挡者已失能：本帧不结算，状态在 _release_invalid_blocks 中被释放
			continue
		var dmg := combat_math.compute_damage(e.attack, blocker.defense, e.damage_type)
		var applied := blocker.take_damage(dmg)
		e.total_damage_dealt += applied
		e.attack_cooldown = e.attack_interval
		GameLog.debug("StageRuntime", "%s 攻击 %s 造成 %d 伤害（剩余 HP %d）"
			% [e.enemy_id, blocker.display_name, applied, blocker.hp])
		if blocker.is_incapacitated():
			characters_lost += 1
			GameLog.info("StageRuntime", "%s 失去战斗能力" % blocker.display_name)


## 清理死亡实体
func _cleanup_dead() -> void:
	# 敌人死亡：HP 耗尽者统一置为 DEAD 并计数（击杀统计的唯一入口）
	var still_alive: Array[EnemyRuntime] = []
	for e: EnemyRuntime in enemies:
		if e.hp <= 0:
			if e.state != BattleTypes.EnemyState.DEAD:
				e.state = BattleTypes.EnemyState.DEAD
				enemies_killed += 1
				GameLog.debug("StageRuntime", "敌人 %s 被击败" % e.enemy_id)
			continue
		if e.is_active():
			still_alive.append(e)
	enemies = still_alive

	# 角色侧同步清理：移除指向已消失敌人的阻挡引用
	for c: CharacterRuntime in characters:
		if c.blocking_enemy_ids.is_empty():
			continue
		var kept_ids: Array[int] = []
		for eid: int in c.blocking_enemy_ids:
			if get_enemy(eid) != null:
				kept_ids.append(eid)
		c.blocking_enemy_ids = kept_ids

	# 角色失能：清空其残留的阻挡关系
	for c: CharacterRuntime in characters:
		if c.is_incapacitated() and not c.blocking_enemy_ids.is_empty():
			c.blocking_enemy_ids.clear()


# ============================================================
#  查询
# ============================================================

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


# ============================================================
#  测试夹具（P0.1 引入；明确标注仅供测试，不得出现在正式游戏流程）
# ============================================================

## 供测试使用：按 instance_id 移除一个敌人（模拟"被清除"）。
## P0.1 无攻击系统时用于验证胜负；P0.2 起已有真实击杀路径，
## 本夹具仅保留以维持 P0.1 测试（禁止在正式游戏流程中调用）。
func despawn_for_test(instance_id: int) -> bool:
	for i: int in range(enemies.size()):
		if enemies[i].instance_id == instance_id:
			enemies[i].state = BattleTypes.EnemyState.DEAD
			enemies.remove_at(i)
			return true
	return false


## 供测试使用：清除场上全部敌人。
func despawn_all_for_test() -> int:
	var n := enemies.size()
	for e: EnemyRuntime in enemies:
		e.state = BattleTypes.EnemyState.DEAD
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
		"deployed": characters.size(),
		"enemies": enemies_dbg,
		"characters": chars_dbg,
	}
