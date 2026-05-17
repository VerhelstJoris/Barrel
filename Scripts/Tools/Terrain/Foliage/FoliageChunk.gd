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
	#RenderingServer.call_on_render_thread(_render_process.bind(_delta, rd))
	var _cam_transform : Transform3D

	if Engine.is_editor_hint():
		_cam_transform = EditorInterface.get_editor_viewport_3d().get_camera_3d().global_transform
	else:
		_cam_transform = get_viewport().get_camera_3d().global_transform
	
	if(player_transform_to_pass.is_equal_approx(_cam_transform)):
		return
		
	if(!compute_active && initialized):
		player_transform_to_pass = _cam_transform
		RenderingServer.call_on_render_thread(_update_compute_data.bind(player_transform_to_pass))
		
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

	var float_parameter_uniform_block = RDUniform.new()
	float_parameter_uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	float_parameter_uniform_block.binding = 3
	float_parameter_uniform_block.add_id(fparameter_buffer_RID)
	
	#int parameter binding
	var int_params_arr : PackedByteArray =  PackedInt32Array(
													  [estimated_per_chunk , int(chunk_dimenstion_size_m / vertex_spacing)]
												).to_byte_array()
	var iparameter_buffer_RID :RID = rd.storage_buffer_create(int_params_arr.size(), int_params_arr)
	RID_arr.append(iparameter_buffer_RID)

	var int_parameter_uniform_block = RDUniform.new()
	int_parameter_uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_parameter_uniform_block.binding = 4
	int_parameter_uniform_block.add_id(iparameter_buffer_RID)	
	
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
			[height_data_uniform, transform_array_uniform, blade_count_array_uniform, float_parameter_uniform_block, mask_tex_uniform, player_data_uniform, int_parameter_uniform_block]
			, compute_pos_shader_RID, 0)
	RID_arr.append(uniform_set_primary_RID)

	uniform_set_secondary_RID = rd.uniform_set_create(
		[multimesh_transform_buffer_uniform, transform_array_uniform , blade_count_array_uniform,multimesh_command_buffer_uniform, int_parameter_uniform_block]
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

func _update_compute_data(_player_cam_transform_world: Transform3D)->void:
	if(!pipeline_primary_RID.is_valid() || !uniform_set_primary_RID.is_valid() || !uniform_set_secondary_RID.is_valid()):
		return
	
	compute_active = true
	
	#this would be where we pass player transform through or updated textures
	rd = RenderingServer.get_rendering_device()
	_update_player_data_buffer(rd, _player_cam_transform_world)

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