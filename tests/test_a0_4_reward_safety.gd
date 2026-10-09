## Alpha A0.4 加固验收测试：奖励结算安全性与待领取权益。
##
## 覆盖本轮指令第一阶段要求的全部验收点：
##   ① 启动读档（修复「启动不读档 → 结算覆盖玩家进度」的致命缺陷）
##   ② 保存失败时内存状态可恢复，不留半结算状态
##   ③ 崩溃恢复（重开游戏后进度与权益一致）
##   ④ 重复结算不重复发放（货币与权益都幂等）
##   ⑤ 旧存档升级（已首通但缺权益 → 补登记，且不重复发放）
##   ⑥ 重复领取 / 重复兑现不复制装备
##
## 纪律：本文件所有用例都在 `_testenv` 重定向后的 APPDATA 下运行，
## 不触碰正式用户存档。
extends GutTest

const SAVE_PATH := "user://save/savegame.json"
const BACKUP_PATH := "user://save/savegame_backup.json"

const STAGE_1_1 := "1-1"
const STAGE_1_2 := "1-2"
const STAGE_1_9 := "1-9"
const STAGE_1_10 := "1-10"
const EQUIP_1_2 := "equip_ch1_1_2_fine_weapon"
const EQUIP_1_9 := "equip_ch1_1_9_rare_accessory"
const MEMENTO_BOSS := "memento_ch1_boss_cleared"


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func before_each() -> void:
	_cleanup_save_files()
	SaveService.new_game()


func after_each() -> void:
	_cleanup_save_files()
	SaveService.new_game()


# ============================================================
#  ① 启动读档：致命缺陷的回归防线
# ============================================================

## **本文件最重要的用例**。复现修复前的破坏链：
##   磁盘上有玩家进度 → 启动（旧实现从不读档）→ 结算 → 进度被空档覆盖。
## 修复后：启动必须把磁盘存档读进内存，结算必须建立在既有进度之上。
func test_startup_loads_existing_save_instead_of_discarding_it() -> void:
	# 1) 造一份"玩家的进度"
	var save: Dictionary = SaveService.build_default_save()
	save["profile"]["playerName"] = "老玩家"
	save["currencies"]["school_coin"] = 999
	save["currencies"]["club_badge"] = 7
	save["progression"]["characters"] = {
		"amamiya_mio": {"level": 10, "exp": 37, "breakthrough": 1},
	}
	save["stages"]["1-1"] = {"cleared": true, "firstClearClaimed": true, "clearCount": 3}
	assert_true(SaveService.commit(save), "玩家存档应写入成功")

	# 2) 模拟"重新启动游戏"：新建一个 SaveService 并触发 _ready
	var svc := _new_service()
	assert_false(
		svc.get_current().is_empty(),
		"启动后内存存档不得为空（旧缺陷：_ready 只检查存在性、从不读档）"
	)
	assert_eq(
		str(svc.get_current()["profile"]["playerName"]), "老玩家",
		"启动必须读回玩家存档，而不是丢掉它"
	)
	assert_eq(
		int(svc.get_current()["currencies"]["school_coin"]), 999,
		"启动后学园币必须与磁盘一致"
	)
	assert_eq(
		int(svc.get_current()["stages"]["1-1"]["clearCount"]), 3,
		"启动后通关次数必须与磁盘一致"
	)


## 结算必须**叠加**在既有进度上，而不是另起一份。
func test_settlement_accumulates_on_existing_progress() -> void:
	var save: Dictionary = SaveService.build_default_save()
	save["currencies"]["school_coin"] = 999
	save["progression"]["characters"] = {
		"amamiya_mio": {"level": 10, "exp": 37, "breakthrough": 1},
	}
	assert_true(SaveService.commit(save), "玩家存档应写入成功")

	# 模拟重启 + 打完 1-1
	var svc := _new_service()
	assert_eq(int(svc.get_current()["currencies"]["school_coin"]), 999, "重启后应读回 999")

	var cfg: Dictionary = DataRegistry.get_entry("stages", STAGE_1_1)
	var res := StageRewardService.settle(cfg, true, true)
	assert_true(res.ok, "结算应成功：%s" % res.reason)

	# 1-1 首通 = battleRewards 160 + firstClear 500
	assert_eq(
		int(SaveService.get_current()["currencies"]["school_coin"]), 999 + 660,
		"结算后的学园币应是「原进度 999 + 本次 660」，而不是被清成 660"
	)
	assert_eq(
		int(SaveService.get_current()["progression"]["characters"]["amamiya_mio"]["level"]), 10,
		"结算不得清空既有角色等级"
	)


