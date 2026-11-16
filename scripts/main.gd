extends Node2D

const TILE_W := 96.0
const TILE_H := 48.0
const GRID_SIZE := 8
const RESIDENTS := [
	{"name": "Milo", "role": "Garden enthusiast", "level": 1, "asset": "milo", "line": "My plants are thriving. The HOA is deeply suspicious."},
	{"name": "Nora", "role": "Caffeine optimist", "level": 2, "asset": "nora", "line": "I put the 'pro' in procrastination. Coffee helps."},
	{"name": "Pip", "role": "Bread visionary", "level": 3, "asset": "pip", "line": "My retirement plan? A diversified bread portfolio."},
]
const ASSETS := {
	"house": "res://assets/house.png", "cafe": "res://assets/cafe.png",
	"bakery": "res://assets/bakery.png", "tree": "res://assets/tree.png",
	"milo": "res://assets/milo.png", "nora": "res://assets/nora.png", "pip": "res://assets/pip.png",
}

var economy: Economy
var saver := SaveManager.new()
var textures: Dictionary = {}
var texture_regions: Dictionary = {}
var offset := Vector2(500, 215)
var active_type := ""
var pointer_down := false
var pointer_origin := Vector2.ZERO
var pointer_last := Vector2.ZERO
var dragged := false
var hover_cell := Vector2i(-1, -1)
var preview_cell := Vector2i(-1, -1)
var panel_mode := "buildings"
var status_message := ""
var status_until := 0.0
var elapsed := 0.0
var refresh_elapsed := 0.0
var last_level := 1

var canvas: Control
var coin_label: Label
var level_label: Label
var xp_label: Label
var hint_label: Label
var toast_label: Label
var save_warning: Label
var panel_title: Label
var panel_caption: Label
var card_holder: VBoxContainer
var cancel_button: Button
var buildings_tab: Button
var residents_tab: Button

func _ready() -> void:
	for key in ASSETS:
		var path: String = ASSETS[key]
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			if texture:
				textures[key] = texture
				texture_regions[key] = texture.get_image().get_used_rect()
	var now := _now()
	economy = saver.load_game(now)
	_build_ui()
	if economy == null:
		if saver.last_error.is_empty():
			economy = Economy.new(now)
			_save()
		else:
			buildings_tab.disabled = true
			residents_tab.disabled = true
			_show_error("Your city could not be loaded. Your save files were kept intact. " + saver.last_error)
	if economy:
		last_level = economy.level()
		if saver.recovered_from_backup or saver.recovered_from_temporary:
			_toast("Your city was restored from a recovery copy.", 7.0)
		_refresh_ui()
	set_process(true)

func _now() -> int:
	return int(Time.get_unix_time_from_system())

func _process(delta: float) -> void:
	elapsed += delta
	refresh_elapsed += delta
	if refresh_elapsed >= 0.25:
		refresh_elapsed = 0.0
		if economy:
			_update_hud()
		queue_redraw()
	if status_until > 0.0 and elapsed >= status_until:
		status_until = 0.0
		toast_label.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if economy:
			_save()

func _save() -> bool:
	if not economy:
		return false
	economy.observe_time(_now())
	var saved := saver.save_game(economy)
	if save_warning:
		save_warning.visible = not saved
		if not saved:
			save_warning.text = "SAVE FAILED — progress may be lost: " + saver.last_error
	return saved

