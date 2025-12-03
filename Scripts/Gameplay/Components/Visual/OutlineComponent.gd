class_name OutlineComponent extends  Node

@export var meshes : Array[MeshInstance3D]

@export var outline_mat : Material

@export var enabled : bool = true:
	set(new):
		enabled = new
		_sync_outline_settings()

func _ready() -> void:
	if(!outline_mat):
		push_error("No outline material assigned on ", self.name, ", on ", owner)
		return
		
	_sync_outline_settings()

func _sync_outline_settings() -> void:
	if(enabled):
		_add_material_overlay_to_meshes()
	else:
		_clear_outline_overlay_material_from_meshes()
	
func _add_material_overlay_to_meshes() -> void:
	for mesh in meshes:
		if mesh && mesh.get_material_overlay() != outline_mat:
			mesh.set_material_overlay(outline_mat)

func _clear_outline_overlay_material_from_meshes() -> void:			
	for mesh in meshes:
		if mesh && mesh.get_material_overlay() == outline_mat:
			mesh.set_material_overlay(null)
