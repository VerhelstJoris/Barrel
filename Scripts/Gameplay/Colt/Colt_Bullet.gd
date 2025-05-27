class_name ColtBullet extends Node

@onready var projectile_object : Node3D = %Projectile

@export_group("Bullet Materials")
@export var primer_default_material : Material
@export var primer_fired_material : Material

func _ready() -> void:
	pass
	
func _physics_process(delta: float) -> void:
	pass	
	
func _on_fired() -> void:
	projectile_object.set_visible(false)
	pass
	