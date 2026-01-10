class_name ColtBullet extends Node

@onready var projectile_object : Node3D = %Projectile
@onready var jacket_object : MeshInstance3D = %Jacket

@export_group("Bullet Materials")
@export var primer_default_material : Material
@export var primer_fired_material : Material

enum EBulletState{Ready, Fired}

var current_state : EBulletState = EBulletState.Ready

const primer_material_id : int = 1


func _ready() -> void:
	current_state = EBulletState.Ready
	jacket_object.set_surface_override_material(primer_material_id,primer_default_material)

func _can_be_fired() -> bool:
	return current_state == EBulletState.Ready

func _on_fired() -> void:
	current_state = EBulletState.Fired
	projectile_object.set_visible(false)
	jacket_object.set_surface_override_material(primer_material_id,primer_fired_material)
	pass
	