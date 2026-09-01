class_name AtmosphereManager extends Node

@export var sky : Sky3D

func _ready() -> void:
	_initialize_wind_data()
	
func _initialize_wind_data() -> void:
	EnvironmentManager.on_wind_changed.connect(_on_wind_direction_changed)
	_on_wind_direction_changed(EnvironmentManager.current_wind_direction, EnvironmentManager.current_wind_speed_m_s)
	
 # v = (x, z), direction wind blows toward	
func _wind_dir_to_sky_angle(v: Vector2) -> float: 
	return fposmod(rad_to_deg(atan2(-v.x, v.y)), 360.0)	
	
func _on_wind_direction_changed(new_dir : Vector2, new_speed : float) -> void:
	if(sky == null):
		return
		
	var angle : float = _wind_dir_to_sky_angle(new_dir)
	
	#map the 2D vector into a single angle	
	sky.wind_direction = angle
	sky.wind_speed = new_speed
