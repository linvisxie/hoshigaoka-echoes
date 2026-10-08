## Phase 0 验收测试：数据目录与 SSOT 结构（V2.1.4 B6）
##
## 验证：
##   1) B6 SSOT 表列出的 canonical 数据文件全部存在且可解析
##   2) 按 V2.1.4 裁决：不得存在同义总表 stages.json / story.json
##   3) 关卡为 data/stages/ch1/<stageId>.json（10 关），剧情为 data/story/<storyId>.json
##   4) balance.json 承载 V2.1.4 明文锁定的布局参数
extends GutTest

const DATA_DIR := "res://data"

## B6 SSOT 表：canonical 单文件（V2.1.4）
const EXPECTED_FILES := [
	"terms.json",
	"balance.json",
	"characters.json",
	"skills.json",
	"enemies.json",
	"currencies.json",
	"character_growth.json",
	"upgrade_costs.json",
	"upgrades.json",
	"equipment.json",
	"equipment_affixes.json",
	"mementos.json",
	"stage_rewards.json",
]

## V2.1.4 明令不得创建的同义总表
const FORBIDDEN_FILES := [
	"stages.json",
	"story.json",
	"currencies_growth.json",
]


func test_canonical_files_exist() -> void:
	for fname: String in EXPECTED_FILES:
		var path := "%s/%s" % [DATA_DIR, fname]
		assert_true(FileAccess.file_exists(path), "canonical 数据文件应存在: %s" % fname)


func test_forbidden_alias_files_absent() -> void:
	for fname: String in FORBIDDEN_FILES:
		var path := "%s/%s" % [DATA_DIR, fname]
		assert_false(
			FileAccess.file_exists(path),
			"V2.1.4 禁止创建同义总表: %s" % fname
		)


func test_all_canonical_files_are_valid_json_with_schema_version() -> void:
	for fname: String in EXPECTED_FILES:
		var path := "%s/%s" % [DATA_DIR, fname]
		var data: Variant = _read_json(path)
		assert_not_null(data, "%s 应为合法 JSON" % fname)
		if data == null:
			continue
		assert_true(data.has("schemaVersion"), "%s 应含 schemaVersion" % fname)
		assert_true(data.has("domain"), "%s 应含 domain" % fname)


func test_stages_use_subdirectory_layout() -> void:
	var dir := DirAccess.open("res://data/stages/ch1")
	assert_not_null(dir, "关卡目录 res://data/stages/ch1 应存在")
	if dir == null:
		return
	var json_files: Array[String] = []
	for f: String in dir.get_files():
		if f.ends_with(".json"):
			json_files.append(f)
	assert_eq(json_files.size(), 10, "第一章应有 10 个关卡文件（1-1～1-10）")


func test_stage_ids_are_sequential_and_present() -> void:
	for i: int in range(1, 11):
		var sid := "1-%d" % i
		var path := "res://data/stages/ch1/%s.json" % sid
		assert_true(FileAccess.file_exists(path), "关卡文件应存在: %s" % sid)
		var data: Variant = _read_json(path)
		if data == null:
			continue
		assert_eq(str(data.get("stageId", "")), sid, "%s 的 stageId 应自洽" % sid)
		assert_eq(int(data.get("chapter", 0)), 1, "%s 的 chapter 应为 1" % sid)


func test_story_uses_subdirectory_layout() -> void:
	var dir := DirAccess.open("res://data/story")
	assert_not_null(dir, "剧情目录 res://data/story 应存在")
	if dir == null:
		return
	var count := 0
	for f: String in dir.get_files():
		if f.ends_with(".json"):
			count += 1
			var data: Variant = _read_json("res://data/story/%s" % f)
			assert_not_null(data, "剧情文件应可解析: %s" % f)
			if data != null:
				assert_true(data.has("storyId"), "%s 应含 storyId" % f)
				assert_true(data.has("nodes"), "%s 应含 nodes" % f)
	assert_gt(count, 0, "应至少存在 1 个剧情文件")


## V2.1.4 LOCKED：逻辑格与渲染度量分离
func test_balance_carries_locked_layout_params() -> void:
	var data: Variant = _read_json("res://data/balance.json")
	assert_not_null(data, "balance.json 应可解析")
	if data == null:
		return
	var layout: Dictionary = data.get("layout", {})
	assert_eq(int(layout.get("tileSizePx", 0)), 192, "tileSizePx 应为 V2.1.4 锁定值 192")
	assert_eq(int(layout.get("laneSpacingPx", 0)), 192, "laneSpacingPx 应为 V2.1.4 锁定值 192")
	assert_eq(int(layout.get("lanes", 0)), 3, "应为 3 条路线")
	assert_eq(int(layout.get("columns", 0)), 6, "每路应为 6 个部署格")
	assert_eq(
		int(layout.get("boardReferenceWidthPx", 0)), 1152,
		"6 格参考占宽应为 1152px（192×6）"
	)


func test_balance_carries_combat_baseline() -> void:
	var data: Variant = _read_json("res://data/balance.json")
	if data == null:
		fail_test("balance.json 不可解析")
		return
	var combat: Dictionary = data.get("combat", {})
	assert_eq(int(combat.get("startingAp", 0)), 10, "开局 AP 应为 10")
	assert_eq(int(combat.get("maxAp", 0)), 30, "AP 上限应为 30")
	assert_eq(int(combat.get("coreHpDefault", 0)), 3, "核心生命默认应为 3")
	assert_eq(int(combat.get("squadLimit", 0)), 6, "战前编队上限应为 6")
	assert_eq(int(combat.get("fieldDeployLimit", 0)), 5, "场上同时部署上限应为 5")


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
