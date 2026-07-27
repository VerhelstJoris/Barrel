@tool
class_name FoliageChunk extends Node3D

enum EFoliageLOD {NONE, TEX, LOW, HIGH}

@export_tool_button("Preview in Editor", "Callable") var preview_action : Callable = _preview_in_editor
@export_tool_button("Generate Height Data for Chunk", "Callable") var generate_height_data_action : Callable = _generate_height_data

const foliage_node_meta : String = "Node_FoliageChunk"
const foliage_shader_bend_mask : String = "shader_parameter/bending_mask"
const foliage_shader_bend_mask_size : String = "shader_parameter/bending_mask_size_m"

@export_group("Setup Data")
@export var visibility_notifier : VisibleOnScreenNotifier3D
@export var terrain_node : Terrain3D
@export var inverse_terrain_node : Terrain3D
@export var bender_mask_subviewport : SubViewport
@export var bender_mask_camera : Camera3D

@export var chunk_transform_centered : bool = false
@export var chunk_dimenstion_size_m : float = 200.0
@export var chunk_mask : Texture2D

@export var positions_compute_shader : RDShaderFile
@export var transfer_compute_shader : RDShaderFile
@export var bender_compute_shader : RDShaderFile

@export_group("High LOD")
@export var target_density_sq_m_high_LOD : float = 80
@export var foliage_cam_bias_degrees_high_LOD : float = 30
@export var distance_thresholds_high_lod : Vector3 = Vector3(8,16,32)
@export var foliage_mesh_high_LOD : Mesh
@export var foliage_material_high_LOD :Material
@export var high_lod_num_work_groups : Vector2i = Vector2i(8,8)

@export_group("Low LOD")
@export var target_density_sq_m_low_LOD : float = 10
@export var foliage_cam_bias_degrees_low_LOD : float = 70
@export var distance_thresholds_low_lod : Vector3 = Vector3(32,32,32)
@export var foliage_mesh_low_LOD : Mesh
@export var foliage_material_low_LOD :Material

@export_group("Foliage Bending")
@export var bender_mask_res : int = 512
@export var unbend_rate_per_second : float = 0.05

var bend_float_param_arr : PackedByteArray
var fparameter_buffer_bend_RID :RID

@export_group("Customizable Parameters")
	
@export var max_foliage_individual_random_offset : float = 0.2
@export var max_foliage_tilt_degrees : float = 15.0
# In ascending order, at what distances from the player should a segment of grass blades draw 1/2/3 blades less per 4

@export var min_grass_blade_scale : float = 0.2

@export_group("runtime data - DO NOT EDIT MANUALLY")
@export var height_array : PackedFloat32Array

const large_float_dist : float = 99999999999

var created_bender_image : Image
var created_bender_image_RID : RID
var created_bender_tex_RD : Texture2DRD


var rd : RenderingDevice

var RID_arr : Array[RID]

var scenario_RID

var mm_high_RID : RID
var mm_high_instance_RID : RID
var mm_high_sparse_transform_buffer_rid : RID
var mm_high_packed_transform_buffer_rid : RID
var mm_high_command_buffer_rid : RID
var mm_high_instance_count_buffer_rid : RID

var mm_low_RID : RID
var mm_low_instance_RID : RID
var mm_low_sparse_transform_buffer_rid : RID
var mm_low_packed_transform_buffer_rid : RID
var mm_low_command_buffer_rid : RID
var mm_low_instance_count_buffer_rid : RID

#shader rid
var compute_pos_shader_RID : RID
var transfer_shader_RID : RID
var bender_shader_RID : RID

#uniform sets
var mm_high_uniform_set_pos_calc_RID : RID
var mm_low_uniform_set_pos_calc_RID : RID
var mm_high_uniform_set_pos_transfer_RID : RID
var mm_low_uniform_set_pos_transfer_RID : RID
var uniform_set_bender_RID : RID

#pipelines
var mm_pipeline_pos_calc_RID : RID
var mm_pipeline_pos_transfer_RID : RID
var pipeline_bender_RID : RID

#player transform data
var player_transform_data_arr : PackedFloat32Array
var player_transform_data_mm_high_buffer_rid : RID
var player_transform_to_pass : Transform3D

#current foliage bending data
var current_bender_data_tex_RID : RID

# segment coord data
var segments_per_dim : int = 0
var segment_coord_data_arr : PackedInt32Array
var segment_work_data_arr : PackedByteArray
var segment_found_edges_left : PackedInt32Array
var segment_found_edges_right : PackedInt32Array
var segment_center_edges : PackedInt32Array
var segment_center_corner_edges_left : PackedInt32Array
var segment_center_corner_edges_right : PackedInt32Array

var segments_found_left : int
var segments_found_right : int
var segments_found_center : int
var segment_work_filled_in : int
var flood_fill_query_directions : Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO,Vector2i.ZERO]

var segments_filled_map : Dictionary[Vector2i, int]
var update_counter : int = 0

var segment_coord_data_mm_buffer_rid : RID

var compute_active : bool = false

var initialized : bool = false

func _get_vertex_spacing() -> float:
	if(!terrain_node):
		push_error("Terrain node is null, cannot retrieve vertex spacing, returning default value")
		return 4.0
		
	return terrain_node.vertex_spacing

func _generate_height_data() -> void:
	var min_height :float = large_float_dist
	var max_height :float = -large_float_dist

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
						int( (global_position.x - (chunk_dimenstion_size_m * 0.5) )/ vertex_spacing) ,
						int( (global_position.z - (chunk_dimenstion_size_m * 0.5) )/ vertex_spacing) )
				else:
					chunk_pixel_coord = Vector2i(int(global_position.x / vertex_spacing) ,int(global_position.z / vertex_spacing) )
				var corresponding_world_pos : Vector3 = Vector3( (chunk_pixel_coord.x + row) * vertex_spacing, 0, (chunk_pixel_coord.y + col) * vertex_spacing)
				var found_height : float = terrain_node.data.get_height(corresponding_world_pos)
				if(found_height == NAN):
					push_error("NO height for chunk at (", row , ", ", col, ") and id: " , current_index , " and world pos ", corresponding_world_pos, ", Defaulting to 0!")
					height_array[current_index] = 0
					continue
				min_height = min(min_height, found_height)
				max_height = max(max_height, found_height)	
				height_array[current_index] = found_height
				print("height for chunk at (", row , ", ", col, ") and id: " , current_index , " and world pos ", corresponding_world_pos, " : " , found_height)
	else:
		for row in elem_per_dim:
			for col in elem_per_dim:
				var current_index : int = row * elem_per_dim + col
				height_array[current_index]= current_index
				min_height = min(min_height, current_index)
				max_height = max(max_height, current_index)	
				
			
	const offset : float = 5.0			
	if(bender_mask_camera):
		bender_mask_camera.size = chunk_dimenstion_size_m
		bender_mask_camera.global_position.x = get_global_position().x
		bender_mask_camera.global_position.y = min_height -offset		
		bender_mask_camera.global_position.z = get_global_position().z
		bender_mask_camera.far = abs(max_height - min_height) + (offset *2)
		
	if(visibility_notifier):
		const size_padding : float = 5.0
		visibility_notifier.aabb.size = Vector3(chunk_dimenstion_size_m + size_padding,  abs(max_height - min_height) + (offset * 2), chunk_dimenstion_size_m + size_padding)
		var horizontal_offset := (chunk_dimenstion_size_m* 0.5) + (size_padding * 0.5)
		visibility_notifier.aabb.position.x = -horizontal_offset
		visibility_notifier.aabb.position.z = -horizontal_offset
		visibility_notifier.aabb.position.y = min_height - offset

