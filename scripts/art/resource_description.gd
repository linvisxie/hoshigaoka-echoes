class_name ResourceDescription
extends Panel

var body := Label.new()
var quote := Label.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel",GameSkin.panel(Color("101d33"),GameSkin.BLUE))
	var kai := SystemFont.new()
	kai.font_names = PackedStringArray(["KaiTi","楷体","STKaiti"])
	quote.add_theme_font_override("font",kai)
	quote.add_theme_color_override("font_color",GameSkin.GOLD)
	body.add_theme_font_override("font",GameSkin.body_font())
	body.add_theme_color_override("font_color",GameSkin.WHITE)
	for line: Label in [body,quote]:
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(line)
	set_ui_scale(1.0)

func set_ui_scale(factor: float) -> void:
	size = Vector2(540,120)*factor
	body.position = Vector2(24,20)*factor
	quote.position = Vector2(24,65)*factor
	body.size = Vector2(492,44)*factor
	quote.size = Vector2(492,45)*factor
	body.add_theme_font_size_override("font_size",int(24*factor))
	quote.add_theme_font_size_override("font_size",int(21*factor))

func set_currency(currency_id: String) -> void:
	var config := definition(currency_id)
	body.text = GameLocale.text(str(config.get("uiDescription",config.get("use",""))))
	quote.text = GameLocale.text(str(config.get("flavorText","")))

static func definition(currency_id: String) -> Dictionary:
	for entry: Dictionary in DataRegistry.get_domain("currencies").get("currencies",[]):
		if str(entry.get("id","")) == currency_id: return entry
	return {}
