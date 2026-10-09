## V2.1.4 LOCKED「场上同时部署上限 5」的执行回归。
##
## 存在的理由：`balance.json` 里 `combat.fieldDeployLimit = 5` 早已存在，
## 但**没有任何代码读取它** —— 等于一条 LOCKED 规则从未实现。
## 本文件把该规则变成可执行断言：既验证"读到了权威值"，也验证"真的会拦"，
## 并守住"对现有关卡零影响"（首章最多 3 名可部署角色，上限永不触发）。
##
## 纪律：夹具一律先 duplicate(true) 再改，绝不修改 DataRegistry 权威字典；
## 不为了通过测试而改任何 LOCKED 数值（上限值 5 来自权威配置，不在本文件写死为规则）。
extends GutTest

const CHAR_MIO := "amamiya_mio"
const CHAR_YUMA := "kamiya_yuma"
const CHAR_YUI := "ogawa_yui"
const TRIPLE: Array[String] = [CHAR_MIO, CHAR_YUMA, CHAR_YUI]
const COST := {CHAR_MIO: 10, CHAR_YUMA: 12, CHAR_YUI: 14}


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


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


## 可控关卡夹具：三人全部解锁、无出怪（不干扰部署计数）、核心血厚、AP 充足。
func _cfg(ap: int) -> Dictionary:
	var c: Dictionary = DataRegistry.get_entry("stages", "1-1").duplicate(true)
	c.erase("waves")
	c["coreHp"] = 99
	c["startingAp"] = ap
	c["apRegen"] = 1.0
	c["enemySpawnTimeline"] = []
	c["availableCharacters"] = TRIPLE.duplicate()
	return c


func _runtime(ap: int, combat: Dictionary) -> StageRuntime:
	return StageRuntime.from_config(_cfg(ap), _enemy_table(), _grid(), _char_table(), combat)


func _deploy_all_ap_enough(rt: StageRuntime) -> void:
	rt.ap = rt.ap_max


# ============================================================ 权威值读取

func test_field_limit_read_from_balance_authority() -> void:
	var rt := _runtime(30, _combat())
	assert_eq(rt.get_errors().size(), 0, "构建应无错误：%s" % str(rt.get_errors()))
	# 权威值来自 data/balance.json，规格 L614/L1811/L2113 LOCKED = 5
	assert_eq(rt.field_deploy_limit, int(_combat().get("fieldDeployLimit", -1)))
	assert_eq(rt.field_deploy_limit, 5, "V2.1.4 场上同时部署上限应为 5")


func test_field_limit_not_enforced_when_combat_disabled() -> void:
	# P0.1 类专项测试传空 combat（不启用 AP/编队系统），此时不得施加人数限制。
	var rt := _runtime(30, {})
	assert_eq(rt.field_deploy_limit, 0, "未启用编队系统时上限为 0（不生效）")


func test_field_limit_nonpositive_is_reported() -> void:
	var bad := _combat().duplicate(true)
	bad["fieldDeployLimit"] = 0
	var rt := _runtime(30, bad)
	assert_gt(rt.get_errors().size(), 0, "非正整数上限必须报错而非静默降级")
	assert_true(_has_error_mentioning(rt, "fieldDeployLimit"),
		"错误信息应点名 fieldDeployLimit：%s" % str(rt.get_errors()))


func _has_error_mentioning(rt: StageRuntime, needle: String) -> bool:
	for e: String in rt.get_errors():
		if e.contains(needle):
			return true
	return false


# ============================================================ 真的会拦

func test_sixth_concurrent_deploy_is_blocked_at_limit_two() -> void:
	# 用可配置的低上限（2）验证机制本身：首章只有 3 名角色，无法自然触达 5。
	var combat := _combat().duplicate(true)
	combat["fieldDeployLimit"] = 2
	var rt := _runtime(999, combat)
	rt.ap_max = 999
	rt.ap = 999
	assert_true(rt.deploy_character(CHAR_MIO, 1, 0).ok)
	assert_true(rt.deploy_character(CHAR_YUMA, 2, 1).ok)
	assert_eq(rt.characters.size(), 2)
	var third := rt.deploy_character(CHAR_YUI, 3, 2)
	assert_false(third.ok, "达到上限后第 3 名必须被拒")
	assert_eq(third.reason, StageRuntime.DeployReject.FIELD_LIMIT_REACHED)
	assert_eq(rt.characters.size(), 2, "被拒不得改变场上人数")


func test_limit_reason_text_names_the_limit() -> void:
	var combat := _combat().duplicate(true)
	combat["fieldDeployLimit"] = 2
	var rt := _runtime(999, combat)
	rt.ap_max = 999
	rt.ap = 999
	rt.deploy_character(CHAR_MIO, 1, 0)
	rt.deploy_character(CHAR_YUMA, 2, 1)
	var r := rt.query_deploy(CHAR_YUI, 3, 2)
	assert_eq(r.reason, StageRuntime.DeployReject.FIELD_LIMIT_REACHED)
	var text := r.reason_text()
	assert_true(text.contains("上限"), "文案应说明是人数上限：%s" % text)
	assert_true(text.contains("2"), "文案应携带实际上限数值：%s" % text)


