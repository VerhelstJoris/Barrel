class_name PlayerEquipment extends Node


enum Equipment_Type {Permanent , Consumable, Temporary}
enum Equipment_Hold {MainHand, OffHand, Both}

@export_group("Equipment Details")
@export var equip_type : Equipment_Type = Equipment_Type.Permanent
@export var hold_type : Equipment_Hold = Equipment_Hold.MainHand

@export_group("Equipment Input Details")
@export var use_input : EquipmentInputInfo
@export var secondary_use_input : EquipmentInputInfo

@onready var anim_tree : AnimationTree = %AnimationTree

signal on_equipped()
signal on_unequipped()

signal on_available_equipment_actions_changed
signal on_available_equipment_actions_cleared

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(use_input.input_string):
		_try_use_equipment()
	elif event.is_action_pressed(secondary_use_input.input_string):
		_try_use_equipment_secondary()
	
func _on_equipped():
	on_equipped.emit()
	
func _on_unequipped():
	on_unequipped.emit()

func _try_use_equipment():
	# not implemented in base class
	pass	
	
func _try_use_equipment_secondary():
	# not implemented in base class
	pass
