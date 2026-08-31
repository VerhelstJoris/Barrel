class_name BarrelEnvironmentManagerDebugNode extends BarrelSceneDebugNode

var ed_wind_dir : Array[float] = [1.0,1.0]
var ed_wind_speed: Array[float] = [1.0]

func _get_name() -> String:
	return "Environment Manager"

func _draw_contents(_delta : float) -> void:
	
	ImGui.Text("Wind Settings")
	ImGui.Indent()
	_draw_wind_contents(_delta)
	ImGui.Unindent()
	
	
func _draw_wind_contents(_delta : float ) -> void:
	var editable_wind_dir : Array[float] = [EnvironmentManager.current_wind_direction.x, EnvironmentManager.current_wind_direction.y]
	if(ImGui.DragFloat2Ex("Wind Direction", editable_wind_dir , 0.01,-1.0,1.0)):
		EnvironmentManager._set_wind_direction(Vector2(editable_wind_dir[0],editable_wind_dir[1]))
		
	ed_wind_speed[0] = EnvironmentManager.current_wind_speed_m_s
	if(ImGui.DragFloatEx("Wind Speed", ed_wind_speed, 0.01)):
		EnvironmentManager._set_wind_speed(ed_wind_speed[0])
