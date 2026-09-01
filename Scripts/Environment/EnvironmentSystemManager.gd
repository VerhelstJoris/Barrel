class_name EnvironmentSystemManager extends Node

var current_wind_speed_m_s : float = 3.3
var current_gust_speed_m_s : float = 40.0
var current_wind_direction : Vector2 = Vector2(0.664929, 0.746907)

signal on_wind_changed(direction ,speed)
signal on_gust_changed(speed)

func _set_wind_direction(new_dir : Vector2) -> Vector2:
	var temp := new_dir.normalized()
	
	if(temp == current_wind_direction):
		return temp
		
	current_wind_direction = temp
	on_wind_changed.emit(current_wind_direction, current_wind_speed_m_s)
	return current_wind_direction

func _set_wind_speed(new_speed_m_s : float) -> float:
	if(current_wind_speed_m_s == new_speed_m_s):
		return current_wind_speed_m_s
		
	current_wind_speed_m_s = new_speed_m_s	
	on_wind_changed.emit(current_wind_direction, current_wind_speed_m_s)
	return current_wind_speed_m_s

func _set_gust_speed(new_gust_speed_m_s : float) -> float:
	if(current_gust_speed_m_s == new_gust_speed_m_s):
		return current_gust_speed_m_s
		
	current_gust_speed_m_s = new_gust_speed_m_s	
	on_gust_changed.emit(current_gust_speed_m_s)
	return current_gust_speed_m_s