func _build_ui() -> void:
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)

	var header := _panel(Rect2(24, 20, 1220, 72), Color("173b44"), 20)
	canvas.add_child(header)
	var title := _label("LITTLE CITY", 24, Color("ffffff"))
	title.position = Vector2(24, 12)
	header.add_child(title)
	var subtitle := _label("YOUR NEIGHBORHOOD, YOUR STORY", 13, Color("afd7d0"))
	subtitle.position = Vector2(26, 43)
	header.add_child(subtitle)
	coin_label = _label("", 23, Color("ffe3a2"))
	coin_label.position = Vector2(500, 19)
	header.add_child(coin_label)
	level_label = _label("", 20, Color("ffffff"))
	level_label.position = Vector2(765, 20)
	header.add_child(level_label)
	xp_label = _label("", 16, Color("b6dbd3"))
	xp_label.position = Vector2(930, 25)
	header.add_child(xp_label)

	var sidebar := _panel(Rect2(975, 112, 270, 572), Color("f9f3df"), 20)
	canvas.add_child(sidebar)
	panel_title = _label("BUILD YOUR CITY", 20, Color("173b44"))
	panel_title.position = Vector2(20, 18)
	sidebar.add_child(panel_title)
	panel_caption = _label("Zoning laws: merely suggestions.", 13, Color("66847a"))
	panel_caption.position = Vector2(20, 43)
	sidebar.add_child(panel_caption)
	buildings_tab = _button("BUILDINGS", Rect2(18, 68, 112, 45))
	residents_tab = _button("PEOPLE", Rect2(138, 68, 112, 45))
	buildings_tab.pressed.connect(_show_buildings)
	residents_tab.pressed.connect(_show_residents)
	sidebar.add_child(buildings_tab)
	sidebar.add_child(residents_tab)
	card_holder = VBoxContainer.new()
	card_holder.position = Vector2(18, 123)
	card_holder.size = Vector2(232, 360)
	card_holder.add_theme_constant_override("separation", 10)
	sidebar.add_child(card_holder)
	cancel_button = _button("CANCEL PLACEMENT", Rect2(18, 510, 232, 42))
	cancel_button.pressed.connect(_cancel_placement)
	cancel_button.visible = false
	sidebar.add_child(cancel_button)

	var hint_panel := _panel(Rect2(24, 642, 680, 43), Color("173b44"), 14)
	canvas.add_child(hint_panel)
	hint_label = _label("TAP COINS OR PEOPLE   •   DRAG TO EXPLORE", 15, Color("e5f4e7"))
	hint_label.position = Vector2(16, 12)
	hint_panel.add_child(hint_label)
	toast_label = _label("", 17, Color("ffffff"))
	toast_label.position = Vector2(45, 108)
	toast_label.add_theme_color_override("font_shadow_color", Color("173b44"))
	toast_label.add_theme_constant_override("shadow_offset_x", 2)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	toast_label.visible = false
	canvas.add_child(toast_label)
	save_warning = _label("", 15, Color("ffdf9a"))
	save_warning.position = Vector2(35, 608)
	save_warning.add_theme_color_override("font_shadow_color", Color("4b1f1f"))
	save_warning.add_theme_constant_override("shadow_offset_x", 2)
	save_warning.add_theme_constant_override("shadow_offset_y", 2)
	save_warning.visible = false
	canvas.add_child(save_warning)

func _panel(rect: Rect2, color: Color, radius: int) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.08, 0.19, 0.17, 0.22)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", style)
	return p

