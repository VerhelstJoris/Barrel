class_name PlayerEquipmentThrowable extends  PlayerEquipment

func _on_start_unholster():
	super()
	print("throwable unholster")
	player.arms.arms_animation_bus.throwable_unholstered = true
	if(input_receiver):
		input_receiver._change_HUD_available_actions(input_receiver.input_dictionary.keys(), slot)
		
func _on_start_holster():
	super()
	print("throwable holster")
	player.arms.arms_animation_bus.throwable_unholstered = false
	
func _can_be_holstered() -> bool:
	return false
	
func _try_use_equipment(_event : InputEvent) -> void:
	print("Try Use throwable")
		