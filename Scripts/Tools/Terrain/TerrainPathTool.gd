@tool
extends Path3D


@export var created_path_objects : Node3D
@export var terrain: Terrain3D

@export_tool_button("Regenerate Path", "Callable") var regenerate_action = _regenerate

@export_group("Beam Settings")
@export var fence_beam_scene : PackedScene
@export var default_beam_length : float = 10.0
@export var tilt_beams : bool = false

@export_group("Pole Settings")
@export var fence_scene1 : PackedScene
@export var spacing: float = 0.3
@export var height_offset : float = 0.0
@export var point_up : bool = false
@export var enable_random_rotation : bool = true


var is_updating : bool = false
var point_alpha_distance_dictionary : Dictionary[int, float]

func _regenerate() -> void:
	if is_updating:
		return
	is_updating = true

	spawn_fences()

	is_updating = false
	
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
	var target_pos : Vector3 = get_global_position()
	created_path_objects.set_global_position( Vector3(target_pos.x, 0, target_pos.z))
	
	if curve.point_count == 0:
		push_error("Path has no points")
		return
		
	_determine_points_distance()
	
	var full_distance : float = curve.get_baked_length()
	
	if(point_alpha_distance_dictionary.is_empty() || point_alpha_distance_dictionary.keys().size() != curve.point_count):
		push_error("Point Distance Map filled in incorrectly!")
		return

	for id in range(curve.point_count -1 ):
		_fill_curve_segment(id, id +1, full_distance, false)
		
	if(curve.closed):
		_fill_curve_segment(curve.point_count - 1,0, full_distance, true)
	else:
		if(curve.point_count > 1):
			#create end segment
			var last_pos : Vector3 = curve.get_point_position(curve.point_count -1)
			var prev_pos : Vector3 = curve.get_point_position(curve.point_count -2)
			var direction : Vector3 = (prev_pos - last_pos).normalized()
			_create_object_at(fence_scene1,  _determine_object_pos_on_terrain(last_pos), direction)
			
func _determine_points_distance() -> void:
	point_alpha_distance_dictionary[0] = 0.0
	
	var current_point_id : int = 1
	var current_point_to_check : Vector3 = curve.get_point_position(current_point_id)

	const check_interval_distance: float = 0.5
	const check_interval_distance_squared : float = pow(check_interval_distance,2)

	var full_length : float = curve.get_baked_length()

	var current_distance : float = 0.0
	while current_distance < full_length:
		current_distance += check_interval_distance
		var sampled_point : Vector3= curve.sample_baked(current_distance)
		if(sampled_point.distance_squared_to(current_point_to_check) < check_interval_distance_squared):
			point_alpha_distance_dictionary[current_point_id] = current_distance
			print("point ID ", current_point_id, " at distance ", current_distance , " (", current_distance/ full_length," )")
			if(current_point_id == curve.point_count-1):	#this was the last point
				return

			current_point_id = current_point_id+1
			current_point_to_check = curve.get_point_position(current_point_id)
			
func _fill_curve_segment(start_id : int, end_id, _full_dist : float, end_segment : bool) -> void:
	var pos : Vector3= curve.get_point_position(start_id)
	var end_pos : Vector3 = curve.get_point_position(end_id)
	
	var distance_on_curve_between : float = 0 
	if(end_segment):
		distance_on_curve_between = _full_dist - point_alpha_distance_dictionary[start_id]
	else:
		distance_on_curve_between=  (point_alpha_distance_dictionary[end_id] - point_alpha_distance_dictionary[start_id])	
	
	#create object at start
	var direction : Vector3 = (end_pos - pos).normalized()
	_create_object_at(fence_scene1,  _determine_object_pos_on_terrain(pos), direction)
	
	var amount_needed_rounded : int = round(distance_on_curve_between / spacing)
	
	var distance_per_item_avg_needed : float =  distance_on_curve_between / amount_needed_rounded
	var beam_scale_mult : float = distance_per_item_avg_needed / default_beam_length

	print("filling segment between ID ", start_id , " AND ", end_id, ", dist: ", distance_on_curve_between , " of total ", _full_dist , " with ", amount_needed_rounded , " items, distance per item ", distance_per_item_avg_needed)

	var prev_seg_pos : Vector3 = pos

	for seg_id in range(1,amount_needed_rounded):
		var seg_dist_on_curve : float = point_alpha_distance_dictionary[start_id] + (seg_id * distance_per_item_avg_needed)
		var next_seg_dist_on_curve : float = point_alpha_distance_dictionary[start_id] + ((seg_id +1) * distance_per_item_avg_needed)
		var seg_pos : Vector3 = curve.sample_baked(seg_dist_on_curve)

		# make this post face what would be the next one
		var next_seg_pos : Vector3 = curve.sample_baked(next_seg_dist_on_curve)
		var new_seg_direction : Vector3 = (next_seg_pos - seg_pos).normalized()

		var new_segment_pos : Vector3 = _determine_object_pos_on_terrain(seg_pos)
		
		#create a post at the new spot
		_create_object_at(fence_scene1,new_segment_pos, new_seg_direction)

		#create beam inbetween last and this post
		_create_beam(prev_seg_pos,new_segment_pos, beam_scale_mult , distance_per_item_avg_needed)
		
		prev_seg_pos = new_segment_pos
		
	#create a beam at the very final segment
	_create_beam(prev_seg_pos, end_pos, beam_scale_mult, distance_per_item_avg_needed)
		
func _create_beam(start_pos: Vector3 , end_pos : Vector3, scale_mult : float, beam_dist : float ) -> void:
	if(fence_beam_scene == null):
		return
		
	var beam : Node3D = _create_object_at(fence_beam_scene,(start_pos + end_pos) / 2 , (start_pos - end_pos).normalized())
	
	if(beam):
		beam.set_scale(Vector3(1, 1,scale_mult))
		
		if(tilt_beams):
			var height_diff : float = start_pos.y - end_pos.y
			var angle : float = atan(height_diff / beam_dist)
			
			beam.set_rotation(Vector3(angle, beam.rotation.y, beam.rotation.z))
		
	

func _determine_object_pos_on_terrain(world_pos : Vector3) -> Vector3:
	var new_pos : Vector3 = world_pos
	
	var terrain_height : float = get_terrain_height(new_pos)
	if !is_nan(terrain_height) and !is_inf(terrain_height):
		new_pos.y = terrain_height + height_offset
		
	return new_pos	
	
func _create_object_at(packed_scene: PackedScene, pos: Vector3, _look_at : Vector3) -> Node3D:
	var new_instance: Node = packed_scene.instantiate()

	if(point_up):
		_look_at.y = 0

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
		
	return new_instance
	
func randf_range(min_val: float, max_val: float) -> float:
	return min_val + (max_val - min_val) * randf()