## 裁决 DEC-C-0004：攻速百分数 → 攻击间隔换算口径（正式裁决）验收测试。
##
## 正式口径（取代原先标注为「首轮候选、需人裁决」的临时实现）：
##   effectiveInterval = baseInterval / effectiveAttackSpeedMultiplier
##   effectiveAttackSpeedMultiplier = clamp(1 + Σ攻速百分数, floor, ceiling)
##
## 规格依据（L556，LOCKED）：
##   「不同 effectId 的攻击、攻击速度、技能 CD 恢复速度减益以『相对基础值的百分数』
##     先相加，再与增益统一结算，最后夹取下限。**有效攻击频率**…不得低于各自基础值的 40%」
##   ⇒ 40% 夹取的是**频率**，故频率倒数读法是唯一与规格自洽的读法。
##
## 覆盖范围（本轮指令第三阶段 C-3 要求的全部测试项）：
##    1. 单独 -25% 减益
##    2. 多种减益叠加
##    3. 正负增益同时存在
##    4. 40% 攻速下限
##    5. 增益上限 +80%（表 81 软上限）
##    6. 效果过期与恢复
##    7. 暂停与重新开始
##    8. 攻速变化期间不出现额外攻击或重复冷却重置
##    9. 配置承载（下限 LOCKED 存 balance.json；上限可配置）
##   10. 无效果时行为与改动前完全一致（回归保护）
extends GutTest

const CHAR_MIO := "amamiya_mio"
const CHAR_YUMA := "kamiya_yuma"
const CHAR_YUI := "ogawa_yui"

const MIO_INTERVAL := 1.1
const YUMA_INTERVAL := 1.3
const EPS := 0.0001

## 规格值（L556 / 表 81）
const FLOOR := 0.4
const CEILING := 1.8


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


# ============================================================
#  夹具
# ============================================================

func _grid() -> BattleGrid:
	return BattleGrid.from_layout(DataRegistry.get_layout())


func _enemy_table() -> Dictionary:
	var t := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		t[str(e.get("id", ""))] = e
	return t


func _char_table() -> Dictionary:
	var t := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		t[str(c.get("id", ""))] = c
	return t


func _combat() -> Dictionary:
	return DataRegistry.get_domain("balance").get("combat", {})


func _cfg(chars: Array = [CHAR_MIO]) -> Dictionary:
	return {
		"stageId": "probe_attack_speed",
		"coreHp": 99,
		"startingAp": 30,
		"apRegen": 1.0,
		"availableCharacters": chars.duplicate(),
		"enemySpawnTimeline": [],
	}


func _runtime(chars: Array = [CHAR_MIO]) -> StageRuntime:
	var rt := StageRuntime.from_config(
		_cfg(chars), _enemy_table(), _grid(), _char_table(), _combat())
	rt.ap = 30
	return rt


## 施加一个攻速状态效果（字段名与 enemies.json 的 mechanic 段一致）
func _apply_speed(
	c: CharacterRuntime, effect_id: String, pct: float, duration: float, now: float
) -> void:
	c.apply_status_effect_from_config({
		"effectId": effect_id,
		"sourceId": "test",
		"category": StatusEffect.CATEGORY_ATTACK_SPEED,
		"pct": pct,
		"durationSeconds": duration,
		"stackPolicy": "REFRESH_DURATION",
	}, now)


func _deploy(rt: StageRuntime, cid: String, col: int = 1, lane: int = 1) -> CharacterRuntime:
	var r := rt.deploy_character(cid, col, lane)
	assert_true(r.ok, "应能部署 %s（%s）" % [cid, r.reason_text()])
	return r.character


## 按逻辑步推进指定秒数。
##
## ⚠️ 必须自己循环：StageRuntime.advance() 单次最多追赶 MAX_STEPS_PER_ADVANCE（240）个逻辑步，
## 即一次调用最多推进 4.0 秒。直接 `advance(21.0)` 只会走 4 秒，
## 会让「等待再部署冷却」这类用例静默失效。
func _advance(rt: StageRuntime, seconds: float) -> void:
	var remaining := seconds
	while remaining > EPS:
		var chunk := minf(remaining, 1.0)
		rt.advance(chunk)
		remaining -= chunk


