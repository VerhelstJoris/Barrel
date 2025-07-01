class_name PlayerEquipment extends Node


enum Equipment_Type {Permanent , Consumable, Temporary}
enum Equipment_Hold {MainHand, OffHand, Both}

@export_group("Equipment Details")
@export var equip_type : Equipment_Type = Equipment_Type.Permanent
@export var hold_type : Equipment_Hold = Equipment_Hold.MainHand

@export_group("Equipment Input Details")
@export var use_input : InputActionInfo
@export var secondary_use_input : InputActionInfo

@onready var anim_tree : AnimationTree = %AnimationTree
@export var input_receiver : InputReceiver

signal on_equipped
signal on_unequipped

signal use_equipment_input(event: InputEvent)

func _ready() -> void:
	use_equipment_input.connect(_try_use_equipment)

func _on_equipped():
	on_equipped.emit()
	pass
	
func _on_unequipped():
	on_unequipped.emit()
	pass
	
func _try_use_equipment(_event : InputEvent):
	# not implemented in base class
	pass	
	
func _try_use_equipment_secondary():
	# not implemented in base class
	pass

	
func _get_available_inputs() -> Array[InputActionInfo]:
	return [use_input, secondary_use_input]