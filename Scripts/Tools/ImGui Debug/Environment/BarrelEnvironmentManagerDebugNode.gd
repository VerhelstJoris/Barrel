class_name BarrelEnvironmentManagerDebugNode extends BarrelSceneDebugNode

@export var env_setup_node : EnvironmentSetup

var ed_wind_dir : Array[float] = [1.0,1.0]
var ed_wind_speed: Array[float] = [1.0]
var ed_gust_speed: Array[float] = [1.0]

@export var sdf_path : String = "res://wind/wind_sdf"
@export var sdf_meta_path : String = "res://wind/wind_meta"

func _ready() -> void:
	super()
	if(env_setup_node):
		BarrelDebugWindow.environment_node._register_environment_node(self, BarrelEnvironmentDebugNode.EDebugEnvNodeType.Manager)
	else:
		queue_free()
		
		
func _get_name() -> String:
	return "Environment Manager"

func _draw_contents(_delta : float) -> void:
	ImGui.Text("Wind Settings")
	ImGui.Indent()
	_draw_wind_contents(_delta)
	ImGui.Unindent()
	_draw_sdf()
	
func _draw_sdf() -> void:
	ImGuiDrawSDF._draw_sdf_contents(sdf_meta_path,sdf_path)
	
	
func _draw_wind_contents(_delta : float ) -> void:
	var editable_wind_dir : Array[float] = [EnvironmentManager._get_wind_direction_deg()]
	if(ImGui.DragFloatEx("Wind Direction Deg", editable_wind_dir,2.0,0.0,360.0)):
		EnvironmentManager._set_wind_direction_deg(editable_wind_dir[0])
		
	ed_wind_speed[0] = EnvironmentManager.current_wind_speed_m_s
	if(ImGui.DragFloatEx("Wind Speed", ed_wind_speed,0.01,0,20)):
		EnvironmentManager._set_wind_speed(ed_wind_speed[0])
	
	ed_gust_speed[0] = EnvironmentManager.current_gust_speed_m_s
	if(ImGui.DragFloatEx("Gust Speed", ed_gust_speed,0.5,0,100)):
		EnvironmentManager._set_gust_speed(ed_gust_speed[0])
		
