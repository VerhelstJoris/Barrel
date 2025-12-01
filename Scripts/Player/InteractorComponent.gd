@icon("res://DEBUG/Icons/Ico_Interact.png")
class_name InteractorComponent extends Node

@export var interact_ray : RayCast3D

var interact_cast_result : Dictionary

var current_hovered_object : Object = null

func _ready() -> void:
	if(!interact_ray):
		push_error("Interact Raycast not set on ", self.name, ", on ", owner)

func _physics_process(_delta: float) -> void:
	_find_current_hovered_object()
	
func _can_currently_interact() -> bool:
	return true
	
func _can_current_hover_over_interactables() -> bool:
	return true

func _find_current_hovered_object() -> void:
	var new_object : Object= interact_ray.get_collider()
	if(current_hovered_object == new_object):
		return
		
	#unhover over the current object first
	if(current_hovered_object && current_hovered_object.has_user_signal(InteractableComponent.hover_end_signal_name)):
		current_hovered_object.emit_signal(InteractableComponent.hover_end_signal_name, self)
		
	#now start hovering over the new one
	current_hovered_object = new_object
	
	if(new_object):
		if(current_hovered_object.has_user_signal(InteractableComponent.hover_start_signal_name)):
			current_hovered_object.emit_signal(InteractableComponent.hover_start_signal_name, self)
			
func _attempt_interact() -> void:
	pass
	