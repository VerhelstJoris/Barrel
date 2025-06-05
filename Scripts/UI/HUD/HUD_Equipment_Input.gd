class_name HUDEquipmentInput extends Control


@export var input_item_scene: PackedScene

@onready var input_item_container: BoxContainer = %VBoxContainer

var animate_speed : float = 0.3

func _ready() -> void:
	_clear_current_input_details()
	
func _clear_current_input_details() -> void:
	for child in input_item_container.get_children():
		input_item_container.remove_child(child)

func _create_new_item(info: EquipmentInputInfo):
	var new_item: HUDEquipmentInputItem = input_item_scene.instantiate()
	input_item_container.add_child(new_item)
	new_item.input_text = info.description_string
	new_item.input_action = info.input_string

	input_item_container.notification(NOTIFICATION_RESIZED)
	
func _on_equipment_input_actions_changed(new_inputs : Array[EquipmentInputInfo]) -> void:

	_clear_current_input_details()
	for info in new_inputs:
		_create_new_item(info)
		UIAnimation.animate_slide_from_right(self, 5.0, animate_speed, Tween.EASE_OUT, Tween.TRANS_CUBIC)
		

func _on_equipment_input_actions_cleared() -> void:
	UIAnimation.animate_slide_to_right(self, animate_speed, Tween.EASE_IN, Tween.TRANS_CUBIC)
