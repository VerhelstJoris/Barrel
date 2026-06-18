class_name BarrelFoliageChunkDebugNode extends BarrelSceneDebugNode

@export var chunk : FoliageChunk

func _ready() -> void:
	super()
	BarrelDebugWindow.environment_node._register_environment_node(self, BarrelEnvironmentDebugNode.EDebugEnvNodeType.Foliage)

func _get_name() -> String:
	return chunk.name
	
func _draw_contents(_delta : float) -> void:
	ImGui.Text("Chunk DATA HERE")
