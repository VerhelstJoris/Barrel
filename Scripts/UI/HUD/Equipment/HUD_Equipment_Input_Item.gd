
class_name HUDEquipmentInputItem extends Control

@export var input_label: Label 

@export var hbox_container : Container
@export var prompt : HUDPrompt
@export var text_container : Container

@export var unavailable_text_color : Color

var available_color : Color

@export var currently_available: bool = true:
	set = _change_availability

@export var input_text: String = "lorem ipsum":
	set(new_value):
		input_text = new_value
		if(input_label):	
			input_label.text = input_text

const font_color_property_name : String = "theme_override_colors/font_color"

var equipment_slot :EquipmentManager.Equipment_Slot = EquipmentManager.Equipment_Slot.Right

@export var input_action : String:
	set(new_value):
		input_action = new_value
		if(prompt):
			prompt.current_input_action_to_display = input_action
	
func _ready() -> void:
	if(input_label):
		input_label.text = input_text
		available_color = input_label[font_color_property_name]
	if(prompt):
		prompt.current_input_action_to_display = input_action
		prompt.currently_available = currently_available
		
func _set_slot_visual_data(slot: EquipmentManager.Equipment_Slot) -> void:
	match slot:
		EquipmentManager.Equipment_Slot.Right:
			hbox_container.move_child(prompt,text_container.get_index() +1)
		
			set_h_size_flags(Control.GROW_DIRECTION_END)
		
			input_label.set_horizontal_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT)
			set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_CENTER_RIGHT, Control.LayoutPresetMode.PRESET_MODE_KEEP_SIZE, 0)
		EquipmentManager.Equipment_Slot.Left:
			hbox_container.move_child(text_container,prompt.get_index())

			set_h_size_flags(Control.GROW_DIRECTION_BEGIN)
	
			input_label.set_horizontal_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
			set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_CENTER_LEFT, Control.LayoutPresetMode.PRESET_MODE_KEEP_SIZE, 0)
		_:
			pass
			
func _change_availability(available : bool)	-> void:
	if(available):
		if(input_label):
			input_label[font_color_property_name] =  available_color
	else:
		if(input_label):
			input_label[font_color_property_name] = unavailable_text_color

	if(prompt):
		prompt.currently_available = available
	currently_available = available			