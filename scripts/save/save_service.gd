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

## **最后一次成功落盘**的存档内容（深拷贝，与 _current 不共享引用）。
##
## 用途（A0.4 加固）：commit() 失败时用它把内存状态回滚到"磁盘上真实存在的那一份"，
## 从而保证**失败不会留下半结算状态**——例如奖励已加到内存、但写盘失败，
## 若不回滚，玩家会在内存里"凭空多出资源"，而磁盘上并没有，重开即消失（或更糟：
## 后续某次成功的提交会把这些从未真正发放成功的奖励一并写盘）。
var _last_persisted: Dictionary = {}

## 是否存在有效存档
var _has_save: bool = false

## 存档「世代号」：每次内存存档被**整体替换**（读档 / 开新档 / 从 backup 恢复）时 +1。
##
## 用途（A0.4 加固）：成长系统（CharacterGrowthService）在启动时从存档构建一次
## 内存状态；若之后存档又被重新加载，那份成长状态就**过期**了——此时若把它写回，
## 会用旧面板覆盖新存档里的角色等级。调用方（App）用本计数判断是否需要重建。
var _generation: int = 0


## 当前存档世代号。见 _generation 的说明。
func save_generation() -> int:
	return _generation


func _ready() -> void:
	_ensure_dirs()
	_register_migrations()
	_load_on_startup()


## 启动时把磁盘存档读进内存（V2.1.4 L6：「读取流程 parse → validate → sequential
## migrate → validate → use」）。
##
## **为什么必须在这里做（存档安全缺陷修复）**：在此之前，生产流程中**没有任何地方
## 调用过 load_game()**——`_ready` 只用 has_valid_save() 判断"磁盘上有没有存档"，
## 却从不把内容读进 `_current`。于是启动后 `get_current()` 恒为空字典，而
## StageRewardService.settle() 见内存为空就会调用 new_game()，
## **用一份全新默认存档覆盖磁盘**：玩家每次启动后的第一次关卡结算都会静默清空
## 等级、资源、通关记录与首通标记。这是不可恢复的数据损失，属必须修复的缺陷。
##
## 不变量（修复后）：Autoload 就绪之后，`get_current()` 必然反映磁盘上的存档
## （若磁盘上确实存在有效存档）；调用方因此**不需要**再自己判断"要不要先读档"。
func _load_on_startup() -> void:
	var has_main := FileAccess.file_exists(SAVE_PATH)
	var has_backup := FileAccess.file_exists(BACKUP_PATH)
	if not has_main and not has_backup:
		# 全新玩家：磁盘上还没有任何存档。此处**刻意不写盘**——首份存档由
		# new_game() 或第一次事务式结算建立，避免"只是打开游戏就产生存档文件"，
		# 也让"是否存在存档"继续可用于判断是否首次游玩。
		_has_save = false
		GameLog.info(TAG, "未发现既有存档：将在首次保存时创建")
		return
	_has_save = load_game()
	if not _has_save:
		# 主存档与 backup 都不可用：不阻断启动（玩家仍可开新档），
		# 但必须把失败明确打到日志里，绝不能静默退化成"新档"。
		GameLog.error(TAG, "启动时读取存档失败：主存档与 backup 均不可用，本次运行不会加载任何既有进度")


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
		# A0.4 加固：待领取权益（装备 / 纪念物等需要实例化系统才能发放的奖励）。
		#
		# 结构：{ "pending": [...], "fulfilled": [...] }
		# 为什么放在顶层而不放在 stages 里：权益是**账号级**的持有物，
		# 而 stages 记录的是逐关的通关状态；装备系统（A0.5）需要按"我有哪些
		# 还没到手的奖励"来查询，跨关卡聚合，放顶层更直接。
		#
		# 由 StageRewardService 负责写入与兑现，本文件不定义其语义。
		"entitlements": {
			"pending": [],
			"fulfilled": [],
		},
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


## 磁盘上是否已经存在存档（主存档或 backup 任一存在即算）。
##
## 用途：区分「全新玩家」与「有进度但读取失败」——前者可以安全建新档，
## 后者绝不能被新档覆盖。
func has_save_on_disk() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH)


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
	_last_persisted = save.duplicate(true)
	_generation += 1
	GameLog.info(TAG, "存档加载成功（schema %d）" % int(save.get("schema_version", 0)))
	return true


## 开始新游戏：构建默认存档并写入。
## **注意**：本函数会覆盖磁盘上的既有存档，只应在玩家明确选择"开始新游戏"时调用。
## 关卡结算等流程**不得**用它来"兜底建一份存档"——那会摧毁玩家进度，
## 应改用 ensure_loaded()。
func new_game(player_name: String = "") -> bool:
	var save := build_default_save()
	save["profile"]["playerName"] = player_name
	# 刻意**不**在这里预先赋值 _current：赋值统一由 commit() 在写盘成功后完成，
	# 这样 commit() 失败时回滚到的仍是"上一份真正落盘的存档"，
	# 而不会把这份从未写成功的存档留在内存里冒充既成事实。
	return commit(save)


