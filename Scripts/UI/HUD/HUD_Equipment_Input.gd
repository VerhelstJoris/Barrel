class_name HUDEquipmentInput extends Control


@export var input_item_scene: PackedScene

@onready var input_item_container: BoxContainer = %VBoxContainer


func _ready() -> void:
	for child in input_item_container.get_children():
		input_item_container.remove_child(child)
		
	#var new_item: HUDEquipmentInputItem = input_item_scene.instantiate()
	#new_item._set_label_text("peepee poopoo")
	#input_item_container.add_child(new_item)
	#input_item_container.resized.emit()
		