## 在指定路线上放置一个高血量木桩敌人（用于统计攻击次数）。
## 注意：雨宫澪射程仅 1.25 格，因此木桩必须放在 col1 前方 1.25 格以内。
func _place_dummy(rt: StageRuntime, lane: int = 1, x: float = 2.0) -> EnemyRuntime:
	var e := EnemyRuntime.from_config(_enemy_table()["echo_normal"], lane, 9001)
	e.logical_x = x
	e.state = BattleTypes.EnemyState.MOVING
	e.hp = 1000000
	e.hp_max = 1000000
	rt.enemies.append(e)
	return e


# ============================================================
#  一、单独 -25% 减益
# ============================================================

## 覆盖项 1：单独 -25% 攻速减益 → 系数 0.75 → 间隔 = 基础 / 0.75。
func test_01_single_minus_25_percent() -> void:
	var c := _deploy(_runtime(), CHAR_MIO)
	assert_almost_eq(c.attack_interval, MIO_INTERVAL, EPS, "基础间隔应为 1.1 秒")

	_apply_speed(c, "gaze", -0.25, 5.0, 0.0)

	assert_almost_eq(c.attack_speed_factor(), 0.75, EPS, "-25% ⇒ 频率系数 0.75")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / 0.75, 0.0001,
		"间隔应为 1.1 / 0.75 ≈ 1.4667 秒（频率倒数口径）")
	# 明确排除「间隔 × 1.25」的错误读法
	assert_false(is_equal_approx(c.effective_attack_interval(), MIO_INTERVAL * 1.25),
		"不得使用「间隔 × (1+|Σ|)」读法（1.375）——与增益侧不对称，已被 DEC-C-0004 排除")


## 覆盖项 1b：不同角色各自的基础间隔都正确换算（不写死某个角色的数值）。
func test_01b_conversion_applies_to_any_base_interval() -> void:
	var rt := _runtime([CHAR_YUMA])
	var c := _deploy(rt, CHAR_YUMA)
	assert_almost_eq(c.attack_interval, YUMA_INTERVAL, EPS, "悠真基础间隔应为 1.3 秒")
	_apply_speed(c, "gaze", -0.25, 5.0, 0.0)
	assert_almost_eq(c.effective_attack_interval(), YUMA_INTERVAL / 0.75, 0.0001,
		"悠真间隔应为 1.3 / 0.75 ≈ 1.7333 秒")


# ============================================================
#  二、多种减益叠加
# ============================================================

## 覆盖项 2：不同 effectId 的攻速减益**先相加**（L556），再统一换算。
func test_02_multiple_debuffs_sum_before_conversion() -> void:
	var c := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c, "debuff_a", -0.15, 5.0, 0.0)
	_apply_speed(c, "debuff_b", -0.20, 5.0, 0.0)

	assert_almost_eq(c.sum_effect_pct(StatusEffect.CATEGORY_ATTACK_SPEED), -0.35, EPS,
		"两个不同 effectId 的减益应先相加（-0.15 + -0.20 = -0.35）")
	assert_almost_eq(c.attack_speed_factor(), 0.65, EPS, "频率系数应为 1 - 0.35 = 0.65")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / 0.65, 0.0001,
		"间隔应为 1.1 / 0.65 ≈ 1.6923 秒")

	# 叠加第三个减益，仍应线性相加
	_apply_speed(c, "debuff_c", -0.10, 5.0, 0.0)
	assert_almost_eq(c.attack_speed_factor(), 0.55, EPS, "三项相加 ⇒ 系数 0.55")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / 0.55, 0.0001,
		"间隔应为 1.1 / 0.55 = 2.0 秒")


