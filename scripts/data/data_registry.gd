## DataRegistry — 配置加载、ID 索引、校验（L4 Autoload）。
##
## 严格遵循 V2.1.4 B6 SSOT：
##   data/ 下只有 SSOT 表列出的权威文件；
##   关卡为 data/stages/ch1/<stageId>.json，剧情为 data/story/<storyId>.json；
##   不创建同义总表 stages.json 或 story.json；检索索引由本注册表在加载时生成内存索引。
##
## Phase 0 范围：按相对目录加载 + JSON 必填字段校验 + 内存 ID 索引 + 引用关系校验骨架。
## 不含玩法规则；数据文件本身为最小合法占位。
extends Node

const TAG := "DataRegistry"

## B6 SSOT：canonical 单文件数据域（相对 res://）
const CANONICAL_FILES := {
	"terms": "res://data/terms.json",
	"balance": "res://data/balance.json",
	"characters": "res://data/characters.json",
	"skills": "res://data/skills.json",
	"enemies": "res://data/enemies.json",
	"currencies": "res://data/currencies.json",
	"character_growth": "res://data/character_growth.json",
	"upgrade_costs": "res://data/upgrade_costs.json",
	"upgrades": "res://data/upgrades.json",
	"equipment": "res://data/equipment.json",
	"equipment_affixes": "res://data/equipment_affixes.json",
	"mementos": "res://data/mementos.json",
	"stage_rewards": "res://data/stage_rewards.json",
}

## 目录型数据域（V2.1.4：分目录，禁止同义总表）
const STAGES_DIR := "res://data/stages/ch1"
const STORY_DIR := "res://data/story"

## 每个数据域必须具备的顶层字段（Phase 0 校验基线）
const REQUIRED_FIELDS := {
	"terms": ["schemaVersion", "domain", "terms"],
	"balance": ["schemaVersion", "domain", "layout", "combat"],
	"characters": ["schemaVersion", "domain", "characters"],
	"skills": ["schemaVersion", "domain", "skills"],
	"enemies": ["schemaVersion", "domain", "enemies"],
	"currencies": ["schemaVersion", "domain", "currencies"],
	"character_growth": ["schemaVersion", "domain", "growthProfiles"],
	"upgrade_costs": ["schemaVersion", "domain", "upgradeCosts"],
	"upgrades": ["schemaVersion", "domain", "upgrades"],
	"equipment": ["schemaVersion", "domain", "equipment"],
	"equipment_affixes": ["schemaVersion", "domain", "affixes"],
	"mementos": ["schemaVersion", "domain", "mementos"],
	"stage_rewards": ["schemaVersion", "domain", "rewards"],
}

const STAGE_REQUIRED_FIELDS := [
	"schemaVersion", "domain", "stageId", "chapter", "mapId", "coreHp",
	"startingAp", "apRegen", "availableCharacters", "enemySpawnTimeline",
	"firstClearRewardId", "repeatRewardId", "storyBefore", "storyAfter",
]

## 已加载的原始数据域：domain -> Dictionary
var _domains: Dictionary = {}

## 内存 ID 索引：domain -> { id_string -> Dictionary(entry) }
var _indices: Dictionary = {}

## 加载过程中的问题记录（不阻断启动，由调用方决定如何呈现）
var _load_errors: Array[String] = []

## 是否已完成加载
var _loaded: bool = false


func _ready() -> void:
	load_all()


## 加载全部数据域。返回是否全部无错。
func load_all() -> bool:
	_domains.clear()
	_indices.clear()
	_load_errors.clear()

	for domain: String in CANONICAL_FILES.keys():
		var path: String = CANONICAL_FILES[domain]
		var data: Variant = _read_json(path)
		if data == null:
			_load_errors.append("%s: 无法加载 %s" % [domain, path])
			continue
		if typeof(data) != TYPE_DICTIONARY:
			_load_errors.append("%s: %s 顶层不是 JSON 对象" % [domain, path])
			continue
		var dict: Dictionary = data
		var missing: Array = []
		for field: String in REQUIRED_FIELDS.get(domain, []):
			if not dict.has(field):
				missing.append(field)
		if not missing.is_empty():
			_load_errors.append("%s: 缺少必填字段 %s" % [domain, ", ".join(missing)])
			continue
		_domains[domain] = dict

	_load_stages()
	_load_story()
	_validate_references()

	_loaded = true
	if _load_errors.is_empty():
		GameLog.info(TAG, "数据加载完成：%d 个数据域（含 %d 关、%d 剧情）"
			% [_domains.size(), _indices.get("stages", {}).size(), _indices.get("story", {}).size()])
	else:
		for e: String in _load_errors:
			GameLog.error(TAG, e)
	return _load_errors.is_empty()


## 是否已完成加载。
func is_loaded() -> bool:
	return _loaded


## 取某个数据域的原始字典。
func get_domain(domain: String) -> Dictionary:
	return _domains.get(domain, {})


