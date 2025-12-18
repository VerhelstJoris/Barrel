class_name PlayerEquipmentThrowable extends  PlayerEquipment

func _on_start_unholster():
	super()
	print("throwable unholster")
	player.arms.arms_animation_bus.throwable_unholstered = true

func _on_start_holster():
	super()
	print("throwable holster")
	player.arms.arms_animation_bus.throwable_unholstered = false
	
func _can_be_holstered() -> bool:
	return false