## Alpha A0.7 测试：关卡选择画面（GUT 验收）。
##
## 覆盖范围：
##   1. 场景资源存在且可加载（stage_select.tscn / .gd）；
##   2. SceneRouter.SCENES 含 stage_select 且路径真实存在；bootstrap.BOOT_TARGETS 亦然；
##   3. 可进关卡列表**只含 enemySpawnTimeline 非空**的关卡（1-6～1-10 空占位不得出现）；
##   4. 解锁规则是纯函数：1-1 恒真、1-5 在 1-4 未通时为假、1-4 通后为真；
##   5. Retail 与 Prototype 的直选差异（用可注入的 build mode 判定，不依赖 OS.has_feature）；
##   6. 每行显示规格（标题 / 首通状态 / 徽标 / 灰显）与「不虚构」纪律；
##   7. 场景行集合与纯函数算出的数据源逐项一致（.tscn 缺行会被现场补建）；
##   8. 标题画面 MENU_ITEMS 含 stage_select，且 5 行菜单与提示行 / 版本行不重叠；
##   9. 关卡选择不写存档（只读纪律，静态检查）。
##
## 纪律：
##   - 本文件**只读存档**：锁定的解锁/首通断言全部使用**假 lookup**，
##     真实存档只经 StageRewardService.is_first_cleared 被当作 Callable 传参；
##     绝不写存档、绝不调用 SaveService.commit() / new_game()、绝不新增存档字段；
##   - 纯函数断言不实例化场景；只有「场景结构」用例才实例化，且一律 autofree。
extends GutTest

const STAGE_SELECT_SCENE := "res://scenes/menus/stage_select.tscn"
const STAGE_SELECT_SCRIPT := "res://scenes/menus/stage_select.gd"
const TITLE_SCENE := "res://scenes/title/title.tscn"
const TITLE_SCRIPT := "res://scenes/title/title.gd"

## Alpha A0.3 已填充内容的五关（enemySpawnTimeline 非空）
const IMPLEMENTED: Array[String] = ["1-1", "1-2", "1-3", "1-4", "1-5"]
## Phase 0 空占位关卡（enemySpawnTimeline 为空）——**不得**出现在可进列表里
const PLACEHOLDERS: Array[String] = ["1-6", "1-7", "1-8", "1-9", "1-10"]

## 与 stage_select.gd 对齐的常量（避免在测试里对实例做常量动态取用）
const BACK_ID := "__back__"
const ALPHA_BADGE := "Alpha 预览 · 未按主线解锁"

## 标题画面布局预算常量（与 title.gd 对齐，用于重叠核算）
const MENU_TOP := 436.0
const MENU_ROW_H := 80.0
const MENU_GAP := 20.0
const HINT_BASELINE := 1080.0 - 116.0
const HINT_SIZE := 26.0
const VERSION_BASELINE := 1080.0 - 48.0
const TITLE_SUB_BASELINE := 392.0


func after_each() -> void:
	# 每例结束后恢复生产判定（读 BuildMode），避免注入值泄漏到其它测试文件。
	_set_override(-1)


# ============================================================
#  注入辅助（不真读 OS.has_feature）
# ============================================================

func _script() -> GDScript:
	return load(STAGE_SELECT_SCRIPT) as GDScript


func _set_override(value: int) -> void:
	_script().build_mode_override = value


func _get_override() -> int:
	return int(_script().build_mode_override)


func _allow_direct() -> bool:
	return bool(_script().direct_select_allowed())


## 假首通查询：只有传入列表中的 id 返回 true。**完全不接触存档。**
static func _fake_cleared(cleared: Array) -> Callable:
	return func(stage_id: String) -> bool:
		return cleared.has(stage_id)


## 恒 false / 恒 true 的查询
static func _never() -> Callable:
	return func(_stage_id: String) -> bool: return false


static func _always() -> Callable:
	return func(_stage_id: String) -> bool: return true


