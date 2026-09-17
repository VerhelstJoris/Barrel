class_name ImGuiDrawSDF

# cached per path pair, because decoding the image and building the preview are both full passes over every texel
static var _cache : Dictionary = {}

class Field extends RefCounted:
	var resolution : int = 0
	var origin : Vector2 = Vector2.ZERO
	var world_size : Vector2 = Vector2.ONE
	var texel_size : Vector2 = Vector2.ONE
	var values : PackedFloat32Array = PackedFloat32Array()

	var texture : ImageTexture = null
	var status : String = ""
	var min_value : float = 0.0
	var max_value : float = 0.0
	var inside_texels : int = 0

	var display_size : Array = [512.0]
	var max_distance : Array = [20.0]
	var band_spacing : Array = [5.0]

	func is_loaded() -> bool:
		return !values.is_empty()
		
		
# split out so the same readout can be dropped inside a window the caller already opened
static func _draw_sdf_contents(json_path : String, image_path : String, tracked : Node3D = null) -> void:
	var field : Field = _get_field(json_path, image_path)

	if(!field.is_loaded()):
		ImGui.Text(field.status if !field.status.is_empty() else "no field loaded")
		if(ImGui.Button("Reload")):
			clear_cache(json_path, image_path)
		return

	_draw_header(field)
	ImGui.Separator()
	_draw_controls(field, json_path, image_path)
	ImGui.Separator()
	_draw_map(field, tracked)
	ImGui.Separator()
	_draw_legend(field)

static func sample(json_path : String, image_path : String, world_x : float, world_z : float) -> float:
	return _sample(_get_field(json_path, image_path), world_x, world_z)

static func clear_cache(json_path : String = "", image_path : String = "") -> void:
	if(json_path.is_empty() && image_path.is_empty()):
		_cache.clear()
		return

	_cache.erase(_cache_key(json_path, image_path))

static func _cache_key(json_path : String, image_path : String) -> String:
	return json_path + "|" + image_path

static func _get_field(json_path : String, image_path : String) -> Field:
	var key : String = _cache_key(json_path, image_path)
	if(_cache.has(key)):
		return _cache[key]

	var field : Field = _load_field(json_path, image_path)
	_cache[key] = field
	return field

static func _load_field(json_path : String, image_path : String) -> Field:
	var field : Field = Field.new()

	if(!_load_metadata(field, json_path)):
		return field

	var image : Image = _load_image(image_path)
	if(image == null):
		field.status = "no image could be loaded from %s" % image_path
		return field

	if(!_is_float_format(image.get_format())):
		field.status = "format %d is not floating point, so distances inside obstacles have lost their sign" % image.get_format()

	if(image.get_format() != Image.FORMAT_RF):
		image = image.duplicate() as Image
		image.convert(Image.FORMAT_RF)

	field.resolution = image.get_width()
	field.values = image.get_data().to_float32_array()

	if(field.values.size() != field.resolution * image.get_height()):
		field.status = "decoded %d values for a %dx%d image" % [field.values.size(), field.resolution, image.get_height()]
		field.values.clear()
		return field

	_measure(field)
	_rebuild_texture(field)
	return field

# the json carries the world mapping, without which the texture is a grid of numbers with no position in the level
static func _load_metadata(field : Field, json_path : String) -> bool:
	var file : FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if(file == null):
		field.status = "no metadata at %s" % json_path
		return false

	var parsed : Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if(typeof(parsed) != TYPE_DICTIONARY):
		field.status = "%s is not valid json" % json_path
		return false

	field.origin = Vector2(parsed.get("origin_x", 0.0), parsed.get("origin_z", 0.0))
	field.world_size = Vector2(parsed.get("size_x", 1.0), parsed.get("size_z", 1.0))
	field.texel_size = Vector2(parsed.get("metres_per_texel_x", 1.0), parsed.get("metres_per_texel_z", 1.0))
	return true