## 全新玩家（磁盘上什么都没有）应正常开局。
func test_fresh_player_starts_with_empty_memory_but_can_play() -> void:
	_cleanup_save_files()
	var svc := _new_service()
	assert_true(
		svc.get_current().is_empty(),
		"全新玩家启动时内存应为空（首次保存时才落盘）"
	)
	assert_true(svc.ensure_loaded(), "全新玩家应能建立新档")
	assert_false(svc.get_current().is_empty(), "ensure_loaded 后应有存档")


## 磁盘上有存档但读不出来时，**绝不能**用新档覆盖。
func test_unreadable_save_is_never_overwritten_by_new_game() -> void:
	var save: Dictionary = SaveService.build_default_save()
	save["currencies"]["school_coin"] = 12345
	assert_true(SaveService.commit(save), "存档应写入成功")
	# 主存档损坏，且删掉 backup（使两条恢复路径都不可用）
	_write_raw(SAVE_PATH, "{ 这不是合法 JSON")
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(BACKUP_PATH)

	var svc := _new_service()
	assert_false(svc.ensure_loaded(), "存档不可读时 ensure_loaded 应失败而非覆盖")
	assert_true(
		svc.get_current().is_empty(),
		"读档失败后内存必须保持为空（绝不静默建新档）"
	)
	# 断言之后再收错误：本用例刻意制造损坏存档，这些错误是**被测行为**。
	_mark_errors_handled()


# ============================================================
#  ② 保存失败：内存状态可恢复，不留半结算状态
# ============================================================

## commit 失败时内存必须回滚到调用前，不得留下"奖励已入账但没写盘"的假象。
func test_commit_failure_rolls_back_memory_state() -> void:
	var save: Dictionary = SaveService.build_default_save()
	save["currencies"]["school_coin"] = 500
	assert_true(SaveService.commit(save), "初始提交应成功")
	var before: Dictionary = SaveService.get_current().duplicate(true)

	# 制造写盘失败：把主存档路径变成一个目录，使 FileAccess.open(WRITE) 失败。
	var blocked := _block_save_path()
	if not blocked:
		pass_test("当前环境无法制造写盘失败（跳过）")
		return

	var mutated: Dictionary = SaveService.get_current().duplicate(true)
	mutated["currencies"]["school_coin"] = 99999
	var ok: bool = SaveService.commit(mutated)
	_unblock_save_path()
	_mark_errors_handled()

	assert_false(ok, "写盘失败时 commit 必须返回 false")
	assert_eq(
		int(SaveService.get_current()["currencies"]["school_coin"]),
		int(before["currencies"]["school_coin"]),
		"commit 失败后内存必须回滚到提交前（不得留下半结算状态）"
	)


## 结算在写盘失败时必须报告失败，且**不得**把 firstClearClaimed 置为 true。
func test_settlement_reports_failure_and_does_not_mark_first_clear() -> void:
	var save: Dictionary = SaveService.build_default_save()
	assert_true(SaveService.commit(save), "初始提交应成功")

	var blocked := _block_save_path()
	if not blocked:
		pass_test("当前环境无法制造写盘失败（跳过）")
		return

	var cfg: Dictionary = DataRegistry.get_entry("stages", STAGE_1_1)
	var res := StageRewardService.settle(cfg, true, true)
	_unblock_save_path()
	_mark_errors_handled()

	assert_false(res.ok, "写盘失败时结算必须报告失败")
	assert_false(
		StageRewardService.is_first_cleared(STAGE_1_1),
		"写盘失败时不得把首通标记为已领取（否则玩家会永久失去首通奖励）"
	)


# ============================================================
#  ③ 崩溃恢复：重开后状态一致
# ============================================================

