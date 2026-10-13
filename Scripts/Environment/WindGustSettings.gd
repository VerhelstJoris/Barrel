@tool
class_name WindGustSettings extends Resource

# Shape of the travelling gust wave. Direction and speed live on GlobalEnvironmentManagerSingleton,
# which owns the wind and drives every value here into global shader parameters.
# Every setter funnels through _apply_change so the push path is defined in one place.

@export_group("Travel")
## Distance between crests, so seconds between gusts is this over the gust speed.
@export var wavelength_m : float = 400.0:
	set(value):
		wavelength_m = maxf(value, 0.001)
		_apply_change()

@export_group("Profile")
## Fraction of the cycle the wave occupies; small is a sharp gust, large is a swell.
@export var width : float = 0.15:
	set(value):
		width = maxf(value, 0.001)
		_apply_change()

## Master multiplier; scales every consumer at once without retuning each.
@export var strength : float = 1.75:
	set(value):
		strength = value
		_apply_change()

## Concentrates the wave toward its crest; 1 is a soft swell, 3 is a snap.
@export var sharpness : float = 2.0:
	set(value):
		sharpness = maxf(value, 0.001)
		_apply_change()

## Steepens the arriving edge and lengthens the recovery; 0 is symmetric.
@export_range(0.0, 0.95) var asymmetry : float = 0.5:
	set(value):
		asymmetry = value
		_apply_change()

## Backswing behind the crest, so grass overshoots instead of easing to rest.
@export var rebound : float = 0.15:
	set(value):
		rebound = value
		_apply_change()

## Varies amplitude along the crest so the wave is not a uniform band.
@export_range(0.0, 1.0) var patchiness : float = 0.35:
	set(value):
		patchiness = value
		_apply_change()

@export_group("Crest Wobble")
## Noise that bends the crest and varies its strength; MUST have repeat enabled or the phase wrap seams.
@export var wobble_noise : Texture2D:
	set(value):
		wobble_noise = value
		_apply_change()

## Metres the crest snakes forward and back along its length; 0 disables the bend.
@export var wobble_m : float = 15.0:
	set(value):
		wobble_m = value
		_apply_change()

## Length of one undulation along the crest; smaller is a busier edge.
@export var wobble_scale_m : float = 400.0:
	set(value):
		wobble_scale_m = maxf(value, 0.001)
		_apply_change()

## How fast the crest reshapes. CPU only: the manager integrates it into the pushed wobble phase.
@export var wobble_speed : float = 0.02:
	set(value):
		wobble_speed = value
		_apply_change()

## Second, finer octave of wobble; 0 is one smooth bend, 1 is ragged.
@export_range(0.0, 1.0) var wobble_detail : float = 0.1:
	set(value):
		wobble_detail = value
		_apply_change()


# One place for every property change, so dirty flagging or deferred pushes only ever need adding here.
func _apply_change() -> void:
	emit_changed()


# The single mapping from this resource onto the shader globals, so the environment manager and
# FoliageWorld's editor preview cannot push different subsets. Travel direction comes from the
# caller because it belongs to the wind, not to the shape of the wave.
func _push_to_globals(travel_direction : Vector2) -> void:
	RenderingServer.global_shader_parameter_set("foliage_gust_direction", travel_direction)
	RenderingServer.global_shader_parameter_set("foliage_gust_wavelength_m", wavelength_m)
	RenderingServer.global_shader_parameter_set("foliage_gust_width", width)
	RenderingServer.global_shader_parameter_set("foliage_gust_strength", strength)
	RenderingServer.global_shader_parameter_set("foliage_gust_sharpness", sharpness)
	RenderingServer.global_shader_parameter_set("foliage_gust_asymmetry", asymmetry)
	RenderingServer.global_shader_parameter_set("foliage_gust_rebound", rebound)
	RenderingServer.global_shader_parameter_set("foliage_gust_patchiness", patchiness)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_noise", wobble_noise)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_m", wobble_m)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_scale_m", wobble_scale_m)
	RenderingServer.global_shader_parameter_set("foliage_gust_wobble_detail", wobble_detail)
