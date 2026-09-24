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
const PARAM_USE_HEIGHT_CHANNEL : StringName = &"use_height_channel"

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

# cached from the json so the runtime path never opens a file, refreshed whenever the field is applied in the editor
@export var field_origin : Vector2 = Vector2.ZERO
@export var field_size : Vector2 = Vector2.ONE

# half float halves the upload, and its precision near zero is far finer than a texel so steering cannot tell the difference
@export var half_precision : bool = true
@export var load_in_background : bool = true
@export var report_timing : bool = false

@export var wind_speed_mult : float = 5.0

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
	if(Engine.is_editor_hint()):
		return

	if(load_in_background):
		apply_field_async()
	else:
		apply_field()
		
	EnvironmentManager.on_wind_changed.connect(_on_wind_direction_changed)
	_on_wind_direction_changed(EnvironmentManager.current_wind_direction, EnvironmentManager.current_wind_speed_m_s)

func _on_wind_direction_changed(new_dir : Vector2, new_speed : float):
	_push_wind_base_params(new_speed * wind_speed_mult, new_dir)
	_push_wind_tuning_params()

## Blocking apply, used by the editor button. Also refreshes the cached metadata from the json.
func apply_field() -> void:
	var material : ShaderMaterial = _shader_material(true)
	if(material == null):
		return

	var json_started : int = Time.get_ticks_usec()
	_refresh_metadata()
	var json_usec : int = Time.get_ticks_usec() - json_started

	var load_started : int = Time.get_ticks_usec()
	var image : Image = _load_image(field_image)
	var load_usec : int = Time.get_ticks_usec() - load_started

	if(image == null):
		push_error("WindStreak: no image could be loaded from %s" % field_image)
		return

	_finish_apply(material, image, json_usec, load_usec)

## Same work with the file read moved onto a worker thread, so only the upload lands on the main thread.
func apply_field_async() -> void:
	var material : ShaderMaterial = _shader_material(true)
	if(material == null):
		return

	var json_started : int = Time.get_ticks_usec()
	if(field_size == Vector2.ONE):
		_refresh_metadata()
	var json_usec : int = Time.get_ticks_usec() - json_started

	var load_started : int = Time.get_ticks_usec()
	var image : Image = await _load_image_threaded(field_image)
	var load_usec : int = Time.get_ticks_usec() - load_started

	if(image == null):
		push_error("WindStreak: no image could be loaded from %s" % field_image)
		return

	if(!is_inside_tree()):
		return

	_finish_apply(material, image, json_usec, load_usec)

func _finish_apply(material : ShaderMaterial, image : Image, json_usec : int, load_usec : int) -> void:
	_warn_about_format(image, load_usec)

	var source_format : int = image.get_format()
	var upload_started : int = Time.get_ticks_usec()
	material.set_shader_parameter(PARAM_SDF_MAP, _build_texture(image, material))
	var upload_usec : int = Time.get_ticks_usec() - upload_started

	material.set_shader_parameter(PARAM_SDF_ORIGIN, field_origin)
	material.set_shader_parameter(PARAM_SDF_SIZE, field_size)

	# a fizzled particle has to outlive its own trail history, and that history is exactly trail_lifetime long
	material.set_shader_parameter(PARAM_TAIL_HOLD, trail_lifetime)

	_push_wind_base_params(EnvironmentManager.current_gust_speed_m_s, EnvironmentManager.current_wind_direction)
	_push_wind_tuning_params()
	_apply_world_settings()
	_warn_about_trails(material)

	if(report_timing):
		print("WindStreak: %dx%d %s | json %.1f ms, load %.1f ms, upload %.1f ms" % [
			image.get_width(), image.get_height(), _format_name(source_format),
			json_usec / 1000.0, load_usec / 1000.0, upload_usec / 1000.0])

func _push_wind_base_params(new_speed : float, new_dir : Vector2) -> void:
	var material : ShaderMaterial = _shader_material()
	if(material == null):
		return

	material.set_shader_parameter(PARAM_WIND_DIRECTION, new_dir)
	material.set_shader_parameter(PARAM_WIND_SPEED, new_speed)

# a time in the shader is a distance divided by speed and a rate is a speed divided by a distance, so holding the distances fixed keeps the behaviour identical as speed changes
func _push_wind_tuning_params() -> void:
	if(!scale_tuning_with_speed):
		return

	var material : ShaderMaterial = _shader_material()
	if(material == null):
		return

	var speed : float = maxf(EnvironmentManager.current_wind_speed_m_s * wind_speed_mult, 0.001)
	material.set_shader_parameter(PARAM_TURN_RATE, speed / maxf(turn_distance, 0.001))
	material.set_shader_parameter(PARAM_SWAY_FREQUENCY, speed / maxf(sway_wavelength, 0.001))
	material.set_shader_parameter(PARAM_STALL_WINDOW, stall_distance / speed)
	material.set_shader_parameter(PARAM_FIZZLE_TIME, fizzle_distance / speed)
	material.set_shader_parameter(PARAM_LOOKAHEAD_TIME, lookahead_distance / speed)