func test_progress_and_entitlements_survive_restart() -> void:
	var cfg: Dictionary = DataRegistry.get_entry("stages", STAGE_1_2)
	var res := StageRewardService.settle(cfg, true, true)
	assert_true(res.ok, "1-2 首通结算应成功：%s" % res.reason)

	var coin_before := int(SaveService.get_current()["currencies"]["school_coin"])
	var pending_before := StageRewardService.pending_for_stage(STAGE_1_2)
	assert_eq(pending_before.size(), 1, "1-2 首通应登记 1 条待领取权益（优秀级基础武器）")

	# 模拟崩溃后重开
	var svc := _new_service()
	assert_eq(
		int(svc.get_current()["currencies"]["school_coin"]), coin_before,
		"重开后学园币应与崩溃前一致"
	)
	assert_true(
		StageRewardService.is_first_cleared(STAGE_1_2),
		"重开后首通标记应保持"
	)
	var pending_after := StageRewardService.pending_for_stage(STAGE_1_2)
	assert_eq(pending_after.size(), 1, "重开后待领取权益应保持 1 条")
	assert_eq(
		str(pending_after[0]["itemId"]), EQUIP_1_2,
		"待领取权益的 itemId 应保持为 1-2 的装备 ID"
	)


# ============================================================
#  ④ 重复结算：货币与权益都幂等
# ============================================================

func test_repeat_settlement_does_not_duplicate_currency_or_entitlement() -> void:
	var cfg: Dictionary = DataRegistry.get_entry("stages", STAGE_1_2)
	var first := StageRewardService.settle(cfg, true, true)
	assert_true(first.ok and first.first_clear, "首次应为首通")
	var coin_after_first := int(SaveService.get_current()["currencies"]["school_coin"])

	# 再结算两次
	var second := StageRewardService.settle(cfg, true, true)
	var third := StageRewardService.settle(cfg, true, true)
	assert_true(second.ok and third.ok, "重复结算应正常返回")
	assert_false(second.first_clear, "第二次不应再是首通")
	assert_false(third.first_clear, "第三次不应再是首通")

	# 1-2 的即时战斗奖励每次通关都发；重复通关额外再发重复奖励。
	# battleRewards = 学园币 160；reward_repeat_standard = 学园币 60。
	# 因此第二、三次各 +220。
	var expected := coin_after_first + (160 + 60) * 2
	assert_eq(
		int(SaveService.get_current()["currencies"]["school_coin"]), expected,
		"重复通关只发「即时战斗奖励 + 重复奖励」，不得重发首通货币"
	)
	assert_eq(
		StageRewardService.pending_for_stage(STAGE_1_2).size(), 1,
		"重复结算不得重复登记权益"
	)
	assert_eq(
		StageRewardService.clear_count(STAGE_1_2), 3,
		"通关次数应正确累计为 3"
	)


## 失败不发放任何奖励，也不登记权益。
func test_defeat_grants_nothing() -> void:
	var cfg: Dictionary = DataRegistry.get_entry("stages", STAGE_1_2)
	var res := StageRewardService.settle(cfg, false, true)
	assert_true(res.ok, "失败路径应正常返回")
	assert_false(res.rewarded, "失败不得发放奖励")
	assert_true(res.granted.is_empty(), "失败不得发放任何货币")
	assert_eq(
		StageRewardService.pending_for_stage(STAGE_1_2).size(), 0,
		"失败不得登记权益"
	)
	assert_false(
		StageRewardService.is_first_cleared(STAGE_1_2),
		"失败不得标记首通"
	)


# ============================================================
#  ⑤ 旧存档升级：补登记权益且不重复发放
# ============================================================

## 构造"旧版存档"：已首通、有货币，但完全没有 entitlements 段。
func test_legacy_save_gets_entitlements_backfilled() -> void:
	var legacy: Dictionary = SaveService.build_default_save()
	legacy.erase("entitlements")  # 模拟旧结构
	legacy["currencies"]["school_coin"] = 2800
	legacy["stages"]["1-2"] = {"cleared": true, "firstClearClaimed": true, "clearCount": 1}
	legacy["stages"]["1-9"] = {"cleared": true, "firstClearClaimed": true, "clearCount": 1}
	assert_true(SaveService.commit(legacy), "旧存档应写入成功")

	var svc := _new_service()
	assert_false(
		svc.get_current().has("entitlements"),
		"旧存档确实没有 entitlements 段（前置条件）"
	)

	var coin_before := int(svc.get_current()["currencies"]["school_coin"])
	var backfilled := StageRewardService.backfill_entitlements()
	assert_eq(backfilled.size(), 2, "应补登记 2 条权益（1-2 武器 + 1-9 稀有饰品）")

	var items := _pending_item_ids()
	assert_true(items.has(EQUIP_1_2), "1-2 的装备权益应被补登记")
	assert_true(items.has(EQUIP_1_9), "1-9 的装备权益应被补登记")
	assert_eq(
		int(SaveService.get_current()["currencies"]["school_coin"]), coin_before,
		"补登记权益**不得**发放任何货币（旧存档的货币早已发过）"
	)