## 取「最后一次成功落盘」的存档内容（副本）。
## 供测试与诊断确认"内存状态是否真的与磁盘一致"。
func get_last_persisted() -> Dictionary:
	return _last_persisted.duplicate(true)


## 事务快照：调用方在**开始改内存之前**取一份，失败时用它整体回滚。
##
## 为什么 commit() 自身的回滚不够：commit() 的快照是在**进入 commit 时**取的，
## 此时调用方（如结算服务）对内存的改动**已经发生**了。因此 commit 失败后
## 内存里仍留着"这次没写成功的改动"。真正的原子性必须由**发起事务的一方**
## 在改动前取快照——本函数即为此提供。
func snapshot() -> Dictionary:
	return _current.duplicate(true)


## 用快照整体替换内存存档（配合 snapshot() 使用）。
##
## 这里**必须递增世代号**：它是一次整体替换，任何缓存了旧存档内容的派生服务
## （目前是 App.growth）都必须被判定为过期。若不递增，App.ensure_growth() 会继续
## 使用按旧存档构建的成长面板，并在下一次 commit 时把过期等级写回存档——
## 这正是"用旧面板覆盖新存档角色等级"的那类静默数据损坏。
func restore(snap: Dictionary) -> void:
	_current = snap
	_generation += 1


## 确保内存中有一份可用存档；**优先从磁盘读取，绝不用新档覆盖既有进度**。
##
## 这是结算/成长等写盘流程在"内存为空"时的**正确兜底入口**：
##   ① 内存已有存档 → 直接返回 true（不做任何 IO）；
##   ② 磁盘上有存档 → load_game() 读进来（含 backup 回退与 schema 迁移）；
##   ③ 磁盘上确实没有任何存档（全新玩家）→ 才建立一份新档。
##
## 为什么必须这样：旧实现里结算流程见内存为空就调 new_game()，
## 而启动时又没有读档，于是**每次启动后的第一次结算都会清空玩家进度**。
## 本函数把"兜底建新档"限制在"磁盘上确实什么都没有"这一种情形。
func ensure_loaded() -> bool:
	if not _current.is_empty():
		return true
	if FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH):
		if load_game():
			return true
		# 磁盘上有存档但读不出来（损坏且 backup 也不可用）：
		# 绝不静默覆盖，交由调用方处理并告知玩家。
		GameLog.error(TAG, "磁盘存在存档但无法读取，拒绝以新档覆盖（以免丢失玩家进度）")
		return false
	return new_game()


## 事务式提交存档：先 backup 现有存档，再写主存档。
## 避免"资源扣了但结果没保存"（L6）。
##
## 事务语义（A0.4 加固）：
##   成功 → 内存 `_current` 与磁盘同时前进到新内容，并记录 `_last_persisted`；
##   失败 → **内存状态回滚到调用前**（等价于最后一次成功落盘的内容），
##          并返回 false，调用方据此向玩家报告"未保存"，不得声称已发放。
##   这样"奖励已入账内存但存档写入失败"不会留下不可恢复的半结算状态。
func commit(save: Dictionary) -> bool:
	# 记住调用前的内存状态，供失败回滚使用。
	var snapshot: Dictionary = _current.duplicate(true)

	save["schema_version"] = CURRENT_SCHEMA_VERSION
	save["game_version"] = App.APP_VERSION
	# 1) 先把上一份已验证存档转为 backup
	if FileAccess.file_exists(SAVE_PATH):
		var prev: Variant = _read_json(SAVE_PATH)
		if prev != null and typeof(prev) == TYPE_DICTIONARY:
			if not _write_json(BACKUP_PATH, prev):
				GameLog.error(TAG, "备份失败，中止提交以防数据丢失")
				_rollback(snapshot)
				return false
	# 2) 写主存档
	if not _write_json(SAVE_PATH, save):
		GameLog.error(TAG, "主存档写入失败")
		_rollback(snapshot)
		return false
	_current = save
	_last_persisted = save.duplicate(true)
	_has_save = true
	GameLog.debug(TAG, "存档已提交")
	return true


## 提交失败时把内存状态回滚到调用前（A0.4 加固）。
##
## 为什么回滚到"调用前快照"而不是"最后一次落盘内容"：两者在正常流程下等价，
## 但快照更保守——即使内存此前已被其他路径改动而尚未落盘，本函数也不会
## 把这些未落盘改动当成既成事实保留下来。
func _rollback(snapshot: Dictionary) -> void:
	_current = snapshot
	GameLog.warn(TAG, "提交失败：内存存档已回滚到提交前状态（未产生任何半结算写入）")


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
	_last_persisted = save.duplicate(true)
	_generation += 1
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
