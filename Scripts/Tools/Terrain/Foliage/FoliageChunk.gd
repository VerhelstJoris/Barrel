@tool
class_name FoliageChunk extends Node3D

enum EFoliageLOD {NONE, TEX, LOW, HIGH}

@export_tool_button("preview in Editor", "Callable") var preview_action = _preview_in_editor
@export_tool_button("Generate Height Data for Chunk", "Callable") var generate_height_data_action = _generate_height_data

@export_group("Setup Data")
@export var chunk_transform_centered : bool = false
@export var chunk_dimenstion_size_m : float = 200.0
@export var positions_compute_shader : RDShaderFile
@export var transfer_compute_shader : RDShaderFile
@export var high_LOD_mesh : Mesh
@export var low_LOD_mesh : Mesh

@export var chunk_mask : Texture2D
@export var grass_material :Material

@export var terrain_node : Terrain3D

@export_group("Customizable Parameters")
@export var high_lod_num_work_groups_xz : int = 4

@export var foliage_target_density_sq_m : float = 80
@export var max_foliage_individual_random_offset : float = 0.2
@export var max_foliage_tilt_degrees : float = 15.0

@export var min_grass_blade_scale : float = 0.2

@export_group("runtime data - DO NOT EDIT MANUALLY")
@export var height_array : PackedFloat32Array

const vertex_move_amount_shader_parameter : String = "vertex_move_amount"

var current_lod : EFoliageLOD = EFoliageLOD.NONE

var rd : RenderingDevice

var RID_arr : Array[RID]

var instance_RID
var scenario_RID

var created_multimesh_RID : RID
var created_multimesh_buffer_RID : RID
var created_multimesh_command_buffer_RID : RID

var compute_pos_shader_RID : RID
var transfer_shader_RID : RID

var uniform_set_primary_RID : RID
var uniform_set_secondary_RID : RID
var pipeline_primary_RID : RID
var pipeline_secondary_RID : RID

var secondary_transform_buffer_RID : RID
var blade_count_buffer_RID : RID

#player transform data
var player_transform_data_arr : PackedFloat32Array
var player_transform_data_buffer_RID : RID
var player_transform_to_pass : Transform3D

# segment coord data
var segments_per_dim : int = 0
var segment_coord_data_arr : PackedInt32Array
var segment_work_data_arr : Array[Vector2i]
var segment_found_edges_left : Array[Vector2i]
var segment_found_edges_right : Array[Vector2i]
var segment_center_edges : Array[Vector2i]

var segments_filled_map : Dictionary[Vector2i, int]
var update_counter : int = 0

var segment_coord_data_buffer_RID : RID

var compute_active : bool = false

var initialized : bool = false

func _get_vertex_spacing() -> float:
	if(!terrain_node):
		push_error("Terrain node is null, cannot retrieve vertex spacing, returning default value")
		return 4.0
		
	return terrain_node.vertex_spacing

func _generate_height_data() -> void:
	height_array.clear()
	var vertex_spacing :float = _get_vertex_spacing()
	
	var elem_per_dim : int = int(chunk_dimenstion_size_m / vertex_spacing) +1
	height_array.resize( elem_per_dim * elem_per_dim)
	
	if(terrain_node):
		for row in elem_per_dim:
			for col in elem_per_dim:
				var current_index : int = row * elem_per_dim + col
				var chunk_pixel_coord : Vector2i
				if(chunk_transform_centered):
					chunk_pixel_coord = Vector2i( 
						int( (global_position.x - (chunk_dimenstion_size_m * 0.5) )/ terrain_node.vertex_spacing) ,
						int( (global_position.z - (chunk_dimenstion_size_m * 0.5) )/ terrain_node.vertex_spacing) )
				else:
					chunk_pixel_coord = Vector2i(int(global_position.x / terrain_node.vertex_spacing) ,int(global_position.z / terrain_node.vertex_spacing) )
				var corresponding_world_pos : Vector3 = Vector3( (chunk_pixel_coord.x + row) * terrain_node.vertex_spacing, 0, (chunk_pixel_coord.y + col) * terrain_node.vertex_spacing)
				var found_height : float = terrain_node.data.get_height(corresponding_world_pos)
				if(found_height == NAN):
					push_error("NO height for chunk at (", row , ", ", col, ") and id: " , current_index , " and world pos ", corresponding_world_pos, ", Defaulting to 0!")
					height_array[current_index] = 0
					continue
				height_array[current_index] = found_height
				print("height for chunk at (", row , ", ", col, ") and id: " , current_index , " and world pos ", corresponding_world_pos, " : " , found_height)
	else:
		for row in elem_per_dim:
			for col in elem_per_dim:
				var current_index : int = row * elem_per_dim + col
				height_array[current_index]= current_index