## 旧存档升级必须幂等：重复补登记不得产生重复权益。
func test_legacy_backfill_is_idempotent() -> void:
	var legacy: Dictionary = SaveService.build_default_save()
	legacy.erase("entitlements")
	legacy["stages"]["1-9"] = {"cleared": true, "firstClearClaimed": true, "clearCount": 1}
	assert_true(SaveService.commit(legacy), "旧存档应写入成功")

	var first := StageRewardService.backfill_entitlements()
	var second := StageRewardService.backfill_entitlements()
	var third := StageRewardService.backfill_entitlements()
	assert_eq(first.size(), 1, "首次补登记应为 1 条")
	assert_eq(second.size(), 0, "第二次补登记应为 0 条（幂等）")
	assert_eq(third.size(), 0, "第三次补登记应为 0 条（幂等）")
	assert_eq(
		StageRewardService.pending_for_stage(STAGE_1_9).size(), 1,
		"1-9 的权益必须恰好 1 条"
	)


## 未首通的关卡不得被补登记权益。
func test_backfill_skips_stages_not_first_cleared() -> void:
	var legacy: Dictionary = SaveService.build_default_save()
	legacy.erase("entitlements")
	legacy["stages"]["1-2"] = {"cleared": true, "firstClearClaimed": false, "clearCount": 0}
	assert_true(SaveService.commit(legacy), "旧存档应写入成功")

	var backfilled := StageRewardService.backfill_entitlements()
	assert_eq(backfilled.size(), 0, "未首通的关卡不得补登记权益")
	assert_eq(StageRewardService.pending_for_stage(STAGE_1_2).size(), 0, "不应有 1-2 权益")


# ============================================================
#  ⑥ 重复领取 / 重复兑现：不得复制装备
# ============================================================

func test_fulfill_entitlement_is_idempotent() -> void:
	# 1-9 目前仍是 Phase 0 占位关卡（其 StageConfig 未引用首通奖励），
	# 但 stage_rewards.json 已配置 reward_1_9_first 且含 equipmentId。
	# 因此 1-9 的权益走**旧存档补登记**路径进入（这正是该路径的真实场景）。
	var eid := _grant_1_9_entitlement_via_backfill()
	assert_false(eid.is_empty(), "1-9 应能补登记出 1 条权益")
	assert_eq(
		StageRewardService.pending_for_stage(STAGE_1_9).size(), 1,
		"1-9 应登记 1 条权益"
	)

	assert_true(
		StageRewardService.fulfill_entitlement(eid, "inst_0001", true),
		"首次兑现应成功"
	)
	assert_eq(
		StageRewardService.pending_for_stage(STAGE_1_9).size(), 0,
		"兑现后不应再留在待领取列表"
	)
	assert_eq(
		StageRewardService.fulfilled_entitlements().size(), 1,
		"已兑现列表应有 1 条"
	)

	# 重复兑现必须被拒绝
	assert_false(
		StageRewardService.fulfill_entitlement(eid, "inst_0002", true),
		"重复兑现必须被拒绝（否则会复制装备）"
	)
	_mark_errors_handled()
	assert_eq(
		StageRewardService.fulfilled_entitlements().size(), 1,
		"已兑现列表仍应只有 1 条，不得因重复兑现而增加"
	)

	# 兑现后再补登记，权益也不得复活
	var again := StageRewardService.backfill_entitlements()
	assert_eq(again.size(), 0, "已兑现的权益不得被重新补登记")
	assert_eq(
		StageRewardService.pending_for_stage(STAGE_1_9).size(), 0,
		"已兑现的权益绝不能被重新登记为待领取"
	)
	assert_eq(
		StageRewardService.fulfilled_entitlements().size(), 1,
		"已兑现数量不得变化"
	)


## 兑现记录必须跨重启保持（否则重开后能再领一次）。
func test_fulfilled_entitlement_survives_restart() -> void:
	var eid := _grant_1_9_entitlement_via_backfill()
	assert_false(eid.is_empty(), "1-9 应能补登记出 1 条权益")
	assert_true(StageRewardService.fulfill_entitlement(eid, "inst_0001", true), "兑现应成功")

	var svc := _new_service()
	assert_eq(
		StageRewardService.pending_for_stage(STAGE_1_9).size(), 0,
		"重开后不应出现待领取权益（已兑现）"
	)
	assert_false(
		StageRewardService.fulfill_entitlement(eid, "inst_0002", true),
		"重开后重复兑现仍必须被拒绝"
	)
	_mark_errors_handled()


