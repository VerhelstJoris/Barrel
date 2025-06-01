class_name HUDEquipmentInput extends Control


@export var input_item_scene: PackedScene

@onready var input_item_container: BoxContainer = %VBoxContainer


func _ready() -> void:
	_clear_current_input_details()
		
	_create_new_item("peepee")
	_create_new_item("poopoo")
	#input_item_container.set_size(input_item_container.get_minimum_size())
	
func _clear_current_input_details() -> void:
	for child in input_item_container.get_children():
		input_item_container.remove_child(child)

func _create_new_item(label_text : String):
	var new_item: HUDEquipmentInputItem = input_item_scene.instantiate()
	input_item_container.add_child(new_item)
	new_item.input_text = label_text

	input_item_container.notification(NOTIFICATION_RESIZED)
	
func _on_equipment_input_actions_changed(new_inputs : Array[EquipmentInputInfo]) -> void:
	_clear_current_input_details()
	for info in new_inputs:
		_create_new_item(info.description_string)