# an exr in res:// comes back as whatever the importer produced, so a Texture2D has to be unpacked and a raw file is the last resort
static func _load_image(image_path : String) -> Image:
	if(ResourceLoader.exists(image_path)):
		var loaded : Resource = load(image_path)
		if(loaded is Image):
			return loaded as Image
		if(loaded is Texture2D):
			return (loaded as Texture2D).get_image()

	return Image.load_from_file(image_path)

static func _is_float_format(format : int) -> bool:
	return format == Image.FORMAT_RF || format == Image.FORMAT_RH \
		|| format == Image.FORMAT_RGF || format == Image.FORMAT_RGH \
		|| format == Image.FORMAT_RGBF || format == Image.FORMAT_RGBH \
		|| format == Image.FORMAT_RGBAF || format == Image.FORMAT_RGBAH

# a field with no negative texels means nothing was ever rasterised, which is the failure most likely to look plausible as an image
static func _measure(field : Field) -> void:
	field.min_value = field.values[0]
	field.max_value = field.values[0]
	field.inside_texels = 0

	for value in field.values:
		field.min_value = minf(field.min_value, value)
		field.max_value = maxf(field.max_value, value)
		if(value < 0.0):
			field.inside_texels += 1

static func _texel(field : Field, x : int, y : int) -> float:
	var cx : int = clampi(x, 0, field.resolution - 1)
	var cy : int = clampi(y, 0, field.resolution - 1)
	return field.values[cy * field.resolution + cx]

static func _sample(field : Field, world_x : float, world_z : float) -> float:
	if(!field.is_loaded()):
		return 0.0

	var u : float = (world_x - field.origin.x) / field.texel_size.x - 0.5
	var v : float = (world_z - field.origin.y) / field.texel_size.y - 0.5
	var x0 : int = floori(u)
	var y0 : int = floori(v)
	var fx : float = u - float(x0)
	var fy : float = v - float(y0)

	var top : float = lerpf(_texel(field, x0, y0), _texel(field, x0 + 1, y0), fx)
	var bottom : float = lerpf(_texel(field, x0, y0 + 1), _texel(field, x0 + 1, y0 + 1), fx)
	return lerpf(top, bottom, fy)

# the gradient points away from the nearest surface, so a normal that is not perpendicular to the wall under the cursor means the field is misaligned with the world
static func _sample_normal(field : Field, world_x : float, world_z : float) -> Vector2:
	if(!field.is_loaded()):
		return Vector2.ZERO

	var gradient : Vector2 = Vector2(
		_sample(field, world_x + field.texel_size.x, world_z) - _sample(field, world_x - field.texel_size.x, world_z),
		_sample(field, world_x, world_z + field.texel_size.y) - _sample(field, world_x, world_z - field.texel_size.y))

	if(gradient.length_squared() < 0.000001):
		return Vector2.ZERO

	return gradient.normalized()

# a full CPU pass over every texel, so it only runs on load and when a parameter that changes the image actually moves
static func _rebuild_texture(field : Field) -> void:
	field.texture = null
	if(!field.is_loaded()):
		return

	var bytes : PackedByteArray = PackedByteArray()
	bytes.resize(field.values.size() * 3)

	for i in field.values.size():
		var colour : Color = _debug_colour(field, field.values[i])
		bytes[i * 3] = int(colour.r * 255.0)
		bytes[i * 3 + 1] = int(colour.g * 255.0)
		bytes[i * 3 + 2] = int(colour.b * 255.0)

	var image : Image = Image.create_from_data(field.resolution, field.resolution, false, Image.FORMAT_RGB8, bytes)
	field.texture = ImageTexture.create_from_image(image)

# raw metres would clip to white nearly everywhere, so inside and outside get separate ramps and contour bands make the falloff readable
static func _debug_colour(field : Field, distance : float) -> Color:
	if(absf(distance) < field.texel_size.x):
		return Color(1.0, 0.95, 0.2)

	var magnitude : float = clampf(absf(distance) / maxf(field.max_distance[0], 0.001), 0.0, 1.0)
	var colour : Color
	if(distance < 0.0):
		colour = Color(0.85, 0.2, 0.2).lerp(Color(0.2, 0.0, 0.0), magnitude)
	else:
		colour = Color(0.1, 0.2, 0.45).lerp(Color(0.85, 0.92, 1.0), magnitude)

	if(field.band_spacing[0] > 0.0 && fposmod(absf(distance), field.band_spacing[0]) / field.band_spacing[0] < 0.08):
		colour = colour.darkened(0.35)

	return colour

