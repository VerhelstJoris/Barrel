@tool
class_name FoliageMaskPainterPlugin extends EditorPlugin

const OVERLAY_SHADER_PATH := "res://addons/FoliagePainter/FoliagePainterDebugOverlay.gdshader"

var _toolbar: HBoxContainer
var _paint_toggle: CheckButton
var _radius: SpinBox
var _hardness: SpinBox
var _strength: SpinBox
var _fit_button: Button
var _save_button: Button
var _clear_button: Button

var _mask_node: FoliageMaskPainter = null
var _terrain = null
var _overlay_target = null
var _overlay_shader: Shader = null
var _prev_shader: Shader = null
var _prev_enabled := false

var _painting := false
var _erasing := false
var _dirty := false
var _last_stamp := Vector2.INF

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
	_toolbar.add_child(VSeparator.new())
	_fit_button = Button.new()
	_fit_button.text = "Fit To Terrain"
	_fit_button.tooltip_text = "Centre and size the mask on the terrain's allocated regions"
	_toolbar.add_child(_fit_button)
	_save_button = Button.new()
	_save_button.text = "Save Mask"
	_toolbar.add_child(_save_button)
	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_toolbar.add_child(_clear_button)
	_ensure_connections()
	_toolbar.visible = false
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar)

func _exit_tree() -> void:
	_remove_overlay()
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar)
		_toolbar.queue_free()
		_toolbar = null

# Re-checked on every selection so a hot script reload can't leave signals dangling.
func _ensure_connections() -> void:
	if _paint_toggle != null and not _paint_toggle.toggled.is_connected(_on_paint_toggled):
		_paint_toggle.toggled.connect(_on_paint_toggled)
	if _fit_button != null and not _fit_button.pressed.is_connected(_on_fit_pressed):
		_fit_button.pressed.connect(_on_fit_pressed)
	if _save_button != null and not _save_button.pressed.is_connected(_on_save_pressed):
		_save_button.pressed.connect(_on_save_pressed)
	if _clear_button != null and not _clear_button.pressed.is_connected(_on_clear_pressed):
		_clear_button.pressed.connect(_on_clear_pressed)

func _handles(object: Object) -> bool:
	return object is FoliageMaskPainter

func _edit(object: Object) -> void:
	var node := object as FoliageMaskPainter
	if node != _mask_node:
		_remove_overlay()
	_mask_node = node
	if _mask_node != null:
		_terrain = _find_terrain(get_tree().edited_scene_root)
		if _paint_toggle != null and _paint_toggle.button_pressed:
			_install_overlay()

func _make_visible(vis: bool) -> void:
	_ensure_connections()
	if _toolbar != null:
		_toolbar.visible = vis
	if not vis and _paint_toggle != null:
		_paint_toggle.button_pressed = false

func _process(_delta: float) -> void:
	if _mask_node == null or not is_instance_valid(_mask_node):
		return
	if _dirty:
		_mask_node.flush()
		_dirty = false
	if _overlay_target != null:
		_push_mask_params()

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _mask_node == null or _paint_toggle == null or not _paint_toggle.button_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.ctrl_pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if mb.pressed:
				var step := maxf(0.5, _radius.value * 0.1)
				_radius.value += step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -step
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_painting = true
				_erasing = mb.shift_pressed
				_last_stamp = Vector2.INF
				_paint_at(viewport_camera, mb.position)
			else:
				_painting = false
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	elif event is InputEventMouseMotion and _painting:
		var mm := event as InputEventMouseMotion
		_erasing = mm.shift_pressed
		_paint_at(viewport_camera, mm.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _paint_at(cam: Camera3D, mouse: Vector2) -> void:
	if cam == null:
		return
	var hit := _raycast(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if is_nan(hit.x):
		return
	var xz := Vector2(hit.x, hit.z)
	var radius := float(_radius.value)
	# Brush spacing keeps a slow drag from stacking stamps on one spot.
	if _last_stamp.is_finite() and _last_stamp.distance_to(xz) < radius * 0.25:
		return
	_last_stamp = xz
	_mask_node.stamp(xz, radius, float(_hardness.value), float(_strength.value), _erasing)
	_dirty = true

func _raycast(from: Vector3, dir: Vector3) -> Vector3:
	if _terrain != null and is_instance_valid(_terrain):
		var point: Vector3 = _terrain.get_intersection(from, dir, false)
		if not is_nan(point.x) and point.z < 3.4e38:
			return point
	# Fall back to the mask plane so painting works outside terrain regions.
	var plane := Plane(Vector3.UP, _mask_node.global_position.y)
	var flat = plane.intersects_ray(from, dir)
	return flat if flat != null else Vector3(NAN, NAN, NAN)

func _on_paint_toggled(pressed: bool) -> void:
	if pressed:
		_install_overlay()
	else:
		_painting = false
		_remove_overlay()

func _on_fit_pressed() -> void:
	if _mask_node == null:
		return
	if _terrain == null:
		_terrain = _find_terrain(get_tree().edited_scene_root)
	if not _mask_node.fit_to_terrain(_terrain):
		push_warning("Foliage mask painter: no Terrain3D regions found to fit to.")

func _on_save_pressed() -> void:
	if _mask_node == null:
		return
	var err := _mask_node.save_mask()
	if err != OK:
		push_warning("Foliage mask painter: save failed - %s" % error_string(err))
	else:
		print("Foliage mask saved to %s" % _mask_node.save_path)

func _on_clear_pressed() -> void:
	if _mask_node != null:
		_mask_node.clear_mask()

func _install_overlay() -> void:
	if _overlay_target != null or _mask_node == null:
		return
	if _terrain == null:
		_terrain = _find_terrain(get_tree().edited_scene_root)
	if _terrain == null:
		push_warning("Foliage mask painter: no Terrain3D node found in the edited scene.")
		return
	var mat = _terrain.material
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
	_overlay_target = _terrain
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
	if _mask_node == null or not is_instance_valid(_mask_node):
		return
	var mat = _overlay_target.material
	if mat == null:
		return
	var rect := _mask_node.get_world_rect()
	mat.set_shader_param(&"fmask_tex", _mask_node.get_texture())
	mat.set_shader_param(&"fmask_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	mat.set_shader_param(&"fmask_color", _mask_node.overlay_color)
	mat.set_shader_param(&"fmask_opacity", _mask_node.overlay_opacity)

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