func _preview_in_editor() -> void:
	if(initialized):
		RenderingServer.call_on_render_thread(_cleanup)
	else:
		RenderingServer.call_on_render_thread(_setup_compute_pipeline)
	
func _ready() -> void:
	segments_per_dim = int(chunk_dimenstion_size_m / _get_vertex_spacing())
	segment_work_data_arr.resize(segments_per_dim*segments_per_dim)
	segment_found_edges_left.resize(segments_per_dim)
	segment_found_edges_right.resize(segments_per_dim)
	segment_center_edges.resize(segments_per_dim)
	for row in range(segments_per_dim):
		for col in range(segments_per_dim):
			segments_filled_map[Vector2i(row,col)] = 0

	if(!Engine.is_editor_hint()):
		RenderingServer.call_on_render_thread(_cleanup)
		RenderingServer.call_on_render_thread(_setup_compute_pipeline)
		
func _contruct_multimesh_bounding_box() ->AABB:
	var extra_offset : float = 5
	
	var bb_size : Vector3 = Vector3(chunk_dimenstion_size_m + extra_offset,500,chunk_dimenstion_size_m + extra_offset)
	#offset by half the size towards 0
	var bb_pos : Vector3 = Vector3( -(chunk_dimenstion_size_m + extra_offset) * 0.5,
	0,
	-(chunk_dimenstion_size_m + extra_offset) * 0.5)
	
	var bounding_box : AABB = AABB(bb_pos, bb_size)
	return bounding_box


func _process(_delta: float) -> void:
	var viewport : Viewport
	if Engine.is_editor_hint():
		viewport = EditorInterface.get_editor_viewport_3d()
	else:
		viewport = get_viewport()

	var cam : Camera3D = viewport.get_camera_3d()
	var cam_transform : Transform3D = cam.global_transform
	
	if(player_transform_to_pass.is_equal_approx(cam_transform)):
		return
		
	if(!compute_active && initialized):
		player_transform_to_pass = cam_transform
		RenderingServer.call_on_render_thread(_update_compute_data.bind(player_transform_to_pass, cam))
		