func test_limit_takes_precedence_over_insufficient_ap() -> void:
	# 满员时 AP 再够也放不了；先报"上限"比"AP 不足"更可执行
	# （AP 会自然回复，空位不会自己出现）。
	var combat := _combat().duplicate(true)
	combat["fieldDeployLimit"] = 2
	var rt := _runtime(23, combat)   # 10 + 12 = 22 已用，剩 1 < 结衣的 14
	rt.deploy_character(CHAR_MIO, 1, 0)
	rt.deploy_character(CHAR_YUMA, 2, 1)
	var r := rt.query_deploy(CHAR_YUI, 3, 2)
	assert_eq(r.reason, StageRuntime.DeployReject.FIELD_LIMIT_REACHED,
		"同时满足'满员'与'AP不足'时应优先报满员，实际：%s" % r.reason_text())


func test_withdraw_frees_a_slot_and_redeploy_is_allowed() -> void:
	var combat := _combat().duplicate(true)
	combat["fieldDeployLimit"] = 2
	var rt := _runtime(999, combat)
	rt.ap_max = 999
	rt.ap = 999
	var mio := rt.deploy_character(CHAR_MIO, 1, 0)
	rt.deploy_character(CHAR_YUMA, 2, 1)
	assert_false(rt.deploy_character(CHAR_YUI, 3, 2).ok)
	# 主动撤退一名 → 场上 1 名，上限重新可容纳
	var res := rt.withdraw_character(mio.character.instance_id)
	assert_true(res.ok, "撤退应成功")
	assert_eq(rt.characters.size(), 1)
	# 冷却会挡住刚撤退的角色，但另一名（结衣）不受影响
	var yui := rt.deploy_character(CHAR_YUI, 3, 2)
	assert_true(yui.ok, "空出名额后应可部署另一名：%s" % yui.reason_text())


func test_incapacitated_character_frees_a_slot() -> void:
	# 上限计的是**在场**角色数；失能离场必须释放名额（否则玩家会被永久卡死）。
	var combat := _combat().duplicate(true)
	combat["fieldDeployLimit"] = 2
	var rt := _runtime(999, combat)
	rt.ap_max = 999
	rt.ap = 999
	var mio := rt.deploy_character(CHAR_MIO, 1, 0).character
	rt.deploy_character(CHAR_YUMA, 2, 1)
	assert_false(rt.deploy_character(CHAR_YUI, 3, 2).ok)
	mio.hp = 0
	mio.alive = false
	rt._cleanup_dead()
	assert_eq(rt.characters.size(), 1, "失能角色应已离场")
	assert_true(rt.deploy_character(CHAR_YUI, 3, 2).ok, "失能后应释放名额")


# ============================================================ 现有关卡零影响

func test_no_existing_stage_exceeds_the_field_limit() -> void:
	# 上限启用后，任何已实现关卡的可部署角色数都必须 <= 上限，
	# 否则本改动会破坏既有可通关性（那是改数值，不是修表现）。
	var limit := int(_combat().get("fieldDeployLimit", 5))
	var checked := 0
	for sid: String in DataRegistry.get_ids("stages"):
		var cfg: Dictionary = DataRegistry.get_entry("stages", sid)
		var ac: Variant = cfg.get("availableCharacters", null)
		if typeof(ac) != TYPE_ARRAY or (ac as Array).is_empty():
			continue
		checked += 1
		assert_lte((ac as Array).size(), limit,
			"关卡 %s 可部署角色 %d 名超过场上上限 %d，将导致必然无法全上阵"
			% [sid, (ac as Array).size(), limit])
	for pid: String in DataRegistry.get_ids(PrototypeEntry.PROTOTYPE_STAGES_KEY):
		var cfg: Dictionary = DataRegistry.get_entry(PrototypeEntry.PROTOTYPE_STAGES_KEY, pid)
		var ac: Variant = cfg.get("availableCharacters", null)
		if typeof(ac) == TYPE_ARRAY and not (ac as Array).is_empty():
			checked += 1
			assert_lte((ac as Array).size(), limit,
				"演示关 %s 可部署角色数超过场上上限" % pid)
	assert_gt(checked, 0, "应至少校验到真实关卡")


func test_existing_stages_still_build_clean_with_limit_active() -> void:
	for sid: String in ["1-1", "1-2", "1-3", "1-4", "1-5"]:
		var rt := StageRuntime.from_config(
			DataRegistry.get_entry("stages", sid), _enemy_table(), _grid(),
			_char_table(), _combat())
		assert_eq(rt.get_errors().size(), 0, "%s 构建应无错误：%s" % [sid, str(rt.get_errors())])
		assert_eq(rt.field_deploy_limit, 5, "%s 应读到权威上限" % sid)


func test_deploy_count_is_not_inflated_by_rejected_attempts() -> void:
	# 被拒的部署不得计入 deploy_success_count，也不得扣 AP（既有纪律的再确认）。
	var combat := _combat().duplicate(true)
	combat["fieldDeployLimit"] = 2
	var rt := _runtime(999, combat)
	rt.ap_max = 999
	rt.ap = 999
	rt.deploy_character(CHAR_MIO, 1, 0)
	rt.deploy_character(CHAR_YUMA, 2, 1)
	var ap_before := rt.ap
	for i: int in range(5):
		assert_false(rt.deploy_character(CHAR_YUI, 3, 2).ok)
	assert_eq(rt.deploy_success_count, 2, "成功计数只应记 2 次")
	assert_eq(rt.ap, ap_before, "被拒不得扣 AP")
	assert_eq(rt.characters.size(), 2, "被拒不得改变场上人数")
