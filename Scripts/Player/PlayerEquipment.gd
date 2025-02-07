extends Node


enum Equipment_Type {Permanent , Consumable, Temporary}
enum Equipment_Hold {MainHand, OffHand, Both}

@export_group("Equipment Details")
@export var equip_type : Equipment_Type = Equipment_Type.Permanent
@export var hold_type : Equipment_Hold = Equipment_Hold.MainHand

@export_group("Equipment Input Details")
@export var USE_EQUIPMENT: String = "equipment_main_use"
@export var USE_EQUIPMENT_SECONDARY: String = "equipment_secondary_use"

@onready var anim_tree : AnimationTree = %AnimationTree

func _physics_process(_delta: float):
	if Input.is_action_just_pressed(USE_EQUIPMENT):
		_try_use_equipment()
	if Input.is_action_just_pressed(USE_EQUIPMENT_SECONDARY):
		_try_use_equipment_secondary()

func _try_use_equipment():
	# not implemented in base class
	pass	
	
func _try_use_equipment_secondary():
	# not implemented in base class
	pass
