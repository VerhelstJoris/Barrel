@tool
class_name WorldSDFBaker extends Node3D

@export_tool_button("Bake Now", "Callable") var bake_height_action : Callable = _bake_sdf


@export_group("World")
@export var resolution : int = 2048
@export var region_size : Vector2i = Vector2i(2048, 2048)
@export var fit_sdf_to_terrain : bool = true
@export var world_padding : float = 0.0


@export_group("Output")
@export_dir var output_directory : String = "res://wind"
@export var output_name : String = "WorldSDF"
@export var half_precision_output : bool = true
@export var compress_output : bool = false

@export_group("Terrain")
@export var terrain_node : Terrain3D
@export var terrain_fallback_height : float = 0.0
@export var treat_holes_as_solid : bool = false
 
@export_group("Occluder Filtering")
@export var scan_root : Node3D
@export var min_height_above_terrain : float = 0.5
@export var occluder_height_band : float = 3.0
@export var include_classes : Array[String] = []
@export var exclude_classes : Array[String] = []
@export var force_include_nodes : Array[NodePath] = []
@export var force_exclude_nodes : Array[NodePath] = []
@export var use_mesh_triangles : bool = true
@export var max_triangles_per_mesh : int = 20000
 
const FAR_OFFSET : int = 20000
 
var _terrain_data : Object = null
var _height_grid : PackedFloat32Array = PackedFloat32Array()
var _hole_grid : PackedByteArray = PackedByteArray()
var _origin : Vector2 = Vector2.ZERO
var _texel_size : Vector2 = Vector2.ONE
 
var _stat_considered : int = 0
var _stat_included : int = 0
var _stat_below_threshold : int = 0
var _stat_filtered : int = 0
var _stat_triangles : int = 0
var _stat_no_data : int = 0
 
func _bake_sdf() -> void:
	if(!Engine.is_editor_hint()):
		return
	
	var started : int = Time.get_ticks_msec()
 
	if(resolution < 8):
		push_error("WindSDFBaker: resolution must be at least 8")
		return
 
	if(!_resolve_terrain_data()):
		return
 
	_resolve_region()
	_build_height_grid()
 
	var mask : PackedByteArray = PackedByteArray()
	mask.resize(resolution * resolution)
	_rasterise_occluders(mask)
 
	var field : PackedFloat32Array = _build_signed_field(mask)
	_save_field(field)
 
	print("WindSDFBaker: baked %dx%d in %d ms | considered %d, included %d, filtered %d, under height threshold %d, triangles %d, texels with no terrain data %d" % [
		resolution, resolution, Time.get_ticks_msec() - started,
		_stat_considered, _stat_included, _stat_filtered, _stat_below_threshold, _stat_triangles, _stat_no_data])
 
# Terrain3D moved its height data from storage to data in 1.0, so resolve whichever this project has rather than assuming
func _resolve_terrain_data() -> bool:
	_terrain_data = null
 
	if(terrain_node == null):
		push_error("WindSDFBaker: no terrain_node assigned")
		return false
 
	if(terrain_node.get("data") != null):
		_terrain_data = terrain_node.get("data")
	elif(terrain_node.get("storage") != null):
		_terrain_data = terrain_node.get("storage")
 
	if(_terrain_data == null || !_terrain_data.has_method("get_height")):
		push_error("WindSDFBaker: terrain_node is not a Terrain3D, or its data has not been assigned yet")
		return false
 
	return true
 
func _terrain_property(property : String, fallback : float) -> float:
	var value : Variant = terrain_node.get(property)
	if(value == null):
		return fallback
 
	return float(value)
 
# the region is anchored on this node so the bake follows wherever the baker sits in the level
func _resolve_region() -> void:
	var size : Vector2 = region_size
	var bounds : Rect2 = _terrain_bounds()
 
	if(fit_sdf_to_terrain && bounds.size.x > 0.0 && bounds.size.y > 0.0):
		_origin = bounds.position - Vector2(world_padding, world_padding)
		size = bounds.size + Vector2(world_padding, world_padding) * 2.0
	else:
		_origin = Vector2(global_position.x, global_position.z) - size * 0.5
 
	region_size = size
	_texel_size = size / float(resolution)
 
# Terrain3D is a Node3D with no AABB of its own, so world bounds come from the region grid scaled by region size and vertex spacing
func _terrain_bounds() -> Rect2:
	if(!_terrain_data.has_method("get_region_locations")):
		return Rect2()
 
	var locations : Array = _terrain_data.call("get_region_locations")
	if(locations.is_empty()):
		return Rect2()
 
	var region_extent : float = _terrain_property("region_size", 1024.0) * _terrain_property("vertex_spacing", 1.0)
	var bounds : Rect2 = Rect2(Vector2(locations[0]) * region_extent, Vector2(region_extent, region_extent))
 
	for location in locations:
		bounds = bounds.merge(Rect2(Vector2(location) * region_extent, Vector2(region_extent, region_extent)))
 
	return bounds
 
