class_name FoliageLODTest extends Node3D


@export var foliage_material_high_LOD :Material
@export var foliage_material_low_LOD :Material

@export var foliage_mesh_high_LOD : Mesh
@export var foliage_mesh_low_LOD : Mesh

@export var switch_dist : float = 12

@export var multimesh : MultiMeshInstance3D

var current_high : bool= true



func _switch_to(mesh: Mesh, material: Material) -> void:
	if(multimesh == null):
		return
		
	multimesh.multimesh.mesh = mesh
	multimesh.material_override = material

func _process(_delta: float) -> void:
	var viewport : Viewport
	if Engine.is_editor_hint():
		viewport = EditorInterface.get_editor_viewport_3d()
	else:
		viewport = get_viewport()

	var cam : Camera3D = viewport.get_camera_3d()
	if cam == null:
		return
	var cam_transform : Transform3D = cam.global_transform
	
	var dist : float = cam_transform.origin.distance_to(get_global_position())
	
	if(current_high):
		if(dist > switch_dist):
			print("SWITCH TO LOW")
			current_high = false
			_switch_to(foliage_mesh_low_LOD, foliage_material_low_LOD)
	else:
		if(dist < switch_dist):
			print("SWITCH TO HIGH")
			current_high = true
			_switch_to(foliage_mesh_high_LOD, foliage_material_high_LOD)
