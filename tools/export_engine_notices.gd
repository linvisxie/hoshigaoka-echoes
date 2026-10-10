## Export the notices embedded in the installed engine, without version guessing.
extends SceneTree

func _initialize() -> void:
	var engine_notice := FileAccess.open("res://assets/licenses/Godot-MIT.txt",FileAccess.WRITE)
	engine_notice.store_string("This game uses Godot Engine. https://godotengine.org/license/\n\n" + Engine.get_license_text())
	var third_party := FileAccess.open("res://assets/licenses/Godot-Third-Party-Notices.txt",FileAccess.WRITE)
	third_party.store_string("Godot Engine " + str(Engine.get_version_info().get("string", "")) + "\nEmbedded third-party copyright and license notices.\n\n")
	for component: Dictionary in Engine.get_copyright_info():
		third_party.store_string(str(component.get("name", "")) + "\n")
		for part: Dictionary in component.get("parts", []):
			for copyright_line: String in part.get("copyright", []):
				third_party.store_string(copyright_line + "\n")
			third_party.store_string("License: " + str(part.get("license", "")) + "\n")
			for source_file: String in part.get("files", []):
				third_party.store_string("  " + source_file + "\n")
		third_party.store_string("\n")
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for name: String in names:
		third_party.store_string("\n===== " + name + " =====\n" + str(licenses[name]) + "\n")
	engine_notice.close()
	third_party.close()
	print("Exported embedded Godot and third-party notices")
	quit()