## 从磁盘读关卡正文（绕开 DataRegistry 的内存副本，避免跨文件执行顺序影响）
func _stage_from_file(stage_id: String) -> Dictionary:
	var path := "res://data/stages/ch1/%s.json" % stage_id
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


# ============================================================
#  用例 1：场景资源存在且可加载
# ============================================================

func test_01_stage_select_scene_exists_and_loads() -> void:
	assert_true(ResourceLoader.exists(STAGE_SELECT_SCENE),
		"关卡选择场景 %s 应存在" % STAGE_SELECT_SCENE)
	assert_true(ResourceLoader.exists(STAGE_SELECT_SCRIPT),
		"关卡选择脚本 %s 应存在" % STAGE_SELECT_SCRIPT)

	var packed: Resource = load(STAGE_SELECT_SCENE)
	assert_not_null(packed, "关卡选择场景应能被 load() 解析")
	assert_true(packed is PackedScene, "关卡选择场景应加载为 PackedScene")

	var instance: Node = null
	if packed is PackedScene:
		instance = (packed as PackedScene).instantiate()
	assert_not_null(instance, "关卡选择场景应能实例化")
	if instance == null:
		return
	assert_true(instance is Control, "关卡选择根节点应为 Control")
	assert_not_null(instance.get_node_or_null("MenuList"), "关卡选择场景应含 MenuList 容器")
	instance.free()


# ============================================================
#  用例 2：路由接线
# ============================================================

func test_02_scene_router_and_bootstrap_register_stage_select() -> void:
	var scenes: Dictionary = (load("res://scripts/app/scene_router.gd") as GDScript).SCENES
	assert_true(scenes.has("stage_select"), "SceneRouter.SCENES 应登记 stage_select")
	assert_eq(str(scenes.get("stage_select", "")), STAGE_SELECT_SCENE,
		"stage_select 应指向关卡选择场景")
	assert_true(ResourceLoader.exists(STAGE_SELECT_SCENE),
		"SceneRouter 登记的路径必须真实存在（不得只登记不落地）")

	var targets: Dictionary = (load("res://scripts/app/bootstrap.gd") as GDScript).BOOT_TARGETS
	assert_true(targets.has("stage_select"),
		"bootstrap.BOOT_TARGETS 应登记 stage_select（便于 --scene=stage_select 自动化）")
	assert_eq(str(targets.get("stage_select", "")), STAGE_SELECT_SCENE,
		"BOOT_TARGETS 的 stage_select 应与 SceneRouter 指向同一资源")

	# 既有登记不得被本阶段改动（回归）
	for key: String in ["battle", "character", "title", "bootstrap", "home"]:
		assert_true(scenes.has(key), "SceneRouter.SCENES 应仍然登记 %s" % key)


# ============================================================
#  用例 3：可进关卡列表只含真实有内容的关卡
# ============================================================

func test_03_implemented_list_excludes_empty_placeholders() -> void:
	var script := _script()
	var ids: Array = ["1-1", "1-2", "1-3", "1-4", "1-5", "1-6", "1-7", "1-8", "1-9", "1-10"]
	var lookup := func(sid: String) -> Dictionary: return _stage_from_file(sid)

	var got: Array = script.implemented_stage_ids(ids, lookup)
	assert_eq(got, IMPLEMENTED, "可进关卡列表应为 1-1～1-5 且升序（实际 %s）" % str(got))

	for sid: String in PLACEHOLDERS:
		assert_false(got.has(sid),
			"占位关卡 %s（enemySpawnTimeline 为空）**不得**出现在可进列表中" % sid)
		var cfg := _stage_from_file(sid)
		assert_false(cfg.is_empty(), "前提校验：占位关卡 %s 的文件仍应存在" % sid)
		assert_eq((cfg.get("enemySpawnTimeline", []) as Array).size(), 0,
			"前提校验：%s 的 enemySpawnTimeline 确实为空（否则用例失去意义）" % sid)

	# 每张被列出的关卡确实有出怪内容
	for sid: String in got:
		assert_true(bool(script.is_implemented(_stage_from_file(sid))),
			"被列出的关卡 %s 必须有真实内容（enemySpawnTimeline 非空）" % sid)

	# 非法 id / 取不到配置的 id 不得被列出
	var none: Array = script.implemented_stage_ids(["", "1-x", "battle"], lookup)
	assert_eq(none.size(), 0, "非法 id 与取不到配置的 id 都不得被列出（实际 %s）" % str(none))
	assert_eq(got.size(), 5, "应恰好列出 5 关（实际 %d）" % got.size())


