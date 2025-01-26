class_name PlayerEquipmentPistol extends "PlayerEquipment.gd"

const log_pistol : String = "PlayerPistol" 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _try_use_equipment():
	Logging.info("Try Shoot")