func _setup_compute_pipeline()	-> void:
	if(get_world_3d() == null):
		return
		
	rd = RenderingServer.get_rendering_device()

	scenario_RID = get_world_3d().scenario
	
	if(!scenario_RID.is_valid()):
		return
	RID_arr.append(scenario_RID)

	instance_RID = RenderingServer.instance_create()
	if(!instance_RID.is_valid()):
		return
	RID_arr.append(instance_RID)	
		
	#load shaders
	compute_pos_shader_RID = _load_shader_from_file(positions_compute_shader)
	if(!compute_pos_shader_RID.is_valid()):
		push_error("FAILED TO LOAD SHADER: ", positions_compute_shader.to_string())
		return
	RID_arr.append(compute_pos_shader_RID)


	transfer_shader_RID = _load_shader_from_file(transfer_compute_shader)
	if(!transfer_shader_RID.is_valid()):
		push_error("FAILED TO LOAD SHADER: ", transfer_compute_shader.to_string())
		return
	RID_arr.append(transfer_shader_RID)
	
	#height data binding
	var height_data_uniform = RDUniform.new()
	height_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	height_data_uniform.binding = 0
	var input_bytes := height_array.to_byte_array()
	var height_data_RID : RID = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	RID_arr.append(height_data_RID)
	height_data_uniform.add_id(height_data_RID)
	
	#multimesh storage buffer binding
	var multimesh_transform_buffer_uniform := RDUniform.new()
	multimesh_transform_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	multimesh_transform_buffer_uniform.binding = 0

	var vertex_spacing : float = _get_vertex_spacing()
	var estimated_per_chunk : int = int(foliage_target_density_sq_m * vertex_spacing * vertex_spacing)
	var estimated_count : int = int(high_lod_num_work_groups_xz * high_lod_num_work_groups_xz * estimated_per_chunk)
	_create_new_multimesh(rd,estimated_count, vertex_spacing)
	var buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(created_multimesh_RID)
	RID_arr.append(buffer_rid)
	multimesh_transform_buffer_uniform.add_id(buffer_rid)

	#Blade count per group binding
	var blade_count_array_uniform = RDUniform.new()
	blade_count_array_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	blade_count_array_uniform.binding = 2
	
	blade_count_buffer_RID = rd.storage_buffer_create(high_lod_num_work_groups_xz*high_lod_num_work_groups_xz * 4) #*4 to account for int size
	RID_arr.append(blade_count_buffer_RID)
	blade_count_array_uniform.add_id(blade_count_buffer_RID)	
	
	#multimesh command buffer binding
	var multimesh_command_buffer_uniform := RDUniform.new()
	multimesh_command_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	multimesh_command_buffer_uniform.binding = 3
	multimesh_command_buffer_uniform.add_id(created_multimesh_command_buffer_RID)
	
	# float parameter binding
	var float_params_arr : PackedByteArray =  PackedFloat32Array(
		[vertex_spacing, 100.0, sqrt(foliage_target_density_sq_m), max_foliage_individual_random_offset, deg_to_rad(max_foliage_tilt_degrees), min_grass_blade_scale, 100.0]
		 ).to_byte_array()
	var fparameter_buffer_RID :RID = rd.storage_buffer_create(float_params_arr.size(), float_params_arr)
	RID_arr.append(fparameter_buffer_RID)

	var float_parameter_uniform = RDUniform.new()
	float_parameter_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	float_parameter_uniform.binding = 3
	float_parameter_uniform.add_id(fparameter_buffer_RID)
	
	#int parameter binding
	var int_params_arr : PackedByteArray =  PackedInt32Array(
													  [estimated_per_chunk , int(chunk_dimenstion_size_m / vertex_spacing)]
												).to_byte_array()
	var iparameter_buffer_RID :RID = rd.storage_buffer_create(int_params_arr.size(), int_params_arr)
	RID_arr.append(iparameter_buffer_RID)

	var int_parameter_uniform = RDUniform.new()
	int_parameter_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_parameter_uniform.binding = 4
	int_parameter_uniform.add_id(iparameter_buffer_RID)	
	
	#mask binding
	var mask_tex_uniform = RDUniform.new()
	mask_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mask_tex_uniform.binding = 5
	mask_tex_uniform.add_id(_init_existing_texture_data(rd, chunk_mask))

	#player data binding
	player_transform_data_arr = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var player_data_arr : PackedByteArray = player_transform_data_arr.to_byte_array()
	player_transform_data_buffer_RID = rd.storage_buffer_create(player_data_arr.size(), player_data_arr)
	RID_arr.append(player_transform_data_buffer_RID)

	var player_data_uniform = RDUniform.new()
	player_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	player_data_uniform.binding = 6
	player_data_uniform.add_id(player_transform_data_buffer_RID)

	# array with coordinates of segments to draw
	segment_coord_data_arr.resize(high_lod_num_work_groups_xz * high_lod_num_work_groups_xz *2)
	var segment_coord_packed_arr : PackedByteArray = segment_coord_data_arr.to_byte_array()
	segment_coord_data_buffer_RID = rd.storage_buffer_create(segment_coord_packed_arr.size(), segment_coord_packed_arr)
	RID_arr.append(segment_coord_data_buffer_RID)	
	
	var segments_coord_uniform : RDUniform = RDUniform.new()
	segments_coord_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	segments_coord_uniform.binding = 7
	segments_coord_uniform.add_id(segment_coord_data_buffer_RID)
	
	#sparse tranform buffer pre-condensed
	var transform_array_uniform = RDUniform.new()
	transform_array_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	transform_array_uniform.binding = 1
	# *45 for 12 elements of a transform with size 4 (float)
	secondary_transform_buffer_RID = rd.storage_buffer_create(estimated_count * 48,PackedByteArray())
	RID_arr.append(secondary_transform_buffer_RID)
	transform_array_uniform.add_id(secondary_transform_buffer_RID)	

	#add all uniforms bindings into the set
	uniform_set_primary_RID = rd.uniform_set_create(
			[height_data_uniform, transform_array_uniform, blade_count_array_uniform, float_parameter_uniform, mask_tex_uniform, player_data_uniform, int_parameter_uniform, segments_coord_uniform]
			, compute_pos_shader_RID, 0)
	RID_arr.append(uniform_set_primary_RID)

	uniform_set_secondary_RID = rd.uniform_set_create(
		[multimesh_transform_buffer_uniform, transform_array_uniform , blade_count_array_uniform,multimesh_command_buffer_uniform, int_parameter_uniform]
		, transfer_shader_RID, 0)
	RID_arr.append(uniform_set_secondary_RID)

	
	# Create a compute pipeline
	# don't actually run them or anything yet
	pipeline_primary_RID = rd.compute_pipeline_create(compute_pos_shader_RID)
	RID_arr.append(pipeline_primary_RID)
	pipeline_secondary_RID = rd.compute_pipeline_create(transfer_shader_RID)
	RID_arr.append(pipeline_secondary_RID)

	set_process(true)
	initialized = true
	