# ============================================================
#  用例 4：解锁规则（纯函数 + 假 lookup）
# ============================================================

func test_04_unlock_rule_is_pure_and_conservative() -> void:
	var script := _script()

	# 1-1 恒可进（无论存档如何）
	assert_true(bool(script.is_unlocked("1-1", _never())), "1-1 应恒可进（无前置）")
	assert_true(bool(script.is_unlocked("1-1", _always())), "1-1 在任意存档下同样可进")

	# 其余关卡需上一关首通
	assert_false(bool(script.is_unlocked("1-2", _never())), "1-2 在 1-1 未首通时应为未解锁")
	assert_true(bool(script.is_unlocked("1-2", _fake_cleared(["1-1"]))),
		"1-1 首通后 1-2 应解锁")

	# 1-5：1-4 未通时为假，1-4 通后为真
	assert_false(bool(script.is_unlocked("1-5", _never())), "1-5 在 1-4 未首通时应为未解锁")
	assert_false(bool(script.is_unlocked("1-5", _fake_cleared(["1-1", "1-2", "1-3"]))),
		"只通到 1-3 时 1-5 仍应未解锁（必须**恰好**是上一关）")
	assert_true(bool(script.is_unlocked("1-5", _fake_cleared(["1-4"]))),
		"1-4 首通后 1-5 应解锁（只看上一关，不要求前面全部通关）")

	# 第一章以外无规格依据 -> 不猜，一律未解锁
	assert_false(bool(script.is_unlocked("2-1", _always())),
		"第二章关卡的解锁条件无规格依据，应视为未解锁")
	assert_false(bool(script.is_unlocked("", _always())), "空 id 不得解锁")
	assert_false(bool(script.is_unlocked("1-x", _always())), "非法 id 不得解锁")

	# 未解锁原因必须点明缺什么条件
	assert_eq(str(script.locked_reason("1-5")), "需先通关 1-4",
		"1-5 的未解锁原因应指出前置关卡")
	assert_eq(str(script.locked_reason("1-1")), "", "1-1 无前置，不应有未解锁原因")


# ============================================================
#  用例 5：Retail 与 Prototype 的直选差异
# ============================================================

