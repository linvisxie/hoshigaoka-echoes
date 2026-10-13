## Presentation-only localization. IDs, configuration and saves stay canonical.
class_name GameLocale
extends RefCounted

const CATALOG_PATH := "res://assets/localization/en.json"
static var language := "zh"
static var _catalog: Dictionary = {}
static var _templates: Array = []
static var _numeric_fragments: Array = []
static var _phrases: RegEx
static var _atomic_phrases: RegEx
static var _cjk: RegEx
static var _cache: Dictionary = {}

static func initialize() -> void:
	if not _catalog.is_empty(): return
	_catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	_cjk = RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
	var sources: Array = _catalog.keys()
	sources.sort_custom(func(a: String,b: String) -> bool: return a.length()>b.length())
	var phrases := PackedStringArray()
	var atomic := PackedStringArray()
	var placeholder := RegEx.create_from_string("%[-+0-9.]*[sdf]|%%")
	var template_sources: Array[String] = []
	for source: String in sources:
		if placeholder.search(source)!=null: template_sources.append(source)
	for source: String in sources:
		var tokens := placeholder.search_all(source)
		if tokens.is_empty():
			phrases.append(_escape(source))
			var is_template_piece := false
			for candidate: String in template_sources:
				if candidate.contains(source):
					is_template_piece = true
					break
			if not is_template_piece and source.length()>2: atomic.append(_escape(source))
			continue
		var pattern := "^"
		var cursor := 0
		var target: String = _catalog[source]
		var target_tokens := placeholder.search_all(target)
		if target_tokens.size()!=tokens.size(): continue
		var parts: Array[String] = []
		var target_cursor := 0
		for i: int in range(tokens.size()):
			var token: RegExMatch = tokens[i]
			pattern += _escape(source.substr(cursor,token.get_start()-cursor))
			pattern += "(%)" if token.get_string()=="%%" else ("(.*?)" if token.get_string().ends_with("s") else "([-+0-9.]+)")
			cursor = token.get_end()
			var output_token: RegExMatch = target_tokens[i]
			parts.append(target.substr(target_cursor,output_token.get_start()-target_cursor))
			target_cursor = output_token.get_end()
		parts.append(target.substr(target_cursor))
		pattern += _escape(source.substr(cursor))+"$"
		_templates.append({"regex":RegEx.create_from_string(pattern),"parts":parts})
		if not source.contains("%s"):
			_numeric_fragments.append({"regex":RegEx.create_from_string(pattern.substr(1,pattern.length()-2)),"parts":parts})
	_phrases = RegEx.create_from_string("|".join(phrases))
	_atomic_phrases = RegEx.create_from_string("|".join(atomic))
	var settings := ConfigFile.new()
	settings.load("user://settings/settings.cfg")
	language = "en" if str(settings.get_value("language","locale","zh"))=="en" else "zh"
	TranslationServer.set_locale(language)

static func _escape(value: String) -> String:
	var result := ""
	for character: String in value:
		if "\\.^$|?*+()[]{}".contains(character): result += "\\"
		result += character
	return result

static func is_english() -> bool:
	return language=="en"

static func set_language(value: String) -> void:
	initialize()
	language = "en" if value=="en" else "zh"
	_cache.clear()
	TranslationServer.set_locale(language)

static func text(value: String) -> String:
	if language!="en" or value.is_empty(): return value
	initialize()
	if _cache.has(value): return _cache[value]
	if _cjk.search(value)==null: return value
	var result := ""
	if _catalog.has(value): result = str(_catalog[value])
	else:
		for template: Dictionary in _templates:
			var found: RegExMatch = template.regex.search(value)
			if found==null: continue
			for i: int in range(found.get_group_count()):
				result += template.parts[i]+text(found.get_string(i+1))
			result += template.parts.back()
			break
		if result.is_empty():
			var fragments := _replace_literals(value,_atomic_phrases)
			for template: Dictionary in _numeric_fragments:
				var matches: Array[RegExMatch] = template.regex.search_all(fragments)
				for at: int in range(matches.size()-1,-1,-1):
					var found: RegExMatch = matches[at]
					var replacement := ""
					for i: int in range(found.get_group_count()): replacement += template.parts[i]+found.get_string(i+1)
					replacement += template.parts.back()
					fragments = fragments.substr(0,found.get_start())+replacement+fragments.substr(found.get_end())
			result = _replace_literals(fragments,_phrases)
	if _cache.size()>=4096: _cache.clear()
	_cache[value] = result
	return result

static func _replace_literals(value: String,pattern: RegEx) -> String:
	var output := ""
	var cursor := 0
	for match_value: RegExMatch in pattern.search_all(value):
		output += value.substr(cursor,match_value.get_start()-cursor)+str(_catalog[match_value.get_string()])
		cursor = match_value.get_end()
	return output+value.substr(cursor)

static func release_resources() -> void:
	_cache.clear()
	_catalog.clear()
	_templates.clear()
	_numeric_fragments.clear()
	_phrases = null
	_atomic_phrases = null
	_cjk = null
