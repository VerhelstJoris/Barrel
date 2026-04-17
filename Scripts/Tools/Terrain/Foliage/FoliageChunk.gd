@tool
class_name FoliageChunk extends Node3D


enum EFoliageLOD {NONE, TEX, LOW, HIGH}


@export var foliage_multimesh : MultiMeshInstance3D

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

var scenario_RID

var multimesh_RID
var created_high_LOD_multimesh

var test_storage_buffer_RID : RID

var shader_RID : RID
var uniform_set_RID : RID
var pipeline_RID : RID
var height_buffer_RID : RID

var compute_active : bool = false

func _ready() -> void:
	if(foliage_multimesh == null):
		push_error("No Valid multimesh assigned on Foliage Chunk : ", owner.name)
		return
		
	foliage_multimesh.set_instance_shader_parameter(vertex_move_amount_shader_parameter, 1.0)

	set_process(true)	

	scenario_RID =  get_world_3d().scenario
	
	_setup_compute_pipeline()

	var _packedArr : PackedFloat32Array = PackedFloat32Array([0.027,0.0,1.0,2.331,0.0,1.0,0.0,0.0,-1.0,0.0,0.027,-3.764])
	

func _process(_delta: float) -> void:
	#RenderingServer.call_on_render_thread(_render_process.bind(_delta, rd))
	#var camera_pos
#
	#if Engine.is_editor_hint():
	#	camera_pos = EditorInterface.get_editor_viewport_3d().get_camera_3d().global_position
	#else:
	#	camera_pos = get_viewport().get_camera_3d().global_position
#
	#var camera_distance_squared : float = global_position.distance_squared_to(camera_pos)
#
	#if camera_distance_squared < lod_switch_distance_squared:
	#	_change_LOD(EFoliageLOD.HIGH)
	#else:
	#	_change_LOD(EFoliageLOD.LOW)
	if(!compute_active):
		RenderingServer.call_on_render_thread(_execute_compute_test)

		
func _change_LOD(new_lod : EFoliageLOD) -> void:
	if(current_lod == new_lod):
		return
	
	current_lod = new_lod
	
	match new_lod:
		EFoliageLOD.LOW:
			foliage_multimesh.multimesh.mesh = low_LOD_mesh
			foliage_multimesh.set_instance_shader_parameter(vertex_move_amount_shader_parameter, 0.0)
		EFoliageLOD.HIGH:
			foliage_multimesh.multimesh.mesh = high_LOD_mesh
			foliage_multimesh.set_instance_shader_parameter(vertex_move_amount_shader_parameter, 1.0)
		EFoliageLOD.TEX:
			pass
		EFoliageLOD.NONE:
			pass
			
func _render_process(_delta : float, _rd : RenderingDevice) -> void:
	return
	
func _setup_compute_pipeline()	-> void:
	rd = RenderingServer.get_rendering_device()

	#load shader
	var shader_file := load("res://Materials/Shaders/Environment/compute_grass_positions.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader_RID = rd.shader_create_from_spirv(shader_spirv)
	
	#texture binding
	var tex_uniform = RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(_init_existing_texture_data(rd))
	
	#storage buffer binding
	var multimesh_uniform := RDUniform.new()
	multimesh_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	multimesh_uniform.binding = 0

	var command_buffer_RID = _create_new_multimesh(rd)
	var buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(created_high_LOD_multimesh)
	multimesh_uniform.add_id(buffer_rid)
	
	uniform_set_RID = rd.uniform_set_create([multimesh_uniform], shader_RID, 0)
	
	# Create a compute pipeline
	pipeline_RID = rd.compute_pipeline_create(shader_RID)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_RID, 0)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()

	#has to be called or it's not visible for some reason reason
	RenderingServer.multimesh_set_visible_instances(created_high_LOD_multimesh, 1)
	

