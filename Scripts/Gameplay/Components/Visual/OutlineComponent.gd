class_name OutlineComponent extends  Node

@export var meshes : Array[MeshInstance3D]

@export var outline_mat : Material

@export var enabled : bool = true:
	set(new):
		enabled = new
		_sync_outline_settings()
	
@export var outline_width : float = 1.0

@export var outline_color : Color

const width_shader_param : String = "outline_width"
const colour_shader_param : String = "outline_colour"

func _ready() -> void:
	if(!outline_mat):
		push_error("No outline material assigned on ", self.name, ", on ", owner)

	_add_material_overlay_to_meshes()
	_sync_outline_settings()

func _sync_outline_settings() -> void:
	var width_to_set : float = 0
	if(enabled):
		width_to_set = outline_width
		
	_set_outline_width(width_to_set)
	_set_outline_colour(outline_color)

func _add_material_overlay_to_meshes() -> void:
	for mesh in meshes:
		if mesh && mesh.get_material_overlay() != outline_mat:
			mesh.set_material_overlay(outline_mat)

func _set_outline_width(width : float) -> void:
	for mesh in meshes:
		if(mesh):
			mesh.set_instance_shader_parameter(width_shader_param,width)
			
func _set_outline_colour(colour : Color) -> void:
	for mesh in meshes:
		if(mesh):
			mesh.set_instance_shader_parameter(colour_shader_param,colour)