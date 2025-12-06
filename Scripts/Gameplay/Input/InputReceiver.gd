@icon("res://DEBUG/Icons/Ico_Keyboard.png")
class_name InputReceiver extends Node

@export_group("Input Map")
@export var input_dictionary : Dictionary[InputActionInfo, ExposedSignalConnector]

@export var description_dictionary : Dictionary[InputActionInfo, String] 

signal on_available_equipment_actions_changed
signal on_available_equipment_actions_cleared

func _get_available_inputs() -> Dictionary[InputActionInfo, ExposedSignalConnector]:
	return input_dictionary

func _get_description_for_input(action_to_find: InputActionInfo) -> String:
	if(description_dictionary.has(action_to_find)):
		return description_dictionary[action_to_find]
	
	push_error("description key not found for input : " , action_to_find.name , " on ", self.name)	
	return "DESC_STRING_NOT_FOUND"
	
func _change_HUD_available_actions(new_available: Array[InputActionInfo]) -> void:
	if(new_available.is_empty()):
		on_available_equipment_actions_cleared.emit()
		return
		
	var new_description_data : Dictionary[InputActionInfo, String]
	
	for id in new_available.size():
		new_description_data[new_available[id]] = _get_description_for_input(new_available[id])

	on_available_equipment_actions_changed.emit(new_description_data)
