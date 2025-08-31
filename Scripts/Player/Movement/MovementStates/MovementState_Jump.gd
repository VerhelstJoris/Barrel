class_name Jump extends PlayerState

func _on_enter_internal() -> void:
	super()
	print("ON ENTER JUMP")
	
func _check_transitions() -> void:
	if(player.is_on_floor()):
		state_machine._transition_to(state_machine.E_StateName.Grounded)
	elif (player.velocity.y < 0):
		state_machine._transition_to(state_machine.E_StateName.Fall)