func _texel_to_world(x : int, y : int) -> Vector2:
	return _origin + Vector2((float(x) + 0.5) * _texel_size.x, (float(y) + 0.5) * _texel_size.y)
 
func _world_to_texel(world_x : float, world_z : float) -> Vector2:
	return Vector2((world_x - _origin.x) / _texel_size.x, (world_z - _origin.y) / _texel_size.y)
 
# terrain height is sampled once per texel up front, so the per triangle height tests are array lookups rather than repeated queries
func _build_height_grid() -> void:
	_height_grid.resize(resolution * resolution)
	_hole_grid.resize(resolution * resolution)
	_stat_no_data = 0
 
	for y in resolution:
		for x in resolution:
			var world : Vector2 = _texel_to_world(x, y)
			var index : int = y * resolution + x
			# get_height returns NAN over a hole and anywhere outside a defined region, so both need a fallback rather than propagating
			var height : float = _terrain_data.call("get_height", Vector3(world.x, 0.0, world.y))
 
			if(is_nan(height)):
				_stat_no_data += 1
				_height_grid[index] = terrain_fallback_height
				_hole_grid[index] = 1
			else:
				_height_grid[index] = height
				_hole_grid[index] = 0
 
func _height_at_texel(x : int, y : int) -> float:
	var cx : int = clampi(x, 0, resolution - 1)
	var cy : int = clampi(y, 0, resolution - 1)
	return _height_grid[cy * resolution + cx]
 
func _height_at_world(world_x : float, world_z : float) -> float:
	var texel : Vector2 = _world_to_texel(world_x, world_z)
	return _height_at_texel(int(floor(texel.x)), int(floor(texel.y)))
 
func _rasterise_occluders(mask : PackedByteArray) -> void:
	_stat_considered = 0
	_stat_included = 0
	_stat_below_threshold = 0
	_stat_filtered = 0
	_stat_triangles = 0
 
	if(treat_holes_as_solid):
		for i in mask.size():
			if(_hole_grid[i] != 0):
				mask[i] = 1
 
	var root : Node = scan_root if scan_root != null else get_tree().edited_scene_root
	if(root == null):
		root = get_parent()
	if(root == null):
		push_error("WindSDFBaker: no scan root to walk")
		return
 
	var forced_out : Array[Node] = _resolve_paths(force_exclude_nodes)
	var forced_in : Array[Node] = _resolve_paths(force_include_nodes)
 
	for node in _walk(root):
		if(node == self || forced_out.has(node)):
			continue
 
		# Terrain3D builds its mesh through the RenderingServer, but its instancer and any helper children are still nodes
		if(terrain_node != null && (node == terrain_node || terrain_node.is_ancestor_of(node))):
			continue
 
		var visual := node as VisualInstance3D
		if(visual == null):
			continue
 
		_stat_considered += 1
 
		if(!forced_in.has(node)):
			if(!_passes_filters(visual)):
				_stat_filtered += 1
				continue
			if(!_clears_terrain(visual)):
				_stat_below_threshold += 1
				continue
 
		_stat_included += 1
		_rasterise_visual(visual, mask)
 
func _walk(node : Node) -> Array[Node]:
	var found : Array[Node] = [node]
	for child in node.get_children():
		found.append_array(_walk(child))
	return found
 
func _resolve_paths(paths : Array[NodePath]) -> Array[Node]:
	var nodes : Array[Node] = []
	for path in paths:
		if(path.is_empty()):
			continue
		var node : Node = get_node_or_null(path)
		if(node != null):
			nodes.push_back(node)
	return nodes
 
func _passes_filters(visual : VisualInstance3D) -> bool:
	if(!include_classes.is_empty()):
		var matched : bool = false
		for class_name_entry in include_classes:
			if(visual.is_class(class_name_entry)):
				matched = true
				break
		if(!matched):
			return false
 
	for class_name_entry in exclude_classes:
		if(visual.is_class(class_name_entry)):
			return false
 
	return true
 
# anything that barely breaks the surface is scenery rather than an obstacle, so it never reaches the mask
func _clears_terrain(visual : VisualInstance3D) -> bool:
	var box : AABB = visual.global_transform * visual.get_aabb()
	var centre : Vector3 = box.get_center()
	return box.end.y - _height_at_world(centre.x, centre.z) >= min_height_above_terrain
 
func _rasterise_visual(visual : VisualInstance3D, mask : PackedByteArray) -> void:
	var mesh_instance := visual as MeshInstance3D
	if(use_mesh_triangles && mesh_instance != null && mesh_instance.mesh != null):
		var faces : PackedVector3Array = mesh_instance.mesh.get_faces()
		if(faces.size() >= 3 && faces.size() / 3 <= max_triangles_per_mesh):
			_rasterise_faces(faces, mesh_instance.global_transform, mask)
			return
 
	_rasterise_box(visual.global_transform * visual.get_aabb(), mask)
 