func _exit_tree() -> void:
	rd.free_rid(shader_RID)
	rd.free_rid(uniform_set_RID)
	rd.free_rid(pipeline_RID)
	rd.free_rid(height_buffer_RID)
	rd.free()
	
func _init_generic_buffer(_rd : RenderingDevice) -> RID:
	var test_input := PackedFloat32Array([0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0])
	var input_bytes := test_input.to_byte_array()

	# Create a storage buffer that can hold our float values.
	# Each float has 4 bytes (32 bit) so 10 x 4 = 40 bytes
	return rd.storage_buffer_create(input_bytes.size(), input_bytes)
	
func _init_empty_image_data(_rd : RenderingDevice) -> RID:
	var format = RDTextureFormat.new()
	format.width = 512
	format.height = 512
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT + RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	#this needs to line up with our image format
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT

	var image:= Image.create_empty(512,512,false,Image.FORMAT_RF)
	image.fill(Color(0.0,0.0,0.0,1.0))
	return _rd.texture_create(format, RDTextureView.new(), [image.get_data()])
	
func _init_existing_texture_data(_rd : RenderingDevice)-> RID:
	var image := height_map_tex.get_image()
	image.convert(Image.FORMAT_RGBAF)
	
	var heightmap_format := RDTextureFormat.new()
	heightmap_format.width = image.get_width()
	heightmap_format.height = image.get_height()
	heightmap_format.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT + RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	heightmap_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	
	return _rd.texture_create(heightmap_format, RDTextureView.new(), [image.get_data()])

func _create_new_multimesh(_rd : RenderingDevice) -> RID:
	created_high_LOD_multimesh =RenderingServer.multimesh_create()
	RenderingServer.multimesh_allocate_data(created_high_LOD_multimesh, 1 , RenderingServer.MULTIMESH_TRANSFORM_3D,false, false, true)
	high_LOD_mesh.surface_set_material(0,grass_material)
	RenderingServer.multimesh_set_mesh(created_high_LOD_multimesh, high_LOD_mesh.get_rid())
	var instance = RenderingServer.instance_create()
	var scenario = get_world_3d().scenario
	
	var aabb : Vector3 = Vector3(512.0, 1000.0, 512.0)
	RenderingServer.instance_set_custom_aabb(instance, AABB(foliage_multimesh.get_global_position() , aabb))
	RenderingServer.instance_set_transform(instance, foliage_multimesh.get_global_transform())
	RenderingServer.instance_set_scenario(instance, scenario)
	RenderingServer.instance_set_base(instance, created_high_LOD_multimesh)
	RenderingServer.instance_geometry_set_flag(instance, RenderingServer.InstanceFlags.INSTANCE_FLAG_USE_DYNAMIC_GI, true)
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance, RenderingServer.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF)
	
	#var foundBuffer = RenderingServer.multimesh_get_buffer(created_high_LOD_multimesh);
	
	#var packedArr : PackedFloat32Array = PackedFloat32Array([0.027,0.0,1.0,2.331,0.0,1.0,0.0,0.0,-1.0,0.0,0.027,-3.764])
	var packedArr : PackedFloat32Array = PackedFloat32Array([0,0,0,0,0,0,0,0,0,0,0,0])
	#set new buffer
	RenderingServer.multimesh_set_buffer(created_high_LOD_multimesh, packedArr);

	var commandBuffer = RenderingServer.multimesh_get_command_buffer_rd_rid(created_high_LOD_multimesh);

	return commandBuffer
	
func _execute_compute_test()->void:
	compute_active = true
	
	#this would be where we pass player transform through or updated textures
	var foundBuffer = RenderingServer.multimesh_get_buffer(created_high_LOD_multimesh);

	print("process test: " , foundBuffer)	

	rd = RenderingServer.get_rendering_device()

	var compute_list = rd.compute_list_begin()
	
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_RID)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_RID, 0)
	
	rd.compute_list_dispatch(compute_list,1,1,1)
	rd.compute_list_end()

	compute_active = false
