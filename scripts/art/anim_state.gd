## Pure presentation state, advanced from update (never from draw).
## Priority death > hit > attack; one pending attack is coalesced, never unbounded.
class_name AnimState
extends RefCounted

const IDLE := "idle"
const MOVE := "move"
const ATTACK := "attack"
const HIT := "hit"
const DEATH := "death"
const ATTACK_SECONDS := 0.36
const HIT_SECONDS := 0.18
const DEATH_SECONDS := 0.5

var anim: String = IDLE
var started_at: float = 0.0
var dead: bool = false
var _last_damage_dealt: int = -1
var _last_healing_done: int = -1
var _initialized: bool = false
var _pending_attack: bool = false

func reset(now: float) -> void:
	anim = IDLE
	started_at = now
	dead = false
	_last_damage_dealt = -1
	_last_healing_done = -1
	_initialized = false
	_pending_attack = false

func tick_character(c: CharacterRuntime, now: float, hit: bool, attack_event: bool = false) -> void:
	if c == null:
		return
	var attacked := attack_event
	if _initialized:
		attacked = attacked or c.total_damage_dealt > _last_damage_dealt \
			or c.total_healing_done > _last_healing_done
	_last_damage_dealt = c.total_damage_dealt
	_last_healing_done = c.total_healing_done
	_initialized = true
	_advance(now, c.is_incapacitated(), hit, attacked, IDLE)

func tick_enemy(e: EnemyRuntime, now: float, hit: bool, attack_event: bool = false) -> void:
	if e == null:
		return
	var attacked := attack_event
	if _initialized:
		attacked = attacked or e.total_damage_dealt > _last_damage_dealt
	var first := not _initialized
	_last_damage_dealt = e.total_damage_dealt
	_initialized = true
	var rest := MOVE if e.state == BattleTypes.EnemyState.MOVING \
		or e.state == BattleTypes.EnemyState.SPAWNING else IDLE
	# Keep the previous public first-observation contract; explicit events aren't discarded.
	if first and e.is_active() and not hit and not attacked:
		return
	_advance(now, not e.is_active(), hit, attacked, rest)

func _advance(now: float, terminal: bool, hit: bool, attacked: bool, rest: String) -> void:
	if terminal:
		begin_death(now)
	if dead:
		return
	_pending_attack = _pending_attack or attacked
	if hit:
		_switch_to(HIT, now)
		return
	if anim == HIT and now - started_at < HIT_SECONDS:
		return
	if _pending_attack:
		_pending_attack = false
		_switch_to(ATTACK, now)
		return
	if is_one_shot() and now - started_at < _duration_of(anim):
		return
	if anim != rest:
		_switch_to(rest, now)

func begin_death(now: float) -> void:
	if dead:
		return
	dead = true
	_pending_attack = false
	_switch_to(DEATH, now)

func progress(now: float) -> float:
	var duration := _duration_of(anim)
	if duration <= 0.0:
		return 0.0
	return clampf((now - started_at) / duration, 0.0, 1.0)

func is_one_shot() -> bool:
	return anim == ATTACK or anim == HIT or anim == DEATH

func finished(now: float) -> bool:
	return dead and progress(now) >= 1.0

func _switch_to(name: String, now: float) -> void:
	anim = name
	started_at = now

func _duration_of(name: String) -> float:
	match name:
		ATTACK: return ATTACK_SECONDS
		HIT: return HIT_SECONDS
		DEATH: return DEATH_SECONDS
		_: return 0.0

func to_dict() -> Dictionary:
	return {"anim": anim, "startedAt": started_at, "dead": dead,
		"initialized": _initialized, "pendingAttack": _pending_attack}
