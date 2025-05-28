class_name ColtBullet extends Node

@onready var projectile_object : Node3D = %Projectile
@onready var jacket_object : MeshInstance3D = %Jacket

@export_group("Bullet Materials")
@export var primer_default_material : Material
@export var primer_fired_material : Material

enum E_bullet_state{Ready, Fired}

var current_state : E_bullet_state = E_bullet_state.Ready

const primer_material_id : int = 1


func _ready() -> void:
	current_state = E_bullet_state.Ready
	jacket_object.set_surface_override_material(primer_material_id,primer_default_material)

func _can_be_fired() -> bool:
	return current_state == E_bullet_state.Ready

func _on_fired() -> void:
	current_state = E_bullet_state.Fired
	projectile_object.set_visible(false)
	jacket_object.set_surface_override_material(primer_material_id,primer_fired_material)
	pass
	