extends Control
## Complete, read-only topology map. Operating a node belongs to its workspace.
## Rectangles and edges are exposed so rendering and interaction share geometry.
signal inspect_requested(component_id: String, domain: String)

const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const BORDER = Color("294050")
const CYAN = Color("5ed9df")
const AMBER = Color("f4c574")
const GREEN = Color("78e2af")
const DIM = Color("466171")
const CARD_SIZE = Vector2(180, 44)
const COLUMN_STEP: float = 224.0
const ROW_STEP: float = 50.0

var ship
var presenter
var domain: String = "power"
var focus_id: String = ""
var buttons: Dictionary = {}
var node_rects: Dictionary = {}
var edges: Array[Dictionary] = []
var scroll: ScrollContainer
var canvas: Control
var _readings: Dictionary = {}
var _signature: String = ""
var _legend: Label
var _ids: Array[String] = []
var _ranks: Dictionary = {}


func configure(simulation, ship_presenter, connection_domain: String, focused: String = "") -> void:
	ship = simulation
	presenter = ship_presenter
	domain = connection_domain
	focus_id = focused
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend = Label.new()
	_legend.position = Vector2(12, 3)
	_legend.size = Vector2(1140, 28)
	_legend.add_theme_font_size_override("font_size", 14)
	_legend.add_theme_color_override("font_color", MUTED)
	_legend.text = "Electrical supply →  •  dashed = no delivery  •  select equipment to inspect in Power" if domain == "power" else "Cyan: circulation   Amber: heat path   Green: bypass   •   arrows show connection direction; dashed = no transfer"
	add_child(_legend)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(0, 34)
	scroll.size = Vector2(1164, 486)
	scroll.follow_focus = true
	add_child(scroll)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_network)
	scroll.add_child(canvas)
	refresh()
	if buttons.has(focus_id):
		_reveal_focus.call_deferred()
	queue_redraw()


func _reveal_focus() -> void:
	if is_inside_tree() and is_instance_valid(scroll) and buttons.has(focus_id) and is_instance_valid(buttons[focus_id]) and scroll.is_ancestor_of(buttons[focus_id]):
		scroll.ensure_control_visible(buttons[focus_id])


func refresh() -> void:
	if presenter == null or not is_instance_valid(canvas):
		return
	edges = presenter.network_connections(domain)
	var signature_parts: Array[String] = []
	for edge in edges:
		signature_parts.append("%s:%s:%s:%s" % [edge.id, edge.from_component, edge.to_component, edge.domain])
	signature_parts.sort()
	var signature: String = "|".join(signature_parts)
	if signature != _signature or buttons.is_empty():
		_signature = signature
		_build_nodes()
	for id in _readings:
		var caption: String = presenter.caption(id)
		if domain == "power" and ship.components[id].kind in ["load", "pump", "engine"]:
			caption = "%.1f / %.1f kW" % [float(ship.components[id].state.get("power", 0)), float(ship.components[id].state.get("requested_power", 0))]
		elif domain == "cooling" and ship.components[id].kind in ["reactor", "engine"]:
			caption = "%.1f °C • %.1f kW heat" % [float(ship.components[id].state.get("temperature", 0)), float(ship.components[id].state.get("heat_generated", 0))]
		if not edges.any(func(edge): return edge.from_component == id or edge.to_component == id):
			caption = "No connected supply" if ship.components[id].kind != "battery" else "Isolated reserve reference"
		_readings[id].text = caption
		var status: String = presenter.equipment_status(id)
		_readings[id].add_theme_color_override("font_color", CYAN if status in ["Online", "Idle", "Standby reference", "Ramping"] else AMBER)
		buttons[id].tooltip_text = "%s\n%s\n%s\nOpen in %s" % [ship.definition.component(id).display_name, caption, presenter.equipment_reason(id), "Power" if domain == "power" else "Cooling"]
	canvas.queue_redraw()


