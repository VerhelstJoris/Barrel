class_name PlayerInputManager extends Node

@export var _player : Player

var input_action_time_map : Dictionary[String, float]

signal on_input_held(input_action : String, start_time : float )

func _ready() -> void:
	pass
	
func _input(event: InputEvent) -> void:
	if(event is InputEventMouseMotion):
		_player._on_mouse_motion_input(event)
		return
		
	if(_player.input_receiver != null):
		_process_input_receiver(_player.input_receiver, event)
		
	if(_player._can_use_equipment() && _player.current_equipment.input_receiver):
		_process_input_receiver(_player.current_equipment.input_receiver, event)
		
func _process_input_receiver(receiver : InputReceiver, event : InputEvent) -> void:
	var available_receiver_inputs = receiver._get_available_inputs()
	for key : InputActionInfo in available_receiver_inputs:
		_process_single_input(key, event,receiver, available_receiver_inputs[key])
	
func _process_single_input(input_action_info: InputActionInfo, event : InputEvent, node : Node, exposed_signal_connector: ExposedSignalConnector) -> void:
	var action_to_check : String = input_action_info.input_string
	
	if(!event.is_action(action_to_check)):
		return
		
	if(input_action_info.is_hold):
		if(event.is_released() && input_action_time_map.has(action_to_check)):
			var found : float = input_action_time_map.get(action_to_check)
			if(found + input_action_info.hold_time < Time.get_unix_time_from_system()):
				input_action_time_map.erase(action_to_check)
				ExposedSignalConnector._try_send_signal(node, exposed_signal_connector, event)
		elif (event.is_pressed() && !input_action_time_map.has(action_to_check)):
			input_action_time_map[input_action_info.input_string] = Time.get_unix_time_from_system()
	else:
		ExposedSignalConnector._try_send_signal(node, exposed_signal_connector, event)
		
func _physics_process(_delta: float) -> void:
	for input in input_action_time_map:
		_process_held_input(input)
		
func _process_held_input(input : String) -> void:
	if(Input.is_action_pressed(input)):
		on_input_held.emit(input, input_action_time_map[input])
	else:
		input_action_time_map.erase(input)	
