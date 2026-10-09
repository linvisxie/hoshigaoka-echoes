## Alpha A0.4 加固验收工具：存档安全性与待领取权益端到端校验。
##
## **为什么是场景而不是 --script**：`--script` 模式不加载 Autoload，
## 因此 `SaveService` 等全局标识符在编译期不可解析（既有
## tools/verify_a0_4_economy.gd 的注释亦已记录这一点，它只能自行实例化数据加载）。
## 本轮要验证的恰恰是**真实 Autoload 启动路径**下的存档行为，所以必须走场景：
## Autoload 正常加载 → 本节点 _ready 在帧末执行校验 → 打印结果 → 退出。
##
## 覆盖：
##   [1] 启动读档：磁盘有进度时，重启后内存必须反映它（致命缺陷回归）
##   [2] 结算叠加：结算建立在既有进度之上，而不是覆盖
##   [3] 待领取权益：登记 stageId/rewardId/itemId/kind/唯一标识
##   [4] 幂等：重复结算不重复登记权益
##   [5] 兑现：可兑现为实例，重复兑现被拒绝（不复制装备）
##   [6] 旧存档升级：补登记权益且重复补登记为 0
##   [7] 预算口径：表 71 首通预算不因加固而改变
##
## **纪律：必须在 APPDATA 重定向到 _testenv 的前提下运行**，工具会自检隔离，
## 未隔离则直接中止（退出码 2），绝不触碰正式用户存档。
##
## 用法：
##   $env:APPDATA = 'D:\星丘残响\_testenv\appdata'
##   godot --headless --path . res://tools/verify_a0_4_save_safety.tscn
extends Node

const SAVE_PATH := "user://save/savegame.json"
const BACKUP_PATH := "user://save/savegame_backup.json"
const ISOLATION_MARKER := "_testenv"

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	print("=== Alpha A0.4 存档安全性与待领取权益 · 端到端校验 ===")
	print("")

	if not _assert_isolation():
		print("!! 环境隔离未生效，已中止（绝不触碰正式用户存档）")
		_quit(2)
		return

	# 等一帧，确保全部 Autoload 的 _ready（含 deferred 初始化）都已完成
	await get_tree().process_frame

	_check_budget()
	# 注意：_check_startup_load 内部有 await，是协程。必须 await 它，
	# 否则会立刻返回、让后续检查插到它前面，输出顺序与证据归属都会错乱。
	await _check_startup_load()
	_check_entitlement_flow()
	_check_backfill_idempotent()

	print("")
	print("=== 结果：%d 项检查，%d 项失败 ===" % [_checks, _failures])
	_quit(0 if _failures == 0 else 1)


func _quit(code: int) -> void:
	get_tree().quit(code)


# ============================================================
#  环境隔离自检
# ============================================================

func _assert_isolation() -> bool:
	var ud := OS.get_user_data_dir().replace("\\", "/")
	print("[隔离] 用户数据目录: %s" % ud)
	if not ud.contains(ISOLATION_MARKER):
		print("[隔离] **失败**：路径不含 '%s'，说明 APPDATA 未重定向。" % ISOLATION_MARKER)
		return false
	print("[隔离] 通过：APPDATA 已重定向到测试目录")
	print("")
	return true


# ============================================================
#  [7] 预算口径
# ============================================================

func _check_budget() -> void:
	print("[7] 表 71 首通预算口径（不因本轮加固而改变）")
	var total: Dictionary = StageRewardService.first_clear_budget_total()
	print("    学园币 %d ｜ 学习记录 %d EXP ｜ 徽章 %d ｜ 结晶 %d ｜ 零件 %d"
		% [int(total["school_coin"]), int(total["study_record_exp"]),
			int(total["club_badge"]), int(total["echo_crystal"]),
			int(total["equipment_part"])])
	print("    尚未配置奖励的关卡: %s" % str(total["missing"]))
	_expect_eq(int(total["school_coin"]), 2800, "已配置 5 关的学园币应为 2800")
	_expect_eq(int(total["study_record_exp"]), 5000, "已配置 5 关的学习记录应为 5000 EXP")
	_expect_eq(int(total["club_badge"]), 6, "社团徽章应为 6")
	print("")


