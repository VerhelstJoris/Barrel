@icon("res://DEBUG/Icons/Ico_Interact.png")
class_name InteractorComponent extends Node

@export var interact_ray : RayCast3D

@export var interactable_prompt : HUDInteractablePrompt
@export var equipment_manager : EquipmentManager

var interact_cast_result : Dictionary

var current_hovered_object : Object = null
var current_hovered_interactable : InteractableComponent = null

signal on_interact_input_received(event : InputEvent)

func _ready() -> void:
	if(!interact_ray):
		push_error("Interact Raycast not set on ", self.name, ", on ", owner)
	if(!interactable_prompt):
		push_error("No prompt set on " , self.name , " on " , owner)
	else:
		interactable_prompt._init_with_data(null)
	if(!equipment_manager):
		push_error("No equipment manager set on " , self.name , " on " , owner)
	
	on_interact_input_received.connect(_on_interact_input_received)


func _physics_process(_delta: float) -> void:
	_find_current_hovered_object()
	#_check_for_display_promt()
	if(_can_currently_interact_with_hovered()):
		interactable_prompt._init_with_data(current_hovered_interactable)
	else:
		interactable_prompt._init_with_data(null)

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
	
func _try_set_current_interactable(_interactable_component: InteractableComponent)-> void:
	current_hovered_interactable = _interactable_component

func _try_clear_current_interactable(_interactable_component: InteractableComponent) -> void:
	if(current_hovered_interactable == _interactable_component):
		current_hovered_interactable = null
		interactable_prompt._init_with_data(null)

func _on_interact_input_received(_event : InputEvent) -> void:
	print("try interact")
		
func _can_currently_interact_with_hovered() -> bool:
	if(current_hovered_interactable == null):
		return false
	
	match current_hovered_interactable.interact_data.type:
		InteractableDataAsset.InteractionType.Pickup:
			#is left hand slot free?
			return equipment_manager._is_equipment_slot_available(EquipmentManager.Equipment_Slot.Left)
		_:
			pass

	return true	