func _preview_in_editor() -> void:
	if(initialized):
		RenderingServer.call_on_render_thread(_cleanup)
	else:
		RenderingServer.call_on_render_thread(_setup_compute_pipeline)
	
func _ready() -> void:
	_intialize_segments_data()
	_initialize_bender_data()

	if(!Engine.is_editor_hint()):
		RenderingServer.call_on_render_thread(_cleanup)
		RenderingServer.call_on_render_thread(_setup_compute_pipeline)
		

func _intialize_segments_data() -> void:
	segments_per_dim = int(chunk_dimenstion_size_m / _get_vertex_spacing())
	segment_work_data_arr.resize(segments_per_dim*segments_per_dim *2 *4)
	segment_found_edges_left.resize(segments_per_dim *  4)
	segment_found_edges_right.resize(segments_per_dim * 4)
	segment_center_edges.resize(segments_per_dim *2 * 2)
	segment_center_corner_edges_left.resize(segments_per_dim * 2)
	segment_center_corner_edges_right.resize(segments_per_dim * 2)
	for row in range(segments_per_dim):
			for col in range(segments_per_dim):
				segments_filled_map[Vector2i(row,col)] = 0
		
func _initialize_bender_data() -> void:
	if(inverse_terrain_node):
		inverse_terrain_node.material.show_checkered = false
	
	if(bender_mask_subviewport):
		bender_mask_subviewport.size = Vector2(bender_mask_res,bender_mask_res)	
		
	created_bender_image = Image.create_empty(bender_mask_res, bender_mask_res, false, Image.FORMAT_RF)	
	
func _process(_delta: float) -> void:
	if(!visibility_notifier.is_on_screen()):
		return
	
	var viewport : Viewport
	if Engine.is_editor_hint():
		viewport = EditorInterface.get_editor_viewport_3d()
	else:
		viewport = get_viewport()

	var cam : Camera3D = viewport.get_camera_3d()
	var cam_transform : Transform3D = cam.global_transform

	if(player_transform_to_pass.is_equal_approx(cam_transform)):
		RenderingServer.call_on_render_thread(_update_compute_bender_only_data.bind(_delta))		
		return

	if(!compute_active && initialized):
		player_transform_to_pass = cam_transform
		RenderingServer.call_on_render_thread(_update_compute_segments_data.bind(player_transform_to_pass, cam, _delta))
		