func _label(value: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(value: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = value
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color("ffffff"))
	b.add_theme_color_override("font_disabled_color", Color("8a9d93"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("2e8275") if state == "normal" else Color("22685e")
		if state == "disabled":
			style.bg_color = Color("dce6d7")
		if state == "focus":
			style.bg_color = Color(0, 0, 0, 0)
		style.set_corner_radius_all(10)
		b.add_theme_stylebox_override(state, style)
	return b

func _show_error(message: String) -> void:
	var cover := _panel(Rect2(225, 250, 760, 185), Color("173b44"), 20)
	canvas.add_child(cover)
	var label := _label(message, 18, Color("ffffff"))
	label.position = Vector2(25, 25)
	label.size = Vector2(710, 135)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cover.add_child(label)

func _toast(message: String, duration: float = 3.0) -> void:
	status_message = message
	status_until = elapsed + duration
	if toast_label:
		toast_label.text = message
		toast_label.visible = true

func _update_hud() -> void:
	coin_label.text = "●  %s COINS" % economy.coins
	level_label.text = "LEVEL  %s" % economy.level()
	var next := 3 if economy.level() == 1 else 10
	xp_label.text = "%s / %s XP" % [economy.xp, next] if economy.level() < 3 else "%s XP" % economy.xp

func _refresh_ui() -> void:
	if not economy:
		return
	_update_hud()
	for child in card_holder.get_children():
		child.queue_free()
	if panel_mode == "buildings":
		panel_title.text = "BUILD YOUR CITY"
		panel_caption.text = "Zoning laws: merely suggestions."
		for kind in ["house", "cafe", "bakery"]:
			var item: Dictionary = economy.catalog()[kind]
			var locked: bool = economy.level() < int(item.required_level)
			var description := "LEVEL %s TO UNLOCK" % item.required_level if locked else "%sc  •  +%s / %ss" % [item.cost, item.income, item.seconds]
			_add_card(str(item.name).to_upper(), description, kind, locked, "building")
	else:
		panel_title.text = "MEET THE LOCALS"
		panel_caption.text = "Nice people. Questionable decisions."
		for resident in RESIDENTS:
			var locked: bool = economy.level() < int(resident.level)
			var description: String = "LEVEL %s TO UNLOCK" % resident.level if locked else resident.role
			_add_card(str(resident.name).to_upper(), description, resident.asset, locked, "resident")
	cancel_button.visible = not active_type.is_empty()

func _add_card(title: String, description: String, asset: String, locked: bool, kind: String) -> void:
	var card := _panel(Rect2(0, 0, 232, 94), Color("ffffff"), 13)
	card.custom_minimum_size = Vector2(232, 94)
	card_holder.add_child(card)
	var art := TextureRect.new()
	art.position = Vector2(8, 7)
	art.size = Vector2(74, 77)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = textures.get(asset)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if locked:
		art.modulate = Color(0.55, 0.59, 0.57, 0.45)
	card.add_child(art)
	var title_label := _label(title, 17, Color("284b43"))
	title_label.position = Vector2(84, 15)
	card.add_child(title_label)
	var detail := _label(description, 13, Color("66847a"))
	detail.position = Vector2(84, 39)
	card.add_child(detail)
	if kind == "building":
		var button := _button("LOCKED" if locked else "PLACE", Rect2(84, 58, 132, 28))
		button.disabled = locked
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(button)
		if not locked:
			# The whole card is a generous touch target; the smaller pill is visual only.
			var hit_target := Button.new()
			hit_target.size = Vector2(232, 94)
			hit_target.flat = true
			hit_target.tooltip_text = "Place " + title
			hit_target.pressed.connect(_select_building.bind(asset))
			card.add_child(hit_target)

func _show_buildings() -> void:
	if not economy:
		return
	panel_mode = "buildings"
	_refresh_ui()

func _show_residents() -> void:
	if not economy:
		return
	panel_mode = "residents"
	_refresh_ui()

func _select_building(kind: String) -> void:
	if economy.coins < int(economy.catalog()[kind].cost):
		_toast("The bank says: bring more coins. Rude.")
		return
	active_type = kind
	preview_cell = Vector2i(-1, -1)
	hint_label.text = "TAP A TILE TO PREVIEW  •  TAP AGAIN TO BUILD"
	cancel_button.visible = true
	_toast("Choose an empty spot for your %s." % kind)
	queue_redraw()

func _cancel_placement() -> void:
	active_type = ""
	hover_cell = Vector2i(-1, -1)
	preview_cell = Vector2i(-1, -1)
	hint_label.text = "TAP COINS OR PEOPLE   •   DRAG TO EXPLORE"
	cancel_button.visible = false
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not economy:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer(event.position)
	elif event is InputEventScreenDrag:
		_move_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer(event.position)
	elif event is InputEventMouseMotion:
		if pointer_down:
			_move_pointer(event.position)
		elif not active_type.is_empty():
			hover_cell = _cell_at(event.position)
			queue_redraw()

func _begin_pointer(pos: Vector2) -> void:
	if pos.x >= 970 or pos.y < 100 or pos.y >= 635:
		return
	pointer_down = true
	pointer_origin = pos
	pointer_last = pos
	dragged = false

func _move_pointer(pos: Vector2) -> void:
	if not pointer_down:
		return
	if pos.distance_to(pointer_origin) > 8:
		dragged = true
	if dragged:
		offset += pos - pointer_last
		offset.x = clampf(offset.x, 300.0, 700.0)
		offset.y = clampf(offset.y, 110.0, 360.0)
	pointer_last = pos
	queue_redraw()

func _end_pointer(pos: Vector2) -> void:
	if not pointer_down:
		return
	pointer_down = false
	if dragged:
		return
	if not active_type.is_empty():
		var cell := _cell_at(pos)
		if cell.x < 0 or cell.y < 0 or cell.x >= GRID_SIZE or cell.y >= GRID_SIZE:
			_toast("Choose a tile inside your city.")
			return
		for building in economy.buildings:
			if building.x == cell.x and building.y == cell.y:
				_toast("That spot is already taken.")
				return
		if preview_cell != cell:
			preview_cell = cell
			hover_cell = cell
			_toast("Tap the highlighted spot again to build.")
			queue_redraw()
			return
		if economy.purchase(active_type, cell.x, cell.y, _now()):
			if _save():
				_toast("Your %s is open for business. Tax not included." % active_type)
			_cancel_placement()
			_refresh_ui()
		else:
			_toast("That spot is occupied or you need more coins.")
		return
	for building in economy.buildings:
		if economy.is_ready(building.id, _now()):
			var coin_pos := _coin_position(building)
			if pos.distance_to(coin_pos) <= 38.0:
				var old_level := economy.level()
				if economy.collect(building.id, _now()):
					var saved := _save()
					if economy.level() > old_level and saved:
						var resident: Dictionary = RESIDENTS[economy.level() - 1]
						_toast("LEVEL %s! %s moved in. Hide the paperwork." % [economy.level(), resident.name], 5.0)
					elif saved:
						_toast("Coins collected! The economy remains fictional.")
					_refresh_ui()
					queue_redraw()
				return
	for index in range(RESIDENTS.size()):
		if economy.level() >= int(RESIDENTS[index].level):
			var resident_pos := _resident_position(index)
			if Rect2(resident_pos + Vector2(-30, -75), Vector2(60, 85)).has_point(pos):
				_toast("%s: %s" % [RESIDENTS[index].name, RESIDENTS[index].line], 5.0)
				return

func _cell_at(pos: Vector2) -> Vector2i:
	var p := pos - offset
	var x := (p.x / (TILE_W / 2.0) + p.y / (TILE_H / 2.0)) / 2.0
	var y := (p.y / (TILE_H / 2.0) - p.x / (TILE_W / 2.0)) / 2.0
	return Vector2i(roundi(x), roundi(y))

func _tile_center(x: int, y: int) -> Vector2:
	return offset + Vector2((x - y) * TILE_W / 2.0, (x + y) * TILE_H / 2.0)

func _coin_position(building: Dictionary) -> Vector2:
	return _tile_center(building.x, building.y) + Vector2(0, -140)

func _draw() -> void:
	_draw_background()
	_draw_board()
	if not economy:
		return
	if not active_type.is_empty() and preview_cell.x >= 0:
		var preview_pos := _tile_center(preview_cell.x, preview_cell.y)
		_draw_sprite(active_type, preview_pos + Vector2(-70, -138), Vector2(140, 150), Color(1, 1, 1, 0.55))
	var entities: Array = []
	for building in economy.buildings:
		entities.append({"sort": int(building.x) + int(building.y), "kind": "building", "data": building})
	for index in range(RESIDENTS.size()):
		if economy.level() >= int(RESIDENTS[index].level):
			entities.append({"sort": 7 + index, "kind": "resident", "index": index})
	entities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.sort < b.sort)
	for entity in entities:
		if entity.kind == "building":
			_draw_building(entity.data)
		else:
			_draw_resident(entity.index)
	for building in economy.buildings:
		if economy.is_ready(building.id, _now()):
			_draw_coin(_coin_position(building))

func _draw_background() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("b8e5d1"))
	draw_rect(Rect2(0, 95, 1280, 625), Color("a4d6b6"))
	draw_circle(Vector2(80, 175), 110, Color("a9d8bc"))
	draw_circle(Vector2(880, 165), 160, Color("b4dfc5"))
	draw_circle(Vector2(768, 610), 210, Color("9cccad"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(54, 137), "WELCOME HOME", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("427866"))
	draw_string(font, Vector2(54, 169), "A little city with a lot of heart.", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("28574d"))

func _draw_board() -> void:
	# A quiet perimeter road gives the block a clear edge without consuming tiles.
	var road := PackedVector2Array([
		_tile_center(0, 0) + Vector2(0, -TILE_H / 2 - 9),
		_tile_center(7, 0) + Vector2(TILE_W / 2 + 18, 0),
		_tile_center(7, 7) + Vector2(0, TILE_H / 2 + 9),
		_tile_center(0, 7) + Vector2(-TILE_W / 2 - 18, 0),
		_tile_center(0, 0) + Vector2(0, -TILE_H / 2 - 9),
	])
	draw_polyline(road, Color("6c9691"), 22.0, true)
	draw_polyline(road, Color("e5dabb"), 2.0, true)
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var center := _tile_center(x, y)
			var points := PackedVector2Array([center + Vector2(0, -TILE_H / 2), center + Vector2(TILE_W / 2, 0), center + Vector2(0, TILE_H / 2), center + Vector2(-TILE_W / 2, 0)])
			var color := Color("d7e8b0") if (x + y) % 2 == 0 else Color("c6dda1")
			if not active_type.is_empty() and (preview_cell == Vector2i(x, y) or (preview_cell.x < 0 and hover_cell == Vector2i(x, y))):
				color = Color("ffe39b")
			draw_colored_polygon(points, color)
			draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(0.32, 0.53, 0.38, 0.28), 1.0, true)
			if (x * 7 + y * 3) % 11 == 0:
				draw_circle(center + Vector2(15, 5), 2, Color("8ebf83"))
	for tree in [Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, 6), Vector2i(6, -1), Vector2i(8, 6)]:
		_draw_sprite("tree", _tile_center(tree.x, tree.y) + Vector2(-30, -74), Vector2(60, 85))

