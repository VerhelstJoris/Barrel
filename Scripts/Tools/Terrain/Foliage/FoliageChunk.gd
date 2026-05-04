@tool
class_name FoliageChunk extends Node3D

enum EFoliageLOD {NONE, TEX, LOW, HIGH}

@export_tool_button("preview in Editor", "Callable") var preview_action = _preview_in_editor
@export_tool_button("Generate Height Data for Chunk", "Callable") var generate_height_data_action = _generate_height_data

@export_group("Setup Data")
@export var chunk_transform_centered : bool = false
@export var positions_compute_shader : RDShaderFile
@export var high_LOD_mesh : Mesh
@export var low_LOD_mesh : Mesh
@export var grass_material :Material

@export var terrain_node : Terrain3D

@export_group("Customizable Parameters")
@export var high_lod_num_work_groups_xz : int = 4

@export var foliage_target_density_sq_m : float = 80
@export var max_foliage_individual_random_offset : float = 0.2
@export var max_foliage_tilt_degrees : float = 15.0

@export_group("runtime data - DO NOT EDIT MANUALLY")
@export var height_array : PackedFloat32Array

const vertex_move_amount_shader_parameter : String = "vertex_move_amount"

var current_lod : EFoliageLOD = EFoliageLOD.NONE

var rd : RenderingDevice

var instance_RID
var scenario_RID

var created_multimesh_RID : RID
var created_multimesh_buffer_RID : RID
var created_multimesh_command_buffer_RID : RID

var shader_RID : RID
var uniform_set_RID : RID
var pipeline_RID : RID

var compute_active : bool = false

var initialized : bool = false

func _generate_height_data() -> void:
	height_array.clear()
	var elem_per_dim : int = high_lod_num_work_groups_xz +1
	height_array.resize( elem_per_dim * elem_per_dim)
	
	if(terrain_node):
		print("vertex spacing : ", terrain_node.vertex_spacing)
		for row in elem_per_dim:
			for col in elem_per_dim:
				var current_index : int = row * elem_per_dim + col
				var chunk_pixel_coord : Vector2i
				if(chunk_transform_centered):
					chunk_pixel_coord = Vector2i( 
						int((global_position.x - (terrain_node.vertex_spacing * high_lod_num_work_groups_xz * 0.5) )/ terrain_node.vertex_spacing) ,
						int((global_position.z - (terrain_node.vertex_spacing * high_lod_num_work_groups_xz * 0.5) )/ terrain_node.vertex_spacing) )
				else:
					chunk_pixel_coord = Vector2i(int(global_position.x / terrain_node.vertex_spacing) ,int(global_position.z / terrain_node.vertex_spacing) )
				var corresponding_world_pos : Vector3 = Vector3( (chunk_pixel_coord.x + row) * terrain_node.vertex_spacing, 0, (chunk_pixel_coord.y + col) * terrain_node.vertex_spacing)
				height_array[current_index] = terrain_node.data.get_height(corresponding_world_pos)
				print("height for chunk at (", row , ", ", col, ") and id: " , current_index , " and world pos ", corresponding_world_pos, " : " , height_array[current_index])
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
		
func _process(_delta: float) -> void:
	#RenderingServer.call_on_render_thread(_render_process.bind(_delta, rd))
	var _camera_pos : Vector3

	if Engine.is_editor_hint():
		_camera_pos = EditorInterface.get_editor_viewport_3d().get_camera_3d().global_position
	else:
		_camera_pos = get_viewport().get_camera_3d().global_position

	if(!compute_active && initialized):
		RenderingServer.call_on_render_thread(_execute_compute_test)
		
