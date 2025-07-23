class_name ColtFireVFX extends Node3D

@export var barrel_muzzle_initial_vfx : Array[Node3D]
@export var barrel_muzzle_main_vfx : Array[Node3D]
@export var cylinder_fire_vfx : Array[Node3D]


func _toggle_initial_fire_vfx(new_value : bool) -> void:
	#if(barrel_muzzle_flash_light):
	#	barrel_muzzle_flash_light.visible = _visible
	for vfx_node in barrel_muzzle_initial_vfx:
		vfx_node.visible = new_value
	
	
func _toggle_main_fire_vfx(new_value : bool) -> void:
	for vfx_node in barrel_muzzle_main_vfx:
		vfx_node.visible = new_value
	
	
func _toggle_cylinder_fire_vfx(new_value : bool) -> void:
	for vfx_node in cylinder_fire_vfx:
		vfx_node.visible = new_value

