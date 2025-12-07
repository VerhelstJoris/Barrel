class_name HUDInteractablePrompt extends Control

@export var description_label : Label
@export var name_label : Label
@export var prompt : HUDPrompt


func _init_with_data(interactable_data_asset: InteractableDataAsset) -> void:
	if(interactable_data_asset == null):
		_clear_current()
		return

	name_label.text = interactable_data_asset.interactable_display_name
	description_label.text = interactable_data_asset.interaction_description
	prompt.current_input_action_to_display = interactable_data_asset.interaction_input.input_string
	visible = true	
		
func _clear_current() -> void:
	visible = false
