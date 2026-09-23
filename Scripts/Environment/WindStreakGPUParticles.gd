@tool
class_name WindStreakGPUParticles extends GPUParticles3D

# shader uniform names, kept here so renaming one in the shader is a single edit
const PARAM_SDF_MAP : StringName = &"sdf_map"
const PARAM_SDF_ORIGIN : StringName = &"sdf_origin"
const PARAM_SDF_SIZE : StringName = &"sdf_size"
const PARAM_WIND_DIRECTION : StringName = &"wind_direction"
const PARAM_WIND_SPEED : StringName = &"wind_speed"
const PARAM_TURN_RATE : StringName = &"turn_rate"
const PARAM_STALL_WINDOW : StringName = &"stall_window"
const PARAM_FIZZLE_TIME : StringName = &"fizzle_time"
const PARAM_TAIL_HOLD : StringName = &"tail_hold"
const PARAM_LOOKAHEAD_TIME : StringName = &"lookahead_time"
const PARAM_SWAY_FREQUENCY : StringName = &"sway_frequency"
const PARAM_LIFE_FADE_OUT : StringName = &"life_fade_out"

# keys written by the sdf baker into the field's companion json
const META_ORIGIN_X : StringName = &"origin_x"
const META_ORIGIN_Z : StringName = &"origin_z"
const META_SIZE_X : StringName = &"size_x"
const META_SIZE_Z : StringName = &"size_z"

const LIFE_FADE_OUT_DEFAULT : float = 0.2
const AABB_HEIGHT : float = 1000.0

@export_group("Field")
@export_file("*.json") var field_json : String = "res://wind/wind_sdf.json"
@export_file("*.res", "*.exr") var field_image : String = "res://wind/wind_sdf.res"
@export_tool_button("Apply Field") var apply_field_button : Callable = apply_field

@export_group("Wind")
@export var wind_direction : Vector2 = Vector2(1.0, 0.0):
	set(value):
		wind_direction = value
		_push_wind_base_params()
@export var wind_speed : float = 4.0:
	set(value):
		wind_speed = value
		_push_wind_base_params()
		_push_wind_tuning_params()

# authored in metres so the look holds at any speed, since every one of these is a time or a rate in the shader
@export_group("Tuning Distances")
@export var scale_tuning_with_speed : bool = true:
	set(value):
		scale_tuning_with_speed = value
		_push_wind_tuning_params()
@export var turn_distance : float = 11.25:
	set(value):
		turn_distance = value
		_push_wind_tuning_params()
@export var stall_distance : float = 22.5:
	set(value):
		stall_distance = value
		_push_wind_tuning_params()
@export var fizzle_distance : float = 45.0:
	set(value):
		fizzle_distance = value
		_push_wind_tuning_params()
@export var lookahead_distance : float = 50.0:
	set(value):
		lookahead_distance = value
		_push_wind_tuning_params()
@export var sway_wavelength : float = 112.5:
	set(value):
		sway_wavelength = value
		_push_wind_tuning_params()

# only applied automatically in game, since doing it in the editor embeds the whole field into the saved scene
func _ready() -> void:
	if(!Engine.is_editor_hint()):
		apply_field()

func apply_field() -> void:
	var material : ShaderMaterial = _shader_material(true)
	if(material == null):
		return

	var meta : Dictionary = _load_metadata()
	if(meta.is_empty()):
		return

	var image : Image = _load_image(field_image)
	if(image == null):
		push_error("WindStreak: no image could be loaded from %s" % field_image)
		return

	var origin : Vector2 = Vector2(meta.get(META_ORIGIN_X, 0.0), meta.get(META_ORIGIN_Z, 0.0))
	var size : Vector2 = Vector2(meta.get(META_SIZE_X, 1.0), meta.get(META_SIZE_Z, 1.0))

	material.set_shader_parameter(PARAM_SDF_MAP, ImageTexture.create_from_image(image))
	material.set_shader_parameter(PARAM_SDF_ORIGIN, origin)
	material.set_shader_parameter(PARAM_SDF_SIZE, size)

	# a fizzled particle has to outlive its own trail history, and that history is exactly trail_lifetime long
	material.set_shader_parameter(PARAM_TAIL_HOLD, trail_lifetime)

	_push_wind_base_params()
	_push_wind_tuning_params()
	_apply_world_settings(origin, size)
	_warn_about_trails(material)

