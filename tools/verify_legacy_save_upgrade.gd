## 一次性验收场景：用**正式用户存档的副本**验证旧档兼容与不被覆盖。
##
## 复现真实场景：
##   正式存档是**旧结构**（无 entitlements 段），且 1-1 已首通。
##   修复前：启动不读档 → 结算用新档覆盖 → 玩家进度全失。
##   修复后：启动读回该档；结算叠加在它之上；1-1 已首通走重复奖励；
##           1-1 无装备奖励故不产生权益，但货币与通关记录必须原样保留。
##
## 用法（必须先复制正式存档副本，且 APPDATA 已重定向）：
##   godot --headless --path . res://tools/verify_legacy_save_upgrade.tscn
extends Node

const SAVE_PATH := "user://save/savegame.json"
const ISOLATION_MARKER := "_testenv"

var _checks := 0
var _failures := 0


func _ready() -> void:
	print("=== 正式存档副本 · 旧档兼容与不被覆盖验收 ===")
	var ud := OS.get_user_data_dir().replace("\\", "/")
	if not ud.contains(ISOLATION_MARKER):
		print("!! 未隔离，中止")
		get_tree().quit(2)
		return
	await get_tree().process_frame

	# ---- 记录"启动前"磁盘内容 ----
	var disk_before := _read_dict(SAVE_PATH)
	if disk_before.is_empty():
		print("!! 测试目录里没有预置的正式存档副本，中止")
		get_tree().quit(2)
		return
	var coin_before := int((disk_before.get("currencies", {}) as Dictionary).get("school_coin", -1))
	var stages_before: Dictionary = disk_before.get("stages", {})
	print("[启动前] school_coin=%d ｜ 1-1=%s ｜ 含 entitlements=%s" % [
		coin_before, str(stages_before.get("1-1", {})),
		str(disk_before.has("entitlements"))])

	# ---- 检查启动后内存是否读回了它 ----
	var mem: Dictionary = SaveService.get_current()
	_expect_false(mem.is_empty(), "启动后内存存档不为空（修复前恒为空）")
	_expect_eq(int((mem.get("currencies", {}) as Dictionary).get("school_coin", -1)),
		coin_before, "启动后内存学园币与磁盘一致")
	var st: Dictionary = (mem.get("stages", {}) as Dictionary).get("1-1", {})
	_expect_true(bool(st.get("firstClearClaimed", false)), "启动后 1-1 首通标记保持")
	_expect_eq(int(st.get("clearCount", -1)),
		int((stages_before.get("1-1", {}) as Dictionary).get("clearCount", -2)),
		"启动后 1-1 通关次数保持")

	# ---- 结算 1-1（已首通 → 重复奖励）----
	var cfg: Dictionary = DataRegistry.get_entry("stages", "1-1")
	var res: RefCounted = StageRewardService.settle(cfg, true, true)
	_expect_true(res.ok, "1-1 结算成功")
	var after: Dictionary = SaveService.get_current()
	# battleRewards 160 + repeat 60 = 220
	_expect_eq(int((after.get("currencies", {}) as Dictionary).get("school_coin", -1)),
		coin_before + 220, "结算后学园币 = 既有 + 220（而不是被清成 220）")
	_expect_true(bool(((after.get("stages", {}) as Dictionary).get("1-1", {}) as Dictionary)
		.get("firstClearClaimed", false)), "结算后 1-1 首通标记仍保持")
	# 注意：1-1 的首通奖励只有货币，**没有** equipmentId / mementoId，
	# 因此本关不会登记任何权益，entitlements 段也不会被创建——这是正确行为
	# （不为"没有可登记内容"的关卡凭空造一个空段）。
	# 真正要验证的是：该旧档上的权益回填必须**产出 0 条**，不得凭空发装备。
	var backfilled: Array = StageRewardService.backfill_entitlements()
	_expect_eq(backfilled.size(), 0,
		"该旧档只首通 1-1（无装备奖励），权益回填必须为 0 条（不得凭空发装备）")
	_expect_eq(StageRewardService.pending_entitlements().size(), 0,
		"待领取权益总数必须为 0")

	# ---- 写盘后磁盘内容核对 ----
	var disk_after := _read_dict(SAVE_PATH)
	_expect_eq(int((disk_after.get("currencies", {}) as Dictionary).get("school_coin", -1)),
		coin_before + 220, "磁盘上的学园币也应为 既有 + 220")
	var st_after: Dictionary = (disk_after.get("stages", {}) as Dictionary).get("1-1", {})
	_expect_eq(int(st_after.get("clearCount", -1)),
		int((stages_before.get("1-1", {}) as Dictionary).get("clearCount", -2)) + 1,
		"磁盘上 1-1 通关次数应 +1")
	print("[写盘后] school_coin=%d ｜ 1-1=%s ｜ 含 entitlements=%s" % [
		int((disk_after.get("currencies", {}) as Dictionary).get("school_coin", -1)),
		str(st_after), str(disk_after.has("entitlements"))])

	print("")
	print("=== 结果：%d 项检查，%d 项失败 ===" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


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


func _read_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t := f.get_as_text()
	f.close()
	var p := JSON.new()
	if p.parse(t) != OK:
		return {}
	if typeof(p.data) != TYPE_DICTIONARY:
		return {}
	return p.data
