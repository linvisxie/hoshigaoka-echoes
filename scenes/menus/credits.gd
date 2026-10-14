extends CampusScreen

var projects: Array = []
var selected := 0
var project_title: Label
var summary: Label
var documents: OptionButton
var license_text: RichTextLabel
var source_button: Button
var project_buttons: Array[Button] = []

func _ready() -> void:
	super._ready()
	set_background("bg_title_gate")
	page_heading("鸣谢与许可证","感谢这些项目与创作者 · 许可证保留原文，可离线阅读")
	projects = JSON.parse_string(FileAccess.get_file_as_string("res://assets/licenses/credits.json"))
	panel(Rect2(70,210,430,710))
	panel(Rect2(530,210,1310,710))
	var list_scroll := ScrollContainer.new()
	list_scroll.position = Vector2(90,235)
	list_scroll.size = Vector2(390,660)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	canvas.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",14)
	list_scroll.add_child(list)
	for i: int in range(projects.size()):
		var index := i
		var button := button_at(str(projects[i].name),Rect2(0,0,366,78),func() -> void: _select(index))
		canvas.remove_child(button)
		button.custom_minimum_size = Vector2(366,78)
		list.add_child(button)
		project_buttons.append(button)
	project_title = label_at("",Rect2(580,238,1190,58),36,GOLD)
	summary = label_at("",Rect2(580,305,1190,95),23,MUTED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	documents = OptionButton.new()
	documents.position = Vector2(580,415)
	documents.size = Vector2(970,52)
	documents.add_theme_font_size_override("font_size",23)
	documents.item_selected.connect(_read_document)
	canvas.add_child(documents)
	source_button = button_at("项目来源",Rect2(1580,415,210,52),_open_source)
	license_text = RichTextLabel.new()
	license_text.position = Vector2(580,490)
	license_text.size = Vector2(1210,390)
	license_text.add_theme_font_override("normal_font",GameSkin.body_font())
	license_text.add_theme_font_size_override("normal_font_size",23)
	license_text.add_theme_color_override("default_color",WHITE)
	license_text.selection_enabled = true
	license_text.scroll_active = true
	license_text.bbcode_enabled = false
	canvas.add_child(license_text)
	button_at("返回设置",Rect2(70,975,430,65),_back,true)
	_select(0)
	fade_in_content()

func _select(index: int) -> void:
	selected = index
	var entry: Dictionary = projects[index]
	project_title.text = GameLocale.text(str(entry.name))
	summary.text = str(entry.author)+"\n"+GameLocale.text(str(entry.use))+" · "+GameLocale.text(str(entry.license))
	documents.clear()
	for filename: String in entry.files: documents.add_item(filename)
	source_button.disabled = str(entry.url).is_empty()
	for i: int in range(project_buttons.size()): GameSkin.style_button(project_buttons[i],i==index)
	_read_document(0)

func _read_document(index: int) -> void:
	var filename: String = projects[selected].files[index]
	# Manifest is local and reviewed; only bundled filenames are accepted.
	if filename.get_file()!=filename or not filename.ends_with(".txt"): return
	license_text.text = FileAccess.get_file_as_string("res://assets/licenses/"+filename)
	license_text.scroll_to_line(0)

func _open_source() -> void:
	var url := str(projects[selected].url)
	if url.begins_with("https://"): OS.shell_open(url)

func _back() -> void:
	SceneRouter.go_to("settings")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if documents.get_popup().visible: documents.get_popup().hide()
		else: _back.call_deferred()
