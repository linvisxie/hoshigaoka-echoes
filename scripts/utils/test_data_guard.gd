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
