class_name BarrelEnvironmentManagerDebugNode extends BarrelSceneDebugNode

@export var environment_manager : EnvironmentManager

var ed_wind_dir : Array[float] = [1.0,1.0]
var ed_wind_speed: Array[float] = [1.0]
var ed_gust_speed: Array[float] = [1.0]

@export var field_path : String = "res://wind/wind_sdf"

var _display_size : Array = [512.0]
var _max_distance : Array = [20.0]
var _band_spacing : Array = [5.0]
var _show_window : Array = [true]

var wind_sdf_tex : ImageTexture

func _ready() -> void:
	super()
	if(environment_manager):
		BarrelDebugWindow.environment_node._register_environment_node(self, BarrelEnvironmentDebugNode.EDebugEnvNodeType.Manager)
	else:
		queue_free()
		
		
	wind_sdf_tex = field_path.make_debug_texture(_max_distance[0], _band_spacing[0])	

func _get_name() -> String:
	return "Environment Manager"

func _draw_contents(_delta : float) -> void:
	ImGui.Text("Wind Settings")
	ImGui.Indent()
	_draw_wind_contents(_delta)
	ImGui.Unindent()
	_draw_sdf()
	
func _draw_sdf() -> void:
	if(wind_sdf_tex == null):
		ImGui.Text("Preview texture failed to build")
		return
	
	
	
func _draw_wind_contents(_delta : float ) -> void:
	var editable_wind_dir : Array[float] = [environment_manager._get_wind_direction_deg()]
	if(ImGui.DragFloatEx("Wind Direction Deg", editable_wind_dir,2.0,0.0,360.0)):
		environment_manager._set_wind_direction_deg(editable_wind_dir[0])
		
	ed_wind_speed[0] = environment_manager.current_wind_speed_m_s
	if(ImGui.DragFloatEx("Wind Speed", ed_wind_speed,0.01,0,20)):
		environment_manager._set_wind_speed(ed_wind_speed[0])
	
	ed_gust_speed[0] = environment_manager.current_gust_speed_m_s
	if(ImGui.DragFloatEx("Gust Speed", ed_gust_speed,0.5,0,100)):
		environment_manager._set_gust_speed(ed_gust_speed[0])
		
