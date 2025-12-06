class_name HUDEquipmentInput extends Control


@export var input_item_scene: PackedScene

@onready var input_item_container: BoxContainer = %VBoxContainer

var current_inputs : Array[String]

var animate_speed : float = 0.3

func _ready() -> void:
	_clear_current_input_details()
	
func _clear_current_input_details() -> void:
	for child in input_item_container.get_children():
		input_item_container.remove_child(child)
		child.queue_free()
	current_inputs.clear()
		
func _create_new_item(info: InputActionInfo, description : String):
	var new_item: HUDEquipmentInputItem = input_item_scene.instantiate()
	input_item_container.add_child(new_item)
	new_item.input_text = description
	new_item.input_action = info.input_string

	input_item_container.notification(NOTIFICATION_RESIZED)
	
func _on_equipment_input_actions_changed(new_inputs : Dictionary[InputActionInfo, String]) -> void:
	_clear_current_input_details()
	for info in new_inputs:
		var string_desc : String = new_inputs[info]
		if(!current_inputs.has(string_desc)):
			_create_new_item(info, string_desc)
			current_inputs.push_back(string_desc)
		
	UIAnimation.animate_slide_from_right(self, 5.0, animate_speed, Tween.EASE_OUT, Tween.TRANS_CUBIC)
		

func _on_equipment_input_actions_cleared() -> void:
	UIAnimation.animate_slide_to_right(self, animate_speed, Tween.EASE_IN, Tween.TRANS_CUBIC)
