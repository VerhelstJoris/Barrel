class_name HUDEquipmentInput extends Control


@export var input_item_scene: PackedScene

@onready var input_item_container: BoxContainer = %VBoxContainer
@export var equipment_slot_to_track : EquipmentManager.Equipment_Slot = EquipmentManager.Equipment_Slot.Right


var current_inputs : Array[String]

var animate_speed : float = 0.3

func _ready() -> void:
	_clear_current_input_details_internal(equipment_slot_to_track)
	
func _clear_current_input_details_internal(slot : EquipmentManager.Equipment_Slot) -> void:
	if(slot != equipment_slot_to_track):
		return
		
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
	
func _on_equipment_input_actions_changed(new_inputs : Dictionary[InputActionInfo, String], slot : EquipmentManager.Equipment_Slot) -> void:
	if(slot != equipment_slot_to_track):
		return

	if(new_inputs.is_empty()):
		_on_equipment_input_actions_cleared(slot)
		return

	_clear_current_input_details_internal(slot)
	for info in new_inputs:
		var string_desc : String = new_inputs[info]
		if(!current_inputs.has(string_desc)):
			_create_new_item(info, string_desc)
			current_inputs.push_back(string_desc)
		
	UIAnimation.animate_slide_from_right(self, 5.0, animate_speed, Tween.EASE_OUT, Tween.TRANS_CUBIC)

func _on_equipment_input_actions_cleared(slot : EquipmentManager.Equipment_Slot) -> void:
	if(slot != equipment_slot_to_track):
		return
		
	UIAnimation.animate_slide_to_right(self, animate_speed, Tween.EASE_IN, Tween.TRANS_CUBIC)