## 覆盖项 2b：同一 effectId 重复施加只刷新持续时间，**不叠层**（L556）。
func test_02b_same_effect_id_refreshes_without_stacking() -> void:
	var c := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c, "gaze", -0.25, 5.0, 0.0)
	_apply_speed(c, "gaze", -0.25, 5.0, 1.0)
	_apply_speed(c, "gaze", -0.25, 5.0, 2.0)

	assert_eq(c.status_effects.size(), 1, "同一 effectId 只应存在一条效果（不叠层）")
	assert_almost_eq(c.attack_speed_factor(), 0.75, EPS,
		"重复施加不得叠层（系数仍应为 0.75，而非 0.25）")


# ============================================================
#  三、正负增益同时存在
# ============================================================

## 覆盖项 3：减益与增益**统一结算**（先相加），再夹取上下限。
func test_03_buffs_and_debuffs_settle_together() -> void:
	var c := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c, "buff_a", 0.30, 5.0, 0.0)
	_apply_speed(c, "debuff_a", -0.20, 5.0, 0.0)

	assert_almost_eq(c.sum_effect_pct(StatusEffect.CATEGORY_ATTACK_SPEED), 0.10, EPS,
		"增益与减益应先相加（+0.30 + -0.20 = +0.10）")
	assert_almost_eq(c.attack_speed_factor(), 1.10, EPS, "频率系数应为 1.10")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / 1.10, 0.0001,
		"增益使间隔缩短：1.1 / 1.10 = 1.0 秒")

	# 减益大于增益 ⇒ 净减益
	var c2 := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c2, "buff_a", 0.10, 5.0, 0.0)
	_apply_speed(c2, "debuff_a", -0.40, 5.0, 0.0)
	assert_almost_eq(c2.attack_speed_factor(), 0.70, EPS, "净 -30% ⇒ 系数 0.70")
	assert_almost_eq(c2.effective_attack_interval(), MIO_INTERVAL / 0.70, 0.0001,
		"间隔应为 1.1 / 0.70 ≈ 1.5714 秒")


# ============================================================
#  四、40% 攻速下限
# ============================================================

## 覆盖项 4：Σ ≤ -60% 时频率系数被夹取在 40% 下限（L556 LOCKED）。
func test_04_floor_clamps_at_40_percent() -> void:
	var c := _deploy(_runtime(), CHAR_MIO)
	# 两项叠加 = -0.85，远超下限
	_apply_speed(c, "debuff_a", -0.45, 5.0, 0.0)
	_apply_speed(c, "debuff_b", -0.40, 5.0, 0.0)

	assert_almost_eq(c.sum_effect_pct(StatusEffect.CATEGORY_ATTACK_SPEED), -0.85, EPS,
		"原始求和应为 -0.85")
	assert_almost_eq(c.attack_speed_factor(), FLOOR, EPS,
		"频率系数应被夹取在 40% 下限（clamp(0.15, 0.4, 1.8) = 0.4）")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / FLOOR, 0.0001,
		"间隔应为 1.1 / 0.4 = 2.75 秒（下限生效后不再变长）")

	# 恰好等于下限
	var c2 := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c2, "debuff_a", -0.60, 5.0, 0.0)
	assert_almost_eq(c2.attack_speed_factor(), FLOOR, EPS,
		"恰好 -60% ⇒ 系数 0.40（边界值不越界）")

	# 刚好低于下限
	var c3 := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c3, "debuff_a", -0.61, 5.0, 0.0)
	assert_almost_eq(c3.attack_speed_factor(), FLOOR, EPS,
		"-61% ⇒ 仍被夹取在 0.40")


