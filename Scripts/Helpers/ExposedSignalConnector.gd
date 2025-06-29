class_name ExposedSignalConnector extends  Resource

@export	var signal_node : NodePath
@export var signal_name : String

static func _try_send_signal(starting_node : Node ,signal_to_emit : ExposedSignalConnector, params = {}) -> bool:
	var found_node : Node = starting_node.get_node(signal_to_emit.signal_node)
	
	if found_node:
		return found_node.emit_signal(signal_to_emit.signal_name, params) != ERR_UNAVAILABLE
	else:
		printerr("Node to send signal to does not exist")
		return false