# ============================================================
#  [1][2] 启动读档 + 结算叠加
# ============================================================

func _check_startup_load() -> void:
	print("[1][2] 启动读档 + 结算叠加既有进度")
	_cleanup()

	# 造一份"玩家进度"存档并落盘
	var player: Dictionary = SaveService.build_default_save()
	player["profile"]["playerName"] = "验收玩家"
	player["currencies"]["school_coin"] = 999
	player["progression"]["characters"] = {
		"amamiya_mio": {"level": 10, "exp": 37, "breakthrough": 1},
	}
	player["stages"]["1-1"] = {"cleared": true, "firstClearClaimed": true, "clearCount": 3}
	_expect_true(SaveService.commit(player), "玩家存档写入成功")

	# 重新实例化一个 SaveService 并触发 _ready = 模拟一次重启
	var fresh: Node = load("res://scripts/save/save_service.gd").new()
	add_child(fresh)
	await get_tree().process_frame

	var cur: Dictionary = fresh.get_current()
	_expect_false(cur.is_empty(), "重启后内存存档不为空（修复前此处恒为空）")
	if cur.is_empty():
		fresh.queue_free()
		print("")
		return
	_expect_str_eq(str(cur["profile"]["playerName"]), "验收玩家", "重启后读回玩家名")
	_expect_eq(int(cur["currencies"]["school_coin"]), 999, "重启后读回学园币 999")
	_expect_eq(int(cur["stages"]["1-1"]["clearCount"]), 3, "重启后读回 1-1 通关次数 3")

	# 让 SaveService 单例持有同一份存档，供结算使用
	SaveService.restore(cur)

	# 结算 1-1：已首通 → 发重复奖励；**不得**清空既有进度
	var cfg: Dictionary = DataRegistry.get_entry("stages", "1-1")
	var res: RefCounted = StageRewardService.settle(cfg, true, true)
	_expect_true(res.ok, "1-1 结算成功：%s" % res.reason)
	var after: Dictionary = SaveService.get_current()
	# battleRewards 160 + repeat 60 = 220
	_expect_eq(int(after["currencies"]["school_coin"]), 999 + 220,
		"结算后学园币 = 既有 999 + 本次 220（而不是被清成 220）")
	_expect_eq(int(after["progression"]["characters"]["amamiya_mio"]["level"]), 10,
		"结算不得清空既有角色等级")
	_expect_true(bool(after["stages"]["1-1"]["firstClearClaimed"]), "1-1 首通标记保持")
	fresh.queue_free()
	print("")


# ============================================================
#  [3][4][5] 权益登记 / 幂等 / 兑现
# ============================================================