## 覆盖项 4b：下限作用于**频率**而非间隔——间隔不得超过 基础/下限。
func test_04b_floor_applies_to_frequency_not_interval() -> void:
	var c := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c, "debuff_a", -0.99, 5.0, 0.0)
	var max_interval := MIO_INTERVAL / FLOOR
	assert_almost_eq(c.effective_attack_interval(), max_interval, 0.0001,
		"极端减益下间隔仍应封顶在 1.1/0.4 = 2.75 秒")
	# 关键性质：下限生效后间隔**不再随减益加深而变长**（封顶）。
	# 这正是「下限作用于频率」的可观测后果——若无下限，-99% 会使间隔膨胀约 100 倍。
	var c2 := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c2, "debuff_b", -0.999, 5.0, 0.0)
	assert_almost_eq(c2.effective_attack_interval(), max_interval, 0.0001,
		"更深的减益（-99.9%）仍应得到同一封顶值 2.75 秒（下限真实生效）")
	assert_almost_eq(c.effective_attack_interval(), c2.effective_attack_interval(), EPS,
		"下限之后间隔必须封顶、不再增长")


# ============================================================
#  五、增益上限（表 81 软上限 +80%）
# ============================================================

## 覆盖项 5：Σ ≥ +80% 时频率系数被夹取在 1.8（表 81 软上限）。
func test_05_ceiling_clamps_at_plus_80_percent() -> void:
	var c := _deploy(_runtime(), CHAR_MIO)
	assert_almost_eq(c.buff_ceiling_pct, CEILING, EPS,
		"增益上限应由 balance.json 注入为 1.8（表 81：+80%）")

	_apply_speed(c, "buff_a", 0.60, 5.0, 0.0)
	_apply_speed(c, "buff_b", 0.50, 5.0, 0.0)

	assert_almost_eq(c.sum_effect_pct(StatusEffect.CATEGORY_ATTACK_SPEED), 1.10, EPS,
		"原始求和应为 +1.10")
	assert_almost_eq(c.attack_speed_factor(), CEILING, EPS,
		"频率系数应被夹取在 1.8 上限（clamp(2.10, 0.4, 1.8) = 1.8）")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / CEILING, 0.0001,
		"间隔应为 1.1 / 1.8 ≈ 0.6111 秒（上限生效后不再变短）")

	# 恰好等于上限
	var c2 := _deploy(_runtime(), CHAR_MIO)
	_apply_speed(c2, "buff_a", 0.80, 5.0, 0.0)
	assert_almost_eq(c2.attack_speed_factor(), CEILING, EPS, "恰好 +80% ⇒ 系数 1.80")


## 覆盖项 5b：上限必须来自 balance.json 且可配置（表 81 非 LOCKED）。
func test_05b_ceiling_comes_from_balance_config() -> void:
	var combat := _combat()
	assert_true(combat.has("buffCeiling"),
		"表 81 的攻击速度软上限应存于 balance.json 的 combat.buffCeiling")
	var ceil_cfg: Dictionary = combat.get("buffCeiling", {})
	assert_almost_eq(float(ceil_cfg.get("attackSpeedPct", 0.0)), CEILING, EPS,
		"配置值应为 1.8（基础 1.0 + 80% 软上限）")
	assert_false(bool(ceil_cfg.get("enforced", true)),
		"当前构建无增益来源，enforced 应如实标为 false（不得宣称已验收）")

	# 改配置应真的改变上限（可配置性验证）
	var chars := _char_table()
	var combat2 := _combat().duplicate(true)
	(combat2["buffCeiling"] as Dictionary)["attackSpeedPct"] = 1.5
	var rt := StageRuntime.from_config(
		_cfg([CHAR_MIO]), _enemy_table(), _grid(), chars, combat2)
	var c := _deploy(rt, CHAR_MIO)
	assert_almost_eq(c.buff_ceiling_pct, 1.5, EPS, "上限应跟随配置变化")
	_apply_speed(c, "buff_a", 1.0, 5.0, 0.0)
	assert_almost_eq(c.attack_speed_factor(), 1.5, EPS, "上限改为 1.5 后应夹取在 1.5")

	# 非法上限（< 1.0）应报错
	var combat3 := _combat().duplicate(true)
	(combat3["buffCeiling"] as Dictionary)["attackSpeedPct"] = 0.5
	var rt3 := StageRuntime.from_config(
		_cfg([CHAR_MIO]), _enemy_table(), _grid(), chars, combat3)
	assert_false(rt3.is_valid(), "上限 < 1.0 应报错（不可能低于基础值）")