func _setup_compute_pipeline()	-> void:
	if(get_world_3d() == null):
		return
		
	rd = RenderingServer.get_rendering_device()
	scenario_RID = get_world_3d().scenario
	
	if(!scenario_RID.is_valid()):
		return
	RID_arr.append(scenario_RID)
				
	_load_shaders()	
		
	var vertex_spacing : float = _get_vertex_spacing()
	var high_estimated_per_chunk : int = int(target_density_sq_m_high_LOD * vertex_spacing * vertex_spacing)
	var mm_high_estimated_count : int = int(high_lod_num_work_groups.x * high_lod_num_work_groups.y * high_estimated_per_chunk)
		
	var low_estimated_per_chunk : int = int(target_density_sq_m_low_LOD * vertex_spacing * vertex_spacing)
	var chunks_per_dim : int = int(chunk_dimenstion_size_m / vertex_spacing)
	var mm_low_estimated_count : int = int(low_estimated_per_chunk * chunks_per_dim * chunks_per_dim)
	
	_setup_multimesh_data(mm_high_estimated_count, mm_low_estimated_count)
	
	#height data binding
	var height_data_uniform = RDUniform.new()
	height_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	height_data_uniform.binding = 0
	var input_bytes := height_array.to_byte_array()
	var height_data_RID : RID = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	RID_arr.append(height_data_RID)
	height_data_uniform.add_id(height_data_RID)
	
	#multimesh storage buffer binding
	var mm_high_packed_transform_buffer_uniform := RDUniform.new()
	mm_high_packed_transform_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_high_packed_transform_buffer_uniform.binding = 0
	mm_high_packed_transform_buffer_uniform.add_id(mm_high_packed_transform_buffer_rid)

	var mm_low_packed_transform_buffer_uniform := RDUniform.new()
	mm_low_packed_transform_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_low_packed_transform_buffer_uniform.binding = 0
	mm_low_packed_transform_buffer_uniform.add_id(mm_low_packed_transform_buffer_rid)

	#Blade count per group binding
	var mm_high_count_arr_uniform = RDUniform.new()
	mm_high_count_arr_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_high_count_arr_uniform.binding = 2
	
	mm_high_instance_count_buffer_rid = rd.storage_buffer_create(high_lod_num_work_groups.x * high_lod_num_work_groups.y * 4) #*4 to account for int size
	RID_arr.append(mm_high_instance_count_buffer_rid)
	mm_high_count_arr_uniform.add_id(mm_high_instance_count_buffer_rid)
	
	var mm_low_count_arr_uniform = RDUniform.new()
	mm_low_count_arr_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_low_count_arr_uniform.binding = 2
	
	mm_low_instance_count_buffer_rid = rd.storage_buffer_create(chunks_per_dim * chunks_per_dim * 4) #*4 to account for int size
	RID_arr.append(mm_low_instance_count_buffer_rid)
	mm_low_count_arr_uniform.add_id(mm_low_instance_count_buffer_rid)		
	
	#multimesh command buffer binding
	var mm_high_command_buffer_uniform := RDUniform.new()
	mm_high_command_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_high_command_buffer_uniform.binding = 3
	mm_high_command_buffer_uniform.add_id(mm_high_command_buffer_rid)
	
	var mm_low_command_buffer_uniform := RDUniform.new()
	mm_low_command_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_low_command_buffer_uniform.binding = 3
	mm_low_command_buffer_uniform.add_id(mm_low_command_buffer_rid)
	
	# float parameters bindings
	var mm_high_flt_params_arr : PackedByteArray =  PackedFloat32Array(
		[vertex_spacing,
		sqrt(target_density_sq_m_high_LOD), 
		max_foliage_individual_random_offset,
		deg_to_rad(max_foliage_tilt_degrees), 
		deg_to_rad(foliage_cam_bias_degrees_high_LOD),
		min_grass_blade_scale,
		distance_thresholds_high_lod.x,
		distance_thresholds_high_lod.y, 
		distance_thresholds_high_lod.z]
		 ).to_byte_array()
	var fparameter_mm_high_buffer_rid :RID = rd.storage_buffer_create(mm_high_flt_params_arr.size(), mm_high_flt_params_arr)
	RID_arr.append(fparameter_mm_high_buffer_rid)

	var mm_low_flt_params_arr : PackedByteArray = PackedFloat32Array(
		[vertex_spacing, 
		sqrt(target_density_sq_m_low_LOD),
		max_foliage_individual_random_offset, 
		deg_to_rad(max_foliage_tilt_degrees), 
		deg_to_rad(foliage_cam_bias_degrees_low_LOD),
		min_grass_blade_scale,
		distance_thresholds_low_lod.x, 
		distance_thresholds_low_lod.y, 
		distance_thresholds_low_lod.z]
		 ).to_byte_array()
	var fparameter_mm_low_buffer_rid :RID = rd.storage_buffer_create(mm_low_flt_params_arr.size(), mm_low_flt_params_arr)
	RID_arr.append(fparameter_mm_low_buffer_rid)

	var mm_high_flt_param_uniform = RDUniform.new()
	mm_high_flt_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_high_flt_param_uniform.binding = 3
	mm_high_flt_param_uniform.add_id(fparameter_mm_high_buffer_rid)
	
	var mm_low_flt_param_uniform = RDUniform.new()
	mm_low_flt_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_low_flt_param_uniform.binding = 3
	mm_low_flt_param_uniform.add_id(fparameter_mm_low_buffer_rid)
	
	#int parameters bindings
	var mm_high_int_params_arr : PackedByteArray =  PackedInt32Array(
		[high_estimated_per_chunk ,chunks_per_dim, 0]
		).to_byte_array()
	var iparameter_mm_high_buffer_rid :RID = rd.storage_buffer_create(mm_high_int_params_arr.size(), mm_high_int_params_arr)
	RID_arr.append(iparameter_mm_high_buffer_rid)
	
	var offset = high_lod_num_work_groups.x * high_lod_num_work_groups.y
	var mm_low_int_params_arr : PackedByteArray =  PackedInt32Array(
		[low_estimated_per_chunk ,chunks_per_dim, offset]
		).to_byte_array()
	var iparameter_mm_low_buffer_rid :RID = rd.storage_buffer_create(mm_low_int_params_arr.size(), mm_low_int_params_arr)
	RID_arr.append(iparameter_mm_low_buffer_rid)

	var mm_high_int_param_uniform = RDUniform.new()
	mm_high_int_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_high_int_param_uniform.binding = 4
	mm_high_int_param_uniform.add_id(iparameter_mm_high_buffer_rid)	
	
	var mm_low_int_param_uniform = RDUniform.new()
	mm_low_int_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_low_int_param_uniform.binding = 4
	mm_low_int_param_uniform.add_id(iparameter_mm_low_buffer_rid)
	
	#mask binding
	var mask_tex_uniform = RDUniform.new()
	mask_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mask_tex_uniform.binding = 5
	var chunk_image = chunk_mask.get_image()
	chunk_image.convert(Image.FORMAT_R8)
	mask_tex_uniform.add_id(_init_existing_image_data(rd, chunk_image, RenderingDevice.DATA_FORMAT_R8_UNORM, false))

	#player data binding
	player_transform_data_arr = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var player_data_arr : PackedByteArray = player_transform_data_arr.to_byte_array()
	player_transform_data_mm_high_buffer_rid = rd.storage_buffer_create(player_data_arr.size(), player_data_arr)
	RID_arr.append(player_transform_data_mm_high_buffer_rid)

	var player_data_uniform = RDUniform.new()
	player_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	player_data_uniform.binding = 6
	player_data_uniform.add_id(player_transform_data_mm_high_buffer_rid)

	# array with coordinates of segments to draw
	segment_coord_data_arr.resize(chunks_per_dim * chunks_per_dim *2)
	var segment_coord_packed_arr : PackedByteArray = segment_coord_data_arr.to_byte_array()
	segment_coord_data_mm_buffer_rid = rd.storage_buffer_create(segment_coord_packed_arr.size(), segment_coord_packed_arr)
	RID_arr.append(segment_coord_data_mm_buffer_rid)	
	
	var segments_coord_uniform : RDUniform = RDUniform.new()
	segments_coord_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	segments_coord_uniform.binding = 7
	segments_coord_uniform.add_id(segment_coord_data_mm_buffer_rid)
	
	#sparse tranform buffer pre-condensed
	var mm_high_sparse_transform_uniform = RDUniform.new()
	mm_high_sparse_transform_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_high_sparse_transform_uniform.binding = 1
	# *48 for 12 elements of a transform with size 4 (float)
	mm_high_sparse_transform_buffer_rid = rd.storage_buffer_create(mm_high_estimated_count * 48,PackedByteArray())
	RID_arr.append(mm_high_sparse_transform_buffer_rid)
	mm_high_sparse_transform_uniform.add_id(mm_high_sparse_transform_buffer_rid)
	
	var mm_low_sparse_transform_uniform = RDUniform.new()
	mm_low_sparse_transform_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mm_low_sparse_transform_uniform.binding = 1
	# *48 for 12 elements of a transform with size 4 (float)
	mm_low_sparse_transform_buffer_rid = rd.storage_buffer_create(mm_low_estimated_count * 48,PackedByteArray())
	RID_arr.append(mm_low_sparse_transform_buffer_rid)
	mm_low_sparse_transform_uniform.add_id(mm_low_sparse_transform_buffer_rid)	
	
	#add all uniforms bindings into the set
	mm_high_uniform_set_pos_calc_RID = rd.uniform_set_create(
			[height_data_uniform, mm_high_sparse_transform_uniform, mm_high_count_arr_uniform, mm_high_flt_param_uniform,mm_high_int_param_uniform, mask_tex_uniform, player_data_uniform, segments_coord_uniform]
			, compute_pos_shader_RID, 0)
	RID_arr.append(mm_high_uniform_set_pos_calc_RID)

	mm_low_uniform_set_pos_calc_RID = rd.uniform_set_create(
		[height_data_uniform, mm_low_sparse_transform_uniform, mm_low_count_arr_uniform, mm_low_flt_param_uniform,mm_low_int_param_uniform, mask_tex_uniform, player_data_uniform, segments_coord_uniform]
		, compute_pos_shader_RID,0	)
	RID_arr.append(mm_low_uniform_set_pos_calc_RID)

	#transfer shader RID
	mm_high_uniform_set_pos_transfer_RID = rd.uniform_set_create(
		[mm_high_packed_transform_buffer_uniform, mm_high_sparse_transform_uniform , mm_high_count_arr_uniform, mm_high_command_buffer_uniform, mm_high_int_param_uniform]
		, transfer_shader_RID, 0)
	RID_arr.append(mm_high_uniform_set_pos_transfer_RID)
	
	mm_low_uniform_set_pos_transfer_RID = rd.uniform_set_create(
		[mm_low_packed_transform_buffer_uniform, mm_low_sparse_transform_uniform , mm_low_count_arr_uniform, mm_low_command_buffer_uniform, mm_low_int_param_uniform]
		, transfer_shader_RID, 0)
	RID_arr.append(mm_low_uniform_set_pos_transfer_RID)

	# Create the foliage compute pipelines
	# don't actually run them or anything yet
	mm_pipeline_pos_calc_RID = rd.compute_pipeline_create(compute_pos_shader_RID)
	RID_arr.append(mm_pipeline_pos_calc_RID)
	mm_pipeline_pos_transfer_RID = rd.compute_pipeline_create(transfer_shader_RID)
	RID_arr.append(mm_pipeline_pos_transfer_RID)
	
	_setup_foliage_bender_pipeline()

	set_process(true)
	initialized = true
	