## Sets both at once so the derived tuning is only recomputed once.
func set_wind(direction : Vector2, speed : float) -> void:
	wind_direction = direction
	wind_speed = speed

## Direction on the XZ plane; a zero vector is ignored since the shader normalises it.
func set_wind_direction(direction : Vector2) -> void:
	if(direction.length_squared() < 0.000001):
		push_warning("WindStreak: ignoring a zero wind direction")
		return

	wind_direction = direction

## Metres per second; everything under Tuning Distances is rederived from this.
func set_wind_speed(speed : float) -> void:
	wind_speed = maxf(speed, 0.0)

func _push_wind_base_params() -> void:
	var material : ShaderMaterial = _shader_material()
	if(material == null):
		return

	material.set_shader_parameter(PARAM_WIND_DIRECTION, wind_direction)
	material.set_shader_parameter(PARAM_WIND_SPEED, wind_speed)

# a time in the shader is a distance divided by speed and a rate is a speed divided by a distance, so holding the distances fixed keeps the behaviour identical as speed changes
func _push_wind_tuning_params() -> void:
	if(!scale_tuning_with_speed):
		return

	var material : ShaderMaterial = _shader_material()
	if(material == null):
		return

	var speed : float = maxf(wind_speed, 0.001)
	material.set_shader_parameter(PARAM_TURN_RATE, speed / maxf(turn_distance, 0.001))
	material.set_shader_parameter(PARAM_SWAY_FREQUENCY, speed / maxf(sway_wavelength, 0.001))
	material.set_shader_parameter(PARAM_STALL_WINDOW, stall_distance / speed)
	material.set_shader_parameter(PARAM_FIZZLE_TIME, fizzle_distance / speed)
	material.set_shader_parameter(PARAM_LOOKAHEAD_TIME, lookahead_distance / speed)

func _apply_world_settings(origin : Vector2, size : Vector2) -> void:
	# particles travel in world space, so they must not be dragged along when this node moves
	local_coords = false

	# the default AABB is a few metres wide, and a system spread over the region gets culled the moment that box leaves the view
	var world_box : AABB = AABB(
		Vector3(origin.x, -AABB_HEIGHT * 0.5, origin.y),
		Vector3(size.x, AABB_HEIGHT, size.y))
	visibility_aabb = global_transform.affine_inverse() * world_box

func _warn_about_trails(material : ShaderMaterial) -> void:
	if(!trail_enabled):
		push_warning("WindStreak: trail_enabled is off, particles will render as points rather than ribbons")
		return

	# a streak has to reach zero width before it expires or its trail history pops, and that is not visible from either value alone
	var fade_out : Variant = material.get_shader_parameter(PARAM_LIFE_FADE_OUT)
	var fade_out_seconds : float = (LIFE_FADE_OUT_DEFAULT if fade_out == null else float(fade_out)) * lifetime
	if(fade_out_seconds < trail_lifetime):
		push_warning("WindStreak: life_fade_out covers %.2fs but trail_lifetime is %.2fs, so trails will pop when particles expire" % [fade_out_seconds, trail_lifetime])

func _load_metadata() -> Dictionary:
	var file : FileAccess = FileAccess.open(field_json, FileAccess.READ)
	if(file == null):
		push_error("WindStreak: no metadata at %s" % field_json)
		return {}

	var parsed : Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if(typeof(parsed) != TYPE_DICTIONARY):
		push_error("WindStreak: %s is not valid json" % field_json)
		return {}

	return parsed

# a .res holding the Image skips the import pipeline, which is the only route guaranteed to keep the float data and its sign
func _load_image(path : String) -> Image:
	if(ResourceLoader.exists(path)):
		var loaded : Resource = load(path)
		if(loaded is Image):
			return loaded as Image
		if(loaded is Texture2D):
			return (loaded as Texture2D).get_image()

	return Image.load_from_file(path)

# the push functions run from property setters during scene load, well before a material exists, so only an explicit apply reports the failure
func _shader_material(report : bool = false) -> ShaderMaterial:
	var material := process_material as ShaderMaterial
	if(material == null && report):
		push_error("WindStreak: process_material must be a ShaderMaterial using wind_particles.gdshader")

	return material
