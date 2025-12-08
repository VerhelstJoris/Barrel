class_name PlayerInputManager extends Node

@export var _player : Player

enum InputTrackData{ Node, SignalConnector , StartTime, StartInputEvent}

var input_action_time_map : Dictionary

signal on_input_held(input_action : InputActionInfo, start_time : float )

func _input(event: InputEvent) -> void:
	if(event is InputEventMouseMotion):
		_player._on_mouse_motion_input(event)
		return
		
	if(_player.input_receiver != null):
		_process_input_receiver(_player.input_receiver, event)
		
	if(_player.equipment_manager._can_use_equipment() && _player.equipment_manager.current_right_equipment.input_receiver):
		_process_input_receiver(_player.equipment_manager.current_right_equipment.input_receiver, event)
		
func _process_input_receiver(receiver : InputReceiver, event : InputEvent) -> void:
	var available_receiver_inputs = receiver._get_available_inputs()
	for key : InputActionInfo in available_receiver_inputs:
		_process_single_input(key, event,receiver, available_receiver_inputs[key])
	
func _process_single_input(input_action_info: InputActionInfo, event : InputEvent, node : Node, exposed_signal_connector: ExposedSignalConnector) -> void:
	var action_to_check : String = input_action_info.input_string
	
	if(!event.is_action(action_to_check)):
		return
		
	var current_time : float = 	Time.get_unix_time_from_system()
	if(input_action_info.is_hold):
		if(event.is_released() && input_action_time_map.has(input_action_info)):
			input_action_time_map.erase(input_action_info)
		elif (Input.is_action_just_pressed(action_to_check) && !input_action_time_map.has(input_action_info)):
			_add_new_map_entry(input_action_info, event, node, exposed_signal_connector, current_time)
	else:
		_on_input_succesful(node, exposed_signal_connector, event)

func _on_input_succesful(node : Node, exposed_signal_connector: ExposedSignalConnector, event: InputEvent) -> void:
	ExposedSignalConnector._try_send_signal(node, exposed_signal_connector, event)
	
func _add_new_map_entry(input_action_info : InputActionInfo, event : InputEvent, node : Node, exposed_signal_connector: ExposedSignalConnector, start_time : float)	-> void:	
	input_action_time_map[input_action_info] = {InputTrackData.StartTime:start_time, InputTrackData.SignalConnector: exposed_signal_connector, InputTrackData.Node: node , InputTrackData.StartInputEvent: event }

func _physics_process(_delta: float) -> void:
	var current_time : float =  Time.get_unix_time_from_system()
	for input in input_action_time_map:
		_process_held_input(input, current_time)
		
func _process_held_input(input : InputActionInfo, current_time : float) -> void:
	if(Input.is_action_pressed(input.input_string)):
		if(input_action_time_map[input][InputTrackData.StartTime] + input.hold_time < current_time):
			_on_input_succesful(input_action_time_map[input][InputTrackData.Node], input_action_time_map[input][InputTrackData.SignalConnector], input_action_time_map[input][InputTrackData.StartInputEvent])
			input_action_time_map.erase(input)
		else:	
			on_input_held.emit(input, input_action_time_map[input][InputTrackData.StartTime])
	else:
		input_action_time_map.erase(input)	
		