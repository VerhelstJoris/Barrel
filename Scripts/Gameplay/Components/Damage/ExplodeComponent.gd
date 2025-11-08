@icon("res://DEBUG/Icons/Ico_Explode.png")
class_name ExplodeComponent extends Node

@export var hitbox : HitboxComponent

@export var on_explode_effect : GPUParticles3D

func _ready() -> void:
	if(hitbox):
		hitbox.on_shape_hit.connect(_on_owner_health_change)	

		
func _on_owner_health_change(_new_health : float, _old_health : float) -> void:
	if(on_explode_effect):
		print("spawn particle")
	owner.queue_free()
	