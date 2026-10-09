## Phase 0 验收测试：SaveService 存档管线（V2.1.4 L6）
##
## 验证：
##   1) 默认存档含 schema_version 与 flow_state（J0.13 契约字段）
##   2) parse -> validate -> migrate 管线的校验分支正确
##   3) 事务提交写入主存档，且旧存档转为 backup
##   4) backup 回退路径可用
extends GutTest

var _svc: Node


func before_each() -> void:
	# 直接实例化以隔离测试，不依赖 Autoload 的全局状态
	_svc = load("res://scripts/save/save_service.gd").new()
	add_child_autofree(_svc)
	_cleanup_save_files()


func after_each() -> void:
	_cleanup_save_files()


func test_default_save_has_schema_version() -> void:
	var save: Dictionary = _svc.build_default_save()
	assert_true(save.has("schema_version"), "默认存档应含 schema_version")
	assert_eq(int(save["schema_version"]), 1, "Phase 0 schema_version 应为 1")


func test_default_save_has_flow_state_contract() -> void:
	var save: Dictionary = _svc.build_default_save()
	assert_true(save.has("flow_state"), "默认存档应含 flow_state（J0.13）")
	var flow: Dictionary = save["flow_state"]
	for key: String in [
		"mode", "current_story_id", "current_story_node",
		"pending_stage_id", "pending_story_after", "last_stable_screen",
	]:
		assert_true(flow.has(key), "flow_state 应含契约字段: %s" % key)
	assert_eq(str(flow["mode"]), "hub", "初始 mode 应为 hub")


func test_validate_rejects_missing_schema_version() -> void:
	var result: Dictionary = _svc._validate({"flow_state": {}})
	assert_false(result["ok"], "缺少 schema_version 应校验失败")


func test_validate_rejects_missing_flow_state() -> void:
	var result: Dictionary = _svc._validate({"schema_version": 1})
	assert_false(result["ok"], "缺少 flow_state 应校验失败")


func test_validate_rejects_future_schema() -> void:
	var result: Dictionary = _svc._validate({"schema_version": 999, "flow_state": {}})
	assert_false(result["ok"], "来自更高 schema 的存档应校验失败")


func test_validate_accepts_current_schema() -> void:
	var result: Dictionary = _svc._validate({"schema_version": 1, "flow_state": {}})
	assert_true(result["ok"], "当前 schema 的合法存档应通过校验")


func test_commit_writes_main_save() -> void:
	var save: Dictionary = _svc.build_default_save()
	var ok: bool = _svc.commit(save)
	assert_true(ok, "提交应成功")
	assert_true(FileAccess.file_exists("user://save/savegame.json"), "主存档应已写入")


func test_commit_creates_backup_of_previous_save() -> void:
	var first: Dictionary = _svc.build_default_save()
	first["profile"]["playerName"] = "第一次"
	assert_true(_svc.commit(first), "首次提交应成功")

	var second: Dictionary = _svc.build_default_save()
	second["profile"]["playerName"] = "第二次"
	assert_true(_svc.commit(second), "第二次提交应成功")

	assert_true(
		FileAccess.file_exists("user://save/savegame_backup.json"),
		"第二次提交后应存在 backup"
	)
	var backup: Variant = _read_json("user://save/savegame_backup.json")
	assert_not_null(backup, "backup 应可解析")
	if backup != null:
		assert_eq(str(backup["profile"]["playerName"]), "第一次", "backup 应是上一份存档")


func test_load_restores_committed_save() -> void:
	var save: Dictionary = _svc.build_default_save()
	save["profile"]["playerName"] = "恢复测试"
	assert_true(_svc.commit(save), "提交应成功")

	var svc2: Node = load("res://scripts/save/save_service.gd").new()
	add_child_autofree(svc2)
	assert_true(svc2.load_game(), "加载应成功")
	assert_eq(
		str(svc2.get_current()["profile"]["playerName"]), "恢复测试",
		"应恢复出已提交的玩家名"
	)


func test_has_valid_save_rejects_structurally_invalid_file() -> void:
	# 写入一个 JSON 合法但结构不合规的存档（缺 flow_state）
	var f := FileAccess.open("user://save/savegame.json", FileAccess.WRITE)
	f.store_string('{"schema_version": 1}')
	f.close()

	var svc2: Node = load("res://scripts/save/save_service.gd").new()
	add_child_autofree(svc2)
	# A0.4 加固后，SaveService._ready 会尝试把磁盘存档读进内存；
	# 这里刻意放了不合规存档，因此启动加载按设计失败并记录错误日志。
	# 这些是**预期行为**（正是本用例要验证的"不合规存档不被接受"），
	# 取出并标记 handled，避免被 GUT 计为"意外错误"。
	var errs: Array = get_errors()
	assert_gt(errs.size(), 0, "不合规存档在启动加载时应产生错误记录")
	for e in errs:
		e.handled = true

	assert_false(
		svc2.has_valid_save(),
		"JSON 合法但缺 flow_state 的存档不应被视为有效"
	)
	# 关键安全性断言：读取失败**不得**退化成"内存里有一份新档"
	# （否则后续结算会把这份空档写盘，覆盖玩家进度）。
	assert_true(
		svc2.get_current().is_empty(),
		"启动加载失败时内存存档必须保持为空，不得静默建新档"
	)


func test_has_valid_save_accepts_wellformed_file() -> void:
	var save: Dictionary = _svc.build_default_save()
	assert_true(_svc.commit(save), "提交应成功")

	var svc2: Node = load("res://scripts/save/save_service.gd").new()
	add_child_autofree(svc2)
	assert_true(svc2.has_valid_save(), "合规存档应被视为有效")


func test_load_falls_back_to_backup_when_main_corrupted() -> void:
	# 建立有效主存档 + backup
	var first: Dictionary = _svc.build_default_save()
	first["profile"]["playerName"] = "备份里的人"
	assert_true(_svc.commit(first), "首次提交应成功")
	var second: Dictionary = _svc.build_default_save()
	second["profile"]["playerName"] = "将被破坏的人"
	assert_true(_svc.commit(second), "第二次提交应成功")

	# 故意破坏主存档（此步会触发预期的 push_error，属被测行为而非缺陷）
	var f := FileAccess.open("user://save/savegame.json", FileAccess.WRITE)
	f.store_string("{ 这不是合法 JSON ")
	f.close()

	var svc2: Node = load("res://scripts/save/save_service.gd").new()
	add_child_autofree(svc2)
	var recovered: bool = svc2.load_game()

	# 本测试刻意制造了损坏存档，加载路径会按设计记录错误日志（_ready 的
	# has_valid_save 与 load_game 各一次）。这些是预期行为而非缺陷：
	# 取出本轮全部错误并标记 handled，避免被 GUT 计为"意外错误"。
	var errs: Array = get_errors()
	assert_gt(errs.size(), 0, "损坏存档应产生错误记录（证明错误路径被走到）")
	for e in errs:
		e.handled = true

	assert_true(recovered, "主存档损坏时应能从 backup 恢复")
	assert_eq(
		str(svc2.get_current()["profile"]["playerName"]), "备份里的人",
		"应恢复 backup 中的内容"
	)


func _cleanup_save_files() -> void:
	for p: String in ["user://save/savegame.json", "user://save/savegame_backup.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data
