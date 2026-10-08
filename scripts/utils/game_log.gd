## 日志工具（L4 未列入 Autoload，以 class_name 提供，供其他单例与场景静态调用）。
##
## Phase 0 范围：结构化日志输出 + 级别过滤 + 落盘 user://logs/latest.log（L6）。
## 不含玩法逻辑。
class_name GameLog
extends RefCounted

## 日志级别
enum Level {
	DEBUG = 0,
	INFO = 1,
	WARN = 2,
	ERROR = 3,
}

## 低于此级别的日志不输出。Release 构建可通过 set_min_level(Level.INFO) 收敛。
static var _min_level: Level = Level.DEBUG

## 是否同时写入 user://logs/latest.log
static var _file_logging_enabled: bool = true

const LOG_DIR := "user://logs"
const LOG_FILE := "user://logs/latest.log"

## 设置最低输出级别。
static func set_min_level(level: Level) -> void:
	_min_level = level


## 读取当前最低输出级别。
static func get_min_level() -> Level:
	return _min_level


## 启用/禁用文件日志。
static func set_file_logging(enabled: bool) -> void:
	_file_logging_enabled = enabled


## 写入一行日志。
static func write_line(level: Level, tag: String, message: String) -> void:
	if level < _min_level:
		return
	var level_name := _level_name(level)
	var line := "[%s] %s | %s" % [level_name, tag, message]
	match level:
		Level.ERROR:
			push_error(line)
		Level.WARN:
			push_warning(line)
		_:
			print(line)
	if _file_logging_enabled:
		_append_to_file(line)


## 便捷方法
static func debug(tag: String, message: String) -> void:
	write_line(Level.DEBUG, tag, message)


static func info(tag: String, message: String) -> void:
	write_line(Level.INFO, tag, message)


static func warn(tag: String, message: String) -> void:
	write_line(Level.WARN, tag, message)


static func error(tag: String, message: String) -> void:
	write_line(Level.ERROR, tag, message)


static func _level_name(level: Level) -> String:
	match level:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARN:
			return "WARN"
		Level.ERROR:
			return "ERROR"
		_:
			return "?"


static func _append_to_file(line: String) -> void:
	# Phase 0：每次追加打开，简单可靠；性能优化留待后续按需做缓冲。
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		var err := DirAccess.make_dir_recursive_absolute(LOG_DIR)
		if err != OK:
			# 文件日志失败不应中断游戏，静默降级为仅控制台。
			_file_logging_enabled = false
			return
	var f := FileAccess.open(LOG_FILE, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	if f == null:
		_file_logging_enabled = false
		return
	f.seek_end()
	f.store_line(line)
	f.close()
