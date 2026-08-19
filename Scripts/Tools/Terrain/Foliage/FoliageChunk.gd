@tool
class_name FoliageChunk extends Node3D

enum EFoliageLOD {NONE, TEX, LOW, HIGH}

@export_tool_button("Preview in Editor", "Callable") var preview_action : Callable = _preview_in_editor
@export_tool_button("Generate Data for Chunk", "Callable") var generate_height_data_action : Callable = _generate_height_data
@export_tool_button("Generate Terrain Mesh Copy", "Callable") var generate_terrain_copy_action : Callable = _create_terrain_mesh

const foliage_node_meta : String = "Node_FoliageChunk"
const foliage_shader_bend_mask : String = "shader_parameter/bending_mask"
const foliage_shader_bend_mask_size : String = "shader_parameter/bending_mask_size_m"

@export_group("Setup Data")
@export var visibility_notifier : VisibleOnScreenNotifier3D
@export var terrain_node : Terrain3D
@export var inverse_terrain_node : Terrain3D
@export var bender_mask_subviewport : SubViewport
@export var bender_mask_camera : Camera3D
@export var foliage_lowest_LOD_mesh : MeshInstance3D

@export var settings_DA : FoliageChunkSettings

@export var chunk_mask : Texture2D

var foliage_lowest_LOD_distance_squared : float = 0.0

var bend_float_param_arr : PackedByteArray
var fparameter_buffer_bend_RID :RID

@export_group("runtime data - DO NOT EDIT MANUALLY")
@export var height_array : PackedFloat32Array

const large_float_dist : float = INF
const no_ray_box_intersection : Vector2 = Vector2(INF, INF)

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
var player_transform_data_arr : PackedByteArray
var player_transform_data_mm_high_buffer_rid : RID
var player_transform_to_pass : Transform3D

# cached for debug purposes
var current_projected_player_segment : Vector2i
var current_player_segment : Vector2i

#current foliage bending data
var current_bender_data_tex_RID : RID

# segment coord data
var segments_per_dim : int = 0
var segment_coord_data_arr : PackedInt32Array
var segment_work_data_arr : PackedInt32Array
var segment_found_edges_left : PackedInt32Array
var segment_found_edges_right : PackedInt32Array
var segment_center_edges : PackedInt32Array

var segments_found_left : int
var segments_found_right : int
var segments_found_center : int
var segment_work_filled_in : int

var segments_filled_arr : PackedInt32Array
var update_counter : int = 0

# per-cell flag (indexed like segments_filled_arr): set for cells known to be interior (center-bridge cells and flood-filled cells)
var segment_laterial_fill : PackedByteArray

var segment_coord_data_mm_buffer_rid : RID

var compute_active : bool = false

var initialized : bool = false

var chunk_material_high_LOD_inst : Material
var chunk_material_low_LOD_inst : Material
var chunk_material_lowest_LOD_inst : Material

# everything the render-thread segment update needs, all sampled on the main thread before being passed over
class FoliageFrameSnapshot extends RefCounted:
	var cam_transform : Transform3D
	var cam_origin : Vector3
	var cam_forward : Vector3
	var left_dir : Vector3
	var right_dir : Vector3
	var center_dir : Vector3
	var chunk_global_pos : Vector3
	var chunk_min_corner : Vector2	# world x/z of this chunk's (0,0) segment
	var vertex_spacing : float
	var ground_y_guess : float
	var player_sub_pos : Vector2
	var backward_sub_offset : Vector2	# reverse-forward pad, in segment units

func _try_assign_chunk_material_instances() -> void:
	if(chunk_material_high_LOD_inst == null && settings_DA.foliage_material_high_LOD):
		chunk_material_high_LOD_inst = settings_DA.foliage_material_high_LOD.duplicate()
	if(chunk_material_low_LOD_inst == null && settings_DA.foliage_material_low_LOD):
		chunk_material_low_LOD_inst = settings_DA.foliage_material_low_LOD.duplicate()
	if(chunk_material_lowest_LOD_inst == null && settings_DA.foliage_lowest_LOD_material):
		chunk_material_lowest_LOD_inst = settings_DA.foliage_lowest_LOD_material.duplicate()

func _get_vertex_spacing() -> float:
	if(!terrain_node):
		print("Terrain node is null, cannot retrieve vertex spacing, returning default value")
		return 4.0
		
	return terrain_node.vertex_spacing

func _generate_height_data() -> void:
	var min_height :float = large_float_dist
	var max_height :float = -large_float_dist

	height_array.clear()
	var vertex_spacing :float = _get_vertex_spacing()
	
	var elem_per_dim : int = int(settings_DA.chunk_dimenstion_size_m / vertex_spacing) +1
	height_array.resize( elem_per_dim * elem_per_dim)
	
	if(terrain_node):
		for row in elem_per_dim:
			for col in elem_per_dim:
				var current_index : int = row * elem_per_dim + col
				var chunk_pixel_coord : Vector2i
				chunk_pixel_coord = Vector2i( 
						int( (global_position.x - (settings_DA.chunk_dimenstion_size_m * 0.5) )/ vertex_spacing) ,
						int( (global_position.z - (settings_DA.chunk_dimenstion_size_m * 0.5) )/ vertex_spacing) )
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
				
			
	const vert_offset : float = 5.0
	if(bender_mask_camera):
		bender_mask_camera.size = settings_DA.chunk_dimenstion_size_m
		bender_mask_camera.global_position.x = get_global_position().x
		bender_mask_camera.global_position.y = min_height -vert_offset		
		bender_mask_camera.global_position.z = get_global_position().z
		bender_mask_camera.far = abs(max_height - min_height) + (vert_offset *2)
		
	if(visibility_notifier):
		const size_padding : float = 5.0
		visibility_notifier.aabb.size = Vector3(settings_DA.chunk_dimenstion_size_m + size_padding,  abs(max_height - min_height) + (vert_offset * 2), settings_DA.chunk_dimenstion_size_m + size_padding)
		var horizontal_offset := (settings_DA.chunk_dimenstion_size_m* 0.5) + (size_padding * 0.5)
		visibility_notifier.aabb.position.x = -horizontal_offset
		visibility_notifier.aabb.position.z = -horizontal_offset
		visibility_notifier.aabb.position.y = min_height - vert_offset
		
	_try_assign_chunk_material_instances()
	
	_create_terrain_mesh()	