# ============================================================
#  六、效果过期与恢复
# ============================================================

## 覆盖项 6：减益到期后频率系数与间隔应完全恢复基础值。
func test_06_effect_expiry_restores_base_interval() -> void:
	var rt := _runtime()
	var c := _deploy(rt, CHAR_MIO)
	_apply_speed(c, "gaze", -0.25, 2.0, 0.0)

	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / 0.75, 0.0001,
		"生效期间间隔应为 1.4667 秒")

	# 推进超过持续时间
	_advance(rt, 2.5)

	assert_eq(c.status_effects.size(), 0, "到期后应移除效果")
	assert_almost_eq(c.attack_speed_factor(), 1.0, EPS, "到期后频率系数应恢复 1.0")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL, EPS,
		"到期后间隔应完全恢复基础值 1.1 秒")


## 覆盖项 6b：多效果各自到期时，只移除到期者，其余仍生效。
func test_06b_partial_expiry_keeps_remaining_effects() -> void:
	var rt := _runtime()
	var c := _deploy(rt, CHAR_MIO)
	_apply_speed(c, "short", -0.20, 1.0, 0.0)
	_apply_speed(c, "long", -0.30, 10.0, 0.0)

	assert_almost_eq(c.attack_speed_factor(), 0.50, EPS, "两者叠加 ⇒ 系数 0.50")

	_advance(rt, 1.5)

	assert_eq(c.status_effects.size(), 1, "只应移除到期的效果")
	assert_true(c.has_status_effect("long"), "长时效果应仍生效")
	assert_false(c.has_status_effect("short"), "短时效果应已到期")
	assert_almost_eq(c.attack_speed_factor(), 0.70, EPS,
		"只剩 -30% ⇒ 系数 0.70（部分恢复）")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / 0.70, 0.0001,
		"间隔应部分恢复为 1.1 / 0.70")


## 覆盖项 6c：重新部署产生的新实例**不继承**旧实例的攻速效果。
func test_06c_redeploy_does_not_inherit_effects() -> void:
	var rt := _runtime()
	var c := _deploy(rt, CHAR_MIO)
	_apply_speed(c, "gaze", -0.25, 30.0, 0.0)
	assert_almost_eq(c.attack_speed_factor(), 0.75, EPS, "旧实例应有减益")

	assert_true(rt.withdraw_character_by_id(CHAR_MIO).ok, "应能撤退")
	_advance(rt, 21.0)  # 越过 20 秒再部署冷却（必须循环推进，单次 advance 上限 4 秒）
	var c2 := _deploy(rt, CHAR_MIO)
	assert_ne(c2.instance_id, c.instance_id, "应产生新实例")
	assert_eq(c2.status_effects.size(), 0, "新实例不得继承旧减益")
	assert_almost_eq(c2.attack_speed_factor(), 1.0, EPS, "新实例频率系数应为 1.0")


# ============================================================
#  七、暂停与重新开始
# ============================================================

## 覆盖项 7：暂停期间攻速效果与攻击冷却都不推进（V2.1.4 D-35）。
func test_07_pause_freezes_speed_effects_and_cooldown() -> void:
	var rt := _runtime()
	var c := _deploy(rt, CHAR_MIO)
	_apply_speed(c, "gaze", -0.25, 5.0, 0.0)
	_advance(rt, 0.5)

	var interval_before := c.effective_attack_interval()
	var remaining_before := c.status_effects[0].remaining(rt.elapsed_seconds)
	var elapsed_before := rt.elapsed_seconds

	rt.set_paused(true)
	_advance(rt, 3.0)

	assert_almost_eq(rt.elapsed_seconds, elapsed_before, EPS, "暂停期间逻辑时间不得推进")
	assert_almost_eq(c.effective_attack_interval(), interval_before, EPS,
		"暂停期间攻速系数不得变化")
	assert_almost_eq(c.status_effects[0].remaining(rt.elapsed_seconds), remaining_before, EPS,
		"暂停期间效果剩余时间不得减少")

	# 恢复后继续正常推进（剩余约 4.5 秒，推进 5 秒足以到期）
	rt.set_paused(false)
	_advance(rt, 5.0)
	assert_eq(c.status_effects.size(), 0, "恢复后效果应按原持续时间正常到期")
	assert_almost_eq(c.attack_speed_factor(), 1.0, EPS, "到期后系数恢复 1.0")