func _exit_tree() -> void:
	_cleanup()
	
func _cleanup() -> void:
	if(created_multimesh_RID.is_valid()):
		RenderingServer.multimesh_allocate_data(created_multimesh_RID, 0 , RenderingServer.MULTIMESH_TRANSFORM_3D,false, false, true)

	for rid_to_free in RID_arr:
		_try_free_rid(rd, rid_to_free)
	RID_arr.clear()	
	
	initialized = false
	compute_active = false
	
	set_process(false)

func _try_free_rid(_rd : RenderingDevice, rid : RID) -> void:
	if(_rd == null):
		return
		
	if(!rid.is_valid()):
		return
		
	_rd.free_rid(rid)
	
func _load_shader_from_file(file : RDShaderFile) -> RID:
	var spirv: RDShaderSPIRV = file.get_spirv()
	if(!spirv):
		push_error("FAILED TO LOAD SHADER: ", file.to_string())
		return RID()
		
	return rd.shader_create_from_spirv(spirv)
	
func _init_existing_texture_data(_rd : RenderingDevice, tex: Texture2D)-> RID:
	var image := tex.get_image()
	image.convert(Image.FORMAT_RGBAF)
	
	var tex_format := RDTextureFormat.new()
	tex_format.width = image.get_width()
	tex_format.height = image.get_height()
	tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT + RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	tex_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	var tex_RID : RID = _rd.texture_create(tex_format, RDTextureView.new(), [image.get_data()])
	RID_arr.append(tex_RID)
	return tex_RID
	
func _create_new_multimesh(_rd : RenderingDevice, estimated_transform_count, _vertex_spacing : float) -> void:
	created_multimesh_RID =RenderingServer.multimesh_create()
	RID_arr.append(created_multimesh_RID)
	#calculate an estimated instance count to pass through
	RenderingServer.multimesh_allocate_data(created_multimesh_RID, estimated_transform_count , RenderingServer.MULTIMESH_TRANSFORM_3D,false, false, true)
	high_LOD_mesh.surface_set_material(0,grass_material)
	RenderingServer.multimesh_set_mesh(created_multimesh_RID, high_LOD_mesh.get_rid())
	RenderingServer.instance_set_transform(instance_RID, get_global_transform())
	var created_aabb : AABB = _contruct_multimesh_bounding_box()
	RenderingServer.multimesh_set_custom_aabb(created_multimesh_RID,created_aabb)
	RenderingServer.instance_set_custom_aabb(instance_RID, created_aabb)
	
	RenderingServer.instance_set_scenario(instance_RID, scenario_RID)
	RenderingServer.instance_set_base(instance_RID, created_multimesh_RID)
	RenderingServer.instance_geometry_set_flag(instance_RID, RenderingServer.InstanceFlags.INSTANCE_FLAG_USE_DYNAMIC_GI, true)
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance_RID, RenderingServer.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF)
	
	created_multimesh_buffer_RID = RenderingServer.multimesh_get_buffer_rd_rid(created_multimesh_RID)
	RID_arr.append(created_multimesh_buffer_RID)

	created_multimesh_command_buffer_RID = RenderingServer.multimesh_get_command_buffer_rd_rid(created_multimesh_RID);
	RID_arr.append(created_multimesh_command_buffer_RID)

