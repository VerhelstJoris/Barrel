@tool
class_name FoliageMaskPainterPlugin extends EditorPlugin

# Adjust if the overlay shader lives elsewhere.
const OVERLAY_SHADER_PATH := "res://addons/FoliagePainter/FoliagePainterDebugOverlay.gdshader"

var _toolbar: HBoxContainer
var _paint_toggle: CheckButton
var _radius: SpinBox
var _hardness: SpinBox
var _strength: SpinBox

var _terrain = null
var _overlay_target = null
var _overlay_shader: Shader = null
var _prev_shader: Shader = null
var _prev_enabled := false

var _mask_texture: Texture2D = null
var _mask_region := Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
var _mask_color := Color(0.15, 1.0, 0.35, 1.0)
var _mask_opacity := 0.5

# Mask sampled by the overlay; assigning while it is live updates the terrain immediately.
var mask_texture: Texture2D:
	set(value):
		_mask_texture = value
		_push_mask_params()
	get:
		return _mask_texture

var mask_region: Rect2:
	set(value):
		_mask_region = value
		_push_mask_params()
	get:
		return _mask_region

var mask_color: Color:
	set(value):
		_mask_color = value
		_push_mask_params()
	get:
		return _mask_color

var mask_opacity: float:
	set(value):
		_mask_opacity = clampf(value, 0.0, 1.0)
		_push_mask_params()
	get:
		return _mask_opacity

func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()
	_paint_toggle = CheckButton.new()
	_paint_toggle.text = "Paint Foliage Mask"
	_paint_toggle.tooltip_text = "LMB paint  •  Shift+LMB erase  •  Ctrl+Wheel radius"
	_paint_toggle.toggled.connect(_on_paint_toggled)
	_toolbar.add_child(_paint_toggle)
	_toolbar.add_child(VSeparator.new())
	_radius = _add_spin("Radius", 0.5, 1000.0, 0.5, 16.0)
	_hardness = _add_spin("Hardness", 0.0, 1.0, 0.05, 0.5)
	_strength = _add_spin("Strength", 0.0, 1.0, 0.05, 1.0)
	_toolbar.visible = false
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar)

func _exit_tree() -> void:
	_remove_overlay()
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar)
		_toolbar.queue_free()
		_toolbar = null

func _handles(object: Object) -> bool:
	return object is Node and (object as Node).is_class("Terrain3D")

func _edit(object: Object) -> void:
	var node := object as Node
	if node != null and not node.is_class("Terrain3D"):
		node = null
	if node != _terrain:
		_remove_overlay()
	_terrain = node
	if _terrain != null and _paint_toggle != null and _paint_toggle.button_pressed:
		_install_overlay()

func _make_visible(vis: bool) -> void:
	if _toolbar != null:
		_toolbar.visible = vis
	if not vis and _paint_toggle != null:
		_paint_toggle.button_pressed = false

func _on_paint_toggled(pressed: bool) -> void:
	print("TOGGLED")
	if pressed:
		_install_overlay()
	else:
		_remove_overlay()

func _install_overlay() -> void:
	if _overlay_target != null:
		return
	var terrain = _terrain if _terrain != null else _find_terrain(get_tree().edited_scene_root)
	if terrain == null:
		push_warning("Foliage mask painter: no Terrain3D node found in the edited scene.")
		return
	var mat = terrain.material
	if mat == null:
		push_warning("Foliage mask painter: Terrain3D has no material.")
		return
	var source := load(OVERLAY_SHADER_PATH) as Shader
	if source == null:
		push_warning("Foliage mask painter: could not load %s" % OVERLAY_SHADER_PATH)
		return
	_prev_shader = mat.shader_override
	_prev_enabled = mat.shader_override_enabled
	# Copy so the .gdshader on disk is never modified.
	_overlay_shader = source.duplicate() as Shader
	mat.shader_override = _overlay_shader
	mat.shader_override_enabled = true
	_overlay_target = terrain
	_push_mask_params()

func _remove_overlay() -> void:
	if _overlay_target == null:
		return
	if is_instance_valid(_overlay_target):
		var mat = _overlay_target.material
		if mat != null:
			mat.set_shader_param(&"fmask_tex", null)
			mat.shader_override_enabled = false
			mat.shader_override = _prev_shader
			mat.shader_override_enabled = _prev_enabled
	_overlay_target = null
	_overlay_shader = null
	_prev_shader = null
	_prev_enabled = false

func _push_mask_params() -> void:
	if _overlay_target == null or not is_instance_valid(_overlay_target):
		return
	var mat = _overlay_target.material
	if mat == null:
		return
	mat.set_shader_param(&"fmask_tex", _mask_texture)
	mat.set_shader_param(&"fmask_rect", Vector4(_mask_region.position.x, _mask_region.position.y,
		_mask_region.size.x, _mask_region.size.y))
	mat.set_shader_param(&"fmask_color", _mask_color)
	mat.set_shader_param(&"fmask_opacity", _mask_opacity)

func _find_terrain(node: Node) -> Node:
	if node == null:
		return null
	if node.is_class("Terrain3D"):
		return node
	for child in node.get_children():
		var found := _find_terrain(child)
		if found != null:
			return found
	return null

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
