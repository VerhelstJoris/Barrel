@tool
extends Path3D

@export var fence_scene1 : PackedScene

@export var created_path_objects : Node3D
@export var terrain: Terrain3D


@export var spacing: float = 0.3
@export var height_offset : float = 0.0
@export var enable_random_rotation := true


@export_tool_button("Regenerate Path", "Callable") var regenerate_action = _regenerate

var is_updating : bool = false

func _regenerate() -> void:
	if is_updating:
		return
	is_updating = true

	adjust_curve_with_terrain_data()
	spawn_fences()

	is_updating = false

func adjust_curve_with_terrain_data() -> void:
	if terrain == null:
		push_error("No Valid Terrain3D")
		return

	if curve.point_count == 0:
		push_error("Path has no points")
		return

	print("Path3D has", curve.point_count, "points, start adjustment")

	for i in range(curve.point_count):
		var point: Vector3 = curve.get_point_position(i)
		
		var terrain_height : float = get_terrain_height(point)
#
		if !is_nan(terrain_height) and !is_inf(terrain_height):
			var new_point = Vector3(point.x, terrain_height + height_offset, point.z)
			curve.set_point_position(i, new_point)
		else:
			push_error("NO valid height for" + str(point) + ", fallback to previous")

func get_terrain_height(point_pos: Vector3) -> float:
	if terrain == null or terrain.data == null:
		push_error("no valid Terrain3D or Terrain3D Data")
		return global_position.y  

		
	var point_global_pos : Vector3 = to_global(point_pos)

	var height: float = terrain.data.get_height(point_global_pos) * terrain.scale.y

	if is_nan(height) or is_inf(height):
		push_error("NO valid height for" + str(point_global_pos) + ", fallback to 0")
		return 0.0

	return height

func spawn_fences() -> void:
	if terrain == null:
		push_error("NO valid Terrain3D")
		return

	for child in created_path_objects.get_children():
		child.queue_free()

	created_path_objects.set_global_transform(get_global_transform())


	if curve.point_count == 0:
		push_error("Path has no points")
		return
		
	var point_distance_map : Dictionary[int, float] =  _determine_points_distance()		

	for current_id in range(curve.point_count):
		var pos : Vector3= curve.get_point_position(current_id)
		var next_pos : Vector3 = curve.get_point_position( (current_id +1) % curve.point_count)
			
		var direction : Vector3 = (next_pos - pos).normalized()
		_create_object_at(fence_scene1,  pos, direction)

	# var current_distance : float = 0.0
	# var current_point_id : int = 0	

	#while current_distance < curve.get_baked_length():
	#	var pos : Vector3= curve.sample_baked(current_distance)
	#	var next_pos : Vector3 = curve.sample_baked(current_distance + 0.1)
	#	
	#	var terrain_height : float = get_terrain_height(pos)
	#	if !is_nan(terrain_height) and !is_inf(terrain_height):
	#		pos.y = terrain_height + height_offset  # Pas de hoogte van het hek aan op de terrain hoogte
	#	var direction : Vector3 = (next_pos - pos).normalized()
	#	direction.y = 0
	#	_create_object_at(fence_scene1,  pos, direction)
	#	current_distance += spacing
		
func _determine_points_distance() -> Dictionary[int,float]:
	var ret_data : Dictionary[int,float]
	ret_data[0] = 0.0
	
	var current_point_id : int = 1
	var current_point_to_check : Vector3 = curve.get_point_position(current_point_id)

	const check_interval_distance: float = 0.5
	const check_interval_distance_squared : float = pow(check_interval_distance,2)

	var full_length : float = curve.get_baked_length()

	var current_distance : float = 0.0
	while current_distance < full_length:
		current_distance += 0.5
		var sampled_point : Vector3= curve.sample_baked(current_distance)
		if(sampled_point.distance_squared_to(current_point_to_check) < check_interval_distance_squared):
			ret_data[current_point_id] = current_distance
			print("point ID ", current_point_id, " at distance ", current_distance , " (", current_distance/ full_length," )")
			if(current_point_id == curve.point_count-1):	#this was the last point
				return ret_data	

			current_point_id = current_point_id+1
			current_point_to_check = curve.get_point_position(current_point_id)


	return ret_data

func _create_object_at(packed_scene: PackedScene, pos: Vector3, _look_at : Vector3) -> void:
	var new_instance: Node = packed_scene.instantiate()

	if _look_at.length() > 0:
		var new_basis : Basis = Basis.looking_at(_look_at, Vector3.UP)
		var new_transform : Transform3D = Transform3D(new_basis, pos)
		new_instance.transform = new_transform
	else:
		new_instance.position = pos

	created_path_objects.add_child(new_instance, true)
	new_instance.owner = created_path_objects

	if enable_random_rotation:
		new_instance.rotate_y(randf_range(0.0, 2.0 * PI))
	

func randf_range(min_val: float, max_val: float) -> float:
	return min_val + (max_val - min_val) * randf()