@icon("res://DEBUG/Icons/Ico_Explode.png")
class_name ExplodeComponent extends Node

@export var damage_comp : DamageComponent

func _ready() -> void:
	if(damage_comp):
		damage_comp.on_health_change.connect(_on_owner_health_change)	

		
func _on_owner_health_change(_new_health : float, _old_health : float) -> void:
	owner.queue_free()