
class_name HUDEquipmentInputItem extends Control

@export var input_label: Label 
@export var action_prompt: ActionPrompt
@export var backup_label: Label

@export var input_text: String = "lorem ipsum":
	set(new_value):
		input_text = new_value
		if(input_label):	
			input_label.text = input_text

@export var input_action : String:
	set(new_value):
		input_action = new_value
		action_prompt._set_action(input_action)
		backup_label.visible = false
		
		
		if(action_prompt.texture == null):
			_set_backup_for_keyboard_action()
			
	
func _ready() -> void:
	if(input_label):
		input_label.text = input_text
	if(action_prompt):	
		action_prompt._set_action(input_action)
	
func _set_backup_for_keyboard_action() -> void:
	for ev in InputMap.action_get_events(input_action):
		if(ev is InputEventKey):
			var input_key : InputEventKey = ev as InputEventKey
			if(backup_label):
				backup_label.text =  OS.get_keycode_string(input_key.physical_keycode)
				backup_label.visible = true
			if(action_prompt):	
				action_prompt.texture = PromptManager.get_keyboard_textures().fallback
			return	#quit out early