func _update_compute_data(_player_cam_transform_world: Transform3D, _player_cam : Camera3D)->void:
	if(!pipeline_primary_RID.is_valid() || !uniform_set_primary_RID.is_valid() || !uniform_set_secondary_RID.is_valid()):
		return
	
	compute_active = true
	
	update_counter += 1
	
	#this would be where we pass player transform through or updated textures
	rd = RenderingServer.get_rendering_device()
	_update_player_data_buffer(rd, _player_cam_transform_world)
	_update_segments_to_draw_buffer(rd, _player_cam_transform_world, _player_cam)
	
	var compute_list : int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_primary_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_primary_RID, 0)
	rd.compute_list_dispatch(compute_list,high_lod_num_work_groups_xz,1,high_lod_num_work_groups_xz)

	# wait until the first shader is done
	rd.compute_list_add_barrier(compute_list)

	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_secondary_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_secondary_RID, 0)
	rd.compute_list_dispatch(compute_list, high_lod_num_work_groups_xz,1,high_lod_num_work_groups_xz)

	rd.compute_list_end()

	compute_active = false

func _update_player_data_buffer(_rd: RenderingDevice, _player_cam_transform_world: Transform3D) -> void:
	if(!player_transform_data_buffer_RID.is_valid()):
		return

	player_transform_data_arr[0] = _player_cam_transform_world.origin.x - self.get_global_position().x
	player_transform_data_arr[1] = _player_cam_transform_world.origin.y - self.get_global_position().y
	player_transform_data_arr[2] = _player_cam_transform_world.origin.z - self.get_global_position().z
	
	var cam_rot : Vector3 = _player_cam_transform_world.basis.get_euler()
	player_transform_data_arr[3] = cam_rot.x
	player_transform_data_arr[4] = cam_rot.y
	player_transform_data_arr[5] = cam_rot.z
	
	var player_data_arr : PackedByteArray = player_transform_data_arr.to_byte_array()
	_rd.buffer_update(player_transform_data_buffer_RID, 0, player_data_arr.size() ,player_data_arr)
	
func _update_segments_to_draw_buffer(_rd : RenderingDevice, _player_cam_transform_world: Transform3D, _player_cam : Camera3D) -> void:
	if(!segment_coord_data_buffer_RID.is_valid()):
		return
		

	var vertex_spacing : float = _get_vertex_spacing()		
	#start by calculating the segment we are currently in
	var playerdiff : Vector2 = Vector2(  _player_cam_transform_world.origin.x- (global_position.x - (chunk_dimenstion_size_m * 0.5)), _player_cam_transform_world.origin.z- (global_position.z - (chunk_dimenstion_size_m * 0.5)) )
	
	var player_current_sub_id_pos : Vector2 = Vector2(playerdiff.x / vertex_spacing, playerdiff.y / vertex_spacing)
	var player_current_segment_id : Vector2i = Vector2i( int(floor(player_current_sub_id_pos.x))  ,int(floor(player_current_sub_id_pos.y)) )

	#reset the working data from last frame
	segment_work_data_arr.fill(Vector2i.MIN)
	segment_found_edges_left.fill(Vector2i.MIN)
	segment_found_edges_right.fill(Vector2i.MIN)
	
	segment_work_data_arr[0] = player_current_segment_id
	var segments_found : int = 1
	#find the vector that describe the 'edges' of the camera
	segments_found += _find_camera_edge_vector_additive(_player_cam , player_current_sub_id_pos, segments_per_dim)
	
	var diff_coord_byte_arr : PackedByteArray = segment_coord_data_arr.to_byte_array()
	_rd.buffer_update(segment_coord_data_buffer_RID, 0, diff_coord_byte_arr.size() ,diff_coord_byte_arr)

const compass_directions : Array[Vector2i] = [Vector2i(0,-1),Vector2i(1,-1), Vector2i(1,0),Vector2i(1,1),Vector2i(0,1) ,Vector2i(-1,1),Vector2i(-1,0), Vector2i(-1,-1)]	#clockwise directions starting with NORTH

