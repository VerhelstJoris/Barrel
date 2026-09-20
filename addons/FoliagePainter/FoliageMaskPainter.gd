@tool
class_name FoliageMaskPainter extends Node3D

const MASK_FORMAT := Image.FORMAT_R8
const SAVE_EXTENSIONS := ["res", "tres", "png"]

# Saved mask asset; assigning one loads it into the paint buffer.
@export var mask: Texture2D:
	set(value):
		_mask = value
		_loaded = false
	get:
		return _mask

# Mask pixels along X; the Z resolution follows the world_size aspect.
@export var resolution: int:
	set(value):
		_resolution = maxi(64, value)
		_resample()
	get:
		return _resolution

@export var world_size := Vector2(2000.0, 2000.0):
	set(value):
		_world_size = value
		_resample()
	get:
		return _world_size

@export var save_path := "res://foliage_mask.res"
@export var overlay_color := Color(0.15, 1.0, 0.35, 1.0)
@export_range(0.0, 1.0) var overlay_opacity := 0.5

var _mask: Texture2D = null
var _resolution := 2048
var _world_size := Vector2(2000.0, 2000.0)
var _size := Vector2i.ZERO
var _buf := PackedByteArray()
var _image: Image = null
var _texture: ImageTexture = null
var _loaded := false

func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()

# Mask is centred on this node, so moving it moves the painted area.
# TODO: improve this to calculate this dynamically
func get_world_rect() -> Rect2:
	var centre := Vector2(global_position.x, global_position.z)
	return Rect2(centre - _world_size * 0.5, _world_size)

func get_texture() -> ImageTexture:
	_ensure_buffer()
	return _texture

# Terrain3D keys its region grid off the origin as a corner, so the mask rarely lines up by default.
func fit_to_terrain(terrain: Node) -> bool:
	if terrain == null or not terrain.is_class("Terrain3D"):
		return false
	var data = terrain.data
	if data == null:
		return false
	var locations: Array = []
	if data.has_method("get_region_locations"):
		locations = data.get_region_locations()
	elif data.has_method("get_region_offsets"):
		locations = data.get_region_offsets()
	if locations.is_empty():
		return false
	var span := float(terrain.region_size) * float(terrain.vertex_spacing)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for loc in locations:
		var p := Vector2(loc) * span
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x + span)
		mx.y = maxf(mx.y, p.y + span)
	global_position = Vector3((mn.x + mx.x) * 0.5, global_position.y, (mn.y + mx.y) * 0.5)
	world_size = mx - mn
	return true

func stamp(world_xz: Vector2, radius: float, hardness: float, strength: float, erase: bool) -> void:
	_ensure_buffer()
	var rect := get_world_rect()
	if radius <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var scale := Vector2(float(_size.x) / rect.size.x, float(_size.y) / rect.size.y)
	var c := (world_xz - rect.position) * scale
	var r := maxf(radius * scale.x, 0.5)
	var target := 0.0 if erase else 1.0
	var soft := maxf(1.0 - hardness, 0.001)
	var x0 := maxi(0, floori(c.x - r))
	var x1 := mini(_size.x - 1, ceili(c.x + r))
	var y0 := maxi(0, floori(c.y - r))
	var y1 := mini(_size.y - 1, ceili(c.y + r))
	for y in range(y0, y1 + 1):
		var row := y * _size.x
		var dy := float(y) + 0.5 - c.y
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - c.x
			var d := sqrt(dx * dx + dy * dy) / r
			if d >= 1.0:
				continue
			var a := clampf((1.0 - d) / soft, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var w := a * strength
			if w <= 0.0:
				continue
			var i := row + x
			var v := lerpf(float(_buf[i]) / 255.0, target, w)
			_buf[i] = int(round(clampf(v, 0.0, 1.0) * 255.0))

# Uploads the paint buffer to the GPU; call once per frame, not per stamp.
func flush() -> void:
	if not _loaded:
		return
	_image.set_data(_size.x, _size.y, false, MASK_FORMAT, _buf)
	_texture.update(_image)

func clear_mask() -> void:
	_ensure_buffer()
	_buf.fill(0)
	flush()

func save_mask() -> Error:
	if not Engine.is_editor_hint():
		return ERR_UNAVAILABLE
	var path := save_path.strip_edges()
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	# ResourceSaver reports ERR_FILE_UNRECOGNIZED for any extension it has no saver for.
	if not SAVE_EXTENSIONS.has(path.get_extension().to_lower()):
		path = path.get_basename() + ".res"
		save_path = path
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		var dir_err := DirAccess.make_dir_recursive_absolute(dir)
		if dir_err != OK:
			return dir_err
	_ensure_buffer()
	var img := Image.create_from_data(_size.x, _size.y, false, MASK_FORMAT, _buf)
	var err := OK
	if path.get_extension().to_lower() == "png":
		err = img.save_png(path)
	else:
		var tex := PortableCompressedTexture2D.new()
		tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		err = ResourceSaver.save(tex, path)
	if err != OK:
		return err
	EditorInterface.get_resource_filesystem().update_file(path)
	# Assign the backing var directly so the live buffer survives the save.
	_mask = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	notify_property_list_changed()
	return OK

func _target_size() -> Vector2i:
	var aspect := 1.0 if _world_size.x <= 0.0 else _world_size.y / _world_size.x
	return Vector2i(_resolution, maxi(1, roundi(float(_resolution) * aspect)))

# Image.convert() between single-channel formats averages RGB, so reinterpret the bytes instead.
func _to_mask_format(src: Image) -> Image:
	var fmt := src.get_format()
	if fmt == MASK_FORMAT:
		return src
	if fmt == Image.FORMAT_L8:
		return Image.create_from_data(src.get_width(), src.get_height(), false, MASK_FORMAT, src.get_data())
	if fmt != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var rgba := src.get_data()
	var count := src.get_width() * src.get_height()
	var red := PackedByteArray()
	red.resize(count)
	for i in count:
		red[i] = rgba[i * 4]
	return Image.create_from_data(src.get_width(), src.get_height(), false, MASK_FORMAT, red)

func _ensure_buffer() -> void:
	if _loaded:
		return
	_size = _target_size()
	var src: Image = null
	if _mask != null:
		src = _mask.get_image()
	if src != null and not src.is_empty():
		src = _to_mask_format(src.duplicate() as Image)
		if src.get_width() != _size.x or src.get_height() != _size.y:
			src.resize(_size.x, _size.y, Image.INTERPOLATE_BILINEAR)
		_image = src
	else:
		_image = Image.create_empty(_size.x, _size.y, false, MASK_FORMAT)
	_buf = _image.get_data()
	_texture = ImageTexture.create_from_image(_image)
	_loaded = true

func _resample() -> void:
	if not _loaded:
		return
	var new_size := _target_size()
	if new_size == _size:
		return
	var img := Image.create_from_data(_size.x, _size.y, false, MASK_FORMAT, _buf)
	img.resize(new_size.x, new_size.y, Image.INTERPOLATE_BILINEAR)
	_size = new_size
	_image = img
	_buf = _image.get_data()
	_texture = ImageTexture.create_from_image(_image)
