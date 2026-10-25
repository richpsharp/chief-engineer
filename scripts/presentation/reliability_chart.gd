extends Control
## Draws model-supplied curves. Bands describe operating capability, not
## statistical confidence; the failure curve is a rate, not a survival curve.

const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const GRID = Color("294050")
const CYAN = Color("5ed9df")
const AMBER = Color("f4c574")
var mode: String = "performance"
var samples: Array = []
var observation: Dictionary = {}


func update_profile(profile: Array, info: Dictionary) -> void:
	samples = profile
	observation = info
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var title: String = "FLOW EFFICIENCY" if mode == "performance" else "FAILURE RATE / 1,000 RUNNING HOURS · LOG SCALE"
	draw_style_box(_box(), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(16, 27), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 14, TEXT)
	if samples.is_empty():
		draw_string(font, Vector2(16, 78), "No lifetime model authored for this equipment.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 16, MUTED)
		return
	var plot := Rect2(64, 49, size.x - 88, size.y - 112)
	var maximum_age: float = maxf(float(samples.back().age_hours), float(observation.service_age_hours))
	maximum_age = maxf(1.0, maximum_age)
	var maximum_value: float = 1.0
	var minimum_value: float = 0.0
	if mode == "failure":
		maximum_value = maxf(float(observation.failure_rate) * 1000.0, 0.00001)
		minimum_value = maximum_value
		for sample in samples:
			maximum_value = maxf(maximum_value, float(sample.failure_rate) * 1000.0)
			minimum_value = minf(minimum_value, maxf(float(sample.failure_rate) * 1000.0, 0.00001))
		minimum_value = pow(10.0, floorf(log(minimum_value) / log(10.0)))
		maximum_value = pow(10.0, ceilf(log(maximum_value) / log(10.0)))
		maximum_value = maxf(maximum_value, minimum_value * 10.0)
	else:
		for band in [[0.9, 1.0, Color("78e2af")], [0.6, 0.9, AMBER], [0.0, 0.6, Color("e9958a")]]:
			var color: Color = band[2]
			color.a = 0.12
			draw_rect(Rect2(plot.position + Vector2(0, plot.size.y * (1.0 - band[1])), Vector2(plot.size.x, plot.size.y * (band[1] - band[0]))), color)
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var y: float = plot.end.y - plot.size.y * fraction
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1)
		var rate: float = exp(lerpf(log(maxf(minimum_value, 0.00001)), log(maximum_value), fraction))
		var value: String = "%d%%" % roundi(fraction * 100.0) if mode == "performance" else _rate(rate)
		draw_string(font, Vector2(3, y + 5), value, HORIZONTAL_ALIGNMENT_RIGHT, 51, 12, MUTED)
	for fraction in [0.0, 0.5, 1.0]:
		var x: float = plot.position.x + plot.size.x * fraction
		draw_string(font, Vector2(clampf(x - 40, 8, size.x - 96), plot.end.y + 21), "%s eq h" % _hours(maximum_age * fraction), HORIZONTAL_ALIGNMENT_CENTER, 88, 12, MUTED)
	var rating_x: float = plot.position.x + plot.size.x * clampf(float(observation.rated_life_hours) / maximum_age, 0.0, 1.0)
	draw_dashed_line(Vector2(rating_x, plot.position.y), Vector2(rating_x, plot.end.y), Color(AMBER, 0.65), 1.0, 5.0)
	var points := PackedVector2Array()
	for sample in samples:
		var value: float = float(sample.efficiency) if mode == "performance" else float(sample.failure_rate) * 1000.0
		points.append(_point(plot, float(sample.age_hours), value, maximum_age, minimum_value, maximum_value))
	if points.size() > 1:
		draw_polyline(points, CYAN, 2.5, true)
	var actual: float = float(observation.efficiency) if mode == "performance" else float(observation.failure_rate) * 1000.0
	if mode == "performance" and observation.failed:
		actual = 0.0
	var marker: Vector2 = _point(plot, float(observation.service_age_hours), actual, maximum_age, minimum_value, maximum_value)
	draw_dashed_line(Vector2(marker.x, plot.position.y), Vector2(marker.x, plot.end.y), Color(TEXT, 0.5), 1.0, 4.0)
	draw_circle(marker, 5.0, TEXT)
	draw_circle(marker, 2.0, Color("101f2c"))
	var marker_text: String = "Current wear-part age: %s equivalent h" % _hours(float(observation.service_age_hours))
	if mode == "failure":
		marker_text += " · %.3f failures / 1,000 running h" % (float(observation.failure_rate) * 1000.0)
	draw_string(font, Vector2(16, size.y - 29), marker_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 12, TEXT)
	var footnote: String = "Bands: normal ≥90% · degraded 60–90% · severe <60%" if mode == "performance" else "A rate estimate, not a guarantee or cumulative failure probability."
	draw_string(font, Vector2(16, size.y - 10), footnote, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 12, MUTED)


func _point(plot: Rect2, age: float, value: float, max_age: float, min_value: float, max_value: float) -> Vector2:
	var fraction: float = value / max_value
	if mode == "failure":
		fraction = (log(maxf(value, min_value)) - log(min_value)) / (log(max_value) - log(min_value))
	return Vector2(plot.position.x + plot.size.x * clampf(age / max_age, 0.0, 1.0), plot.end.y - plot.size.y * clampf(fraction, 0.0, 1.0))


func _rate(value: float) -> String:
	if value >= 1.0:
		return "%.0f" % value
	return "%.3f" % value


func _hours(value: float) -> String:
	return "%.1fk" % (value / 1000.0) if value >= 1000.0 else "%.0f" % value


func _box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("0c1924")
	box.border_color = GRID
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	return box