func _setup_multimesh_data(mm_high_estimated_count : int, _mm_low_estimated_count) -> void:	
	
	mm_high_instance_RID = RenderingServer.instance_create()
	RID_arr.append(mm_high_instance_RID)	

	mm_high_RID = RenderingServer.multimesh_create()
	RID_arr.append(mm_high_RID)
	foliage_mesh_high_LOD.surface_set_material(0, foliage_material_high_LOD)
	_init_new_multimesh(rd, mm_high_RID,mm_high_instance_RID, mm_high_estimated_count, foliage_mesh_high_LOD)
	mm_high_packed_transform_buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm_high_RID)
	RID_arr.append(mm_high_packed_transform_buffer_rid)
	mm_high_command_buffer_rid = RenderingServer.multimesh_get_command_buffer_rd_rid(mm_high_RID);
	RID_arr.append(mm_high_command_buffer_rid)
	
	## LOW LOD MULTIMESH
	mm_low_instance_RID = RenderingServer.instance_create()
	RID_arr.append(mm_low_instance_RID)	
	
	mm_low_RID = RenderingServer.multimesh_create()
	RID_arr.append(mm_low_RID)
	foliage_mesh_low_LOD.surface_set_material(0, foliage_material_low_LOD)
	_init_new_multimesh(rd, mm_low_RID, mm_low_instance_RID, _mm_low_estimated_count , foliage_mesh_low_LOD)
	mm_low_packed_transform_buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm_low_RID)
	RID_arr.append(mm_low_packed_transform_buffer_rid)
	mm_low_command_buffer_rid = RenderingServer.multimesh_get_command_buffer_rd_rid(mm_low_RID);
	RID_arr.append(mm_low_command_buffer_rid)
	
func _load_shaders()-> void:
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
	
	#load shaders
	bender_shader_RID = _load_shader_from_file(bender_compute_shader)
	if(!bender_shader_RID.is_valid()):
		push_error("FAILED TO LOAD SHADER: ", bender_compute_shader.to_string())
		return
	RID_arr.append(bender_shader_RID)

func _setup_foliage_bender_pipeline()-> void:
	#pass the subviewport through to process
	var bender_img_uniform = RDUniform.new()
	bender_img_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	bender_img_uniform.binding = 0
	current_bender_data_tex_RID = RenderingServer.texture_get_rd_texture(bender_mask_subviewport.get_texture().get_rid())
	bender_img_uniform.add_id(current_bender_data_tex_RID)
	
	var bender_modified_img_uniform = RDUniform.new()
	bender_modified_img_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	bender_modified_img_uniform.binding = 1
	created_bender_image_RID = _init_existing_image_data(rd, created_bender_image, RenderingDevice.DATA_FORMAT_R32_SFLOAT, true)
	
	created_bender_tex_RD = Texture2DRD.new()
	created_bender_tex_RD.texture_rd_rid = created_bender_image_RID
	foliage_material_high_LOD.set(foliage_shader_bend_mask, created_bender_tex_RD)
	foliage_material_high_LOD.set(foliage_shader_bend_mask_size, chunk_dimenstion_size_m)
	foliage_material_low_LOD.set(foliage_shader_bend_mask, created_bender_tex_RD)
	foliage_material_low_LOD.set(foliage_shader_bend_mask_size, chunk_dimenstion_size_m)

	bender_modified_img_uniform.add_id(created_bender_image_RID)
	
	# float parameter binding
	const delta : float = 1.0/60.0
	bend_float_param_arr  =  PackedFloat32Array(
		[unbend_rate_per_second,delta]
		 ).to_byte_array()
	fparameter_buffer_bend_RID = rd.storage_buffer_create(bend_float_param_arr.size(), bend_float_param_arr)
	RID_arr.append(fparameter_buffer_bend_RID)

	var bender_mm_high_flt_param_uniform = RDUniform.new()
	bender_mm_high_flt_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	bender_mm_high_flt_param_uniform.binding = 2
	bender_mm_high_flt_param_uniform.add_id(fparameter_buffer_bend_RID)
	
	uniform_set_bender_RID = rd.uniform_set_create(
		[bender_img_uniform, bender_modified_img_uniform, bender_mm_high_flt_param_uniform],
		bender_shader_RID ,0)
	RID_arr.append(uniform_set_bender_RID)
	
	pipeline_bender_RID =  rd.compute_pipeline_create(bender_shader_RID)
	RID_arr.append(pipeline_bender_RID)
	
