class_name EnvironmentSettings extends Resource

@export_group("Wind")
@export var current_wind_speed_m_s : float = 3.3
@export var current_wind_direction : Vector2 = Vector2(0.664929, 0.746907)

@export_group("Gusts")
@export var current_gust_speed_m_s : float = 40.0
@export var current_gust_settings : WindGustSettings

@export_group("Misc")
@export var player_following_effects : Array[PackedScene]
