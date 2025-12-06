class_name HUDPrompt extends Node

@onready var action_prompt: ActionPrompt = %ActionPrompt
@onready var backup_label: Label = %BackUpLabel

@export var current_input_action_to_display : String:
	set (new):
		action_prompt._set_action(new)
		backup_label.visible = false
		
		if(action_prompt.texture == null):
			_set_backup_for_keyboard_action()

func _ready() -> void:
	if(action_prompt):
		action_prompt._set_action(current_input_action_to_display)

func _set_backup_for_keyboard_action() -> void:
	for ev in InputMap.action_get_events(current_input_action_to_display):
		if(ev is InputEventKey):
			var input_key : InputEventKey = ev as InputEventKey
			if(backup_label):
				backup_label.text =  OS.get_keycode_string(input_key.physical_keycode)
				backup_label.visible = true
			if(action_prompt):
				action_prompt.texture = PromptManager.get_keyboard_textures().fallback
			return	#quit out early