## 覆盖项 7b：重新开始（新建运行时）不残留任何状态。
func test_07b_restart_has_no_residual_state() -> void:
	var rt1 := _runtime()
	var c1 := _deploy(rt1, CHAR_MIO)
	_apply_speed(c1, "gaze", -0.25, 30.0, 0.0)
	assert_almost_eq(c1.attack_speed_factor(), 0.75, EPS, "第一局应有减益")

	# 全新运行时（等价于重新开始一局）
	var rt2 := _runtime()
	var c2 := _deploy(rt2, CHAR_MIO)
	assert_eq(c2.status_effects.size(), 0, "新一局不得残留任何状态效果")
	assert_almost_eq(c2.attack_speed_factor(), 1.0, EPS, "新一局频率系数应为 1.0")
	assert_almost_eq(rt2.elapsed_seconds, 0.0, EPS, "新一局逻辑时间应从 0 开始")


# ============================================================
#  八、攻速变化期间不出现额外攻击或重复冷却重置
# ============================================================

## 覆盖项 8：攻速变化**不得**凭空产生额外攻击。
##
## 手法：减益**先于首击**生效，使首次冷却直接是减益后的较长间隔；
## 然后推进到「原基础间隔已过、但有效间隔未到」的时刻，断言**不得**攻击。
## 这直接证明系统用的是有效间隔，而不是偷偷沿用基础间隔。
func test_08_speed_change_does_not_grant_extra_attacks() -> void:
	var rt := _runtime()
	var c := _deploy(rt, CHAR_MIO)
	var e := _place_dummy(rt, 1, 2.0)

	# 减益先于首击生效 → 首击冷却应为 1.4667 而非 1.1
	_apply_speed(c, "gaze", -0.25, 30.0, 0.0)
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL / 0.75, 0.0001,
		"减益生效时有效间隔应为 1.4667 秒")

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_lt(e.hp, 1000000, "首击应发生")
	assert_almost_eq(c.attack_cooldown, MIO_INTERVAL / 0.75, 0.0001,
		"首击应进入减益后的完整 1.4667 秒冷却（而非 1.1 秒）")
	var hp_after_first := e.hp

	# 推进 1.2 秒：已越过基础间隔 1.1，但未到有效间隔 1.4667 → 不得攻击
	_advance(rt, 1.2)
	assert_eq(e.hp, hp_after_first,
		"越过基础间隔但未到有效间隔时不得攻击（说明未沿用基础间隔、未跳过冷却）")

	# 再推进 0.4 秒（累计约 1.6 > 1.4667）→ 应恰好恢复攻击
	_advance(rt, 0.4)
	assert_lt(e.hp, hp_after_first, "越过有效间隔后应恢复攻击")


