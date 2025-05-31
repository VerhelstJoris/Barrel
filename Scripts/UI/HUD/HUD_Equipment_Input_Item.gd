class_name HUDEquipmentInputItem extends Control

@onready var input_label: Label = %InputTextLabel

@export var input_text: String = "lorem ipsum"

func _ready() -> void:
	input_label.text = input_text
	
func _set_label_text(new_label : String) -> void:
	input_text = new_label
	input_label.text = new_label
