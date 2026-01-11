@icon("res://DEBUG/Icons/Ico_Hand.png")
class_name PlayerEquipment extends Node


@export_group("Equipment Details")
@export var equip_type : EquipmentManager.EEquipmentType = EquipmentManager.EEquipmentType.Permanent
@export var slot : EquipmentManager.EEquipmentSlot = EquipmentManager.EEquipmentSlot.Right

@export var input_receiver : InputReceiver

var player : Player = null

signal on_equipped
signal on_unequipped

signal on_holstered
signal on_unholstered

signal use_equipment_input(event: InputEvent)

const equipment_node_name : String = "Node_Equipment"

func _enter_tree() -> void:
	NodeUtils._add_node_meta_to_owner(equipment_node_name, self, self)

func _ready() -> void:
	use_equipment_input.connect(_try_use_equipment)
	
func _on_start_holster():
	on_holstered.emit()

func _on_start_unholster():
	on_unholstered.emit()

func _on_equipped(in_player : Player):
	player = in_player
	on_equipped.emit()
	
func _on_unequipped():
	player = null
	on_unequipped.emit()
	
func _try_use_equipment(_event : InputEvent):
	# not implemented in base class
	pass
	
	
func _can_be_holstered() -> bool:
	return true

func _is_right_handed() -> bool:
	return slot == EquipmentManager.EEquipmentSlot.Right
	
func _is_currently_using_both_hands() -> bool:
	return false