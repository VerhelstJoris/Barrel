
class_name HUDEquipmentInputItem extends Control

@onready var input_label: Label = %InputTextLabel
@onready var action_prompt: ActionPrompt = %ActionPrompt

@export var input_text: String = "lorem ipsum":
	set(new_value):
		input_text = new_value
		input_label.text = input_text

@export var input_action : String = "fire":
	set(new_value):
		input_action = new_value
		print("set action", input_action)
		#action_prompt.texture = PromptManager.get_texture_for_input_action(input_action)
		#queue_redraw()
		action_prompt._set_action(input_action)
	
func _ready() -> void:
	input_label.text = input_text
	action_prompt._set_action(input_action)
	
