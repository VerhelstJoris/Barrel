@tool
class_name FoliageChunk extends Node3D

enum EFoliageLOD {NONE, TEX, LOW, HIGH}

@export var high_LOD_mesh : Mesh
@export var low_LOD_mesh : Mesh
@export var grass_material :Material

@export var lod_switch_distance_squared := 100.0
@export var impostor_fade_in_start := 5.0
@export var impostor_fade_in_end := 10.0
@export var grass_fade_out_start := 10.0
@export var grass_fade_out_end := 20.0

@export var height_map_tex : Texture2D

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
var height_buffer_RID : RID

var compute_active : bool = false

var initialized : bool = false

func _ready() -> void:
	if(!Engine.is_editor_hint()):
		_setup_compute_pipeline()
	

func _process(_delta: float) -> void:
	#RenderingServer.call_on_render_thread(_render_process.bind(_delta, rd))
	var _camera_pos : Vector3

	if Engine.is_editor_hint():
		_camera_pos = EditorInterface.get_editor_viewport_3d().get_camera_3d().global_position
	else:
		_camera_pos = get_viewport().get_camera_3d().global_position

	if(!compute_active && initialized):
		RenderingServer.call_on_render_thread(_execute_compute_test)
		
		
func _render_process(_delta : float, _rd : RenderingDevice) -> void:
	return
	
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
	var shader_file : Resource = load("res://Materials/Shaders/Environment/compute_grass_positions.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader_RID = rd.shader_create_from_spirv(shader_spirv)
	
	if(!shader_RID.is_valid()):
		return
	
	#texture binding
	var tex_uniform = RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(_init_existing_texture_data(rd, height_map_tex))
	
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
	var params_arr_float : PackedByteArray = PackedFloat32Array([4.0, 100.0, 100.0]).to_byte_array()
	var parameter_buffer := rd.storage_buffer_create(params_arr_float.size(), params_arr_float)

	var parameter_uniform_block = RDUniform.new()
	parameter_uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	parameter_uniform_block.binding = 3
	parameter_uniform_block.add_id(parameter_buffer)
	
	uniform_set_RID = rd.uniform_set_create([tex_uniform, multimesh_transform_buffer_uniform, multimesh_command_buffer_uniform, parameter_uniform_block], shader_RID, 0)
	
	# Create a compute pipeline
	pipeline_RID = rd.compute_pipeline_create(shader_RID)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_RID, 0)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	
	set_process(true)
	initialized = true


func _exit_tree() -> void:
	rd.free_rid(shader_RID)
	rd.free_rid(uniform_set_RID)
	rd.free_rid(pipeline_RID)
	rd.free_rid(height_buffer_RID)
	rd.free()
	
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
	RenderingServer.multimesh_allocate_data(created_multimesh_RID, 1000 , RenderingServer.MULTIMESH_TRANSFORM_3D,false, false, true)
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
	compute_active = true
	
	#this would be where we pass player transform through or updated textures
	
	rd = RenderingServer.get_rendering_device()

	var compute_list : int = rd.compute_list_begin()
	
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_RID, 0)
	
	rd.compute_list_dispatch(compute_list,1,1,1)
	rd.compute_list_end()

	compute_active = false
