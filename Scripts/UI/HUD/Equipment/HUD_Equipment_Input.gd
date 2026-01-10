class_name HUDEquipmentInput extends Control


@export var input_item_scene: PackedScene

@export var input_item_container: BoxContainer
@export var screen_alignment_container: Container
@export var equipment_slot_to_track : EquipmentManager.EEquipmentSlot = EquipmentManager.EEquipmentSlot.Right


var current_inputs : Dictionary[HUDInputInfo, HUDEquipmentInputItem]
var current_descriptions : Array[String]

@export var animate_speed : float = 0.3

var equipment_manager : EquipmentManager = null

func _ready() -> void:
	_clear_current_input_details_internal(equipment_slot_to_track)
	
func _intialize(player : Player) -> void:
	equipment_manager = player.equipment_manager

func _clear_current_input_details_internal(slot : EquipmentManager.EEquipmentSlot) -> void:
	if(slot != equipment_slot_to_track):
		return
	
	match slot:
		EquipmentManager.EEquipmentSlot.Right:
			set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_CENTER_RIGHT, Control.LayoutPresetMode.PRESET_MODE_KEEP_SIZE, 0)
			screen_alignment_container.set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_CENTER_RIGHT, Control.LayoutPresetMode.PRESET_MODE_KEEP_SIZE, 0)
		EquipmentManager.EEquipmentSlot.Left:
			set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_CENTER_LEFT, Control.LayoutPresetMode.PRESET_MODE_KEEP_SIZE, 0)
			screen_alignment_container.set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_CENTER_LEFT, Control.LayoutPresetMode.PRESET_MODE_KEEP_SIZE, 0)
		_:
			pass
	

	for child in input_item_container.get_children():
		input_item_container.remove_child(child)
		child.queue_free()
	current_inputs.clear()
	current_descriptions.clear()
		
func _create_new_item(info: InputActionInfo, description : HUDInputInfo) -> HUDEquipmentInputItem:
	var new_item: HUDEquipmentInputItem = input_item_scene.instantiate()
	input_item_container.add_child(new_item)
	new_item._set_slot_visual_data(equipment_slot_to_track)
	new_item.input_text = description.display_string
	new_item.input_action = info.input_string
	new_item.currently_available = true

	return new_item
	
func _on_equipment_input_actions_changed(new_inputs : Dictionary[InputActionInfo, HUDInputInfo], slot : EquipmentManager.EEquipmentSlot) -> void:
	if(slot != equipment_slot_to_track):
		return

	if(new_inputs.is_empty()):
		_on_equipment_input_actions_cleared(slot)
		return

	_clear_current_input_details_internal(slot)
	for info in new_inputs:
		var input_info : HUDInputInfo = new_inputs[info]
		if(!current_descriptions.has(input_info.display_string)):
			current_inputs[input_info] = _create_new_item(info, input_info)
			current_descriptions.push_back(input_info.display_string)

	input_item_container.notification(NOTIFICATION_RESIZED)

	var viewport_x_size : float = get_viewport().get_visible_rect().size.x

	match slot:
		EquipmentManager.EEquipmentSlot.Right:
			UIAnimation.animate_slide_from_right(self, viewport_x_size, animate_speed, Tween.EASE_OUT, Tween.TRANS_CUBIC)
		EquipmentManager.EEquipmentSlot.Left:
			UIAnimation.animate_slide_from_left(self, viewport_x_size, animate_speed, Tween.EASE_OUT, Tween.TRANS_CUBIC)
		_:
			pass

func _process(_delta: float) -> void:
	if(!equipment_manager):
		return

	if(current_inputs.is_empty()):
		return
		
	for input_info in current_inputs.keys():
		if(input_info.two_handed):
			current_inputs[input_info].currently_available = equipment_manager._can_enter_two_handed_action(equipment_slot_to_track)
			

func _on_equipment_input_actions_cleared(slot : EquipmentManager.EEquipmentSlot) -> void:
	if(slot != equipment_slot_to_track):
		return
		
	var viewport_x_size : float  = get_viewport().get_visible_rect().size.x	
	match slot:
		EquipmentManager.EEquipmentSlot.Right:
			UIAnimation.animate_slide_to_right(self, viewport_x_size, animate_speed, Tween.EASE_IN, Tween.TRANS_CUBIC)
		EquipmentManager.EEquipmentSlot.Left:
			UIAnimation.animate_slide_to_left(self,viewport_x_size, animate_speed, Tween.EASE_IN, Tween.TRANS_CUBIC)
			pass
		_:
			pass

