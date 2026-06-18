class_name BarrelEnvironmentDebugNode extends BarrelSceneDebugNode

var registered_node_dictionary : Dictionary[EDebugEnvNodeType, BarrelSceneDebugNode]

enum EDebugEnvNodeType { Foliage }

func _ready() -> void:
	super()
	
func _get_name() -> String:
	return "Global Environment Debug"

func _draw(_delta: float) -> void:
	ImGui.Text("This is where we display all environments debug nodes")
	registered_node_dictionary[EDebugEnvNodeType.Foliage]._draw(_delta)
	
func _register_environment_node( new_node : BarrelSceneDebugNode, type : EDebugEnvNodeType)	-> void:
	registered_node_dictionary[type] = new_node
	pass