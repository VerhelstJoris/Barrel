class_name GlobalEnvironmentManagerSingleton extends Node

# All three sample rates in the gust wobble (1.0x, 2.3x, 0.7x) land on whole texture tiles at 10.0,
# so the phase can wrap there without the crest snapping.
const GUST_WOBBLE_PHASE_WRAP : float = 10.0

@export var current_wind_speed_m_s : float = 3.3
@export var current_gust_speed_m_s : float = 40.0
@export var current_wind_direction : Vector2 = Vector2(0.664929, 0.746907)

var current_settings : EnvironmentSettings
var current_gust_settings : WindGustSettings
var current_player_following_effects : Array[Node]

@export var drift_offset_multiplier := 1.0
var current_drift_offset := Vector3.ZERO

# Metres the crest has travelled, wrapped to one wavelength so the pushed float never grows large.
var gust_travel_m : float = 0.0
# Wobble noise scroll, wrapped at GUST_WOBBLE_PHASE_WRAP.
var gust_wobble_phase : float = 0.0

signal on_wind_changed(direction ,speed)
signal on_gust_changed(speed)

func _ready() -> void:
	# The gust_settings setter may have run before the shader globals existed, so push once more here.
	_push_gust_settings()

func _initalize(settings : EnvironmentSettings) -> void:
	current_settings = settings

	var player : Player = Player.current_player
	if(!player):
		push_error("Cannot Initialize the environment, could not find active player")
		return

	for	effect in current_player_following_effects:
		effect.queue_free()
	current_player_following_effects.clear()

	for	effect in settings.player_following_effects:
		if(!effect.can_instantiate()):
			continue

		var new_effect = effect.instantiate()
		player.add_child(new_effect)
		new_effect.set_position(Vector3.ZERO)

	_set_wind_direction(settings.current_wind_direction)
	_set_wind_speed(settings.current_wind_speed_m_s)
	_set_gust_speed(settings.current_gust_speed_m_s)
	
	if current_gust_settings and current_gust_settings.changed.is_connected(_push_gust_settings):
		current_gust_settings.changed.disconnect(_push_gust_settings)
	current_gust_settings = settings.current_gust_settings
	if current_gust_settings and not current_gust_settings.changed.is_connected(_push_gust_settings):
		current_gust_settings.changed.connect(_push_gust_settings)
		_push_gust_settings()

func _set_wind_direction(new_dir : Vector2) -> Vector2:
	var temp := new_dir.normalized()

	if(temp == current_wind_direction):
		return temp

	current_wind_direction = temp
	# The gust travels with the wind, so its direction has to follow in the same step.
	_push_gust_direction()
	on_wind_changed.emit(current_wind_direction, current_wind_speed_m_s)
	return current_wind_direction

func _set_wind_direction_deg(degrees: float) -> Vector2:
	var r := deg_to_rad(degrees)
	return _set_wind_direction(Vector2(-sin(r), cos(r)))

func _set_wind_speed(new_speed_m_s : float) -> float:
	if(current_wind_speed_m_s == new_speed_m_s):
		return current_wind_speed_m_s

	current_wind_speed_m_s = new_speed_m_s
	on_wind_changed.emit(current_wind_direction, current_wind_speed_m_s)
	return current_wind_speed_m_s

func _get_wind_direction_deg() -> float:
	if current_wind_direction.is_zero_approx():
		return 0.0
	return fposmod(rad_to_deg(atan2(-current_wind_direction.x, current_wind_direction.y)), 360.0)


func _set_gust_speed(new_gust_speed_m_s : float) -> float:
	if(current_gust_speed_m_s == new_gust_speed_m_s):
		return current_gust_speed_m_s

	current_gust_speed_m_s = new_gust_speed_m_s
	on_gust_changed.emit(current_gust_speed_m_s)
	return current_gust_speed_m_s

