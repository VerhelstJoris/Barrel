@icon("res://DEBUG/Icons/Ico_Keyboard.png")
class_name InputReceiver extends Node

@export_group("Input Map")
@export var input_dictionary : Dictionary[InputActionInfo, ExposedSignalConnector]

signal on_available_equipment_actions_changed
signal on_available_equipment_actions_cleared

func _get_available_inputs() -> Dictionary[InputActionInfo, ExposedSignalConnector]:
	return input_dictionary