func _rasterise_faces(faces : PackedVector3Array, transform : Transform3D, mask : PackedByteArray) -> void:
	var index : int = 0
	while(index + 2 < faces.size()):
		var v0 : Vector3 = transform * faces[index]
		var v1 : Vector3 = transform * faces[index + 1]
		var v2 : Vector3 = transform * faces[index + 2]
		index += 3
 
		# geometry that sits entirely above the band ground level wind occupies does not block it, which is what lets wind pass under an arch
		var centre_x : float = (v0.x + v1.x + v2.x) / 3.0
		var centre_z : float = (v0.z + v1.z + v2.z) / 3.0
		var ground : float = _height_at_world(centre_x, centre_z)
		if(min(v0.y, v1.y, v2.y) > ground + occluder_height_band):
			continue
		if(max(v0.y, v1.y, v2.y) < ground - occluder_height_band):
			continue
 
		_stat_triangles += 1
		_rasterise_triangle(
			_world_to_texel(v0.x, v0.z),
			_world_to_texel(v1.x, v1.z),
			_world_to_texel(v2.x, v2.z),
			mask)
 
func _rasterise_triangle(a : Vector2, b : Vector2, c : Vector2, mask : PackedByteArray) -> void:
	var min_x : int = clampi(int(floor(min(a.x, b.x, c.x))), 0, resolution - 1)
	var max_x : int = clampi(int(ceil(max(a.x, b.x, c.x))), 0, resolution - 1)
	var min_y : int = clampi(int(floor(min(a.y, b.y, c.y))), 0, resolution - 1)
	var max_y : int = clampi(int(ceil(max(a.y, b.y, c.y))), 0, resolution - 1)
 
	var area : float = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if(absf(area) < 0.000001):
		return
 
	var inv_area : float = 1.0 / area
 
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var px : float = float(x) + 0.5
			var py : float = float(y) + 0.5
			var w0 : float = ((b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)) * inv_area
			var w1 : float = ((c.x - b.x) * (py - b.y) - (c.y - b.y) * (px - b.x)) * inv_area
			var w2 : float = ((a.x - c.x) * (py - c.y) - (a.y - c.y) * (px - c.x)) * inv_area
			if(w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0):
				mask[y * resolution + x] = 1
 
func _rasterise_box(box : AABB, mask : PackedByteArray) -> void:
	var start : Vector2 = _world_to_texel(box.position.x, box.position.z)
	var end : Vector2 = _world_to_texel(box.end.x, box.end.z)
 
	var min_x : int = clampi(int(floor(min(start.x, end.x))), 0, resolution - 1)
	var max_x : int = clampi(int(ceil(max(start.x, end.x))), 0, resolution - 1)
	var min_y : int = clampi(int(floor(min(start.y, end.y))), 0, resolution - 1)
	var max_y : int = clampi(int(ceil(max(start.y, end.y))), 0, resolution - 1)
 
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			mask[y * resolution + x] = 1
 
# outward distance minus inward distance, so the result is positive in open air and negative inside an obstacle
func _build_signed_field(mask : PackedByteArray) -> PackedFloat32Array:
	var outside : PackedFloat32Array = _distance_from(mask, 1)
	var inside : PackedFloat32Array = _distance_from(mask, 0)
 
	var field : PackedFloat32Array = PackedFloat32Array()
	field.resize(resolution * resolution)
	for i in field.size():
		field[i] = outside[i] - inside[i]
 
	return field
 