func _process(delta: float) -> void:
	current_drift_offset += Vector3(current_wind_direction.x,0,current_wind_direction.y) * current_wind_speed_m_s * drift_offset_multiplier * delta
	RenderingServer.global_shader_parameter_set("wind_drift_offset", current_drift_offset)
	_advance_gust_phase(delta)


#region GUST

# Heading the gust travels, guarded so a direction set straight on the export cannot produce NaN.
func _gust_travel_direction() -> Vector2:
	if current_wind_direction.length() < 0.0001:
		return Vector2(1.0, 0.0)
	return current_wind_direction.normalized()


# Seconds between crests passing a fixed point; the number that reads as a metronome if it never varies.
func _gust_period_seconds() -> float:
	if not current_gust_settings:
		return 0.0
	return current_gust_settings.wavelength_m / maxf(absf(current_gust_speed_m_s), 0.001)


# Seconds a single crest takes to pass a fixed point.
func _gust_duration_seconds() -> float:
	if not current_gust_settings:
		return 0.0
	return (current_gust_settings.wavelength_m * current_gust_settings.width) / maxf(absf(current_gust_speed_m_s), 0.001)

# Both phases stay small forever, which keeps fract() precise and removes the old TIME rollover snap.
func _advance_gust_phase(delta : float) -> void:
	if not current_gust_settings:
		return

	gust_travel_m = fposmod(gust_travel_m + current_gust_speed_m_s * delta, current_gust_settings.wavelength_m)
	gust_wobble_phase = fposmod(gust_wobble_phase + current_gust_settings.wobble_speed * delta, GUST_WOBBLE_PHASE_WRAP)

	RenderingServer.global_shader_parameter_set("foliage_gust_travel_m", gust_travel_m)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_phase", gust_wobble_phase)

func _push_gust_direction() -> void:
	RenderingServer.global_shader_parameter_set("foliage_gust_direction", _gust_travel_direction())

func _push_gust_settings() -> void:
	if not current_gust_settings:
		return

	_push_gust_direction()
	RenderingServer.global_shader_parameter_set("foliage_gust_wavelength_m", current_gust_settings.wavelength_m)
	RenderingServer.global_shader_parameter_set("foliage_gust_width", current_gust_settings.width)
	RenderingServer.global_shader_parameter_set("foliage_gust_strength", current_gust_settings.strength)
	RenderingServer.global_shader_parameter_set("foliage_gust_sharpness", current_gust_settings.sharpness)
	RenderingServer.global_shader_parameter_set("foliage_gust_asymmetry", current_gust_settings.asymmetry)
	RenderingServer.global_shader_parameter_set("foliage_gust_rebound", current_gust_settings.rebound)
	RenderingServer.global_shader_parameter_set("foliage_gust_patchiness", current_gust_settings.patchiness)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_noise", current_gust_settings.wobble_noise)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_m", current_gust_settings.wobble_m)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_scale_m", current_gust_settings.wobble_scale_m)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_detail", current_gust_settings.wobble_detail)


func _validate_gust() -> PackedStringArray:
	var problems := PackedStringArray()

	if not current_gust_settings:
		problems.append("gust_settings is unassigned; no gust will be pushed to the shaders.")
		return problems

	if not current_gust_settings.wobble_noise and current_gust_settings.wobble_m > 0.0:
		problems.append("wobble_m is %.1f but wobble_noise is unassigned; the crest will stay perfectly straight." % current_gust_settings.wobble_m)
	if current_wind_direction.length() < 0.0001:
		problems.append("current_wind_direction is zero length; the gust has no travel heading.")
	if absf(current_gust_speed_m_s) < 0.0001:
		problems.append("current_gust_speed_m_s is zero; the gust will never travel.")
	# The profile spans roughly 44% of a cycle including the rebound lobe, so beyond that crests overlap.
	if current_gust_settings.width * (1.0 + current_gust_settings.asymmetry) * 1.3 > 0.5:
		problems.append("width %.2f at asymmetry %.2f makes a crest wide enough to overlap the next one."
			% [current_gust_settings.width, current_gust_settings.asymmetry])

	return problems

#endregion