func _create_terrain_mesh() -> void:
	var vertex_spacing : float = _get_vertex_spacing()
	var segment_per_dim = settings_DA.chunk_dimenstion_size_m / vertex_spacing
	var offset : Vector2 = Vector2.ZERO
	offset =  Vector2(settings_DA.chunk_dimenstion_size_m * -0.5, settings_DA.chunk_dimenstion_size_m * -0.5)
		
	var mesh := FoliageMeshBuilder.build_mesh(height_array,segment_per_dim+1,vertex_spacing,offset)
	if mesh:
		mesh.surface_set_material(0, settings_DA.foliage_lowest_LOD_material)
		foliage_lowest_LOD_mesh.mesh =mesh
		
	foliage_lowest_LOD_mesh.global_position.y = settings_DA.foliage_lowest_LOD_mesh_offset	
	foliage_lowest_LOD_mesh.set_surface_override_material(0, chunk_material_lowest_LOD_inst)


func _preview_in_editor() -> void:
	if(initialized):
		RenderingServer.call_on_render_thread(_cleanup)
	else:
		RenderingServer.call_on_render_thread(_setup_compute_pipeline)
	
func _ready() -> void:
	if(!visible):
		return
		
	if(!settings_DA):
		return
			
	_intialize_segments_data()
	_initialize_bender_data()
	foliage_lowest_LOD_distance_squared = settings_DA.foliage_lowest_LOD_distance_activation * settings_DA.foliage_lowest_LOD_distance_activation

	if(!Engine.is_editor_hint()):
		RenderingServer.call_on_render_thread(_cleanup)
		RenderingServer.call_on_render_thread(_setup_compute_pipeline)
		

func _intialize_segments_data() -> void:
	segments_per_dim = int(settings_DA.chunk_dimenstion_size_m / _get_vertex_spacing())
	segment_work_data_arr.resize(segments_per_dim*segments_per_dim *2)
	segment_found_edges_left.resize(segments_per_dim *  4)
	segment_found_edges_right.resize(segments_per_dim * 4)
	segment_center_edges.resize(segments_per_dim *2 * 2)
	segments_filled_arr.resize(segments_per_dim * segments_per_dim)
	segments_filled_arr.fill(0)
	segment_laterial_fill.resize(segments_per_dim * segments_per_dim)
		

func _initialize_bender_data() -> void:
	if(inverse_terrain_node):
		inverse_terrain_node.material.show_checkered = false
	
	if(bender_mask_subviewport):
		bender_mask_subviewport.size = Vector2(settings_DA.bender_mask_res,settings_DA.bender_mask_res)	
		
	created_bender_image = Image.create_empty(settings_DA.bender_mask_res, settings_DA.bender_mask_res, false, Image.FORMAT_RF)	
	
func _process(_delta: float) -> void:
	if(!settings_DA):
		return
	
	if(!visibility_notifier.is_on_screen()):
		return
	
	var viewport : Viewport
	if Engine.is_editor_hint():
		viewport = EditorInterface.get_editor_viewport_3d()
	else:
		viewport = get_viewport()

	var cam : Camera3D = viewport.get_camera_3d()
	var cam_transform : Transform3D = cam.global_transform

	#check distance from player
	var squared_dist : float = cam_transform.origin.distance_squared_to(get_global_position())
	if(squared_dist > foliage_lowest_LOD_distance_squared):
		foliage_lowest_LOD_mesh.visible = true
		#set active amount on high/low LOD to 0
		#bender_mask_camera.hide()
		return
	else:
		#bender_mask_camera.show()
		foliage_lowest_LOD_mesh.visible = false

	if(player_transform_to_pass.is_equal_approx(cam_transform)):
		RenderingServer.call_on_render_thread(_update_compute_bender_only_data.bind(_delta))		
		return

	if(!compute_active && initialized):
		player_transform_to_pass = cam_transform
		compute_active = true
		var snapshot : FoliageFrameSnapshot = _gather_chunk_snapshot(cam, cam_transform)
		RenderingServer.call_on_render_thread(_update_compute_segments_data.bind(snapshot, _delta))