func _exit_tree() -> void:
	_cleanup()
	
func _cleanup() -> void:
	if(mm_high_RID.is_valid()):
		RenderingServer.multimesh_allocate_data(mm_high_RID, 0 , RenderingServer.MULTIMESH_TRANSFORM_3D,false, false, true)

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
	
func _init_existing_image_data(_rd : RenderingDevice, img : Image, format : RenderingDevice.DataFormat, updateable : bool) -> RID:
	var tex_format := RDTextureFormat.new()
	tex_format.width = img.get_width()
	tex_format.height = img.get_height()
	tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT + RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	if(updateable):
		tex_format.usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	tex_format.format = format
	var tex_RID : RID = _rd.texture_create(tex_format, RDTextureView.new(), [img.get_data()])
	RID_arr.append(tex_RID)
	return tex_RID
	
func _init_new_multimesh(_rd : RenderingDevice, multimesh_rid : RID, instance_RID : RID, estimated_transform_count : int, mesh : Mesh) -> void:
	#calculate an estimated instance count to pass through
	RenderingServer.multimesh_allocate_data(multimesh_rid, estimated_transform_count , RenderingServer.MULTIMESH_TRANSFORM_3D,false, false, true)
	
	RenderingServer.multimesh_set_mesh(multimesh_rid, mesh.get_rid())
	RenderingServer.instance_set_transform(instance_RID, get_global_transform())

	RenderingServer.multimesh_set_custom_aabb(multimesh_rid,visibility_notifier.aabb)
	RenderingServer.instance_set_custom_aabb(instance_RID, 	visibility_notifier.aabb)
	
	RenderingServer.instance_set_scenario(instance_RID, scenario_RID)
	RenderingServer.instance_set_base(instance_RID, multimesh_rid)
	RenderingServer.instance_geometry_set_flag(instance_RID, RenderingServer.InstanceFlags.INSTANCE_FLAG_USE_DYNAMIC_GI, true)
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance_RID, RenderingServer.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF)
		
func _update_compute_bender_only_data(_delta : float) -> void:
	if(!uniform_set_bender_RID.is_valid()):
		return
		
	rd = RenderingServer.get_rendering_device()
	_update_bender_data(rd, _delta)

	var compute_list : int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_bender_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_bender_RID, 0)	
	rd.compute_list_dispatch(compute_list,high_lod_num_work_groups.x ,1, high_lod_num_work_groups.y)
	
	rd.compute_list_end()

func _update_compute_segments_data(_player_cam_transform_world: Transform3D, _player_cam : Camera3D, _delta : float)->void:
	compute_active = true
	update_counter += 1
	
	#this would be where we pass player transform through or updated textures
	rd = RenderingServer.get_rendering_device()
	_update_player_data_buffer(rd, _player_cam_transform_world)
	var filled_in : int = _update_segments_to_draw_buffer(rd, _player_cam_transform_world, _player_cam)
	
	if(uniform_set_bender_RID.is_valid()):
		_update_bender_data(rd, _delta)
		_dispatch_bender_compute_list(rd)
	
	if(mm_pipeline_pos_calc_RID.is_valid() && mm_high_uniform_set_pos_transfer_RID.is_valid()):
		_dispatch_position_compute_list(rd, mm_high_uniform_set_pos_calc_RID, mm_high_uniform_set_pos_transfer_RID, high_lod_num_work_groups)
		pass

	var total_high_lod_groups : int = high_lod_num_work_groups.x * high_lod_num_work_groups.y
	if(filled_in >total_high_lod_groups):
		var work_group_amount : Vector2i = _calculate_low_LOD_group_amount(filled_in, total_high_lod_groups)
		_dispatch_position_compute_list(rd, mm_low_uniform_set_pos_calc_RID, mm_low_uniform_set_pos_transfer_RID,work_group_amount)
	else:
		#set the instance count to 0 on the low LOD
		pass
			

	compute_active = false

func _calculate_low_LOD_group_amount(segment_amount : int, high_lod_amount : int) -> Vector2:
	return Vector2i(segment_amount - high_lod_amount, 1)

func _dispatch_bender_compute_list(_rd : RenderingDevice) -> void:
	var bender_compute_list : int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(bender_compute_list, pipeline_bender_RID)
	_rd.compute_list_bind_uniform_set(bender_compute_list, uniform_set_bender_RID, 0)	
	_rd.compute_list_dispatch(bender_compute_list,high_lod_num_work_groups.x,1,high_lod_num_work_groups.y)
	_rd.compute_list_end()
	
func _dispatch_position_compute_list(_rd :RenderingDevice, pos_calc_uniform_set : RID,pos_transfer_uniform_set : RID,  workgroup_num : Vector2i)	-> void:
	var compute_list : int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, mm_pipeline_pos_calc_RID)
	_rd.compute_list_bind_uniform_set(compute_list, pos_calc_uniform_set, 0)
	_rd.compute_list_dispatch(compute_list,workgroup_num.x,1,workgroup_num.y)

	# wait until the first shader is done
	_rd.compute_list_add_barrier(compute_list)

	_rd.compute_list_bind_compute_pipeline(compute_list, mm_pipeline_pos_transfer_RID)
	_rd.compute_list_bind_uniform_set(compute_list, pos_transfer_uniform_set, 0)
	_rd.compute_list_dispatch(compute_list, workgroup_num.x,1,workgroup_num.y)

	_rd.compute_list_end()
	
func _update_player_data_buffer(_rd: RenderingDevice, _player_cam_transform_world: Transform3D) -> void:
	if(!player_transform_data_mm_high_buffer_rid.is_valid()):
		return

	player_transform_data_arr[0] = _player_cam_transform_world.origin.x - self.get_global_position().x
	player_transform_data_arr[1] = _player_cam_transform_world.origin.y - self.get_global_position().y
	player_transform_data_arr[2] = _player_cam_transform_world.origin.z - self.get_global_position().z
	
	var cam_rot : Vector3 = _player_cam_transform_world.basis.get_euler()
	player_transform_data_arr[3] = cam_rot.x
	player_transform_data_arr[4] = cam_rot.y
	player_transform_data_arr[5] = cam_rot.z
	
	var player_data_arr : PackedByteArray = player_transform_data_arr.to_byte_array()
	_rd.buffer_update(player_transform_data_mm_high_buffer_rid, 0, player_data_arr.size() ,player_data_arr)

