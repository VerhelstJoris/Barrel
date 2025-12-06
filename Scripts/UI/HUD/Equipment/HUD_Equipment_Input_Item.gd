
class_name HUDEquipmentInputItem extends Control

@export var input_label: Label 

@export var prompt : HUDPrompt

@export var input_text: String = "lorem ipsum":
	set(new_value):
		input_text = new_value
		if(input_label):	
			input_label.text = input_text

@export var input_action : String:
	set(new_value):
		input_action = new_value
		if(prompt):
			prompt.current_input_action_to_display = input_action
	
func _ready() -> void:
	if(input_label):
		input_label.text = input_text
	if(prompt):
		prompt.current_input_action_to_display = input_action