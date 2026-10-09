## SaveService — 存档、backup、migration（L4 Autoload）。
##
## 严格遵循 V2.1.4 L6：
##   user://save/savegame.json / savegame_backup.json / settings/settings.cfg / logs/latest.log
##   SaveGame 必须包含 schema_version；
##   读取流程 parse -> validate -> sequential migrate -> validate -> use；
##   每次写主存档前保留上一份已验证存档为 backup；
##   关卡结算/升级/突破/强化使用事务式修改。
##
## Phase 0 范围：文件路径管理、读写、backup、schema 校验与迁移管线骨架、事务性提交骨架。
## 不定义任何具体玩法字段（SaveGame 结构见 build_default_save / L5）。
extends Node

const TAG := "SaveService"

## 存档 schema 版本（改结构时递增，并在 _migrations 中登记迁移）
const CURRENT_SCHEMA_VERSION := 1

const SAVE_DIR := "user://save"
const SAVE_PATH := "user://save/savegame.json"
const BACKUP_PATH := "user://save/savegame_backup.json"
const SETTINGS_DIR := "user://settings"
const SETTINGS_PATH := "user://settings/settings.cfg"

## schema 迁移表：from_version -> Callable(save: Dictionary) -> Dictionary
var _migrations: Dictionary = {}

## 内存中的当前存档
var _current: Dictionary = {}

## 是否存在有效存档
var _has_save: bool = false


func _ready() -> void:
	_ensure_dirs()
	_register_migrations()
	_has_save = has_valid_save()


func _ensure_dirs() -> void:
	for d: String in [SAVE_DIR, SETTINGS_DIR]:
		if not DirAccess.dir_exists_absolute(d):
			var err := DirAccess.make_dir_recursive_absolute(d)
			if err != OK:
				GameLog.error(TAG, "无法创建目录 %s（错误 %d）" % [d, err])


## 登记 schema 迁移。Phase 0 无历史版本，保留管线。
func _register_migrations() -> void:
	# 示例（未来启用）：
	# _migrations[1] = func(save: Dictionary) -> Dictionary:
	#     save["schema_version"] = 2
	#     return save
	pass


## 构建一份默认存档（L5 SaveGame 结构）。
func build_default_save() -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"game_version": App.APP_VERSION,
		"profile": {
			"playerName": "",
			"createdAt": Time.get_datetime_string_from_system(true),
		},
		# J0.13：前台状态契约
		"flow_state": {
			"mode": "hub",              # hub / story / pre_battle / post_battle
			"current_story_id": "",
			"current_story_node": "",
			"pending_stage_id": "",
			"pending_story_after": "",
			"last_stable_screen": "title",
		},
		"progression": {},
		"characters": {},
		"inventory": {},
		# 新档初始资源为空。
		# 纪律：资源的「入口」必须来自关卡/任务/章节（V2.1.4 H 章十七 核心经济循环），
		# 而不是新档白送——否则「打关卡才有资源」这条循环会被绕过。
		# 想让玩家在首关之前就能体验成长系统，应通过首通奖励或教学奖励发放
		# （见 stage_rewards.json / 关卡 battleRewards），而不是改这里。
		"currencies": {},
		"stages": {},
		"story": {
			"readNodes": [],
			"choices": {},
			"flags": {},
		},
		"settings": {},
		"statistics": {},
	}


## 是否存在有效存档（JSON 可解析 + schema 校验通过）。
## 注意：这里只做校验，不执行迁移（迁移在 load_game 中进行），
## 因此一个"来自旧 schema 但可迁移"的存档仍视为有效。
func has_valid_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data: Variant = _read_json(SAVE_PATH)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		return false
	var save: Dictionary = data
	var result := _validate(save)
	return bool(result.get("ok", false))


## 取内存中的当前存档（未加载时返回空字典）。
func get_current() -> Dictionary:
	return _current


## 加载存档。流程：parse -> validate -> sequential migrate -> validate -> use。
## 成功返回 true；失败时尝试 backup 回退。
func load_game() -> bool:
	var data: Variant = _read_json(SAVE_PATH)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		GameLog.warn(TAG, "主存档无效，尝试从 backup 恢复")
		return _load_backup()
	var save: Dictionary = data
	var result := _validate_and_migrate(save)
	if not result.get("ok", false):
		GameLog.warn(TAG, "主存档校验/迁移失败：%s，尝试从 backup 恢复" % result.get("reason", ""))
		return _load_backup()
	_current = save
	GameLog.info(TAG, "存档加载成功（schema %d）" % int(save.get("schema_version", 0)))
	return true


## 开始新游戏：构建默认存档并写入。
func new_game(player_name: String = "") -> bool:
	var save := build_default_save()
	save["profile"]["playerName"] = player_name
	_current = save
	return commit(save)


## 事务式提交存档：先 backup 现有存档，再写主存档。
## 避免"资源扣了但结果没保存"（L6）。
func commit(save: Dictionary) -> bool:
	save["schema_version"] = CURRENT_SCHEMA_VERSION
	save["game_version"] = App.APP_VERSION
	# 1) 先把上一份已验证存档转为 backup
	if FileAccess.file_exists(SAVE_PATH):
		var prev: Variant = _read_json(SAVE_PATH)
		if prev != null and typeof(prev) == TYPE_DICTIONARY:
			if not _write_json(BACKUP_PATH, prev):
				GameLog.error(TAG, "备份失败，中止提交以防数据丢失")
				return false
	# 2) 写主存档
	if not _write_json(SAVE_PATH, save):
		GameLog.error(TAG, "主存档写入失败")
		return false
	_current = save
	_has_save = true
	GameLog.debug(TAG, "存档已提交")
	return true


func _load_backup() -> bool:
	var data: Variant = _read_json(BACKUP_PATH)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		GameLog.error(TAG, "backup 亦不可用")
		return false
	var save: Dictionary = data
	var result := _validate_and_migrate(save)
	if not result.get("ok", false):
		GameLog.error(TAG, "backup 校验失败：%s" % result.get("reason", ""))
		return false
	_current = save
	GameLog.info(TAG, "已从 backup 恢复")
	return true


## validate -> sequential migrate -> validate
func _validate_and_migrate(save: Dictionary) -> Dictionary:
	var v := _validate(save)
	if not v.get("ok", false):
		return v
	var version := int(save.get("schema_version", 0))
	while version < CURRENT_SCHEMA_VERSION:
		if not _migrations.has(version):
			return {"ok": false, "reason": "缺少 %d -> %d 的迁移" % [version, version + 1]}
		var migrate: Callable = _migrations[version]
		save = migrate.call(save)
		version = int(save.get("schema_version", 0))
	return _validate(save)


## schema 校验。
func _validate(save: Dictionary) -> Dictionary:
	if not save.has("schema_version"):
		return {"ok": false, "reason": "缺少 schemaVersion"}
	if not save.has("flow_state"):
		return {"ok": false, "reason": "缺少 flow_state"}
	var version := int(save.get("schema_version", 0))
	if version > CURRENT_SCHEMA_VERSION:
		return {"ok": false, "reason": "存档来自更新的 schema（%d）" % version}
	if version < 1:
		return {"ok": false, "reason": "schemaVersion 非法（%d）" % version}
	return {"ok": true, "reason": ""}


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
		GameLog.error(TAG, "%s JSON 解析失败（第 %d 行）" % [path, parser.get_error_line()])
		return null
	return parser.data


func _write_json(path: String, data: Variant) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true
