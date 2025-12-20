class_name HUDPrompt extends Node

@export var action_prompt: ActionPrompt
@export var backup_label: Label

var unavailable_tween : Tween
@export var unvailable_lerp_time : float = 0.1
@export var unavailable_color : Color

var currently_available: bool = true:
	set = _change_availability

@export var current_input_action_to_display : String:
	set (new):
		action_prompt._set_action(new)
		backup_label.visible = false
		
		if(action_prompt.texture == null):
			push_error("failed to retrieve action for input string ", new)
			_set_backup_for_keyboard_action()

func _ready() -> void:
	if(action_prompt && !current_input_action_to_display.is_empty()):
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

func _change_availability(available : bool)	-> void:
	if(available == currently_available):
		return
		
	if(unavailable_tween && unavailable_tween.is_running()):
		unavailable_tween.stop()

	unavailable_tween = create_tween()
	var color : Color = Color.WHITE
	if(!available):
		color = unavailable_color

	unavailable_tween.tween_property(action_prompt, 'modulate' , color, unvailable_lerp_time)

	currently_available = available