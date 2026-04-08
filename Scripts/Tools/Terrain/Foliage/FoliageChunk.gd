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


var current_lod : EFoliageLOD = EFoliageLOD.NONE

func _ready() -> void:
	if(foliage_multimesh == null):
		push_error("No Valid multimesh assigned on Foliage Chunk : ", owner.name)
		return
		
	set_process(true)	
		

func _process(_delta: float) -> void:
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

	#var start_to_mid = smoothstep(impostor_fade_in_start, impostor_fade_in_end, camera_distance)
	#var mid_to_end = smoothstep(grass_fade_out_start, grass_fade_out_end, camera_distance)
#
	#$Grass.visible = mid_to_end < 1.0
	#$Impostor.visible = start_to_mid >= 0.0
#
	## Interpolate
	#$Impostor.set_instance_shader_parameter("alpha", start_to_mid)
	#$Grass.set_instance_shader_parameter("alpha", 1.0 - mid_to_end)
		
func _change_LOD(new_lod : EFoliageLOD) -> void:
	if(current_lod == new_lod):
		return
	
	current_lod = new_lod
	
	match new_lod:
		EFoliageLOD.LOW:
			print("change lod to low")
			foliage_multimesh.multimesh.mesh = low_LOD_mesh
		EFoliageLOD.HIGH:
			print("change lod to high")
			foliage_multimesh.multimesh.mesh = high_LOD_mesh
		EFoliageLOD.TEX:
			pass
		EFoliageLOD.NONE:
			pass		
		