# REGION BENDERS 
#=================================================================================================================================
func _update_bender_data(_rd : RenderingDevice, delta : float) -> void:
	#update the delta passed through
	bend_float_param_arr.encode_float(4,delta)
	_rd.buffer_update(fparameter_buffer_bend_RID, 0, bend_float_param_arr.size() ,bend_float_param_arr)

# REGION SEGMENT DETECTION 
#=================================================================================================================================
func _update_segments_to_draw_buffer(_rd : RenderingDevice, _player_cam_transform_world: Transform3D, _player_cam : Camera3D) -> int:
	if(!segment_coord_data_mm_buffer_rid.is_valid()):
		return 0
				
	var vertex_spacing : float = _get_vertex_spacing()		
	#start by calculating the segment we are currently in
	const backward_offset : float = 0.5
	var player_start_pos : Vector3 = _player_cam_transform_world.origin + (_player_cam_transform_world.basis.z * backward_offset)
	var playerdiff : Vector2 = Vector2(  player_start_pos.x- (global_position.x - (chunk_dimenstion_size_m * 0.5)), player_start_pos.z- (global_position.z - (chunk_dimenstion_size_m * 0.5)) )
	
	var player_current_sub_id_pos : Vector2 = Vector2(playerdiff.x / vertex_spacing, playerdiff.y / vertex_spacing)
	var player_current_segment : Vector2i   = Vector2i( int(floor(player_current_sub_id_pos.x))  ,int(floor(player_current_sub_id_pos.y)) )

	#reset the working data from last frame
	segment_work_data_arr.fill(Vector2i.MIN.x)
	segment_found_edges_left.fill(Vector2i.MIN.x)
	segment_found_edges_right.fill(Vector2i.MIN.x)
	segment_center_edges.fill(Vector2i.MIN.x)
	segment_center_corner_edges_left.fill(Vector2i.MIN.x)
	segment_center_corner_edges_right.fill(Vector2i.MIN.x)
	
	#find the vector that describe the 'edges' of the camera
	segment_work_filled_in = _fill_work_array_with_current_segments_data(_player_cam , player_current_sub_id_pos, player_current_segment,segments_per_dim)
		
	var element_amount : int = 	min(segment_work_filled_in, pow(int(chunk_dimenstion_size_m / vertex_spacing),2))
	_rd.buffer_update(segment_coord_data_mm_buffer_rid, 0, element_amount*8 ,segment_work_data_arr)
	return element_amount
	
func _fill_work_array_with_current_segments_data(_camera : Camera3D, _player_segment_sub_pos : Vector2, _player_current_segment : Vector2i, max_segments_per_side : int) -> int:
	var cam_frustrum : Array[Plane] = _camera.get_frustum()
	
	var left_dir : Vector3 = cam_frustrum[2].normal.cross(Vector3.UP)
	var right_dir : Vector3 =  cam_frustrum[4].normal.cross(-Vector3.UP)
	segments_found_left = _find_ray_intersect_grid(_player_segment_sub_pos,left_dir ,max_segments_per_side, segment_found_edges_left)
	segments_found_right = _find_ray_intersect_grid(_player_segment_sub_pos, right_dir,max_segments_per_side, segment_found_edges_right)
	segments_found_center = _find_center_edge_segments(_player_current_segment, max_segments_per_side) 	# find all the segments in between those 2 ends

	var edge_amount_prioritize_per_side : int = high_lod_num_work_groups.x
	var post_priotitize_offset : int = edge_amount_prioritize_per_side * edge_amount_prioritize_per_side

	var index_write_offsets : Vector2i = _interleave_edge_data_into_work_array(_player_current_segment, segments_found_left, segments_found_right, segments_found_center, edge_amount_prioritize_per_side, post_priotitize_offset)
	var end_write_id : int = index_write_offsets.y
	var cam_forward : Vector3 = -_camera.get_global_transform().basis.z
	end_write_id =_flood_fill_work_data(cam_forward,index_write_offsets, post_priotitize_offset, max_segments_per_side)
	
	return end_write_id + 1 


func _flood_fill_work_data(camera_forward : Vector3, write_offsets : Vector2i, post_prioritize_write_offset : int,  max_segments_per_side : int) -> int:
	#contruct an array of direction to check
	var compass_index : int = _get_compass_direction_index(Vector2( camera_forward.x, camera_forward.z))
	var prev_id : int = compass_index -1  if compass_index-1 > 0 else  7

	flood_fill_query_directions = [compass_directions[compass_index], compass_directions[prev_id], compass_directions[ (compass_index +1) % 8]]
	
	var current_write_id : int = write_offsets.x
	var current_read_id : int = 0
	var max_possible_tests : int = max_segments_per_side * max_segments_per_side
	var direction_amount_query : int = 1
	while current_write_id < max_possible_tests && current_read_id < current_write_id:
		# how many directions should we query?
		# if this is an edge, only 1, otherwise all 3
		if( (current_read_id > write_offsets.y && write_offsets.y > post_prioritize_write_offset) || # are we past the second block of edge ids
			(current_read_id > write_offsets.x && current_read_id < post_prioritize_write_offset) 	# are we past the second block of edge ids
		):
			direction_amount_query = 3
		else:
			direction_amount_query = 1
		
		var start_segment : Vector2i = Vector2i(segment_work_data_arr.decode_s32(current_read_id *8),segment_work_data_arr.decode_s32(current_read_id *8 +4))
		current_read_id+=1
		
		for query_id in range(0,direction_amount_query):
			var segment_to_check : Vector2i = start_segment + flood_fill_query_directions[query_id]
	
			if(!_is_segment_valid_in_chunk(segment_to_check, max_segments_per_side)):
				continue
	
			# checking if the segment is already in the array has a massive performance impact if we do it via array.contains
			# instead we have a map with all possible combinations we can check
			if segments_filled_map[segment_to_check] == update_counter:	
				continue
	
			segments_filled_map[segment_to_check] = update_counter
			segment_work_data_arr.encode_s32(current_write_id *8,segment_to_check.x)
			segment_work_data_arr.encode_s32(current_write_id *8 +4,segment_to_check.y)

			#update the write id, make sure we don't accidentally 
			current_write_id +=1
			if(current_write_id == post_prioritize_write_offset && write_offsets.y > post_prioritize_write_offset):
				current_write_id = write_offsets.y +1

	return current_write_id
	
