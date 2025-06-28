class_name InputReceiver extends Node

@export_group("Input Map")
@export var input_dictionary : Dictionary[EquipmentInputInfo, ExposedSignalConnector]

var generated_dictionary : Dictionary[String, ExposedSignalConnector]


func _ready() -> void:
	for key in input_dictionary:
		generated_dictionary.get_or_add(key.input_string, input_dictionary[key])
		
	