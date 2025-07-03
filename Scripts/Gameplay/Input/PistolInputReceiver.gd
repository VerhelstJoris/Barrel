class_name PistolInputReceiver extends InputReceiver

@export var input_reload_dictionary : Dictionary[InputActionInfo, ExposedSignalConnector]


var colt_equipment : PlayerEquipmentPistol = null
var is_entering_reload : bool = false
var is_exiting_reload : bool = false


func _ready() -> void:
	colt_equipment = get_owner() as PlayerEquipmentPistol
	colt_equipment.on_action_started.connect(_on_colt_action_started)
	colt_equipment.on_unholstered.connect(_on_unholstered)
	colt_equipment.on_holstered.connect(_on_holstered)
	on_available_equipment_actions_changed.emit(input_dictionary.keys())
	
	
func _get_available_inputs() -> Dictionary[InputActionInfo, ExposedSignalConnector]:
	if(colt_equipment.current_state == EPistolState.State.Reloading):
		return input_reload_dictionary
	else:
		return input_dictionary
		
func _on_unholstered() -> void:
	on_available_equipment_actions_changed.emit(input_dictionary.keys())
	print("ON UNHOLSTERED EMIT")


func _on_holstered() -> void:
	on_available_equipment_actions_cleared.emit()
	print("CLEARED EMIT")


func _on_colt_action_started(action : EPistolState.Actions) -> void:
	if(is_entering_reload):
		is_entering_reload = false
		on_available_equipment_actions_changed.emit(input_reload_dictionary.keys())
	
	if(is_exiting_reload):
		is_entering_reload = false
		on_available_equipment_actions_changed.emit(input_dictionary.keys())

	is_exiting_reload = false
	if(action == EPistolState.Actions.EnterReload || action == EPistolState.Actions.EnterReloadUncock):
		is_entering_reload = true
		on_available_equipment_actions_cleared.emit()
	elif (action == EPistolState.Actions.ExitReload):
		is_exiting_reload = true
		on_available_equipment_actions_cleared.emit()