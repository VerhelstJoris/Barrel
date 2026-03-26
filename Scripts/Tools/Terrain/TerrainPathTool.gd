@tool
extends Path3D

@export var fence_scene1 : PackedScene
@export var fence_scene2 : PackedScene

@export var created_path_objects : Node3D
@export var terrain: Node3D
@export var spacing: float = 0.3:
	set(value):
		spacing = value
		if Engine.is_editor_hint() and is_inside_tree():
			spawn_fences() 

@export var height_offset : float = 0.0: 
	set(value):
		height_offset = value
		if Engine.is_editor_hint() and is_inside_tree():
			spawn_fences() 

@export var enable_random_rotation := true:
	set(value):
		enable_random_rotation = value
		if Engine.is_editor_hint() and is_inside_tree():
			spawn_fences() 

var is_updating : bool = false

func _ready():
	curve.connect("changed", Callable(self, "_on_curve_changed"))

	adjust_curve_with_terrain_data()
	spawn_fences()

func _on_curve_changed() -> void:
	if is_updating:
		return
	is_updating = true

	adjust_curve_with_terrain_data()
	spawn_fences()

	is_updating = false

func adjust_curve_with_terrain_data() -> void:
	if terrain == null or terrain.data == null:
		push_error("No Valid Terrain3D")
		return

	if curve.point_count == 0:
		push_error("Path has no points")
		return

	print("Path3D has", curve.point_count, "points, start adjustment")

	for i in range(curve.point_count):
		var point = curve.get_point_position(i)
		var terrain_height : float = get_terrain_height(point)

		if !is_nan(terrain_height) and !is_inf(terrain_height):
			var new_point = Vector3(point.x, terrain_height + height_offset, point.z)
			curve.set_point_position(i, new_point)
			print("✅ Punt aangepast:", new_point)
		else:
			push_error("⚠️ Ongeldige hoogte voor punt " + str(point) + ", behoud originele hoogte.")

func get_terrain_height(_global_position: Vector3) -> float:
	if terrain == null or terrain.data == null:
		push_error("no valid Terrain3D or Terrain3D Data")
		return global_position.y  

	global_position = to_global(global_position)

	var height: float = terrain.data.get_height(global_position) * terrain.scale.y

	if is_nan(height) or is_inf(height):
		push_error("NO valid height for" + str(global_position) + ", fallback to 0")
		return 0.0

	return height

func spawn_fences() -> void:
	if terrain == null:
		push_error("NO valid Terrain3D")
		return

	for child in created_path_objects.get_children():
		child.queue_free()

	var current_distance : float = 0.0

	while current_distance < curve.get_baked_length():
		var pos = curve.sample_baked(current_distance)
		var next_pos = curve.sample_baked(current_distance + 0.1)

		pos = to_global(pos)
		next_pos = to_global(next_pos)

		var terrain_height : float = get_terrain_height(pos)
		if !is_nan(terrain_height) and !is_inf(terrain_height):
			pos.y = terrain_height + height_offset  # Pas de hoogte van het hek aan op de terrain hoogte

		var direction = (next_pos - pos).normalized()
		direction.y = 0

		var fence_instance = (fence_scene1 if randf() < 0.5 else fence_scene2).instantiate()

		if direction.length() > 0:
			var new_basis = Basis.looking_at(direction, Vector3.UP)
			var new_transform = Transform3D(new_basis, pos)
			fence_instance.transform = new_transform
		else:
			fence_instance.position = pos

		created_path_objects.add_child(fence_instance)

		if enable_random_rotation:
			fence_instance.rotate_y(randf_range(0.0, 2.0 * PI))

		current_distance += spacing

func randf_range(min_val: float, max_val: float) -> float:
	return min_val + (max_val - min_val) * randf()