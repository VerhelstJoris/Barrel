class_name PlayerInputManager extends Node

@export var _player : Player

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
	for key in receiver.input_dictionary:
			if(event.is_action(key.input_string)):
				ExposedSignalConnector._try_send_signal(receiver,receiver.input_dictionary[key], event)
			
func _try_send_signal(event: InputEvent, starting_node : Node ,signal_to_emit : ExposedSignalConnector ):
	var found_node : Node = starting_node.get_node(signal_to_emit.signal_node)
	if found_node:
		found_node.emit_signal(signal_to_emit.signal_name, event)
	else:
		printerr("Node or signal does not exist")	