# returns 	
func _find_camera_edge_vector_additive(_camera : Camera3D, _player_segment_sub_pos : Vector2, max_segments_per_side : int) -> int:
	var cam_frustrum : Array[Plane] = _camera.get_frustum()
	var cam_forward : Vector3 = _camera.get_global_transform().basis.x
	
	var left_pos : Vector3 = cam_frustrum[2].project(_camera.get_global_position() -cam_forward)
	var right_pos : Vector3 = cam_frustrum[4].project(_camera.get_global_position() +cam_forward)

	var left_found_amount : int = _find_ray_intersect_grid(_player_segment_sub_pos, Vector3(left_pos - _camera.get_global_position()),max_segments_per_side, true)
	var right_found_amount : int = _find_ray_intersect_grid(_player_segment_sub_pos, Vector3(right_pos - _camera.get_global_position()),max_segments_per_side, false)
	var center_found_amount : int = 0
	
	var total_edge_points_found : int = left_found_amount + right_found_amount + center_found_amount

	# find all the segments in between those 2 ends
	var edge_amount_prioritize_per_side : int = high_lod_num_work_groups_xz
	
	var end_id : int = _interleave_edge_data_into_work_array(left_found_amount, right_found_amount, center_found_amount, edge_amount_prioritize_per_side)
	
	var compass_index : int = ((int(round( atan2(cam_forward.z, cam_forward.x)/ (2 * PI / 8))) + 8) % 8)	#divide the 360 look direction degrees into 8 sections for the cardinal directions
	#var total_points_found : int =_flood_fill_work_data(compass_index,total_edge_points_found + 1, edge_amount_prioritize_per_side, max_segments_per_side)
	
	return 0


func _flood_fill_work_data(compass_id : int, offset : int, edge_amount_to_prioritize : int,  max_segments_per_side : int) -> int:
	#contruct an array of direction to check
	var prev_id : int = compass_id -1  if compass_id-1 > 0 else  7
	var query_directions : Array[Vector2i] = [compass_directions[compass_id], compass_directions[prev_id], compass_directions[ (compass_id +1) % 8]]
	
	var current_write_id : int = offset
	var current_read_id : int = 0
	var max_possible_tests : int = max_segments_per_side* max_segments_per_side
	while current_write_id < max_possible_tests && current_read_id < current_write_id:
		var segment_to_check : Vector2i = segment_work_data_arr[current_read_id] + query_directions[0]
		current_read_id+=1

		# chances are the next element in the edge is this, if so, skip it
		# how to do this more intelligently
		if(segment_to_check == segment_work_data_arr[current_read_id]+query_directions[0]):	
			continue

		if(segment_to_check.x < 0 ||segment_to_check.y < 0 || segment_to_check.x >= max_segments_per_side || segment_to_check.y >= max_segments_per_side ):
			continue

		# checking if the segment is already in the array has a massive performance impact
		if segments_filled_map[segment_to_check] == update_counter:	
			continue

		segments_filled_map[segment_to_check] = update_counter
		segment_work_data_arr[current_write_id] = segment_to_check
		current_write_id +=1

	return current_write_id
	

func _interleave_edge_data_into_work_array(left_edges_found : int , right_edges_found : int, center_edges_found : int,  edge_cell_amount_to_prioritize_per_side : int) -> int:
	#interleave those segments in the work array so when we iterate to fill in the 'polygon' we do it somewhat in the order of closeness to player
	
	var read_index_data : Dictionary[String, int] = {"Left" : 0, "Right":0, "Center":0}
	var final_write_id : int = 0

	var amount_to_write_prioritized : int = min(edge_cell_amount_to_prioritize_per_side * 2, left_edges_found + right_edges_found + center_edges_found)
	final_write_id = _write_edge_data_chunk_into_work_array(left_edges_found, right_edges_found, center_edges_found, 1,amount_to_write_prioritized, read_index_data)

	var amount_to_write_post_prio : int = left_edges_found + right_edges_found + center_edges_found - amount_to_write_prioritized	

	if(amount_to_write_post_prio > 0):
		var post_prioritize_write_offset : int = 1 + (edge_cell_amount_to_prioritize_per_side * edge_cell_amount_to_prioritize_per_side)
		final_write_id = _write_edge_data_chunk_into_work_array(left_edges_found, right_edges_found, center_edges_found, post_prioritize_write_offset, amount_to_write_post_prio, read_index_data)

	return final_write_id
	
