class_name AtmosphereManager extends Node

# Converts wind speed in m/s into sky shader units so the clouds drift at a believable pace.
const WIND_SPEED_TO_SKY_UNITS : float = 0.01

@export var sky : Sky3D
@export var wind_speed_mult : float = 1.0

var wind_direction : Vector2 = Vector2.ZERO
var wind_speed_m_s : float = 0.0
var cumulus_position : Vector2 = Vector2.ZERO
var cumulus_small_cloud_position : Vector2 = Vector2.ZERO
var cirrus_position : Vector2 = Vector2.ZERO

func _ready() -> void:
	_initialize_wind_data()

func _initialize_wind_data() -> void:
	EnvironmentManager.on_wind_changed.connect(_on_wind_changed)
	_on_wind_changed(EnvironmentManager.current_wind_direction, EnvironmentManager.current_wind_speed_m_s)

func _on_wind_changed(new_dir : Vector2, new_speed : float) -> void:
	wind_direction = new_dir.normalized()
	wind_speed_m_s = new_speed

func _process(delta: float) -> void:
	if sky == null or sky.sky_material == null:
		return

	var cirrus_speed_scale : float = _get_material_float(sky.sky_material, "cirrus_speed_scale")
	var cumulus_small_cloud_speed_scale : float = _get_material_float(sky.sky_material, "cumulus_small_cloud_speed_scale")
	var position_delta : Vector2 = wind_direction * wind_speed_m_s * wind_speed_mult * WIND_SPEED_TO_SKY_UNITS * delta
	cumulus_position += position_delta
	cumulus_small_cloud_position += position_delta * cumulus_small_cloud_speed_scale
	cirrus_position += position_delta * cirrus_speed_scale

	sky.sky_material.set_shader_parameter("cloud_direction", wind_direction)
	sky.sky_material.set_shader_parameter("cumulus_position", cumulus_position)
	sky.sky_material.set_shader_parameter("cumulus_small_cloud_position", cumulus_small_cloud_position)
	sky.sky_material.set_shader_parameter("cirrus_position", cirrus_position)

# falls back to the shader default when the material has never stored a value for the parameter
func _get_material_float(sky_material : ShaderMaterial, parameter_name : StringName) -> float:
	var parameter_value : Variant = sky_material.get_shader_parameter(parameter_name)
	if parameter_value == null:
		parameter_value = RenderingServer.shader_get_parameter_default(sky_material.shader.get_rid(), parameter_name)
	return parameter_value if parameter_value != null else 1.0