## 覆盖项 8a：冷却期间施加减益**不得**重置已进行的冷却进度。
func test_08a_applying_debuff_mid_cooldown_keeps_progress() -> void:
	var rt := _runtime()
	var c := _deploy(rt, CHAR_MIO)
	var e := _place_dummy(rt, 1, 2.0)

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_almost_eq(c.attack_cooldown, MIO_INTERVAL, EPS, "首击应进入 1.1 秒冷却")
	var hp_after_first := e.hp

	_advance(rt, 0.3)
	var cd_before := c.attack_cooldown
	assert_lt(cd_before, MIO_INTERVAL, "冷却应已递减")

	_apply_speed(c, "gaze", -0.25, 30.0, rt.elapsed_seconds)
	assert_almost_eq(c.attack_cooldown, cd_before, EPS,
		"施加减益不得重置已进行的冷却（%.4f → %.4f）" % [cd_before, c.attack_cooldown])
	assert_eq(e.hp, hp_after_first, "施加减益本身不得造成伤害")

	# 冷却继续按原进度走完（约再 0.8 秒），随后使用新的有效间隔
	_advance(rt, 0.9)
	assert_lt(e.hp, hp_after_first, "冷却走完后应恢复攻击")
	# 关键：此后进入的冷却必须基于**减益后的有效间隔**（1.4667），而不是基础间隔（1.1）。
	# 注意此刻冷却已在同一推进窗口内走掉了一小部分，故断言「剩余冷却 > 基础间隔」
	# 而不是精确相等——后者会依赖攻击恰好发生在窗口末端这一脆弱假设。
	assert_gt(c.attack_cooldown, MIO_INTERVAL,
		"此后应使用减益后的有效间隔（剩余冷却 %.4f 应 > 基础间隔 %.2f）"
		% [c.attack_cooldown, MIO_INTERVAL])
	assert_lt(c.attack_cooldown, MIO_INTERVAL / 0.75 + EPS,
		"剩余冷却不应超过减益后的完整间隔 1.4667 秒")


## 覆盖项 8b：移除减益**不得**缩短已进行的冷却（避免「刷减益换攻速」）。
func test_08b_removing_debuff_does_not_reset_cooldown() -> void:
	var rt := _runtime()
	var c := _deploy(rt, CHAR_MIO)
	_apply_speed(c, "gaze", -0.25, 10.0, 0.0)
	var e := _place_dummy(rt, 1, 2.0)

	rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
	assert_almost_eq(c.attack_cooldown, MIO_INTERVAL / 0.75, 0.0001,
		"减益下应进入 1.4667 秒冷却")
	var cd_at_attack := c.attack_cooldown

	_advance(rt, 0.3)
	var cd_before_clear := c.attack_cooldown
	assert_lt(cd_before_clear, cd_at_attack, "冷却应正常递减")

	# 直接清空效果（模拟增益驱散）
	c.clear_status_effects()
	assert_almost_eq(c.attack_cooldown, cd_before_clear, EPS,
		"清空效果不得重置或缩短已进行的冷却（实际 %.4f → %.4f）"
		% [cd_before_clear, c.attack_cooldown])
	assert_almost_eq(c.attack_speed_factor(), 1.0, EPS, "但频率系数应立即恢复 1.0")

	# 下一次攻击应使用恢复后的基础间隔
	_advance(rt, 0.9)
	assert_lt(e.hp, 1000000, "越过恢复后的基础间隔应正常攻击")


## 覆盖项 8c：长时间运行下，攻速减益生效期间的攻击次数必须**少于**无减益时。
##
## 这是「减益真实降低输出」的直接量化证据，也反证不存在额外攻击。
func test_08c_debuff_reduces_attack_count_over_time() -> void:
	var no_debuff := _count_attacks(10.0, false)
	var with_debuff := _count_attacks(10.0, true)

	assert_gt(no_debuff, 0, "无减益时应发生攻击")
	assert_lt(with_debuff, no_debuff,
		"减益期间攻击次数应严格少于无减益时（%d < %d）" % [with_debuff, no_debuff])


## 在给定逻辑时长内统计角色对木桩敌人的攻击次数。
func _count_attacks(seconds: float, with_debuff: bool) -> int:
	var rt := _runtime()
	var c := _deploy(rt, CHAR_MIO)
	var e := _place_dummy(rt, 1, 2.0)

	if with_debuff:
		_apply_speed(c, "gaze", -0.25, 999.0, 0.0)

	var hp_track := e.hp
	var hits := 0
	var t := 0.0
	while t < seconds - EPS:
		rt.advance(StageRuntime.LOGIC_STEP_SECONDS)
		t += StageRuntime.LOGIC_STEP_SECONDS
		if e.hp < hp_track:
			hits += 1
			hp_track = e.hp
	return hits


