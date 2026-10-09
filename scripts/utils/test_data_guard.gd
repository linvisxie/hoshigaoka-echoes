## Filesystem isolation is separate from node/instance isolation.
class_name TestDataGuard
extends RefCounted

static func is_gut_invocation(args: PackedStringArray) -> bool:
	for arg: String in args:
		if arg.replace("\\", "/").ends_with("addons/gut/gut_cmdln.gd"):
			return true
	return false

static func is_isolated(user_dir: String) -> bool:
	var normalized := user_dir.replace("\\", "/").to_lower()
	return normalized.is_absolute_path() and normalized.contains("/_testenv/")

## True when a GUT run is executing WITHOUT an isolated user://.
static func run_is_unsafe() -> bool:
	return is_gut_invocation(OS.get_cmdline_args()) \
		and not is_isolated(OS.get_user_data_dir())

## Isolation-aware file removal for test cleanup.
## Under a safe (isolated) run this is a normal delete. Under an unsafe GUT run
## it REFUSES, because these very paths are the user's real save files.
static func remove_save_path(path: String) -> bool:
	if run_is_unsafe():
		push_error("TEST_ISOLATION_REFUSED: refusing to delete %s (user:// is not under _testenv)" % path)
		return false
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(path) == OK
	return true

## Gate for raw file writes performed directly by tests (bypassing SaveService).
## Returns false when the write must NOT happen; callers must bail out.
static func may_write_save_path(path: String) -> bool:
	if run_is_unsafe():
		push_error("TEST_ISOLATION_REFUSED: refusing to write %s (user:// is not under _testenv)" % path)
		return false
	return true

## Isolation-aware raw write for tests that deliberately corrupt a save file.
static func write_raw_save(path: String, text: String) -> bool:
	if not may_write_save_path(path):
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true