func _write_edge_data_chunk_into_work_array(left_edges_found : int, right_edges_found : int, _center_edges_found : int, write_offset : int , amount_to_write: int,  read_index_data: Dictionary[String, int]) -> int:
	var read_left_id  :int = read_index_data["Left"]
	var read_right_id  :int = read_index_data["Right"]
	var read_center_id : int = read_index_data["Center"]
	var write_id : int = 0
	for current_point_id in range(amount_to_write):
		#determine where in the work array to write to
		write_id = current_point_id + write_offset

		if(current_point_id % 2 == 0):
		#try left first
			if(read_left_id < left_edges_found):
				segment_work_data_arr[write_id] = segment_found_edges_left[read_left_id]
				read_left_id += 1
			elif(read_right_id < right_edges_found):
				segment_work_data_arr[write_id] = segment_found_edges_right[read_right_id]
				read_right_id += 1
		else:
		#try right first
			if(read_right_id < right_edges_found):
				segment_work_data_arr[write_id] = segment_found_edges_right[read_right_id]
				read_right_id += 1
			elif(read_left_id < left_edges_found):
				segment_work_data_arr[write_id] = segment_found_edges_left[read_left_id]
				read_left_id += 1
	
	read_index_data["Left"] = read_left_id
	read_index_data["Right"] = read_right_id
	read_index_data["Center"] = read_center_id
	return write_id

# use the DDA algorithm to find the edges 	
func _find_ray_intersect_grid(grid_start_pos : Vector2, dir: Vector3, max_segment_id : int, is_left_edge : bool) ->int:
	dir.y = 0
	dir = dir.normalized()

	# setup data
	var ray_unit_step_size : Vector2 = Vector2(sqrt(1 + (dir.z / dir.x) * (dir.z / dir.x)), sqrt(1 + (dir.x / dir.z) * (dir.x / dir.z)))
	var step_unit_dir : Vector2i = Vector2(sign(dir.x), sign(dir.z))

	#iteration data
	var current_tile_to_check : Vector2i = Vector2i(int(grid_start_pos.x),int(grid_start_pos.y))	# no sub-tile-coord
	var current_ray_length_per_dim : Vector2	

	# need to calculate how much or our ray is in the starting cell for both x/y
	if(dir.x < 0):
		current_ray_length_per_dim.x = (grid_start_pos.x - current_tile_to_check.x) * ray_unit_step_size.x
	else:
		current_ray_length_per_dim.x = ((current_tile_to_check.x +1) - grid_start_pos.x) * ray_unit_step_size.x
	
	if(dir.z < 0):
		current_ray_length_per_dim.y = (grid_start_pos.y - current_tile_to_check.y) * ray_unit_step_size.y
	else:
		current_ray_length_per_dim.y = ((current_tile_to_check.y +1) - grid_start_pos.y) * ray_unit_step_size.y

	var current_distance : float =0
	var max_distance : float = 50
	var amount_found : int = 0
	while current_distance < max_distance && amount_found < max_segment_id:
		#step towards current shortest direction
		if(current_ray_length_per_dim.x < current_ray_length_per_dim.y):
			current_tile_to_check.x += step_unit_dir.x
			current_distance = current_ray_length_per_dim.x
			current_ray_length_per_dim.x += ray_unit_step_size.x
		else:
			current_tile_to_check.y += step_unit_dir.y
			current_distance = current_ray_length_per_dim.y
			current_ray_length_per_dim.y += ray_unit_step_size.y

		# we've hit the edge of our chunk -> abort
		if(current_tile_to_check.x < 0 || current_tile_to_check.y < 0 || current_tile_to_check.x > max_segment_id || current_tile_to_check.y > max_segment_id):
			return amount_found

		segments_filled_map[current_tile_to_check] = update_counter
		if(is_left_edge):
			segment_found_edges_left[amount_found] = current_tile_to_check
		else:
			segment_found_edges_right[amount_found] = current_tile_to_check
	
		amount_found +=1

	return amount_found