func _build_nodes() -> void:
	var focused_node: String = ""
	for id in buttons:
		if buttons[id].has_focus():
			focused_node = id
	for child in canvas.get_children():
		canvas.remove_child(child)
		child.queue_free()
	buttons.clear()
	_readings.clear()
	node_rects.clear()
	_ids.clear()
	for id in ship.components:
		var ports: Dictionary = ship.definition.component(id).definition.ports
		if (domain == "power" and ship.components[id].kind == "battery") or ports.values().any(func(port): return port.domain == "power" if domain == "power" else port.domain in ["coolant", "thermal"]):
			_ids.append(id)
	_ids.sort_custom(func(a, b): return _sort_key(a) < _sort_key(b))
	_layout_nodes()
	for id in _ids:
		var spec = ship.definition.component(id)
		var rect: Rect2 = node_rects[id]
		var button := Button.new()
		button.position = rect.position
		button.size = rect.size
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(func(): inspect_requested.emit(id, domain))
		button.add_theme_stylebox_override("normal", _style(Color("214452") if id == focus_id else Color("101f2c"), CYAN if id == focus_id else BORDER, 2 if id == focus_id else 1))
		button.add_theme_stylebox_override("hover", _style(Color("214452"), CYAN))
		button.add_theme_stylebox_override("pressed", _style(Color("285664"), CYAN))
		button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), AMBER, 2))
		canvas.add_child(button)
		buttons[id] = button
		var title: Label = _label(str(spec.short_name if not spec.short_name.is_empty() else spec.display_name), 14, TEXT)
		title.position = Vector2(9, 3)
		title.size = Vector2(CARD_SIZE.x - 29, 19)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_child(title)
		var arrow: Label = _label("›", 17, CYAN)
		arrow.position = Vector2(CARD_SIZE.x - 19, 1)
		button.add_child(arrow)
		var reading: Label = _label("", 12, CYAN)
		reading.position = Vector2(9, 22)
		reading.size = Vector2(CARD_SIZE.x - 18, 19)
		reading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_child(reading)
		_readings[id] = reading
	if buttons.has(focused_node):
		buttons[focused_node].grab_focus()


func _layout_nodes() -> void:
	_ranks.clear()
	for id in _ids:
		_ranks[id] = 0
	if domain == "power":
		# The electrical tree is acyclic; relax depths without depending on
		# resource declaration order. All buses remain explicit in the path.
		for iteration in _ids.size():
			var changed: bool = false
			for edge in edges:
				var next_rank: int = int(_ranks[edge.from_component]) + 1
				if next_rank > int(_ranks[edge.to_component]):
					_ranks[edge.to_component] = next_rank
					changed = true
			if not changed:
				break
	else:
		# Circulation and thermal storage share a drawing, not a fictitious
		# serial pipe. Separate columns expose each actual source and sink.
		for id in _ids:
			_ranks[id] = {"reactor": 0, "pump": 0, "engine": 1, "heat_exchanger": 1, "coolant": 2, "radiator": 3}.get(ship.components[id].kind, 0)
	var columns: Dictionary = {}
	for id in _ids:
		var rank: int = int(_ranks[id])
		if not columns.has(rank):
			columns[rank] = []
		columns[rank].append(id)
	var max_rows: int = 1
	var max_rank: int = 0
	for rank in columns:
		max_rows = maxi(max_rows, columns[rank].size())
		max_rank = maxi(max_rank, int(rank))
	var content_height: float = maxf(476, max_rows * ROW_STEP + 26)
	var content_width: float = maxf(1152, max_rank * COLUMN_STEP + CARD_SIZE.x + 48)
	canvas.custom_minimum_size = Vector2(content_width, content_height)
	canvas.size = canvas.custom_minimum_size
	for rank in columns:
		var column: Array = columns[rank]
		var available: float = content_height - 52 - CARD_SIZE.y
		for index in column.size():
			var y: float = 26 + available * (float(index) / (column.size() - 1)) if column.size() > 1 else (content_height - CARD_SIZE.y) * 0.5
			node_rects[column[index]] = Rect2(Vector2(24 + rank * COLUMN_STEP, y), CARD_SIZE)


func _sort_key(id: String) -> String:
	var spec = ship.definition.component(id)
	if domain == "power":
		return _power_path(id, {})
	if domain == "cooling" and ship.components[id].kind in ["reactor", "pump"]:
		var destinations: Array[String] = []
		for edge in edges:
			if edge.from_component == id and not edge.get("bypass", false) and ship.components[edge.to_component].kind in ["engine", "heat_exchanger"]:
				destinations.append(str(ship.definition.component(edge.to_component).display_name).to_lower())
		destinations.sort()
		return (destinations[0] if not destinations.is_empty() else "zz") + (":0:" if ship.components[id].kind == "reactor" else ":1:") + str(spec.display_name).to_lower() + ":" + id
	return str(spec.display_name).to_lower() + ":" + id