func _gather_chunk_snapshot(cam : Camera3D, cam_transform : Transform3D) -> FoliageFrameSnapshot:
	var snapshot := FoliageFrameSnapshot.new()

	snapshot.cam_transform = cam_transform
	snapshot.cam_origin = cam_transform.origin
	snapshot.cam_forward = -cam_transform.basis.z
	snapshot.chunk_global_pos = global_position
	snapshot.vertex_spacing = _get_vertex_spacing()
	var half_size : float = settings_DA.chunk_dimenstion_size_m * 0.5
	snapshot.chunk_min_corner = Vector2(
		global_position.x - half_size,
		global_position.z - half_size
	)

	var vp_size : Vector2 = cam.get_viewport().size
	snapshot.left_dir = cam.project_ray_normal(Vector2(0, vp_size.y))
	snapshot.right_dir = cam.project_ray_normal(Vector2(vp_size.x, vp_size.y))
	snapshot.center_dir = cam.project_ray_normal(Vector2(vp_size.x * 0.5, vp_size.y))

	# terrain height under the camera -- a better local ground estimate than a chunk-wide constant
	snapshot.ground_y_guess = global_position.y
	if(terrain_node):
		var under_cam_height : float = terrain_node.data.get_height(Vector3(snapshot.cam_origin.x, 0.0, snapshot.cam_origin.z))
		if(!is_nan(under_cam_height)):
			snapshot.ground_y_guess = under_cam_height

	const backward_offset : float = 0.5
	var player_start_pos : Vector3 = snapshot.cam_origin + (cam_transform.basis.z * backward_offset)
	snapshot.player_sub_pos = (Vector2(player_start_pos.x, player_start_pos.z) - snapshot.chunk_min_corner) / snapshot.vertex_spacing

	var forward_flat : Vector2 = Vector2(snapshot.cam_forward.x, snapshot.cam_forward.z)
	if(forward_flat.length_squared() > 0.000001):
		snapshot.backward_sub_offset = -forward_flat.normalized() * (snapshot.vertex_spacing)

	return snapshot
		
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
	var high_estimated_per_chunk : int = int(settings_DA.target_density_sq_m_high_LOD * vertex_spacing * vertex_spacing)
	var mm_high_estimated_count : int = int(settings_DA.high_lod_num_work_groups.x * settings_DA.high_lod_num_work_groups.y * high_estimated_per_chunk)
		
	var low_estimated_per_chunk : int = int(settings_DA.target_density_sq_m_low_LOD * vertex_spacing * vertex_spacing)
	var chunks_per_dim : int = int(settings_DA.chunk_dimenstion_size_m / vertex_spacing)
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
	
	mm_high_instance_count_buffer_rid = rd.storage_buffer_create(settings_DA.high_lod_num_work_groups.x * settings_DA.high_lod_num_work_groups.y * 4) #*4 to account for int size
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
		sqrt(settings_DA.target_density_sq_m_high_LOD), 
		settings_DA.max_foliage_individual_random_offset,
		deg_to_rad(settings_DA.max_foliage_tilt_degrees), 
		deg_to_rad(settings_DA.foliage_cam_bias_degress_near_far.x),
		deg_to_rad(settings_DA.foliage_cam_bias_degress_near_far.y),
		settings_DA.min_grass_blade_scale,
		settings_DA.distance_thresholds_high_lod.x,
		settings_DA.distance_thresholds_high_lod.y, 
		settings_DA.distance_thresholds_high_lod.z]
		 ).to_byte_array()
	var fparameter_mm_high_buffer_rid :RID = rd.storage_buffer_create(mm_high_flt_params_arr.size(), mm_high_flt_params_arr)
	RID_arr.append(fparameter_mm_high_buffer_rid)

	var mm_low_flt_params_arr : PackedByteArray = PackedFloat32Array(
		[vertex_spacing, 
		sqrt(settings_DA.target_density_sq_m_low_LOD),
		settings_DA.max_foliage_individual_random_offset, 
		deg_to_rad(settings_DA.max_foliage_tilt_degrees), 
		deg_to_rad(settings_DA.foliage_cam_bias_degress_near_far.x),
		deg_to_rad(settings_DA.foliage_cam_bias_degress_near_far.y),
		settings_DA.min_grass_blade_scale,
		settings_DA.distance_thresholds_low_lod.x, 
		settings_DA.distance_thresholds_low_lod.y, 
		settings_DA.distance_thresholds_low_lod.z]
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
	
	var vert_offset = settings_DA.high_lod_num_work_groups.x * settings_DA.high_lod_num_work_groups.y
	var mm_low_int_params_arr : PackedByteArray =  PackedInt32Array(
		[low_estimated_per_chunk ,chunks_per_dim, vert_offset]
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
	chunk_image.decompress()
	chunk_image.convert(Image.FORMAT_R8)
	if chunk_image.has_mipmaps():
		chunk_image.clear_mipmaps()
	mask_tex_uniform.add_id(_init_existing_image_data(rd, chunk_image, RenderingDevice.DATA_FORMAT_R8_UNORM, false))

	#player data binding
	player_transform_data_arr.resize(6*4)
	player_transform_data_mm_high_buffer_rid = rd.storage_buffer_create(player_transform_data_arr.size(), player_transform_data_arr)
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
	_try_assign_chunk_material_instances()
	mm_high_instance_RID = RenderingServer.instance_create()
	RID_arr.append(mm_high_instance_RID)	

	mm_high_RID = RenderingServer.multimesh_create()
	RID_arr.append(mm_high_RID)
	_init_new_multimesh(rd, mm_high_RID,mm_high_instance_RID, mm_high_estimated_count, settings_DA.foliage_mesh_high_LOD)
	if(chunk_material_high_LOD_inst):
		RenderingServer.instance_geometry_set_material_override(mm_high_instance_RID, chunk_material_high_LOD_inst.get_rid())
	mm_high_packed_transform_buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm_high_RID)
	RID_arr.append(mm_high_packed_transform_buffer_rid)
	mm_high_command_buffer_rid = RenderingServer.multimesh_get_command_buffer_rd_rid(mm_high_RID);
	RID_arr.append(mm_high_command_buffer_rid)
	
	## LOW LOD MULTIMESH
	mm_low_instance_RID = RenderingServer.instance_create()
	RID_arr.append(mm_low_instance_RID)	
	
	mm_low_RID = RenderingServer.multimesh_create()
	RID_arr.append(mm_low_RID)
	_init_new_multimesh(rd, mm_low_RID, mm_low_instance_RID, _mm_low_estimated_count , settings_DA.foliage_mesh_low_LOD)
	if(chunk_material_low_LOD_inst):
		RenderingServer.instance_geometry_set_material_override(mm_low_instance_RID, chunk_material_low_LOD_inst.get_rid())
	mm_low_packed_transform_buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm_low_RID)
	RID_arr.append(mm_low_packed_transform_buffer_rid)
	mm_low_command_buffer_rid = RenderingServer.multimesh_get_command_buffer_rd_rid(mm_low_RID);
	RID_arr.append(mm_low_command_buffer_rid)
	
