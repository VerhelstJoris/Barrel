class_name LineRendererDebugNode extends BarrelSceneDebugNode

@export var line : LineRenderer

func _get_name() -> String:
	return line.name

func _draw_contents(_delta : float) -> void:
	ImGui.Text("Current Amount of points %d" % line.points.size())
	super(_delta)