func test_05_retail_vs_prototype_direct_select_difference() -> void:
	var script := _script()
	var never := _never()

	# ---- Retail（注入 0）：直选关闭，严格按解锁规则 ----
	_set_override(0)
	assert_eq(_get_override(), 0, "注入应生效（Retail）")
	assert_false(_allow_direct(), "Retail 构建不得允许直选已实现关卡")
	assert_false(bool(script.is_selectable("1-5", never, false)),
		"Retail 下 1-5 未解锁即不可进入")
	var retail_spec: Dictionary = script.row_spec("1-5", never, false)
	assert_true(bool(retail_spec["disabled"]), "Retail 下未解锁行应灰显不可点")
	assert_eq(str(retail_spec["disabledNote"]), "需先通关 1-4",
		"Retail 下未解锁行应给出缺失条件")
	assert_eq(str(retail_spec["badge"]), "", "Retail 下未解锁行不应打预览徽标")

	# ---- Prototype（注入 1）：直选开启，但**必须**打诚实徽标 ----
	_set_override(1)
	assert_eq(_get_override(), 1, "注入应生效（Prototype）")
	assert_true(_allow_direct(), "Prototype 构建应允许直选已实现关卡（供项目所有者验收 1-5）")
	assert_true(bool(script.is_selectable("1-5", never, true)), "Prototype 下 1-5 应可直接进入")
	var proto_spec: Dictionary = script.row_spec("1-5", never, true)
	assert_false(bool(proto_spec["disabled"]), "Prototype 下直选行应可点")
	assert_eq(str(proto_spec["badge"]), ALPHA_BADGE,
		"Prototype 直选行必须标注「%s」，不得伪装成已解锁" % ALPHA_BADGE)
	assert_true(bool(proto_spec["badgeWarn"]), "预览徽标应使用警示色（诚实可辨）")
	assert_eq(str(proto_spec["status"]), "未通关",
		"Prototype 直选行的首通状态仍应如实显示为「未通关」")

	# ---- 已解锁行在两种直选口径下规格一致（解锁状态不因构建模式而改变） ----
	# 1-1 恒可进，因此它是检验「已解锁行不带徽标」的最佳样本；
	# 1-4 在 1-3 已首通时同样已解锁。
	var cleared_1_3 := _fake_cleared(["1-3"])
	for sid: String in ["1-1", "1-4"]:
		var a: Dictionary = script.row_spec(sid, cleared_1_3, false)
		var b: Dictionary = script.row_spec(sid, cleared_1_3, true)
		assert_eq(str(a["badge"]), "", "%s 已解锁行不应带预览徽标" % sid)
		assert_false(bool(a["disabled"]), "%s 已解锁行不应灰显" % sid)
		assert_eq(str(a["badge"]), str(b["badge"]),
			"%s 已解锁行不应因直选口径而改变徽标" % sid)
	assert_eq(str(script.row_spec("1-4", cleared_1_3, false)["status"]), "未通关",
		"1-4 自身未首通时应如实显示「未通关」（解锁状态与首通状态是两件事）")

	_set_override(-1)


# ============================================================
#  用例 6：行规格「不虚构」纪律
# ============================================================

func test_06_row_spec_does_not_fabricate() -> void:
	var script := _script()
	var never := _never()

	# 标题：必须自含关卡 id；StageConfig 里**没有**关卡名/推荐等级字段，因此不得编造。
	var spec: Dictionary = script.row_spec("1-5", never, false)
	assert_eq(str(spec["title"]), "关卡 1-5", "标题应为「关卡 <id>」")
	assert_eq(str(spec["subtitle"]), "",
		"StageConfig 无机器可读的关卡名/副标，不得编造副标题")
	assert_eq(str(spec["id"]), "1-5", "行 id 应与关卡 id 一致")

	# 推荐等级：数据里不存在该字段，规格要求「没有就不显示」
	for sid: String in IMPLEMENTED:
		var cfg := _stage_from_file(sid)
		assert_false(cfg.has("_recommendedLevel"),
			"前提校验：%s 不应存在 _recommendedLevel（若数据层补齐，本用例应随之改写）" % sid)
	assert_false(spec.has("recommendedLevel"),
		"行规格不得包含任何推荐等级字段（数据里没有，不得编造）")

	# 首通状态二值且与 lookup 一致
	assert_eq(str(script.row_spec("1-3", _fake_cleared(["1-3"]), false)["status"]), "已通关",
		"首通查询为真时应显示「已通关」")
	assert_eq(str(script.row_spec("1-3", never, false)["status"]), "未通关",
		"首通查询为假时应显示「未通关」")


# ============================================================
#  用例 7：场景行集合与数据源一致
# ============================================================

