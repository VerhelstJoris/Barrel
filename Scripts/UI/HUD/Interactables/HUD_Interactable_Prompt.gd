class_name HUDInteractablePrompt extends Control

@export var description_label : Label
@export var name_label : Label
@export var prompt : HUDPrompt

var current_interactable : InteractableComponent = null

func _init_with_data(interactable: InteractableComponent) -> void:
	if(interactable == null):
		_clear_current()
		current_interactable = null
		return
		
	if(interactable == current_interactable):
		return
	
	current_interactable = interactable	
		
	if(current_interactable.interact_data == null):
		_clear_current()
		return

	name_label.text = current_interactable.interact_data.interactable_display_name
	description_label.text = current_interactable.interact_data.interaction_description
	prompt.current_input_action_to_display = current_interactable.interact_data.interaction_input.input_string
	visible = true	
		
func _clear_current() -> void:
	visible = false
	