# 8SSEDT, two sweeps propagating the nearest seed offset, which lands within a fraction of a texel of the exact euclidean distance
func _distance_from(mask : PackedByteArray, seed_value : int) -> PackedFloat32Array:
	var count : int = resolution * resolution
	var dx : PackedInt32Array = PackedInt32Array()
	var dy : PackedInt32Array = PackedInt32Array()
	dx.resize(count)
	dy.resize(count)
 
	for i in count:
		if(int(mask[i]) == seed_value):
			dx[i] = 0
			dy[i] = 0
		else:
			dx[i] = FAR_OFFSET
			dy[i] = FAR_OFFSET
 
	for y in resolution:
		for x in resolution:
			var i : int = y * resolution + x
			if(x > 0):
				var j : int = i - 1
				var nx : int = dx[j] + 1
				var ny : int = dy[j]
				if(nx * nx + ny * ny < dx[i] * dx[i] + dy[i] * dy[i]):
					dx[i] = nx
					dy[i] = ny
			if(y > 0):
				var j : int = i - resolution
				var nx : int = dx[j]
				var ny : int = dy[j] + 1
				if(nx * nx + ny * ny < dx[i] * dx[i] + dy[i] * dy[i]):
					dx[i] = nx
					dy[i] = ny
			if(x > 0 && y > 0):
				var j : int = i - resolution - 1
				var nx : int = dx[j] + 1
				var ny : int = dy[j] + 1
				if(nx * nx + ny * ny < dx[i] * dx[i] + dy[i] * dy[i]):
					dx[i] = nx
					dy[i] = ny
			if(x < resolution - 1 && y > 0):
				var j : int = i - resolution + 1
				var nx : int = dx[j] - 1
				var ny : int = dy[j] + 1
				if(nx * nx + ny * ny < dx[i] * dx[i] + dy[i] * dy[i]):
					dx[i] = nx
					dy[i] = ny
 
	for y in range(resolution - 1, -1, -1):
		for x in range(resolution - 1, -1, -1):
			var i : int = y * resolution + x
			if(x < resolution - 1):
				var j : int = i + 1
				var nx : int = dx[j] - 1
				var ny : int = dy[j]
				if(nx * nx + ny * ny < dx[i] * dx[i] + dy[i] * dy[i]):
					dx[i] = nx
					dy[i] = ny
			if(y < resolution - 1):
				var j : int = i + resolution
				var nx : int = dx[j]
				var ny : int = dy[j] - 1
				if(nx * nx + ny * ny < dx[i] * dx[i] + dy[i] * dy[i]):
					dx[i] = nx
					dy[i] = ny
			if(x < resolution - 1 && y < resolution - 1):
				var j : int = i + resolution + 1
				var nx : int = dx[j] - 1
				var ny : int = dy[j] - 1
				if(nx * nx + ny * ny < dx[i] * dx[i] + dy[i] * dy[i]):
					dx[i] = nx
					dy[i] = ny
			if(x > 0 && y < resolution - 1):
				var j : int = i + resolution - 1
				var nx : int = dx[j] + 1
				var ny : int = dy[j] - 1
				if(nx * nx + ny * ny < dx[i] * dx[i] + dy[i] * dy[i]):
					dx[i] = nx
					dy[i] = ny
 
	var metres_per_texel : float = (_texel_size.x + _texel_size.y) * 0.5
	var out : PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = sqrt(float(dx[i] * dx[i] + dy[i] * dy[i])) * metres_per_texel
 
	return out
 
# distances are stored raw in metres, which needs a float format, so the companion json carries the world mapping a sampler needs
func _save_field(field : PackedFloat32Array) -> void:
	var image : Image = Image.create_from_data(resolution, resolution, false, Image.FORMAT_RF, field.to_byte_array())
	var base_path : String = output_directory.path_join(output_name)
 
	var error : int = image.save_exr(base_path + ".exr", true)
	if(error != OK):
		push_error("WindSDFBaker: failed to write %s.exr (error %d)" % [base_path, error])
		return

	if(!_save_runtime_image(image, base_path)):
		return

	var meta : Dictionary = {
		"resolution": resolution,
		"origin_x": _origin.x,
		"origin_z": _origin.y,
		"size_x": region_size.x,
		"size_z": region_size.y,
		"metres_per_texel_x": _texel_size.x,
		"metres_per_texel_z": _texel_size.y,
	}
 
	var file : FileAccess = FileAccess.open(base_path + ".json", FileAccess.WRITE)
	if(file != null):
		file.store_string(JSON.stringify(meta, "\t"))
		file.close()
 
	if(Engine.is_editor_hint()):
		EditorInterface.get_resource_filesystem().scan()

# an Image inside a .res never touches the import pipeline, which is both what keeps the float data and its sign and what avoids an exr decode costing seconds at this size
# half float is the format to ship, since its steps stay far finer than a texel at every distance the steering actually reads
func _save_runtime_image(image : Image, base_path : String) -> bool:
	var runtime_image : Image = image
	if(half_precision_output):
		runtime_image = image.duplicate() as Image
		runtime_image.convert(Image.FORMAT_RH)

	var flags : int = ResourceSaver.FLAG_COMPRESS if compress_output else ResourceSaver.FLAG_NONE
	var error : int = ResourceSaver.save(runtime_image, base_path + ".res", flags)
	if(error != OK):
		push_error("WindSDFBaker: failed to write %s.res (error %d)" % [base_path, error])
		return false

	print("WindSDFBaker: wrote %s.res as %s, %s on disk | point field_image at this rather than the exr" % [
		base_path,
		"RH" if half_precision_output else "RF",
		String.humanize_size(_file_size(base_path + ".res"))])

	return true

func _file_size(path : String) -> int:
	var file : FileAccess = FileAccess.open(path, FileAccess.READ)
	if(file == null):
		return 0

	var length : int = file.get_length()
	file.close()
	return length