func _draw_building(building: Dictionary) -> void:
	var p := _tile_center(building.x, building.y)
	draw_ellipse_shadow(p + Vector2(0, 8), Vector2(48, 15))
	_draw_sprite(str(building.type), p + Vector2(-70, -138), Vector2(140, 150))

func _resident_position(index: int) -> Vector2:
	var positions := [Vector2i(3, 4), Vector2i(4, 4), Vector2i(4, 5)]
	var p := _tile_center(positions[index].x, positions[index].y)
	p += Vector2(sin(elapsed * 0.9 + index * 2.0) * 8.0, -3.0 + sin(elapsed * 2.0 + index) * 2.0)
	return p

func _draw_resident(index: int) -> void:
	var p := _resident_position(index)
	draw_ellipse_shadow(p + Vector2(0, 4), Vector2(14, 5))
	_draw_sprite(RESIDENTS[index].asset, p + Vector2(-24, -68), Vector2(48, 72))

func draw_ellipse_shadow(center: Vector2, radius: Vector2) -> void:
	var points := PackedVector2Array()
	for i in range(20):
		var angle := TAU * i / 20.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, Color(0.18, 0.32, 0.24, 0.19))

func _draw_sprite(key: String, pos: Vector2, size: Vector2, tint: Color = Color.WHITE) -> void:
	if textures.has(key):
		draw_texture_rect_region(textures[key], Rect2(pos, size), texture_regions[key], tint)

func _draw_coin(pos: Vector2) -> void:
	var bob := sin(elapsed * 3.0) * 3.0
	var center := pos + Vector2(0, bob)
	draw_circle(center + Vector2(0, 4), 25, Color(0.22, 0.30, 0.18, 0.24))
	draw_circle(center, 25, Color("fff6ce"))
	draw_circle(center, 20, Color("f0aa35"))
	draw_circle(center, 16, Color("ffd36a"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-8, 8), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("9a5b22"))
