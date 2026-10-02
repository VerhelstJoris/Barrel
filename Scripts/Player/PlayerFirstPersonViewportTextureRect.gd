class_name PlayerFirstPersonViewportTextureRect extends TextureRect

# Displays the viewmodel SubViewport and keeps its render size locked to the window's real pixel size.
@export var viewmodel_viewport: SubViewport

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2.ZERO
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = viewmodel_viewport.get_texture()
	get_window().size_changed.connect(_on_window_size_changed)
	_on_window_size_changed()

func _on_window_size_changed() -> void:
	var window_pixel_size: Vector2i = get_window().size
	if window_pixel_size.x <= 0 or window_pixel_size.y <= 0:
		return
	viewmodel_viewport.size = window_pixel_size
