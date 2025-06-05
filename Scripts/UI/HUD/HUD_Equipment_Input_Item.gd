
class_name HUDEquipmentInputItem extends Control

@onready var input_label: Label = %InputTextLabel
@onready var action_prompt: ActionPrompt = %ActionPrompt
@onready var backup_label: Label = %BackUpLabel

@export var input_text: String = "lorem ipsum":
	set(new_value):
		input_text = new_value
		input_label.text = input_text

@export var input_action : String = "fire":
	set(new_value):
		input_action = new_value
		action_prompt._set_action(input_action)
		backup_label.visible = false
		
		
		if(action_prompt.texture == null):
			_set_backup_for_keyboard_action()
			
	
func _ready() -> void:
	input_label.text = input_text
	action_prompt._set_action(input_action)
	
func _set_backup_for_keyboard_action() -> void:
	for ev in InputMap.action_get_events(input_action):
		if(ev is InputEventKey):
			var input_key : InputEventKey = ev as InputEventKey
			backup_label.text =  OS.get_keycode_string(input_key.physical_keycode)
			backup_label.visible = true
			action_prompt.texture = PromptManager.get_keyboard_textures().fallback
			return	#quit out early