func _power_path(id: String, visited: Dictionary) -> String:
	var name_text: String = str(ship.definition.component(id).display_name).to_lower() + ":" + id
	if visited.has(id):
		return name_text
	visited[id] = true
	for edge in edges:
		if edge.to_component == id:
			return _power_path(str(edge.from_component), visited) + "/" + name_text
	return name_text


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _style(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(0)
	return style


func _draw() -> void:
	draw_style_box(_style(Color("0c1a25"), BORDER), Rect2(Vector2.ZERO, size))


func _draw_network() -> void:
	for edge in edges:
		if not node_rects.has(edge.from_component) or not node_rects.has(edge.to_component):
			continue
		var points: PackedVector2Array = edge_path(edge)
		var color: Color = GREEN if edge.get("bypass", false) else (AMBER if edge.domain == "thermal" else CYAN)
		var active: bool = bool(edge.get("active", false))
		if not active:
			color = DIM
		for i in range(points.size() - 1):
			if active:
				canvas.draw_line(points[i], points[i + 1], Color(color, 0.12), 6, true)
				canvas.draw_line(points[i], points[i + 1], color, 1.8, true)
			else:
				canvas.draw_dashed_line(points[i], points[i + 1], color, 1.5, 5, true)
		var finish: Vector2 = points[-1]
		var direction: Vector2 = (finish - points[-2]).normalized()
		var side := Vector2(-direction.y, direction.x)
		canvas.draw_colored_polygon(PackedVector2Array([finish, finish - direction * 7 + side * 3.5, finish - direction * 7 - side * 3.5]), color)


func edge_path(edge: Dictionary) -> PackedVector2Array:
	var source: Rect2 = node_rects[edge.from_component]
	var target: Rect2 = node_rects[edge.to_component]
	var offset: float = 12.0 if edge.get("bypass", false) else (-5.0 if edge.domain == "thermal" else 5.0)
	var start := Vector2(source.end.x, source.get_center().y + offset)
	var finish := Vector2(target.position.x, target.get_center().y + offset)
	if edge.get("bypass", false):
		# The fitted kit gets a separate route lane and port. Overlaying a
		# native connection would make an isolated pump appear connected.
		var lane: float = canvas.size.y - 5.0
		return PackedVector2Array([start, Vector2(start.x + 6, start.y), Vector2(start.x + 6, lane), Vector2(finish.x - 6, lane), Vector2(finish.x - 6, finish.y), finish])
	var middle: float = (start.x + finish.x) * 0.5
	if domain == "power":
		# Independent buses must not appear joined by a shared vertical line.
		var sources: Array[String] = []
		for id in _ids:
			if _ranks[id] == _ranks[edge.from_component] and edges.any(func(other): return other.from_component == id):
				sources.append(id)
		middle = start.x + (finish.x - start.x) * (float(sources.find(edge.from_component) + 1) / (sources.size() + 1))
	var points := PackedVector2Array([start, Vector2(middle, start.y), Vector2(middle, finish.y), finish])
	for id in node_rects:
		if id in [edge.from_component, edge.to_component]:
			continue
		if _intersects(points, node_rects[id].grow(4)):
			# A long circulation edge can skip heat-transfer columns. Carry it
			# around them rather than drawing through an unrelated component.
			var lane: float = 10.0 if start.y < canvas.size.y * 0.5 else canvas.size.y - 10.0
			return PackedVector2Array([start, Vector2(start.x + 12, start.y), Vector2(start.x + 12, lane), Vector2(finish.x - 12, lane), Vector2(finish.x - 12, finish.y), finish])
	return points


func _intersects(points: PackedVector2Array, rect: Rect2) -> bool:
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		if is_equal_approx(a.y, b.y) and a.y > rect.position.y and a.y < rect.end.y and maxf(a.x, b.x) > rect.position.x and minf(a.x, b.x) < rect.end.x:
			return true
		if is_equal_approx(a.x, b.x) and a.x > rect.position.x and a.x < rect.end.x and maxf(a.y, b.y) > rect.position.y and minf(a.y, b.y) < rect.end.y:
			return true
	return false