func test_07_scene_rows_match_data_source() -> void:
	# 注入 Prototype 模式让场景真实构建一次：断言「界面上的行」与「纯函数算出的行」
	# 逐项一致（.tscn 缺行会被现场补建，但行集合本身不得有遗漏或多余）。
	_set_override(1)
	var packed: PackedScene = load(STAGE_SELECT_SCENE) as PackedScene
	var inst: Node = packed.instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	var specs: Array = inst.get("_specs")
	assert_eq(specs.size(), IMPLEMENTED.size() + 1,
		"行数应为「已实现关卡数 + 1 行返回标题」（实际 %d）" % specs.size())

	# 关卡行必须恰好是已实现关卡且升序；最后一行是返回标题
	var stage_rows: Array = []
	for spec_v: Variant in specs:
		var spec: Dictionary = spec_v
		if str(spec["id"]) != BACK_ID:
			stage_rows.append(str(spec["id"]))
	assert_eq(stage_rows, IMPLEMENTED,
		"界面上的关卡行应为 1-1～1-5 且升序（实际 %s）" % str(stage_rows))
	assert_eq(str((specs[specs.size() - 1] as Dictionary)["id"]), BACK_ID,
		"最后一行应为「返回标题」")
	assert_false(bool((specs[specs.size() - 1] as Dictionary)["disabled"]),
		"「返回标题」行必须可点")

	var container := inst.get_node_or_null("MenuList") as Control
	assert_not_null(container, "应存在 MenuList 容器")
	if container == null:
		_set_override(-1)
		return

	var row_nodes := 0
	for child: Node in container.get_children():
		if child is TitleMenuRow:
			row_nodes += 1
	assert_eq(row_nodes, specs.size(),
		".tscn 声明/补建的行节点数（%d）应与数据源行数（%d）一致" % [row_nodes, specs.size()])

	# Prototype 下未解锁的 1-5 可点，但徽标必须存在（诚实标注）
	var row_1_5 := container.get_node_or_null("Row_1-5") as TitleMenuRow
	assert_not_null(row_1_5, "应存在 Row_1-5 节点")
	if row_1_5 != null:
		assert_false(row_1_5.disabled, "Prototype 下 Row_1-5 应可点")
		assert_eq(row_1_5.extra_note, ALPHA_BADGE, "Row_1-5 必须标注「%s」" % ALPHA_BADGE)

	_set_override(-1)


# ============================================================
#  用例 8：标题画面接线与垂直预算
# ============================================================

