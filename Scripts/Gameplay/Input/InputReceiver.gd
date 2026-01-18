@icon("res://DEBUG/Icons/Ico_Keyboard.png")
class_name InputReceiver extends Node

@export_group("Input Map")
const default_mapping_context_name : String = "Default"
@export var input_contexts : Dictionary[String , InputActionMappingContext]
@export var current_input_context : String = default_mapping_context_name

signal on_available_equipment_actions_changed
signal on_available_equipment_actions_cleared

func _ready() -> void:
	if(input_contexts.is_empty()):
		push_error("No Input Mapping Contexts defined on " , name , " on " , owner.name)
		return
		
	if(!input_contexts.has(current_input_context)):
		push_error("No Input Mapping Contexts with name " , current_input_context , " defined on " , owner.name)


func _get_available_inputs() -> Dictionary[InputActionInfo, ExposedSignalConnector]:
	if(current_input_context != null):
		return input_contexts[current_input_context].input_dictionary

	return {}

func _get_description_for_input(action_to_find: InputActionInfo) -> HUDInputInfo:
	if(input_contexts[current_input_context].description_dictionary.has(action_to_find)):
		return (input_contexts[current_input_context].description_dictionary[action_to_find])
	
	push_error("description not found for input : " , action_to_find.get_name() , " on ", self.name)	
	return null
	
func _enable_current_HUD_actions(equipment : PlayerEquipment, new_val : bool) -> void:
	if(new_val):
		_change_HUD_available_actions(input_contexts[current_input_context].input_dictionary.keys(), equipment)
	else:	
		_change_HUD_available_actions([], equipment)
	

func _change_current_input_mapping_context(new_name : String , equipment : PlayerEquipment, update_hud : bool = true ) -> void:
	if(input_contexts.is_empty()):
		push_error("No Input Mapping Contexts defined on " , name , " on " , owner.name)
		return

	if(!input_contexts.has(new_name)):
		push_error("No Input Mapping Contexts with name " , new_name , " defined on " , owner.name)
		return
	
	current_input_context = new_name
	if(update_hud):
		_change_HUD_available_actions(input_contexts[current_input_context].input_dictionary.keys(), equipment)
	
func _change_HUD_available_actions(new_available: Array[InputActionInfo], equipment : PlayerEquipment) -> void:
	if(new_available.is_empty()):
		on_available_equipment_actions_cleared.emit(equipment.slot)
		return
		
	var new_description_data : Dictionary[InputActionInfo, HUDInputInfo]
	
	for id in new_available.size():
		new_description_data[new_available[id]] = _get_description_for_input(new_available[id])

	on_available_equipment_actions_changed.emit(new_description_data, equipment.slot)
			
