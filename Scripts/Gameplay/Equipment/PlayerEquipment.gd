class_name PlayerEquipment extends Node3D


enum Equipment_Type {Permanent , Consumable, Temporary}

@export_group("Equipment Details")
@export var equip_type : Equipment_Type = Equipment_Type.Permanent
@export var slot : EquipmentManager.Equipment_Slot = EquipmentManager.Equipment_Slot.Right

@onready var anim_tree : AnimationTree = %AnimationTree
@export var input_receiver : InputReceiver

var player : Player = null

signal on_equipped
signal on_unequipped

signal on_holstered
signal on_unholstered

signal use_equipment_input(event: InputEvent)

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
	on_unequipped.emit()
	
func _try_use_equipment(_event : InputEvent):
	# not implemented in base class
	pass	
	
func _try_use_equipment_secondary():
	# not implemented in base class
	pass
	
func _can_be_holstered() -> bool:
	return true
	