func test_08_title_menu_has_stage_select_and_no_overlap() -> void:
	var consts: Dictionary = (load(TITLE_SCRIPT) as GDScript).get_script_constant_map()
	var items: Array = consts["MENU_ITEMS"]

	# 5 行、含 stage_select、无重复 id
	var ids: Array[String] = []
	var has_stage_select := false
	for item_v: Variant in items:
		var item: Dictionary = item_v
		var id := str(item["id"])
		assert_false(ids.has(id), "MENU_ITEMS 不应有重复 id：%s" % id)
		ids.append(id)
		if id == "stage_select":
			has_stage_select = true
			assert_false(bool(item["disabled"]), "「关卡选择」必须是可点项")
			assert_eq(str(item["zh"]), "关卡选择", "中文标签应为「关卡选择」")
			assert_eq(str(item["en"]), "STAGE SELECT", "英文标签应为 STAGE SELECT")
	assert_true(has_stage_select, "标题菜单应含 stage_select 项")
	assert_eq(items.size(), 5, "标题菜单应为 5 行（实际 %d）" % items.size())

	# 「继续游戏 / 新游戏」既有行为不得改动
	assert_eq(str((items[0] as Dictionary)["id"]), "continue", "第 1 行应仍为继续游戏")
	assert_eq(str((items[1] as Dictionary)["id"]), "new_game", "第 2 行应仍为新游戏")
	assert_true(bool((items[3] as Dictionary)["disabled"]), "设置行应仍为禁用态（未实现）")
	assert_eq(str((items[4] as Dictionary)["id"]), "quit", "最后一行应仍为退出游戏")

	# 布局常量必须与下方等式一致（防止只改代码不改注释 / 只改注释不改代码）
	assert_eq(float(consts["MENU_TOP"]), MENU_TOP, "MENU_TOP 应与预算等式一致")
	assert_eq(float(consts["MENU_ROW_H"]), MENU_ROW_H, "MENU_ROW_H 应与预算等式一致")
	assert_eq(float(consts["MENU_GAP"]), MENU_GAP, "MENU_GAP 应与预算等式一致")
	assert_eq(float(consts["TITLE_SUB_BASELINE"]), TITLE_SUB_BASELINE,
		"TITLE_SUB_BASELINE 应与预算等式一致")

	# ---- 垂直预算：菜单 / 提示行 / 版本行互不重叠 ----
	var n := items.size()
	var bottom := MENU_TOP + float(n) * MENU_ROW_H + float(n - 1) * MENU_GAP
	assert_eq(bottom, 916.0,
		"5 行菜单下沿应等于重算后的预算值 916（实际 %.1f）" % bottom)

	var hint_top := HINT_BASELINE - HINT_SIZE + 7.0
	assert_lt(bottom, hint_top,
		"菜单下沿（%.1f）必须高于提示行字顶（约 %.1f），否则重叠" % [bottom, hint_top])
	assert_lt(HINT_BASELINE, VERSION_BASELINE,
		"提示行基线（%.1f）必须高于版本行基线（%.1f）" % [HINT_BASELINE, VERSION_BASELINE])
	assert_gt(MENU_TOP, TITLE_SUB_BASELINE,
		"菜单顶部（%.1f）应低于标题块末行基线（%.1f）" % [MENU_TOP, TITLE_SUB_BASELINE])

	# ---- title.tscn 的 Row_ 节点集合应与 MENU_ITEMS 一一对应 ----
	var packed: PackedScene = load(TITLE_SCENE) as PackedScene
	var inst: Node = packed.instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame
	var container := inst.get_node_or_null("MenuList") as Control
	assert_not_null(container, "标题场景应含 MenuList")
	if container == null:
		return
	for id: String in ids:
		assert_not_null(container.get_node_or_null("Row_%s" % id),
			"title.tscn 应声明 Row_%s（与 MENU_ITEMS 一致）" % id)


# ============================================================
#  用例 9：不写存档（只读纪律）
# ============================================================

func test_09_stage_select_does_not_write_save() -> void:
	var src := ""
	if FileAccess.file_exists(STAGE_SELECT_SCRIPT):
		var f := FileAccess.open(STAGE_SELECT_SCRIPT, FileAccess.READ)
		if f != null:
			src = f.get_as_text()
			f.close()
	assert_false(src.is_empty(), "应能读到关卡选择脚本正文以供静态检查")

	# 只检查**代码行**：本文件的文档注释里会写到「本文件不调用 SaveService.commit()」
	# 这类说明性文字，若连注释一起断言，正确写法反而会失败。
	var code := ""
	var doc_lines := 0
	for raw: String in src.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			doc_lines += 1
			continue
		code += line + "\n"
	assert_gt(doc_lines, 0, "前提校验：脚本确实含文档注释（否则上面的过滤毫无意义）")
	assert_false(code.is_empty(), "过滤注释后应仍有代码行")

	# 代码里不得出现任何写存档调用（只读纪律）
	for forbidden: String in ["SaveService.commit", "SaveService.new_game", "new_game()",
			"add_currency", "SaveService.save_now"]:
		assert_false(code.contains(forbidden),
			"关卡选择不得调用写存档 API：%s（只读纪律）" % forbidden)

	# 唯一允许的存档接触点是首通只读查询
	assert_true(code.contains("is_first_cleared"),
		"关卡选择应只通过 StageRewardService.is_first_cleared 只读访问存档")

	# 解锁判定必须纯函数化：不传真实 Callable（假 lookup）即可求值
	var script := _script()
	assert_true(bool(script.is_unlocked("1-1", _never())),
		"解锁判定必须可注入 lookup，否则无法在不碰存档的前提下测试")