func _interleave_edge_data_into_work_array(player_current_segment : Vector2i, left_edges_found : int , right_edges_found : int, center_edges_found : int,  edge_cell_amount_to_prioritize_per_side , non_prioritized_offset : int) -> Vector2i:
	#interleave those segments in the work array so when we iterate to fill in the 'polygon' we do it somewhat in the order of closeness to player
	var return_index_write_offset : Vector2i = Vector2i.ZERO

	var amount_to_write_prioritized : int = min(edge_cell_amount_to_prioritize_per_side * 2, left_edges_found + right_edges_found + center_edges_found)

	var left_id : int = 0
	var center_id : int = 0
	var right_id : int = 0

	var smallest_distance : float = 0.0
	var left_dist : float = large_float_dist
	var center_dist : float = large_float_dist
	var right_dist : float = large_float_dist
	
	if(left_edges_found > 0):
		left_dist = player_current_segment.distance_squared_to(Vector2i(segment_found_edges_left[0],segment_found_edges_left[1]))
	if(center_edges_found > 0):
		center_dist = player_current_segment.distance_squared_to( Vector2i( segment_center_edges[0],segment_center_edges[1]) )
	if(right_edges_found > 0):
		right_dist = player_current_segment.distance_squared_to(Vector2i(segment_found_edges_right[0],segment_found_edges_right[1]))

	for prio_write_id in range(amount_to_write_prioritized):
		smallest_distance = min(left_dist, center_dist, right_dist)

		if(smallest_distance == large_float_dist):
			break
	
		if(smallest_distance == left_dist):
			segment_work_data_arr.encode_s32(prio_write_id *8,segment_found_edges_left[left_id])
			segment_work_data_arr.encode_s32(prio_write_id *8 +4,segment_found_edges_left[left_id +1])
			left_id +=2
			left_dist = player_current_segment.distance_squared_to(Vector2i(segment_found_edges_left[left_id], segment_found_edges_left[left_id +1]))
		elif(smallest_distance == center_dist):
			segment_work_data_arr.encode_s32(prio_write_id *8,segment_center_edges[center_id])
			segment_work_data_arr.encode_s32(prio_write_id *8 +4,segment_center_edges[center_id+1])
			center_id +=2
			center_dist = player_current_segment.distance_squared_to(Vector2i(segment_center_edges[center_id], segment_center_edges[center_id+1]))
		else:
			segment_work_data_arr.encode_s32(prio_write_id *8,segment_found_edges_right[right_id])
			segment_work_data_arr.encode_s32(prio_write_id *8 +4,segment_found_edges_right[right_id+1])
			right_id +=2
			right_dist = player_current_segment.distance_squared_to(Vector2i(segment_found_edges_right[ right_id], segment_found_edges_right[ right_id +1]))

		prio_write_id +=1
		return_index_write_offset.x +=1
		
	var amount_to_write_post_prio : int = left_edges_found + right_edges_found + center_edges_found - amount_to_write_prioritized

	if(amount_to_write_post_prio > 0):
		var post_prio_write_id : int = non_prioritized_offset

		# write the rest of the data linearly
		for l_id in range(left_id, left_edges_found *2,2):
			segment_work_data_arr.encode_s32(post_prio_write_id *8,segment_found_edges_left[l_id])
			segment_work_data_arr.encode_s32(post_prio_write_id *8 +4,segment_found_edges_left[l_id+1])
			post_prio_write_id += 1

		for c_id in range(center_id, center_edges_found *2,2):
			segment_work_data_arr.encode_s32(post_prio_write_id *8,segment_center_edges[c_id])
			segment_work_data_arr.encode_s32(post_prio_write_id *8 +4,segment_center_edges[c_id+1])
			post_prio_write_id += 1
		
		for r_id in range(right_id, right_edges_found *2,2):
			segment_work_data_arr.encode_s32(post_prio_write_id *8,segment_found_edges_right[r_id])
			segment_work_data_arr.encode_s32(post_prio_write_id *8 +4,segment_found_edges_right[r_id+1])
			post_prio_write_id += 1

		return_index_write_offset.y = post_prio_write_id
		
	return return_index_write_offset

# use the DDA algorithm to find the edges 	
func _find_ray_intersect_grid(grid_start_pos : Vector2, dir: Vector3, max_segment_per_side : int, arr_to_edit : PackedInt32Array) ->int:
	dir.y = 0
	dir = dir.normalized()

	var max_segment_id : int = max_segment_per_side -1
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
	# TODO: properly calculate the max possible distance we could travel in a chunk before we should abort
	var max_distance : float = max_segment_per_side  * _get_vertex_spacing()
	var amount_found : int = 0
	while amount_found < max_segment_per_side *2:
		#step towards current shortest direction
		if(current_ray_length_per_dim.x < current_ray_length_per_dim.y):
			current_tile_to_check.x += step_unit_dir.x
			current_distance += current_ray_length_per_dim.x
			current_ray_length_per_dim.x += ray_unit_step_size.x
		else:
			current_tile_to_check.y += step_unit_dir.y
			current_distance += current_ray_length_per_dim.y
			current_ray_length_per_dim.y += ray_unit_step_size.y

		# we've hit the edge of our chunk -> abort
		if(!_is_segment_valid_in_chunk(current_tile_to_check, max_segment_per_side)):
			if(current_distance > max_distance):
				var start_edge_segment :Vector2i
				var include_start : bool = false
				if(amount_found == 0):
					start_edge_segment = _clamp_outside_segment_to_closest_edge(current_tile_to_check, max_segment_id)
					include_start = true
				else:
					#use the last tile added 
					start_edge_segment = Vector2i(arr_to_edit[2* (amount_found-1)],arr_to_edit[(2* (amount_found-1)) +1])
					include_start = false


				var direction_to_check := Vector2i.ZERO
				if(_is_corner_segment(start_edge_segment, max_segment_id)):
					if(abs(dir.x) > abs(dir.z)):
						direction_to_check.x = sign(dir.x)
					else:
						direction_to_check.y = sign(dir.z)
				else:
					if(start_edge_segment.x == 1 || start_edge_segment.x == max_segment_id):
						direction_to_check.y = sign(dir.z)
					else:
						direction_to_check.x = sign(dir.x)
				
				var end_corner : Vector2i = _clamp_outside_segment_to_closest_edge(start_edge_segment + (direction_to_check * max_segment_id), max_segment_id)
				amount_found += _add_edge_segments_between_points(start_edge_segment, end_corner, amount_found, max_segment_per_side, arr_to_edit, include_start, true)
				return amount_found
			else:
				continue
		
		# explicitly don't check for if it's already been updated
		# we assume this tile is needed
		segments_filled_map[current_tile_to_check] = update_counter
		arr_to_edit[2* amount_found] = current_tile_to_check.x
		arr_to_edit[(2* amount_found) +1] = current_tile_to_check.y
	
		amount_found +=1

	return amount_found
	
