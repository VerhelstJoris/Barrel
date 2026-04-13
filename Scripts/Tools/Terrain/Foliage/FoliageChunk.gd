@tool
class_name FoliageChunk extends Node3D


enum EFoliageLOD {NONE, TEX, LOW, HIGH}


@export var foliage_multimesh : MultiMeshInstance3D

@export var high_LOD_mesh : Mesh
@export var low_LOD_mesh : Mesh

@export var lod_switch_distance_squared := 100.0
@export var impostor_fade_in_start := 5.0
@export var impostor_fade_in_end := 10.0
@export var grass_fade_out_start := 10.0
@export var grass_fade_out_end := 20.0

@export var height_map_tex : Texture2D

const vertex_move_amount_shader_parameter : String = "vertex_move_amount"

var current_lod : EFoliageLOD = EFoliageLOD.NONE

var rd : RenderingDevice

var shader_RID : RID
var uniform_set_RID : RID
var pipeline_RID : RID
var height_buffer_RID : RID

func _ready() -> void:
	if(foliage_multimesh == null):
		push_error("No Valid multimesh assigned on Foliage Chunk : ", owner.name)
		return
		
	foliage_multimesh.set_instance_shader_parameter(vertex_move_amount_shader_parameter, 1.0)

	set_process(true)	

	RenderingServer.call_on_render_thread(_setup_compute_pipeline)
	

func _process(_delta: float) -> void:
	RenderingServer.call_on_render_thread(_render_process.bind(_delta, rd))
	var camera_pos

	if Engine.is_editor_hint():
		camera_pos = EditorInterface.get_editor_viewport_3d().get_camera_3d().global_position
	else:
		camera_pos = get_viewport().get_camera_3d().global_position

	var camera_distance_squared : float = global_position.distance_squared_to(camera_pos)

	if camera_distance_squared < lod_switch_distance_squared:
		_change_LOD(EFoliageLOD.HIGH)
	else:
		_change_LOD(EFoliageLOD.LOW)
		
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
	rd = RenderingServer.create_local_rendering_device()

	var shader_file := load("res://Materials/Shaders/Environment/compute_grass_positions.glsl")
	shader_RID = rd.shader_create_from_spirv(shader_file.get_spirv())
	
	var	tex_uniform = RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(_init_existing_texture_data(rd))
	
	# Create a uniform to assign the texture to the rendering device
	uniform_set_RID = rd.uniform_set_create([tex_uniform], shader_RID, 0)

	# Create a compute pipeline
	pipeline_RID = rd.compute_pipeline_create(shader_RID)

func _exit_tree() -> void:
	rd.free_rid(shader_RID)
	rd.free_rid(uniform_set_RID)
	rd.free_rid(pipeline_RID)
	rd.free_rid(height_buffer_RID)
	rd.free()
	
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
	heightmap_format.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT + RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	heightmap_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	
	return _rd.texture_create(heightmap_format, RDTextureView.new(), [image.get_data()])



