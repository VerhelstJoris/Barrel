class_name PlayerInputManager extends Node

@export var _player : Player

func _ready() -> void:
	pass
	
func _input(event: InputEvent) -> void:
	if(event is InputEventMouseMotion):
		_player._on_mouse_motion_input(event)
		return
		
	if(_player.input_receiver != null):	
		for key in _player.input_receiver.input_dictionary:
			if(event.is_action(key.input_string)):
				_try_send_signal(event,_player.input_receiver,_player.input_receiver.input_dictionary[key])
				
	if(_player._can_use_equipment()):
		for equip_key in _player.current_equipment.input_receiver.input_dictionary:
			if(event.is_action(equip_key.input_string)):
				_try_send_signal(event, _player.current_equipment.input_receiver,_player.current_equipment.input_receiver.input_dictionary[equip_key])
				
		
func _try_send_signal(event: InputEvent, starting_node : Node ,signal_to_emit : ExposedSignalConnector ):
	var found_node : Node = starting_node.get_node(signal_to_emit.signal_node)
	if found_node:
		found_node.emit_signal(signal_to_emit.signal_name, event)
	else:
		printerr("Node or signal does not exist")	
