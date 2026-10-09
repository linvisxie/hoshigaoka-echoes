## AnimState — 战斗单位动画状态机（纯表现层）。
##
## 职责（本轮指令 第三条）：
##   把领域层的**已结算事实**翻译成"当前该播哪条动画"，供绘制端使用。
##
## 硬性纪律：
##   1. **只读**领域层计数器（total_damage_dealt / total_healing_done / hp / alive），
##      绝不写回任何战斗状态 —— 因此动画切换**不可能**改变攻击次数、伤害、Wave 或胜负。
##   2. **死亡是终态**：一旦进入 death，永不被受击/攻击覆盖
##      （本轮指令 3.6「不允许受击反复覆盖死亡动画」）。
##   3. **零资源开销**：只存整数/浮点，不持贴图；帧由 ArtRegistry 缓存取用
##      （本轮指令 3.8「不允许动画帧更新产生资源泄漏或大量重复解码」）。
##   4. 无事件时自动回落 idle/move（本轮指令 3.5）。
##
## 优先级（高 → 低）：death > hit > attack > (move) > idle
class_name AnimState
extends RefCounted

## 动画名（与 ArtRegistry.FRAME_COUNT 的键一致）
const IDLE := "idle"
const MOVE := "move"
const ATTACK := "attack"
const HIT := "hit"
const DEATH := "death"

## 各动画的持续时长（秒）。攻击/受击是**一次性**表现，播完自动回落。
const ATTACK_SECONDS := 0.36
const HIT_SECONDS := 0.18

## 当前动画名
var anim: String = IDLE
## 当前动画开始时刻（用于按时间取帧）
var started_at: float = 0.0
## 是否已进入死亡（终态，不可逆）
var dead: bool = false

# ---- 上一次观测到的领域层计数器（用于检测"刚发生"的事件）----
var _last_damage_dealt: int = -1
var _last_healing_done: int = -1
var _last_hp: int = -1
var _initialized: bool = false


## 重置（重新部署 / 对象复用）
func reset(now: float) -> void:
	anim = IDLE
	started_at = now
	dead = false
	_last_damage_dealt = -1
	_last_healing_done = -1
	_last_hp = -1
	_initialized = false


## 依据角色运行时状态推进动画。
##
## c: CharacterRuntime（只读）
## now: 当前时刻（秒，用 session.stage.elapsed_seconds）
## hit: 本帧是否有该角色的受击事件（由表现层从 damage_events 解析后传入）
func tick_character(c: CharacterRuntime, now: float, hit: bool) -> void:
	if c == null:
		return
	# 1) 死亡是终态：进入后不再改变
	if c.is_incapacitated():
		if not dead:
			dead = true
			_switch_to(DEATH, now)
		return
	if dead:
		return  # 已死但领域层尚未标记（极少见）——保持 death，不回退
	# 2) 首次观测：只记录基线，不触发事件（避免开局误播攻击）
	if not _initialized:
		_last_damage_dealt = c.total_damage_dealt
		_last_healing_done = c.total_healing_done
		_last_hp = c.hp
		_initialized = true
		return
	# 3) 受击优先于攻击（被打了当然先演受击）
	if hit:
		_switch_to(HIT, now)
		_sync(c)
		return
	# 4) 攻击或治疗：任一计数器增长即视为"刚出手"
	var dealt: bool = c.total_damage_dealt > _last_damage_dealt
	var healed: bool = c.total_healing_done > _last_healing_done
	if dealt or healed:
		_switch_to(ATTACK, now)
		_sync(c)
		return
	_sync(c)
	# 5) 一次性动画播完回落；无事件时保持 idle
	var dur := _duration_of(anim)
	if dur > 0.0 and now - started_at >= dur:
		_switch_to(IDLE, now)


## 依据敌人运行时状态推进动画。
##
## e: EnemyRuntime（只读）
## hit: 本帧是否有该敌人的受击事件
func tick_enemy(e: EnemyRuntime, now: float, hit: bool) -> void:
	if e == null:
		return
	# 敌人"不活跃"= 已消散 → death 终态
	if not e.is_active():
		if not dead:
			dead = true
			_switch_to(DEATH, now)
		return
	if dead:
		return
	if not _initialized:
		_last_damage_dealt = e.total_damage_dealt
		_last_hp = e.hp
		_initialized = true
		return
	if hit:
		_switch_to(HIT, now)
		_sync_enemy(e)
		return
	if e.total_damage_dealt > _last_damage_dealt:
		_switch_to(ATTACK, now)
		_sync_enemy(e)
		return
	_sync_enemy(e)
	# 敌人的默认状态是**移动**（它们始终在向右→左推进），不是待机。
	# 一次性动画（攻击/受击）播完回落 move；其余情况保持 move。
	var dur := _duration_of(anim)
	if dur > 0.0 and now - started_at >= dur:
		_switch_to(MOVE, now)
	elif anim == IDLE:
		# 首次观测后立即进入 move（敌人不会"站着不动"）
		_switch_to(MOVE, now)


## 当前动画已播放的进度 0..1（一次性动画用；循环动画用绝对时间）。
func progress(now: float) -> float:
	var dur := _duration_of(anim)
	if dur <= 0.0:
		return 0.0
	return clampf((now - started_at) / dur, 0.0, 1.0)


## 该动画是否是一次性播放（播完回落）
func is_one_shot() -> bool:
	return anim == ATTACK or anim == HIT


func _switch_to(name: String, now: float) -> void:
	anim = name
	started_at = now


func _duration_of(name: String) -> float:
	match name:
		ATTACK:
			return ATTACK_SECONDS
		HIT:
			return HIT_SECONDS
		_:
			return 0.0


func _sync(c: CharacterRuntime) -> void:
	_last_damage_dealt = c.total_damage_dealt
	_last_healing_done = c.total_healing_done
	_last_hp = c.hp


func _sync_enemy(e: EnemyRuntime) -> void:
	_last_damage_dealt = e.total_damage_dealt
	_last_hp = e.hp


## 供测试与诊断：导出当前状态
func to_dict() -> Dictionary:
	return {"anim": anim, "startedAt": started_at, "dead": dead,
		"initialized": _initialized}