func _find_center_edge_segments(_player_current_segment : Vector2i, max_segment_per_side : int) -> int:
	var write_id : int = 0
	if(_is_segment_valid_in_chunk(_player_current_segment, max_segment_per_side)):
		segment_center_edges[2 * write_id] = _player_current_segment.x
		segment_center_edges[(2 * write_id) +1] = _player_current_segment.y
		segments_filled_map[_player_current_segment] = update_counter
		write_id += 1
		return write_id
		
	var left_start : Vector2i = Vector2i(segment_found_edges_left[0],segment_found_edges_left[1])
	var right_start : Vector2i = Vector2i(segment_found_edges_right[0],segment_found_edges_right[1])
	
	if( (left_start.x == right_start.x ) || (left_start.y == right_start.y) ):
		if( _player_current_segment.distance_squared_to(left_start) < _player_current_segment.distance_squared_to(right_start)):
			write_id += _add_edge_segments_between_points(left_start, right_start, write_id, max_segment_per_side, segment_center_edges, false)
		else:
			write_id += _add_edge_segments_between_points(right_start, left_start, write_id, max_segment_per_side, segment_center_edges, false)
	elif(left_start != Vector2i.MIN && right_start != Vector2i.MIN):
		var target_corner : Vector2i =  (left_start + right_start /2).snappedi(max_segment_per_side-1)
		#add the corner itself
		segment_center_edges[2 * write_id] = target_corner.x
		segment_center_edges[(2 * write_id) +1] = target_corner.y
		segments_filled_map[target_corner] = update_counter
		write_id +=1
		
		#check left and right and of the corner until the end point and interleave them
		var left_corner_amount_found : int = _add_edge_segments_between_points(target_corner, left_start, 0, max_segment_per_side, segment_center_corner_edges_left, true ,false)
		var right_corner_amount_found : int = _add_edge_segments_between_points(target_corner, right_start, 0 , max_segment_per_side,segment_center_corner_edges_right, false, false)
		var combined_amount_found : int = left_corner_amount_found + right_corner_amount_found

		var left_dist : float = large_float_dist
		if(left_corner_amount_found > 0):
			left_dist = _player_current_segment.distance_squared_to(Vector2i(segment_center_corner_edges_left[0],segment_center_corner_edges_left[1]))
		var right_dist : float = large_float_dist
		if(right_corner_amount_found > 0):
			right_dist = _player_current_segment.distance_squared_to(Vector2i(segment_center_corner_edges_right[0],segment_center_corner_edges_right[1]))
		var left_write_id : int = 0
		var right_write_id : int = 0
		
		for center_write_id in range(combined_amount_found):
			var center_write_offset : int = 2* (center_write_id + write_id)
			if(left_dist < right_dist):
				var left_write_offset : int = 2*  left_write_id
				segment_center_edges[center_write_offset ] =   segment_center_corner_edges_left[left_write_offset]
				segment_center_edges[center_write_offset +1] = segment_center_corner_edges_left[left_write_offset +1]
				left_write_id +=1
				left_write_offset +=2
				left_dist = _player_current_segment.distance_squared_to( Vector2i(segment_center_corner_edges_left[left_write_offset] ,segment_center_corner_edges_left[left_write_offset +1]))
			else:
				var right_write_offset : int = 2*  right_write_id
				segment_center_edges[center_write_offset ] = segment_center_corner_edges_right[right_write_offset]
				segment_center_edges[center_write_offset +1] = segment_center_corner_edges_right[right_write_offset +1 ]
				right_write_id +=1
				right_write_offset +=2
				right_dist = _player_current_segment.distance_squared_to(Vector2i(segment_center_corner_edges_right[right_write_offset], segment_center_corner_edges_right[right_write_offset + 1]))
		
		write_id +=  combined_amount_found
	else:
			push_error("Failed to add edges as our left (", left_start, ") and right (" , right_start, ") starting points are not valid")
	
	return write_id	
	
func _add_edge_segments_between_points(from : Vector2i, to : Vector2i, write_offset : int, max_segments_per_side : int, arr_to_edit : PackedInt32Array, include_start: bool = true, include_end : bool= false) -> int:
	var dir : Vector2i = (to - from).sign()
	var amount_added : int = 0
	var amount_needed : int = int((to - from).length())
	if(include_end):
		amount_needed +=1

	for id in range(0 if include_start else 1, amount_needed):
		var to_add : Vector2i = from + (id * dir)
		if(!_is_segment_valid_in_chunk(to_add, max_segments_per_side)):
			return amount_added
			
		# explicitly don't check for if it's already been updated
		# we assume this tile is needed
		arr_to_edit[ 2*(write_offset + amount_added) ] = to_add.x
		arr_to_edit[ 2*(write_offset + amount_added) +1] = to_add.y
		segments_filled_map[to_add] = update_counter
		amount_added+=1

	return amount_added

const compass_directions : Array[Vector2i] = [Vector2i(1,0),Vector2i(1,1),Vector2i(0,1) ,Vector2i(-1,1),Vector2i(-1,0), Vector2i(-1,-1), Vector2i(0,-1),Vector2i(1,-1)]	#clockwise directions starting with EAST

func _get_compass_direction_index(direction : Vector2) -> int:
	return ((int(round( atan2(direction.y, direction.x)/ (2 * PI / 8))) + 8) % 8)	#divide the 360 look direction degrees into 8 sections for the cardinal directions

func _is_corner_segment(segment : Vector2i, max_segment_id : int) -> bool:
	return ( segment.x == 0 || segment.x == max_segment_id ) &&  ( segment.y == 0 || segment.y == max_segment_id )

func _clamp_outside_segment_to_closest_edge(to_clamp: Vector2i , max_segment_id : int) -> Vector2i:
	#guarantee each element is inside [0 , max_segments_per_side -1]
	return Vector2i(clamp(to_clamp.x, 0, max_segment_id), clamp(to_clamp.y, 0, max_segment_id))
	
func _is_segment_valid_in_chunk(segment_to_check : Vector2i, max_segments_per_side : int) -> bool:
		return segment_to_check.x >= 0 && segment_to_check.y >= 0 &&  segment_to_check.x < max_segments_per_side && segment_to_check.y < max_segments_per_side