# a distance field needs its fine precision near zero, which is exactly where half float is densest, and R16F filters on hardware where R32F may not
# the shader only ever samples r, and g when the height channel is on, so anything wider is bytes uploaded for nothing
func _build_texture(image : Image, material : ShaderMaterial) -> ImageTexture:
	var wants_height : Variant = material.get_shader_parameter(PARAM_USE_HEIGHT_CHANNEL)
	var target : int = Image.FORMAT_RGH if wants_height else Image.FORMAT_RH
	if(!half_precision):
		target = Image.FORMAT_RGF if wants_height else Image.FORMAT_RF

	if(image.get_format() != target):
		image = image.duplicate() as Image
		image.convert(target)

	return ImageTexture.create_from_image(image)

# the baker writes a single channel float, so anything wider came back through the exr import rather than the .res
func _warn_about_format(image : Image, load_usec : int) -> void:
	var format : int = image.get_format()
	if(format != Image.FORMAT_RF && format != Image.FORMAT_RH && format != Image.FORMAT_RGF && format != Image.FORMAT_RGH):
		push_warning("WindStreak: %s loaded as %s rather than a single channel float, point field_image at the baker's .res" % [field_image, _format_name(format)])

	if(load_usec > 250000):
		push_warning("WindStreak: loading %s took %.0f ms, which is an exr decode rather than a .res deserialise" % [field_image, load_usec / 1000.0])

func _apply_world_settings() -> void:
	# particles travel in world space, so they must not be dragged along when this node moves
	local_coords = false

	# the default AABB is a few metres wide, and a system spread over the region gets culled the moment that box leaves the view
	var world_box : AABB = AABB(
		Vector3(field_origin.x, -AABB_HEIGHT * 0.5, field_origin.y),
		Vector3(field_size.x, AABB_HEIGHT, field_size.y))
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

func _refresh_metadata() -> void:
	var file : FileAccess = FileAccess.open(field_json, FileAccess.READ)
	if(file == null):
		push_error("WindStreak: no metadata at %s" % field_json)
		return

	var parsed : Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if(typeof(parsed) != TYPE_DICTIONARY):
		push_error("WindStreak: %s is not valid json" % field_json)
		return

	field_origin = Vector2(parsed.get(META_ORIGIN_X, 0.0), parsed.get(META_ORIGIN_Z, 0.0))
	field_size = Vector2(parsed.get(META_SIZE_X, 1.0), parsed.get(META_SIZE_Z, 1.0))

# a .res holding the Image skips the import pipeline, which is the only route guaranteed to keep the float data and its sign
func _load_image(path : String) -> Image:
	if(ResourceLoader.exists(path)):
		return _image_from(load(path))

	return Image.load_from_file(path)

# the deserialise is the slow half and it never touches the gpu, so it runs on a worker while frames carry on
func _load_image_threaded(path : String) -> Image:
	if(!ResourceLoader.exists(path)):
		return Image.load_from_file(path)

	if(ResourceLoader.load_threaded_request(path) != OK):
		return _image_from(load(path))

	while(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS):
		await get_tree().process_frame

	return _image_from(ResourceLoader.load_threaded_get(path))

func _image_from(loaded : Resource) -> Image:
	if(loaded is Image):
		return loaded as Image
	if(loaded is Texture2D):
		return (loaded as Texture2D).get_image()

	return null

func _format_name(format : int) -> String:
	match format:
		Image.FORMAT_R8: return "R8"
		Image.FORMAT_RGB8: return "RGB8"
		Image.FORMAT_RGBA8: return "RGBA8"
		Image.FORMAT_RF: return "RF"
		Image.FORMAT_RGF: return "RGF"
		Image.FORMAT_RGBF: return "RGBF"
		Image.FORMAT_RGBAF: return "RGBAF"
		Image.FORMAT_RH: return "RH"
		Image.FORMAT_RGH: return "RGH"
		Image.FORMAT_RGBH: return "RGBH"
		Image.FORMAT_RGBAH: return "RGBAH"

	return "format %d" % format

# the push functions run from property setters during scene load, well before a material exists, so only an explicit apply reports the failure
func _shader_material(report : bool = false) -> ShaderMaterial:
	var material := process_material as ShaderMaterial
	if(material == null && report):
		push_error("WindStreak: process_material must be a ShaderMaterial using wind_particles.gdshader")

	return material