static func _draw_header(field : Field) -> void:
	ImGui.Text("%d x %d texels | %.1f x %.1f m | %.2f m per texel" % [
		field.resolution, field.resolution, field.world_size.x, field.world_size.y, field.texel_size.x])
	ImGui.Text("origin %.1f, %.1f | range %.2f to %.2f m | %d texels inside obstacles" % [
		field.origin.x, field.origin.y, field.min_value, field.max_value, field.inside_texels])

	if(field.inside_texels == 0):
		ImGui.Text("nothing was rasterised, every texel reads as open air")
	if(!field.status.is_empty()):
		ImGui.Text(field.status)

static func _draw_controls(field : Field, json_path : String, image_path : String) -> void:
	var dirty : bool = false
	if(ImGui.SliderFloat("Max distance", field.max_distance, 1.0, 200.0)):
		dirty = true
	if(ImGui.SliderFloat("Band spacing", field.band_spacing, 0.0, 50.0)):
		dirty = true

	ImGui.SliderFloat("Display size", field.display_size, 128.0, 1024.0)

	if(ImGui.Button("Rebuild preview")):
		dirty = true
	ImGui.SameLine()
	if(ImGui.Button("Reload field")):
		clear_cache(json_path, image_path)
		return

	if(dirty):
		_rebuild_texture(field)

static func _draw_map(field : Field, tracked : Node3D) -> void:
	if(field.texture == null):
		ImGui.Text("preview texture failed to build")
		return

	var size : float = field.display_size[0]
	ImGui.Image(field.texture, Vector2(size, size))

	var rect_min : Vector2 = ImGui.GetItemRectMin()
	_draw_marker(field, tracked, rect_min, size)

	if(!ImGui.IsItemHovered()):
		ImGui.Text("hover the map for a readout")
		return

	# the image is drawn with its origin top left and the bake walks texels in the same order, so uv maps straight onto world XZ
	var uv : Vector2 = (ImGui.GetMousePos() - rect_min) / size
	var world : Vector2 = field.origin + uv * field.world_size
	var distance : float = _sample(field, world.x, world.y)
	var normal : Vector2 = _sample_normal(field, world.x, world.y)

	ImGui.Text("world    %.1f, %.1f" % [world.x, world.y])
	ImGui.Text("distance %.2f m%s" % [distance, "  (inside)" if distance < 0.0 else ""])
	ImGui.Text("normal   %.2f, %.2f" % [normal.x, normal.y])

static func _draw_marker(field : Field, tracked : Node3D, rect_min : Vector2, size : float) -> void:
	if(tracked == null):
		return

	var position : Vector2 = Vector2(tracked.global_position.x, tracked.global_position.z)
	var uv : Vector2 = (position - field.origin) / field.world_size

	if(uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0):
		ImGui.Text("%s is outside the baked region" % tracked.name)
		return

	var draw_list = ImGui.GetWindowDrawList()
	if(draw_list != null):
		var screen : Vector2 = rect_min + uv * size
		draw_list.AddCircleFilled(screen, 4.0, Color(0.1, 1.0, 0.3).to_abgr32())
		draw_list.AddCircle(screen, 6.0, Color.BLACK.to_abgr32())

	ImGui.Text("%s at %.1f, %.1f reads %.2f m" % [
		tracked.name, position.x, position.y, _sample(field, position.x, position.y)])

static func _draw_legend(field : Field) -> void:
	ImGui.Text("yellow  obstacle outline, distance zero")
	ImGui.Text("red     inside an obstacle, darker is deeper")
	ImGui.Text("blue    open air, brighter is further from anything")
	ImGui.Text("bands   every %.1f m" % field.band_spacing[0])
