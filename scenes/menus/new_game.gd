extends CampusScreen

var name_input: LineEdit
var overwrite_confirmed := false
var notice: Label

func _ready() -> void:
	super._ready()
	set_background("bg_title_gate")
	panel(Rect2(500, 170, 920, 730))
	label_at("转入星丘", Rect2(570, 220, 780, 80), 54, GOLD)
	label_at("你的名字", Rect2(570, 360, 750, 60), 30)
	name_input = LineEdit.new()
	name_input.position = Vector2(570, 450)
	name_input.size = Vector2(780, 85)
	name_input.placeholder_text = "请输入称呼"
	name_input.max_length = 16
	name_input.caret_blink = true
	name_input.caret_blink_interval = 0.5
	name_input.add_theme_constant_override("caret_width", 2)
	name_input.add_theme_color_override("caret_color", WHITE)
	name_input.add_theme_font_size_override("font_size", 34)
	name_input.add_theme_stylebox_override("normal", box(Color("17233e"), BLUE))
	canvas.add_child(name_input)
	name_input.grab_focus()
	name_input.edit.call_deferred()
	notice = label_at("这个称呼会出现在对白中。", Rect2(570, 575, 780, 100), 26, MUTED)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button_at("返回", Rect2(570, 740, 280, 80), func() -> void: SceneRouter.go_to("title"))
	button_at("开始新学期   →", Rect2(880, 740, 470, 80), _start, true)

func _start() -> void:
	if name_input.text.strip_edges().is_empty():
		notice.text = "请先输入一个称呼。"
		return
	if SaveService.has_save_on_disk() and not overwrite_confirmed:
		overwrite_confirmed = true
		notice.text = "已有游戏进度。再次点击「开始新学期」将替换当前进度；返回可取消。"
		notice.add_theme_color_override("font_color", Color("ffb2ac"))
		return
	if not CampaignFlow.start_new(name_input.text):
		notice.text = "新游戏未能保存，请检查磁盘。"