func _load_shaders()-> void:
	compute_pos_shader_RID = _load_shader_from_file(settings_DA.positions_compute_shader)
	if(!compute_pos_shader_RID.is_valid()):
		push_error("FAILED TO LOAD SHADER: ", settings_DA.positions_compute_shader.to_string())
		return
	RID_arr.append(compute_pos_shader_RID)

	transfer_shader_RID = _load_shader_from_file(settings_DA.transfer_compute_shader)
	if(!transfer_shader_RID.is_valid()):
		push_error("FAILED TO LOAD SHADER: ", settings_DA.transfer_compute_shader.to_string())
		return
	RID_arr.append(transfer_shader_RID)
	
	#load shaders
	bender_shader_RID = _load_shader_from_file(settings_DA.bender_compute_shader)
	if(!bender_shader_RID.is_valid()):
		push_error("FAILED TO LOAD SHADER: ", settings_DA.bender_compute_shader.to_string())
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
	_try_assign_chunk_material_instances()
	for mat : Material in [chunk_material_high_LOD_inst, chunk_material_low_LOD_inst, chunk_material_lowest_LOD_inst]:
		if(mat):
			mat.set(foliage_shader_bend_mask, created_bender_tex_RD)
			mat.set(foliage_shader_bend_mask_size, settings_DA.chunk_dimenstion_size_m)
	bender_modified_img_uniform.add_id(created_bender_image_RID)
	
	# float parameter binding
	const delta : float = 1.0/60.0
	bend_float_param_arr  =  PackedFloat32Array(
		[settings_DA.unbend_rate_per_second,delta]
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
	rd.compute_list_dispatch(compute_list,settings_DA.high_lod_num_work_groups.x ,1, settings_DA.high_lod_num_work_groups.y)
	
	rd.compute_list_end()

func _update_compute_segments_data(snapshot : FoliageFrameSnapshot, _delta : float)->void:
	update_counter += 1
	
	#this would be where we pass player transform through or updated textures
	rd = RenderingServer.get_rendering_device()
	_update_player_data_buffer(rd, snapshot)
	var filled_in : int = _update_segments_to_draw_buffer(rd, snapshot)
	
	if(uniform_set_bender_RID.is_valid()):
		_update_bender_data(rd, _delta)
		_dispatch_bender_compute_list(rd)
	
	if(mm_pipeline_pos_calc_RID.is_valid() && mm_high_uniform_set_pos_transfer_RID.is_valid()):
		_dispatch_position_compute_list(rd, mm_high_uniform_set_pos_calc_RID, mm_high_uniform_set_pos_transfer_RID, settings_DA.high_lod_num_work_groups)
		pass

	var total_high_lod_groups : int = settings_DA.high_lod_num_work_groups.x * settings_DA.high_lod_num_work_groups.y
	if(filled_in >total_high_lod_groups):
		var work_group_amount : Vector2i = _calculate_low_LOD_group_amount(filled_in, total_high_lod_groups)
		_dispatch_position_compute_list(rd, mm_low_uniform_set_pos_calc_RID, mm_low_uniform_set_pos_transfer_RID,work_group_amount)
	else:
		#set the instance count to 0 on the low LOD
		pass
			

	# job done
	compute_active = false

func _calculate_low_LOD_group_amount(segment_amount : int, high_lod_amount : int) -> Vector2:
	return Vector2i(segment_amount - high_lod_amount, 1)

func _dispatch_bender_compute_list(_rd : RenderingDevice) -> void:
	var bender_compute_list : int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(bender_compute_list, pipeline_bender_RID)
	_rd.compute_list_bind_uniform_set(bender_compute_list, uniform_set_bender_RID, 0)	
	_rd.compute_list_dispatch(bender_compute_list,settings_DA.high_lod_num_work_groups.x,1,settings_DA.high_lod_num_work_groups.y)
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
	
func _update_player_data_buffer(_rd: RenderingDevice, snapshot : FoliageFrameSnapshot) -> void:
	if(!player_transform_data_mm_high_buffer_rid.is_valid()):
		return

	player_transform_data_arr.encode_float(0, snapshot.cam_origin.x - snapshot.chunk_global_pos.x)
	player_transform_data_arr.encode_float(4, snapshot.cam_origin.y - snapshot.chunk_global_pos.y)
	player_transform_data_arr.encode_float(8, snapshot.cam_origin.z - snapshot.chunk_global_pos.z)
	
	var cam_rot : Vector3 = snapshot.cam_transform.basis.get_euler()
	player_transform_data_arr.encode_float(12, cam_rot.x)
	player_transform_data_arr.encode_float(12, cam_rot.y)
	player_transform_data_arr.encode_float(16, cam_rot.z)
	
	_rd.buffer_update(player_transform_data_mm_high_buffer_rid, 0, player_transform_data_arr.size() ,player_transform_data_arr)

# REGION BENDERS 
#=================================================================================================================================
func _update_bender_data(_rd : RenderingDevice, delta : float) -> void:
	#update the delta passed through
	bend_float_param_arr.encode_float(4,delta)
	_rd.buffer_update(fparameter_buffer_bend_RID, 0, bend_float_param_arr.size() ,bend_float_param_arr)

# REGION SEGMENT DETECTION 
#=================================================================================================================================
func _update_segments_to_draw_buffer(_rd : RenderingDevice, snapshot : FoliageFrameSnapshot) -> int:
	if(!segment_coord_data_mm_buffer_rid.is_valid()):
		return 0

	# reset the working data from last frame
	segment_found_edges_left.fill(Vector2i.MIN.x)
	segment_found_edges_right.fill(Vector2i.MIN.x)
	segment_center_edges.fill(Vector2i.MIN.x)
	
	#find the vector that describe the 'edges' of the camera
	segment_work_filled_in = _fill_work_array_with_current_segments_data(snapshot, segments_per_dim)
		
	var element_amount : int = min(segment_work_filled_in, segments_per_dim * segments_per_dim)
	_rd.buffer_update(segment_coord_data_mm_buffer_rid, 0, element_amount*8, segment_work_data_arr.to_byte_array())
	return element_amount
	
func _ground_intersect_sub_pos(ray_dir : Vector3, snapshot : FoliageFrameSnapshot, fallback_sub_pos : Vector2) -> Vector2:
	const min_vertical_component : float = 0.001
	if(abs(ray_dir.y) < min_vertical_component):
		return fallback_sub_pos

	var t : float = (snapshot.ground_y_guess - snapshot.cam_origin.y) / ray_dir.y
	if(t <= 0.0):
		return fallback_sub_pos

	var hit_pos : Vector3 = snapshot.cam_origin + ray_dir * t
	return (Vector2(hit_pos.x, hit_pos.z) - snapshot.chunk_min_corner) / snapshot.vertex_spacing
	
func _fill_work_array_with_current_segments_data(snapshot : FoliageFrameSnapshot, max_segments_per_side : int) -> int:
	# push each projected point back along reverse camera forward, so segments
	# just behind the near plane still get picked up rather than being culled/clipped
	var left_start_pos : Vector2 = _ground_intersect_sub_pos(snapshot.left_dir, snapshot, snapshot.player_sub_pos) + snapshot.backward_sub_offset
	var right_start_pos : Vector2 = _ground_intersect_sub_pos(snapshot.right_dir, snapshot, snapshot.player_sub_pos) + snapshot.backward_sub_offset
	var projected_player_pos : Vector2 = _ground_intersect_sub_pos(snapshot.center_dir, snapshot, snapshot.player_sub_pos) + snapshot.backward_sub_offset
	
	current_player_segment = Vector2i( int(floor(snapshot.player_sub_pos.x))  ,int(floor(snapshot.player_sub_pos.y)) )
	current_projected_player_segment = Vector2i( int(floor(projected_player_pos.x))  ,int(floor(projected_player_pos.y)) )

	segments_found_left = _find_ray_intersect_chunk(left_start_pos, snapshot.left_dir, max_segments_per_side, segment_found_edges_left, snapshot.vertex_spacing)
	segments_found_right = _find_ray_intersect_chunk(right_start_pos, snapshot.right_dir, max_segments_per_side, segment_found_edges_right, snapshot.vertex_spacing)
	segments_found_center = _find_center_edge_segments(projected_player_pos, left_start_pos, right_start_pos, max_segments_per_side) 	# find all the segments in between those 2 ends

	var edge_amount_prioritize_per_side : int = settings_DA.high_lod_num_work_groups.x
	var post_priotitize_offset : int = edge_amount_prioritize_per_side * edge_amount_prioritize_per_side

	var index_write_offsets : Vector2i = _interleave_edge_data_into_work_array(current_projected_player_segment, segments_found_left, segments_found_right, segments_found_center, edge_amount_prioritize_per_side, post_priotitize_offset)
	var end_write_id : int = index_write_offsets.y
	end_write_id =_flood_fill_work_data(snapshot.cam_forward,index_write_offsets, post_priotitize_offset, max_segments_per_side)

	return end_write_id + 1

func _flood_fill_work_data(camera_forward : Vector3, write_offsets : Vector2i, post_prioritize_write_offset : int, max_segments_per_side : int) -> int:
	# expand into the compass direction the camera faces plus its two neighbours.
	# Unpacked into plain ints so the hot loop never builds a Vector2i temporary.
	var compass_index : int = _get_compass_direction_index(Vector2(camera_forward.x, camera_forward.z))
	var prev_id : int = compass_index - 1 if compass_index - 1 > 0 else 7
	var dir_main : Vector2i = compass_directions[compass_index]
	var dir_prev : Vector2i = compass_directions[prev_id]
	var dir_next : Vector2i = compass_directions[(compass_index + 1) % 8]

	var main_x : int = dir_main.x
	var main_y : int = dir_main.y
	var prev_x : int = dir_prev.x
	var prev_y : int = dir_prev.y
	var next_x : int = dir_next.x
	var next_y : int = dir_next.y

	var current_write_id : int = write_offsets.x
	var current_read_id : int = 0
	var max_possible_tests : int = max_segments_per_side * max_segments_per_side
	var post_prio_boundary : int = write_offsets.y

	while current_write_id < max_possible_tests && current_read_id < current_write_id:
		var read_offset : int = current_read_id * 2
		var start_x : int = segment_work_data_arr[read_offset]
		var start_y : int = segment_work_data_arr[read_offset + 1]
		current_read_id += 1

		# only interior cells (center-bridge and already-filled) fan out sideways.
		# Left/right edge cells sit on the visible boundary, so fanning out would fill segments we guaranteed cannot see
		var query_all_three : bool = segment_laterial_fill[start_x + start_y * segments_per_dim] != 0

		current_write_id = _flood_fill_try_add(start_x + main_x, start_y + main_y, max_segments_per_side, current_write_id, post_prioritize_write_offset, post_prio_boundary)
		if(query_all_three):
			current_write_id = _flood_fill_try_add(start_x + prev_x, start_y + prev_y, max_segments_per_side, current_write_id, post_prioritize_write_offset, post_prio_boundary)
			current_write_id = _flood_fill_try_add(start_x + next_x, start_y + next_y, max_segments_per_side, current_write_id, post_prioritize_write_offset, post_prio_boundary)

	return current_write_id

# tries to add one candidate segment to the work buffer; returns the (possibly unchanged, possibly jumped-past-the-priority-block) write cursor. 
#Takes plain ints rather than a Vector2i so callers don't allocate one per candidate.
func _flood_fill_try_add(check_x : int, check_y : int, max_segments_per_side : int, write_id : int, post_prioritize_write_offset : int, post_prio_boundary : int) -> int:
	if(check_x < 0 || check_y < 0 || check_x >= max_segments_per_side || check_y >= max_segments_per_side):
		return write_id

	var flat_index : int = check_x + check_y * max_segments_per_side
	if(segments_filled_arr[flat_index] == update_counter):
		return write_id

	segments_filled_arr[flat_index] = update_counter
	segment_laterial_fill[flat_index] = 1	# interior -- safe to fan out sideways from
	var write_offset : int = write_id * 2
	segment_work_data_arr[write_offset] = check_x
	segment_work_data_arr[write_offset + 1] = check_y

	write_id += 1
	if(write_id == post_prioritize_write_offset && post_prio_boundary > post_prioritize_write_offset):
		write_id = post_prio_boundary + 1

	return write_id
	
func _interleave_edge_data_into_work_array(player_projected_segment : Vector2i, left_edges_found : int , right_edges_found : int, center_edges_found : int,  edge_cell_amount_to_prioritize_per_side , non_prioritized_offset : int) -> Vector2i:
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
		left_dist = player_projected_segment.distance_squared_to(Vector2i(segment_found_edges_left[0],segment_found_edges_left[1]))
	if(center_edges_found > 0):
		center_dist = player_projected_segment.distance_squared_to( Vector2i( segment_center_edges[0],segment_center_edges[1]) )
	if(right_edges_found > 0):
		right_dist = player_projected_segment.distance_squared_to(Vector2i(segment_found_edges_right[0],segment_found_edges_right[1]))

	for prio_write_id in range(amount_to_write_prioritized):
		smallest_distance = min(left_dist, center_dist, right_dist)

		if(smallest_distance == large_float_dist):
			break

		var write_offset : int = prio_write_id * 2
		if(smallest_distance == left_dist):
			segment_work_data_arr[write_offset] = segment_found_edges_left[left_id]
			segment_work_data_arr[write_offset + 1] = segment_found_edges_left[left_id + 1]
			left_id +=2
			left_dist = player_projected_segment.distance_squared_to(Vector2i(segment_found_edges_left[left_id], segment_found_edges_left[left_id +1]))
		elif(smallest_distance == center_dist):
			segment_work_data_arr[write_offset] = segment_center_edges[center_id]
			segment_work_data_arr[write_offset + 1] = segment_center_edges[center_id + 1]
			center_id +=2
			center_dist = player_projected_segment.distance_squared_to(Vector2i(segment_center_edges[center_id], segment_center_edges[center_id+1]))
		else:
			segment_work_data_arr[write_offset] = segment_found_edges_right[right_id]
			segment_work_data_arr[write_offset + 1] = segment_found_edges_right[right_id + 1]
			right_id +=2
			right_dist = player_projected_segment.distance_squared_to(Vector2i(segment_found_edges_right[ right_id], segment_found_edges_right[ right_id +1]))

		return_index_write_offset.x +=1
		
	var amount_to_write_post_prio : int = left_edges_found + right_edges_found + center_edges_found - amount_to_write_prioritized

	if(amount_to_write_post_prio > 0):
		var post_prio_write_id : int = non_prioritized_offset

		# write the rest of the data linearly
		for l_id in range(left_id, left_edges_found *2,2):
			segment_work_data_arr[post_prio_write_id * 2] = segment_found_edges_left[l_id]
			segment_work_data_arr[post_prio_write_id * 2 + 1] = segment_found_edges_left[l_id+1]
			post_prio_write_id += 1

		for c_id in range(center_id, center_edges_found *2,2):
			segment_work_data_arr[post_prio_write_id * 2] = segment_center_edges[c_id]
			segment_work_data_arr[post_prio_write_id * 2 + 1] = segment_center_edges[c_id+1]
			post_prio_write_id += 1
		
		for r_id in range(right_id, right_edges_found *2,2):
			segment_work_data_arr[post_prio_write_id * 2] = segment_found_edges_right[r_id]
			segment_work_data_arr[post_prio_write_id * 2 + 1] = segment_found_edges_right[r_id+1]
			post_prio_write_id += 1

		return_index_write_offset.y = post_prio_write_id
		
	return return_index_write_offset

# Writes `segment` into `arr_to_edit` at `write_index`, skipping it if another
# edge writer already claimed it this update -- this is what keeps the edge
# arrays (and the interleaved work buffer) duplicate-free.
# `allow_lateral_expand` marks the cell as interior for the flood fill: true for
# center-bridge cells, false for left/right edge cells.
# Returns the next write index (unchanged if skipped).
func _try_write_unique_edge_segment(segment : Vector2i, arr_to_edit : PackedInt32Array, write_index : int, allow_lateral_expand : bool = false) -> int:
	var flat_index : int = _segment_flat_index(segment)
	if(segments_filled_arr[flat_index] == update_counter):
		return write_index

	segments_filled_arr[flat_index] = update_counter
	segment_laterial_fill[flat_index] = 1 if allow_lateral_expand else 0
	arr_to_edit[2 * write_index] = segment.x
	arr_to_edit[2 * write_index + 1] = segment.y
	return write_index + 1

# use the DDA algorithm to find the edges of the chunk starting from outside the chunk
func _ray_chunk_entry_pos(start_pos : Vector2, dir : Vector3, max_segment_id : int) -> Vector2:
	const min_dir_component : float = 0.00001
	var box_max : float = float(max_segment_id + 1)

	var t_enter : float = 0.0
	var t_exit : float = INF

	if(abs(dir.x) < min_dir_component):
		if(start_pos.x < 0.0 || start_pos.x > box_max):
			return no_ray_box_intersection
	else:
		var tx1 : float = (0.0 - start_pos.x) / dir.x
		var tx2 : float = (box_max - start_pos.x) / dir.x
		t_enter = max(t_enter, min(tx1, tx2))
		t_exit = min(t_exit, max(tx1, tx2))

	if(abs(dir.z) < min_dir_component):
		if(start_pos.y < 0.0 || start_pos.y > box_max):
			return no_ray_box_intersection
	else:
		var ty1 : float = (0.0 - start_pos.y) / dir.z
		var ty2 : float = (box_max - start_pos.y) / dir.z
		t_enter = max(t_enter, min(ty1, ty2))
		t_exit = min(t_exit, max(ty1, ty2))

	if(t_enter > t_exit):
		return no_ray_box_intersection

	return start_pos + Vector2(dir.x, dir.z) * t_enter

func _find_ray_intersect_chunk(grid_start_pos : Vector2, dir: Vector3, max_segment_per_side : int, arr_to_edit : PackedInt32Array, vertex_spacing : float) ->int:
	var max_segment_id : int = max_segment_per_side -1

	# if our starting point isn't in our chunk to begin with, find the starting point
	if(!_is_segment_valid_in_chunk(Vector2i(int(grid_start_pos.x), int(grid_start_pos.y)), max_segment_per_side)):
		var entry_pos : Vector2 = _ray_chunk_entry_pos(grid_start_pos,-dir, max_segment_id)
		if(entry_pos == no_ray_box_intersection):
			# the ray never touches this chunk from here at all -- the
			# closest we can offer is the chunk-boundary point nearest the
			# true (off-chunk) start, rather than wandering off in `dir`
			var closest : Vector2i = _clamp_outside_segment_to_closest_edge(Vector2i(int(grid_start_pos.x), int(grid_start_pos.y)), max_segment_id)
			return _try_write_unique_edge_segment(closest, arr_to_edit, 0)

		# nudge along the direction we actually walked so we land inside the cell instead of on its boundary
		grid_start_pos = entry_pos + Vector2(-dir.x, -dir.z) * 0.01

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
	# TODO: properly calculate the max possible distance we could travel in a chunk before we should abort
	var max_distance : float = max_segment_per_side  * vertex_spacing
	var amount_found : int = 0

	# the un-stepped starting cell is the segment closest to the player on this  edge -- DDA only starts *stepping* from here, so without explicitly adding
	# it first the nearest visible row/column on this side of the screen never
	# makes it into the buffer.
	if(_is_segment_valid_in_chunk(current_tile_to_check, max_segment_per_side)):
		amount_found = _try_write_unique_edge_segment(current_tile_to_check, arr_to_edit, amount_found)

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
		
		amount_found = _try_write_unique_edge_segment(current_tile_to_check, arr_to_edit, amount_found)

	return amount_found
	
# Walks a cell DDA from `from_pos` to `to_pos` (continuous grid sub-positions),
# writing every cell the line actually crosses -- unlike
# _add_edge_segments_between_points, which steps the dominant axis and can skip
# cells the line only clips. Clips at the chunk boundary, so an off-chunk
# `to_pos` still contributes the portion that lies inside. Cells written are
# marked interior (segment_laterial_fill): a bridge is not a screen edge.
func _fill_DDA_between_segments(from_pos : Vector2, to_pos : Vector2, write_offset : int, max_segments_per_side : int, arr_to_edit : PackedInt32Array, include_start : bool = true) -> int:
	var write_index : int = write_offset
	var from_tile : Vector2i = Vector2i(int(from_pos.x), int(from_pos.y))
	var target_tile : Vector2i = Vector2i(int(to_pos.x), int(to_pos.y))

	if(include_start && _is_segment_valid_in_chunk(from_tile, max_segments_per_side)):
		write_index = _try_write_unique_edge_segment(from_tile, arr_to_edit, write_index, true)

	var delta : Vector2 = to_pos - from_pos
	if(from_tile == target_tile || delta.length_squared() < 0.000001):
		return write_index - write_offset

	var dir : Vector2 = delta.normalized()
	var target_distance : float = delta.length()

	var ray_unit_step_size : Vector2 = Vector2(sqrt(1 + (dir.y / dir.x) * (dir.y / dir.x)), sqrt(1 + (dir.x / dir.y) * (dir.x / dir.y)))
	var step_unit_dir : Vector2i = Vector2i(sign(dir.x), sign(dir.y))

	var current_tile : Vector2i = from_tile
	var current_ray_length : Vector2

	if(dir.x < 0):
		current_ray_length.x = (from_pos.x - current_tile.x) * ray_unit_step_size.x
	else:
		current_ray_length.x = ((current_tile.x + 1) - from_pos.x) * ray_unit_step_size.x

	if(dir.y < 0):
		current_ray_length.y = (from_pos.y - current_tile.y) * ray_unit_step_size.y
	else:
		current_ray_length.y = ((current_tile.y + 1) - from_pos.y) * ray_unit_step_size.y

	var current_distance : float = 0.0
	while current_tile != target_tile && current_distance <= target_distance:
		if(current_ray_length.x < current_ray_length.y):
			current_tile.x += step_unit_dir.x
			current_distance = current_ray_length.x
			current_ray_length.x += ray_unit_step_size.x
		else:
			current_tile.y += step_unit_dir.y
			current_distance = current_ray_length.y
			current_ray_length.y += ray_unit_step_size.y

		if(!_is_segment_valid_in_chunk(current_tile, max_segments_per_side)):
			break

		write_index = _try_write_unique_edge_segment(current_tile, arr_to_edit, write_index, true)

	return write_index - write_offset

func _find_center_edge_segments(player_projected_pos : Vector2, left_start_pos : Vector2, right_start_pos : Vector2, max_segment_per_side : int) -> int:
	var write_id : int = 0

	# Bridge center -> left and center -> right, aiming at the TRUE corner ground
	# points (which may be off-chunk) rather than the corrected first cell in
	# segment_found_edges_left/right. That correction walks back along the side
	# frustum edge, so bridging to it would skip the near boundary between the
	# chunk edge and that point. Each leg clips independently at the boundary.
	# Nearest leg first, so a truncated bridge keeps the closer portion.
	# include_start on both legs is safe -- de-dup makes the second write a no-op.
	if(player_projected_pos.distance_squared_to(left_start_pos) <= player_projected_pos.distance_squared_to(right_start_pos)):
		write_id += _fill_DDA_between_segments(player_projected_pos, left_start_pos, write_id, max_segment_per_side, segment_center_edges, true)
		write_id += _fill_DDA_between_segments(player_projected_pos, right_start_pos, write_id, max_segment_per_side, segment_center_edges, true)
	else:
		write_id += _fill_DDA_between_segments(player_projected_pos, right_start_pos, write_id, max_segment_per_side, segment_center_edges, true)
		write_id += _fill_DDA_between_segments(player_projected_pos, left_start_pos, write_id, max_segment_per_side, segment_center_edges, true)

	return write_id
	
func _add_edge_segments_between_points(from : Vector2i, to : Vector2i, write_offset : int, max_segments_per_side : int, arr_to_edit : PackedInt32Array, include_start: bool = true, include_end : bool= false) -> int:
	var delta : Vector2i = to - from
	var step_x : int = sign(delta.x)
	var step_y : int = sign(delta.y)
	var abs_x : int = abs(delta.x)
	var abs_y : int = abs(delta.y)
	var step_count : int = max(abs_x, abs_y)

	var amount_added : int = 0
	if(step_count == 0):
		if((include_start || include_end) && _is_segment_valid_in_chunk(from, max_segments_per_side)):
			amount_added = _try_write_unique_edge_segment(from, arr_to_edit, write_offset) - write_offset
		return amount_added

	var start_id : int = 0 if include_start else 1
	var end_id : int = step_count if include_end else step_count - 1

	for id in range(start_id, end_id + 1):
		# walk the dominant axis at 1 cell/step, proportionally advancing the
		# minor axis so both reach `to` together at step_count
		var to_add : Vector2i = Vector2i(
			from.x + int(round(float(step_x * abs_x * id) / step_count)),
			from.y + int(round(float(step_y * abs_y * id) / step_count))
		)

		if(!_is_segment_valid_in_chunk(to_add, max_segments_per_side)):
			return amount_added

		amount_added = _try_write_unique_edge_segment(to_add, arr_to_edit, write_offset + amount_added) - write_offset

	return amount_added

const compass_directions : Array[Vector2i] = [Vector2i(1,0),Vector2i(1,1),Vector2i(0,1) ,Vector2i(-1,1),Vector2i(-1,0), Vector2i(-1,-1), Vector2i(0,-1),Vector2i(1,-1)]	#clockwise directions starting with EAST

func _get_compass_direction_index(direction : Vector2) -> int:
	return ((int(round( atan2(direction.y, direction.x)/ (2 * PI / 8))) + 8) % 8)	#divide the 360 look direction degrees into 8 sections for the cardinal directions

func _is_corner_segment(segment : Vector2i, max_segment_id : int) -> bool:
	return ( segment.x == 0 || segment.x == max_segment_id ) &&  ( segment.y == 0 || segment.y == max_segment_id )

func _clamp_outside_segment_to_closest_edge(to_clamp: Vector2i , max_segment_id : int) -> Vector2i:
	#guarantee each element is inside [0 , max_segments_per_side -1]
	return Vector2i(clamp(to_clamp.x, 0, max_segment_id), clamp(to_clamp.y, 0, max_segment_id))
	
func _segment_flat_index(segment : Vector2i) -> int:
	return segment.x + segment.y * segments_per_dim		
	
func _is_segment_valid_in_chunk(segment_to_check : Vector2i, max_segments_per_side : int) -> bool:
		return segment_to_check.x >= 0 && segment_to_check.y >= 0 &&  segment_to_check.x < max_segments_per_side && segment_to_check.y < max_segments_per_side