# ============================================================
#  权益内容正确性
# ============================================================

func test_entitlement_records_required_fields() -> void:
	var cfg: Dictionary = DataRegistry.get_entry("stages", STAGE_1_2)
	StageRewardService.settle(cfg, true, true)
	var pending := StageRewardService.pending_for_stage(STAGE_1_2)
	assert_eq(pending.size(), 1, "应有 1 条权益")
	var e: Dictionary = pending[0]
	# 指令要求：记录 stageId、rewardId、itemId、奖励类型及唯一发放标识
	for field: String in ["stageId", "rewardId", "itemId", "kind", "entitlementId", "source"]:
		assert_true(e.has(field), "权益必须记录字段 %s" % field)
	assert_eq(str(e["stageId"]), STAGE_1_2, "stageId 应为 1-2")
	assert_eq(str(e["rewardId"]), "reward_1_2_first", "rewardId 应为 1-2 首通奖励")
	assert_eq(str(e["itemId"]), EQUIP_1_2, "itemId 应为装备 ID")
	assert_eq(str(e["kind"]), "EQUIPMENT", "kind 应为 EQUIPMENT")
	assert_eq(
		str(e["entitlementId"]),
		StageRewardService.entitlement_id(STAGE_1_2, "reward_1_2_first", "EQUIPMENT", EQUIP_1_2),
		"entitlementId 必须由固定规则推导（保证跨会话稳定）"
	)


## 1-10 的纪念物同样必须被登记（mementoId 路径）。
func test_memento_reward_is_registered_as_entitlement() -> void:
	var legacy: Dictionary = SaveService.build_default_save()
	legacy.erase("entitlements")
	legacy["stages"]["1-10"] = {"cleared": true, "firstClearClaimed": true, "clearCount": 1}
	assert_true(SaveService.commit(legacy), "旧存档应写入成功")

	StageRewardService.backfill_entitlements()
	var pending := StageRewardService.pending_for_stage(STAGE_1_10)
	assert_eq(pending.size(), 1, "1-10 应登记 1 条纪念物权益")
	assert_eq(str(pending[0]["kind"]), "MEMENTO", "kind 应为 MEMENTO")
	assert_eq(str(pending[0]["itemId"]), MEMENTO_BOSS, "itemId 应为 Boss 纪念物 ID")


## 首通货币数值**不得**因本轮加固而改变（指令第九条）。
func test_first_clear_currency_values_unchanged() -> void:
	var cfg: Dictionary = DataRegistry.get_entry("stages", STAGE_1_2)
	var res := StageRewardService.settle(cfg, true, true)
	# 1-2：battleRewards(school_coin 160 + study_record_short 2 + equipment_part 2)
	#       + firstClear(school_coin 300 + study_record_note 1)
	assert_eq(int(res.granted["school_coin"]), 460, "1-2 首通学园币应为 160+300")
	assert_eq(int(res.granted["study_record_short"]), 2, "1-2 短篇应为 2")
	assert_eq(int(res.granted["study_record_note"]), 1, "1-2 笔记应为 1")
	assert_eq(int(res.granted["equipment_part"]), 2, "1-2 装备零件应为 2")


## 表 71 预算口径不得因加固而变化。
func test_budget_total_unchanged_by_hardening() -> void:
	var total := StageRewardService.first_clear_budget_total()
	assert_eq(int(total["club_badge"]), 6, "社团徽章全章应为 6")
	assert_eq(int(total["school_coin"]), 2800, "已配置 5 关的学园币应为 2800")
	assert_eq(int(total["study_record_exp"]), 5000, "已配置 5 关的学习记录应为 5000 EXP")


# ============================================================
#  存档世代：防止"用旧面板覆盖新存档"的静默数据损坏
# ============================================================

## 存档被整体替换（restore / load）时必须递增世代号，
## 否则按旧存档构建的成长服务会被判定为仍然有效，
## 并在下一次提交时把过期等级写回存档。
func test_restore_bumps_generation_so_growth_is_rebuilt() -> void:
	var gen_before := SaveService.save_generation()
	SaveService.restore(SaveService.get_current().duplicate(true))
	assert_gt(
		SaveService.save_generation(), gen_before,
		"restore() 必须递增存档世代号（否则成长服务会用过期面板覆盖新存档）"
	)


