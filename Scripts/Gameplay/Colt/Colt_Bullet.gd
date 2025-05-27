class_name ColtBullet extends Node

@onready var projectile_object : Node3D = %Projectile
@onready var jacket_object : MeshInstance3D = %Jacket

@export_group("Bullet Materials")
@export var primer_default_material : Material
@export var primer_fired_material : Material

const primer_material_id : int = 1

func _ready() -> void:
	jacket_object.set_surface_override_material(primer_material_id,primer_default_material)

func _on_fired() -> void:
	projectile_object.set_visible(false)
	jacket_object.set_surface_override_material(primer_material_id,primer_fired_material)
	pass
	