func _setup_compute_pipeline()	-> void:
	if(get_world_3d() == null):
		return
		
	rd = RenderingServer.get_rendering_device()

	scenario_RID = get_world_3d().scenario
	
	if(!scenario_RID.is_valid()):
		return
	
	instance_RID = RenderingServer.instance_create()
	if(!instance_RID.is_valid()):
		return

	#load shader
	var shader_spirv: RDShaderSPIRV = positions_compute_shader.get_spirv()
	shader_RID = rd.shader_create_from_spirv(shader_spirv)
	
	if(!shader_RID.is_valid()):
		return
	
	#height data binding
	var height_data_uniform = RDUniform.new()
	height_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	height_data_uniform.binding = 0
	var input_bytes := height_array.to_byte_array()
	height_data_uniform.add_id(rd.storage_buffer_create(input_bytes.size(), input_bytes))
	
	#storage buffer binding
	var multimesh_transform_buffer_uniform := RDUniform.new()
	multimesh_transform_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	multimesh_transform_buffer_uniform.binding = 1

	_create_new_multimesh(rd)
	var buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(created_multimesh_RID)
	multimesh_transform_buffer_uniform.add_id(buffer_rid)

	#command buffer binding
	var multimesh_command_buffer_uniform := RDUniform.new()
	multimesh_command_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	multimesh_command_buffer_uniform.binding = 2
	multimesh_command_buffer_uniform.add_id(created_multimesh_command_buffer_RID)

	# parameter buffer
	var vertex_spacing : float = 4.0
	if(terrain_node):
		vertex_spacing = terrain_node.vertex_spacing
		
	var params_arr_float : PackedByteArray = PackedFloat32Array(
		[vertex_spacing, 100.0, sqrt(foliage_target_density_sq_m), max_foliage_individual_random_offset, deg_to_rad(max_foliage_tilt_degrees)]
		 ).to_byte_array()
	var parameter_buffer := rd.storage_buffer_create(params_arr_float.size(), params_arr_float)

	var parameter_uniform_block = RDUniform.new()
	parameter_uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	parameter_uniform_block.binding = 3
	parameter_uniform_block.add_id(parameter_buffer)
	
	uniform_set_RID = rd.uniform_set_create([height_data_uniform, multimesh_transform_buffer_uniform, multimesh_command_buffer_uniform, parameter_uniform_block], shader_RID, 0)
	
	# Create a compute pipeline
	pipeline_RID = rd.compute_pipeline_create(shader_RID)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_RID, 0)
	rd.compute_list_end()
	
	set_process(true)
	initialized = true
	
func _exit_tree() -> void:
	_cleanup()
	
func _cleanup() -> void:
	if(created_multimesh_RID.is_valid()):
		RenderingServer.multimesh_allocate_data(created_multimesh_RID, 0 , RenderingServer.MULTIMESH_TRANSFORM_3D,false, false, true)

	_try_free_rid(rd,pipeline_RID)
	_try_free_rid(rd,uniform_set_RID)
	_try_free_rid(rd,shader_RID)
	
	initialized = false
	compute_active = false
	
	set_process(false)

func _try_free_rid(_rd : RenderingDevice, rid : RID) -> void:
	if(_rd == null):
		return
		
	if(!rid.is_valid()):
		return
		
	_rd.free_rid(rid)
	
func _init_existing_texture_data(_rd : RenderingDevice, tex: Texture2D)-> RID:
	var image := tex.get_image()
	image.convert(Image.FORMAT_RGBAF)
	
	var heightmap_format := RDTextureFormat.new()
	heightmap_format.width = image.get_width()
	heightmap_format.height = image.get_height()
	heightmap_format.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT + RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	heightmap_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	
	return _rd.texture_create(heightmap_format, RDTextureView.new(), [image.get_data()])

func _create_new_multimesh(_rd : RenderingDevice) -> void:
	created_multimesh_RID =RenderingServer.multimesh_create()

	var vertex_spacing : float = 4.0
	if(terrain_node):
		vertex_spacing = terrain_node.vertex_spacing
	#calculate an estimated instance count to pass through
	var estimated_count : int = int(high_lod_num_work_groups_xz * high_lod_num_work_groups_xz * foliage_target_density_sq_m * vertex_spacing * vertex_spacing)
	RenderingServer.multimesh_allocate_data(created_multimesh_RID, estimated_count , RenderingServer.MULTIMESH_TRANSFORM_3D,false, false, true)
	high_LOD_mesh.surface_set_material(0,grass_material)
	RenderingServer.multimesh_set_mesh(created_multimesh_RID, high_LOD_mesh.get_rid())
	
	var aabb : Vector3 = Vector3(512.0, 1000.0, 512.0)
	RenderingServer.instance_set_custom_aabb(instance_RID, AABB(get_global_position() , aabb))
	RenderingServer.instance_set_transform(instance_RID, get_global_transform())
	RenderingServer.instance_set_scenario(instance_RID, scenario_RID)
	RenderingServer.instance_set_base(instance_RID, created_multimesh_RID)
	RenderingServer.instance_geometry_set_flag(instance_RID, RenderingServer.InstanceFlags.INSTANCE_FLAG_USE_DYNAMIC_GI, true)
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance_RID, RenderingServer.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF)
	
	created_multimesh_buffer_RID = RenderingServer.multimesh_get_buffer_rd_rid(created_multimesh_RID)

	created_multimesh_command_buffer_RID = RenderingServer.multimesh_get_command_buffer_rd_rid(created_multimesh_RID);
	
func _setup_terrain_uniform(_rd : RenderingDevice) -> void:
	pass

func _execute_compute_test()->void:
	if(!pipeline_RID.is_valid() || !uniform_set_RID.is_valid()):
		return
	
	compute_active = true
	
	#this would be where we pass player transform through or updated textures
	rd = RenderingServer.get_rendering_device()

	var compute_list : int = rd.compute_list_begin()
	
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_RID, 0)
	
	rd.compute_list_dispatch(compute_list,high_lod_num_work_groups_xz,1,high_lod_num_work_groups_xz)
	rd.compute_list_end()


	compute_active = false