## 读档同样必须递增世代号。
func test_load_bumps_generation() -> void:
	var save: Dictionary = SaveService.build_default_save()
	assert_true(SaveService.commit(save), "提交应成功")
	var gen_before := SaveService.save_generation()
	# 直接让**单例**读档（世代号是每个 SaveService 实例自己的状态，
	# 用另一个新实例读档不会改变单例的世代号）。
	assert_true(SaveService.load_game(), "读档应成功")
	assert_gt(
		SaveService.save_generation(), gen_before,
		"load_game() 必须递增存档世代号"
	)


## 端到端：磁盘上有高等级角色时，重启 + 结算**不得**把等级清回 Lv.1。
##
## 这是 tools/verify_a0_4_save_safety.tscn 在实机路径上抓到的真实缺陷：
## restore() 曾不递增世代号，导致按旧（空）存档构建的成长服务在结算时
## 用 Lv.1 覆盖了磁盘上的 Lv.10。
func test_settlement_does_not_clobber_loaded_character_level() -> void:
	var save: Dictionary = SaveService.build_default_save()
	save["progression"]["characters"] = {
		"amamiya_mio": {"level": 10, "exp": 37, "breakthrough": 1},
	}
	assert_true(SaveService.commit(save), "玩家存档应写入成功")

	# 模拟重启
	var svc := _new_service()
	assert_true(svc.load_game(), "读档应成功")
	# 让单例持有这份存档（等价于真实启动路径）
	SaveService.restore(svc.get_current())

	var cfg: Dictionary = DataRegistry.get_entry("stages", "1-1")
	var res := StageRewardService.settle(cfg, true, true)
	assert_true(res.ok, "结算应成功：%s" % res.reason)

	var mio: Dictionary = SaveService.get_current()["progression"]["characters"]["amamiya_mio"]
	assert_eq(
		int(mio["level"]), 10,
		"结算不得把已读入的 Lv.10 覆盖回 Lv.1（成长服务必须按当前世代重建）"
	)
	assert_eq(int(mio["breakthrough"]), 1, "突破阶数同样不得被覆盖")


# ============================================================
#  夹具
# ============================================================

## 新建一个 SaveService 实例并加入场景树，触发其 _ready（= 模拟一次游戏启动）。
func _new_service() -> Node:
	var svc: Node = load("res://scripts/save/save_service.gd").new()
	add_child_autofree(svc)
	return svc


func _pending_item_ids() -> Array:
	var out: Array = []
	for e: Dictionary in StageRewardService.pending_entitlements():
		out.append(str(e.get("itemId", "")))
	return out


## 通过"旧存档补登记"路径取得 1-9 的权益，返回其 entitlementId（失败返回空串）。
##
## 为什么走这条路而不是 settle()：1-9 的 StageConfig 目前仍是 Phase 0 占位，
## `firstClearRewardId` 为空，因此**无法通过结算产生 1-9 的权益**；
## 而 stage_rewards.json 里 `reward_1_9_first` 已配置且带 equipmentId。
## 这个错位本身已作为规格缺口登记在验收报告中。
func _grant_1_9_entitlement_via_backfill() -> String:
	var legacy: Dictionary = SaveService.build_default_save()
	legacy.erase("entitlements")
	legacy["stages"]["1-9"] = {"cleared": true, "firstClearClaimed": true, "clearCount": 1}
	if not SaveService.commit(legacy):
		return ""
	StageRewardService.backfill_entitlements()
	var pending := StageRewardService.pending_for_stage(STAGE_1_9)
	if pending.is_empty():
		return ""
	return str(pending[0]["entitlementId"])


## 把本轮已产生的错误标记为 handled。
## 本文件多处刻意制造损坏存档 / 写盘失败，这些错误是**被测行为**而非缺陷。
func _mark_errors_handled() -> void:
	for e in get_errors():
		e.handled = true


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## 制造写盘失败：把主存档路径替换成一个**目录**，使 FileAccess.open(WRITE) 必然失败。
## 返回是否成功制造出该环境。
func _block_save_path() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	var err := DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	return err == OK


func _unblock_save_path() -> void:
	if DirAccess.dir_exists_absolute(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _cleanup_save_files() -> void:
	_unblock_save_path()
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(BACKUP_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
