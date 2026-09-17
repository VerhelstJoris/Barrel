@tool
class_name FoliageMaskPainterPlugin extends EditorPlugin

var _toolbar: HBoxContainer
var _paint_toggle: CheckButton
var _radius: SpinBox
var _hardness: SpinBox
var _strength: SpinBox

func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()
	_paint_toggle = CheckButton.new()
	_paint_toggle.text = "Paint Foliage Mask"
	_paint_toggle.tooltip_text = "LMB paint  •  Shift+LMB erase  •  Ctrl+Wheel radius"
	_toolbar.add_child(_paint_toggle)
	_toolbar.add_child(VSeparator.new())
	_radius = _add_spin("Radius", 0.5, 1000.0, 0.5, 16.0)
	_hardness = _add_spin("Hardness", 0.0, 1.0, 0.05, 0.5)
	_strength = _add_spin("Strength", 0.0, 1.0, 0.05, 1.0)
	_toolbar.visible = false
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar)

func _exit_tree() -> void:
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar)
		_toolbar.queue_free()
		_toolbar = null

func _add_spin(label: String, mn: float, mx: float, step: float, val: float) -> SpinBox:
	var l := Label.new()
	l.text = "  %s " % label
	_toolbar.add_child(l)
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size.x = 74
	_toolbar.add_child(s)
	return s