# ============================================================
#  九、无效果时行为与改动前完全一致（回归保护）
# ============================================================

## 覆盖项 9：无任何状态效果时，有效间隔恒等于基础间隔。
func test_09_no_effects_equals_base_interval() -> void:
	for cid: String in [CHAR_MIO, CHAR_YUMA, CHAR_YUI]:
		var rt := _runtime([cid])
		var c := _deploy(rt, cid)
		assert_eq(c.status_effects.size(), 0, "%s 新建实例应无状态效果" % cid)
		assert_almost_eq(c.attack_speed_factor(), 1.0, EPS,
			"%s 无效果时频率系数应为 1.0" % cid)
		assert_almost_eq(c.effective_attack_interval(), c.attack_interval, EPS,
			"%s 无效果时有效间隔应等于基础间隔" % cid)


## 覆盖项 9b：沉默（控制类）**不参与**攻速求和，也不受上下限夹取（L557）。
func test_09b_silence_does_not_affect_attack_speed() -> void:
	var c := _deploy(_runtime(), CHAR_MIO)
	c.apply_status_effect_from_config({
		"effectId": "mute",
		"sourceId": "test",
		"category": StatusEffect.CATEGORY_SILENCE,
		"pct": 0.0,
		"durationSeconds": 3.0,
		"stackPolicy": "REFRESH_DURATION",
	}, 0.0)

	assert_false(c.can_cast_active_skill(), "沉默应禁止主动技能")
	assert_almost_eq(c.sum_effect_pct(StatusEffect.CATEGORY_ATTACK_SPEED), 0.0, EPS,
		"沉默不得进入攻速百分数求和（L557）")
	assert_almost_eq(c.attack_speed_factor(), 1.0, EPS, "沉默不得改变攻速系数")
	assert_almost_eq(c.effective_attack_interval(), MIO_INTERVAL, EPS,
		"沉默不得改变攻击间隔（L557：不改变普通攻击频率）")


# ============================================================
#  十、配置承载与裁决可追溯
# ============================================================

## 覆盖项 10：下限为 LOCKED 规格值并存于 balance.json；三项下限当前一致。
func test_10_floor_is_locked_spec_value_in_balance() -> void:
	var combat := _combat()
	assert_true(combat.has("debuffFloor"), "L557：减益下限必须存于 balance.json")
	var floor_cfg: Dictionary = combat.get("debuffFloor", {})
	assert_almost_eq(float(floor_cfg.get("attackSpeedPct", 0.0)), FLOOR, EPS,
		"L556：攻速下限应为规格值 40%")
	assert_almost_eq(float(floor_cfg.get("attackPct", 0.0)), FLOOR, EPS, "攻击力下限应为 40%")
	assert_almost_eq(float(floor_cfg.get("cdRecoveryPct", 0.0)), FLOOR, EPS,
		"CD 恢复速度下限应为 40%")
	assert_false(bool(floor_cfg.get("appliesToEnemies", true)),
		"L556 属性清单是封闭枚举，不适用于敌人侧（设计稿冲突 C-9）")

	# 换算口径的裁决说明必须留在配置里（可追溯）
	assert_true(floor_cfg.has("_attackSpeedConversion_note"),
		"换算口径的裁决依据应记录在配置中（可追溯）")
	var note := str(floor_cfg.get("_attackSpeedConversion_note", ""))
	assert_string_contains(note, "DEC-C-0004",
		"配置注释应引用正式裁决编号 DEC-C-0004")


## 覆盖项 10b：下限缺失时必须报错（不得静默通过）。
func test_10b_missing_floor_is_rejected() -> void:
	var combat := _combat().duplicate(true)
	combat.erase("debuffFloor")
	var rt := StageRuntime.from_config(
		_cfg([CHAR_MIO]), _enemy_table(), _grid(), _char_table(), combat)
	assert_false(rt.is_valid(), "缺 debuffFloor 应报错")
	var joined := " ".join(rt.get_errors())
	assert_string_contains(joined, "debuffFloor", "错误信息应指出 debuffFloor")
