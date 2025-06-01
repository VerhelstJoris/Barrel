
class_name HUDEquipmentInputItem extends Control

@onready var input_label: Label = %InputTextLabel

@export var input_text: String = "lorem ipsum":
	set(new_value):
		input_text = new_value
		input_label.text = input_text

func _ready() -> void:
	input_label.text = input_text