## 按 ID 取某域条目。
func get_entry(domain: String, id: String) -> Dictionary:
	var idx: Dictionary = _indices.get(domain, {})
	return idx.get(id, {})


## 取某域的全部 ID。
func get_ids(domain: String) -> Array:
	var idx: Dictionary = _indices.get(domain, {})
	return idx.keys()


## 加载期问题列表。
func get_load_errors() -> Array[String]:
	return _load_errors


## 依据 balance.json 计算逻辑格坐标 -> 参考画布像素（V2.1.4 LOCKED 律）。
## Phase 0 只提供纯函数与参数读取；调用方负责给 boardOrigin。
func get_layout() -> Dictionary:
	return get_domain("balance").get("layout", {})


# ---------- 内部 ----------

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
		_load_errors.append("%s: JSON 解析失败（第 %d 行）: %s"
			% [path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data


func _load_stages() -> void:
	_indices["stages"] = {}
	var dir := DirAccess.open(STAGES_DIR)
	if dir == null:
		_load_errors.append("stages: 无法打开目录 %s" % STAGES_DIR)
		return
	var files := dir.get_files()
	files.sort()  # 保证 1-1, 1-2 ... 顺序稳定，便于测试复现
	for fname: String in files:
		if not fname.ends_with(".json"):
			continue
		var path := "%s/%s" % [STAGES_DIR, fname]
		var data: Variant = _read_json(path)
		if data == null or typeof(data) != TYPE_DICTIONARY:
			_load_errors.append("stages: %s 加载失败" % path)
			continue
		var dict: Dictionary = data
		var missing: Array = []
		for field: String in STAGE_REQUIRED_FIELDS:
			if not dict.has(field):
				missing.append(field)
		if not missing.is_empty():
			_load_errors.append("stages: %s 缺少必填字段 %s" % [fname, ", ".join(missing)])
			continue
		var sid: String = str(dict.get("stageId", ""))
		if sid.is_empty():
			_load_errors.append("stages: %s 的 stageId 为空" % fname)
			continue
		if _indices["stages"].has(sid):
			_load_errors.append("stages: stageId 重复 %s" % sid)
			continue
		_indices["stages"][sid] = dict


func _load_story() -> void:
	_indices["story"] = {}
	var dir := DirAccess.open(STORY_DIR)
	if dir == null:
		_load_errors.append("story: 无法打开目录 %s" % STORY_DIR)
		return
	var files := dir.get_files()
	files.sort()
	for fname: String in files:
		if not fname.ends_with(".json"):
			continue
		var path := "%s/%s" % [STORY_DIR, fname]
		var data: Variant = _read_json(path)
		if data == null or typeof(data) != TYPE_DICTIONARY:
			_load_errors.append("story: %s 加载失败" % path)
			continue
		var dict: Dictionary = data
		if not dict.has("storyId") or not dict.has("nodes"):
			_load_errors.append("story: %s 缺少 storyId 或 nodes" % fname)
			continue
		var sid: String = str(dict.get("storyId", ""))
		if sid.is_empty():
			_load_errors.append("story: %s 的 storyId 为空" % fname)
			continue
		_indices["story"][sid] = dict


## 引用完整性校验（V2.1.4 B6：角色 skillId -> skills.json；
## 关卡 storyBefore/storyAfter -> story/*.json；关卡 rewardId -> stage_rewards.json）。
## Phase 0 数据为占位，故仅校验"非空引用必须存在"；空串视为未配置，跳过。
func _validate_references() -> void:
	var skill_ids := {}
	for s: Dictionary in get_domain("skills").get("skills", []):
		skill_ids[str(s.get("id", ""))] = true

	for c: Dictionary in get_domain("characters").get("characters", []):
		for sid: String in c.get("skillIds", []):
			if not sid.is_empty() and not skill_ids.has(sid):
				_load_errors.append("引用错误: 角色 %s 的 skillId '%s' 不在 skills.json"
					% [c.get("id", "?"), sid])

	var story_ids: Dictionary = _indices.get("story", {})
	var reward_ids := {}
	for r: Dictionary in get_domain("stage_rewards").get("rewards", []):
		reward_ids[str(r.get("id", ""))] = true

	for stage_id: String in _indices.get("stages", {}).keys():
		var st: Dictionary = _indices["stages"][stage_id]
		for key: String in ["storyBefore", "storyAfter"]:
			var v: String = str(st.get(key, ""))
			if not v.is_empty() and not story_ids.has(v):
				_load_errors.append("引用错误: 关卡 %s 的 %s '%s' 不在 story/ 中"
					% [stage_id, key, v])
		for key: String in ["firstClearRewardId", "repeatRewardId"]:
			var v: String = str(st.get(key, ""))
			if not v.is_empty() and not reward_ids.has(v):
				_load_errors.append("引用错误: 关卡 %s 的 %s '%s' 不在 stage_rewards.json"
					% [stage_id, key, v])
