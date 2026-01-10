class_name PistolInputReceiver extends InputReceiver

@export var input_reload_dictionary : Dictionary[InputActionInfo, ExposedSignalConnector]

var colt_equipment : PlayerEquipmentPistol = null
var is_entering_reload : bool = false
var is_exiting_reload : bool = false

func _ready() -> void:
	if(!get_owner().has_meta(PlayerEquipment.equipment_node_name)):
		push_error("Pistol Input Receiver Cannot find equipment node via metadata")
		return

	colt_equipment = get_owner().get_meta(PlayerEquipment.equipment_node_name) as PlayerEquipmentPistol
	colt_equipment.on_action_started.connect(_on_colt_action_started)
	colt_equipment.on_unholstered.connect(_on_unholstered)
	colt_equipment.on_holstered.connect(_on_holstered)
	_change_HUD_available_actions(input_dictionary.keys(),colt_equipment)
	
	
func _get_available_inputs() -> Dictionary[InputActionInfo, ExposedSignalConnector]:
	if(colt_equipment.current_state == PlayerEquipmentPistol.EPistolState.Reloading):
		return input_reload_dictionary
	else:
		return input_dictionary
		
func _on_unholstered() -> void:
	_change_HUD_available_actions(input_dictionary.keys(), colt_equipment)

func _on_holstered() -> void:
	_change_HUD_available_actions([],colt_equipment)

func _on_colt_action_started(action : PlayerEquipmentPistol.EPistolActions) -> void:
	if(is_entering_reload):
		is_entering_reload = false
		_change_HUD_available_actions(input_reload_dictionary.keys(),colt_equipment)
	
	if(is_exiting_reload):
		is_entering_reload = false
		_change_HUD_available_actions(input_dictionary.keys(),colt_equipment)
	
	is_exiting_reload = false
	if(action == PlayerEquipmentPistol.EPistolActions.EnterReload || action == PlayerEquipmentPistol.EPistolActions.EnterReloadUncock):
		is_entering_reload = true
		_change_HUD_available_actions([], colt_equipment)
	elif (action == PlayerEquipmentPistol.EPistolActions.ExitReload):
		is_exiting_reload = true
		_change_HUD_available_actions([],colt_equipment)
		