func _check_entitlement_flow() -> void:
	print("[3][4][5] 待领取权益：登记 / 幂等 / 兑现")
	_cleanup()
	SaveService.new_game()

	# 1-2 首通含 equipmentId = equip_ch1_1_2_fine_weapon
	var cfg: Dictionary = DataRegistry.get_entry("stages", "1-2")
	var first: RefCounted = StageRewardService.settle(cfg, true, true)
	_expect_true(first.ok and first.first_clear, "1-2 首次结算为首通")
	var pending: Array = StageRewardService.pending_for_stage("1-2")
	_expect_eq(pending.size(), 1, "1-2 登记 1 条待领取权益")
	if pending.is_empty():
		print("")
		return
	var e: Dictionary = pending[0]
	print("    权益: kind=%s itemId=%s rewardId=%s" % [
		e.get("kind", "?"), e.get("itemId", "?"), e.get("rewardId", "?")])
	print("    唯一标识: %s" % e.get("entitlementId", "?"))
	_expect_str_eq(str(e["itemId"]), "equip_ch1_1_2_fine_weapon", "权益 itemId 正确")
	_expect_str_eq(str(e["kind"]), "EQUIPMENT", "权益 kind 为 EQUIPMENT")
	_expect_str_eq(str(e["rewardId"]), "reward_1_2_first", "权益 rewardId 正确")
	_expect_str_eq(str(e["stageId"]), "1-2", "权益 stageId 正确")

	# 重复结算两次：不得重复登记
	StageRewardService.settle(cfg, true, true)
	StageRewardService.settle(cfg, true, true)
	_expect_eq(StageRewardService.pending_for_stage("1-2").size(), 1,
		"重复结算不得重复登记权益")
	_expect_eq(StageRewardService.clear_count("1-2"), 3, "通关次数累计为 3")

	# 兑现
	var eid := str(e["entitlementId"])
	_expect_true(StageRewardService.fulfill_entitlement(eid, "inst_verify_0001", true),
		"首次兑现成功")
	_expect_eq(StageRewardService.pending_for_stage("1-2").size(), 0, "兑现后移出待领取")
	_expect_eq(StageRewardService.fulfilled_entitlements().size(), 1, "已兑现列表 1 条")
	_expect_false(StageRewardService.fulfill_entitlement(eid, "inst_verify_0002", true),
		"重复兑现被拒绝（不复制装备）")
	_expect_eq(StageRewardService.fulfilled_entitlements().size(), 1, "已兑现列表仍为 1 条")
	print("")


# ============================================================
#  [6] 旧存档升级
# ============================================================

func _check_backfill_idempotent() -> void:
	print("[6] 旧存档升级：补登记权益且不重复")
	_cleanup()

	# 构造旧结构：无 entitlements 段，但已首通 1-2 / 1-9 / 1-10
	var legacy: Dictionary = SaveService.build_default_save()
	legacy.erase("entitlements")
	legacy["currencies"]["school_coin"] = 2800
	for sid: String in ["1-2", "1-9", "1-10"]:
		legacy["stages"][sid] = {"cleared": true, "firstClearClaimed": true, "clearCount": 1}
	_expect_true(SaveService.commit(legacy), "旧存档写入成功")

	var coin_before := int(SaveService.get_current()["currencies"]["school_coin"])
	var b1: Array = StageRewardService.backfill_entitlements()
	var b2: Array = StageRewardService.backfill_entitlements()
	print("    首次补登记 %d 条，第二次 %d 条" % [b1.size(), b2.size()])
	for entry: Dictionary in b1:
		print("      + %s（%s，%s）" % [entry.get("itemId", "?"),
			entry.get("kind", "?"), entry.get("stageId", "?")])
	_expect_eq(b1.size(), 3, "应补登记 3 条（1-2 武器 + 1-9 稀有饰品 + 1-10 纪念物）")
	_expect_eq(b2.size(), 0, "重复补登记必须为 0 条（幂等）")
	_expect_eq(int(SaveService.get_current()["currencies"]["school_coin"]), coin_before,
		"补登记不得发放任何货币")
	print("")


# ============================================================
#  断言与夹具
# ============================================================

func _expect_true(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("    [PASS] %s" % label)
	else:
		_failures += 1
		print("    [FAIL] %s" % label)


func _expect_false(cond: bool, label: String) -> void:
	_expect_true(not cond, label)


func _expect_eq(actual: int, expected: int, label: String) -> void:
	_checks += 1
	if actual == expected:
		print("    [PASS] %s（%d）" % [label, actual])
	else:
		_failures += 1
		print("    [FAIL] %s：期望 %d，实际 %d" % [label, expected, actual])


func _expect_str_eq(actual: String, expected: String, label: String) -> void:
	_checks += 1
	if actual == expected:
		print("    [PASS] %s（%s）" % [label, actual])
	else:
		_failures += 1
		print("    [FAIL] %s：期望 '%s'，实际 '%s'" % [label, expected, actual])


func _cleanup() -> void:
	for p: String in [SAVE_PATH, BACKUP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
