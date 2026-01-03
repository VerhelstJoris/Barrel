class_name LineRendererDebugNode extends BarrelSceneDebugNode

@export var line : LineRenderer

func _get_name() -> String:
	return line.name

func _draw_contents(_delta : float) -> void:
	var draw_debug : Array[bool] = [line.draw_debug]

	if(ImGui.Checkbox("Draw Debug?", draw_debug)):
		line.draw_debug = draw_debug[0]
		
	ImGui.Text("Current Amount of points %d" % line.points.size())

	super(_delta)
