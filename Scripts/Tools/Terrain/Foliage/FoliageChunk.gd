@tool
class_name FoliageChunk extends Node3D

@export_tool_button("Generate Terrain Mesh Copy", "Callable") var generate_mesh_action : Callable = generate_terrain_copy
@export_tool_button("Toggle Lowest LOD Mesh", "Callable") var toggle_mesh_action : Callable = toggle_mesh

@export_group("Setup")
## The manager this chunk registers with. Leave empty to search ancestors.
@export var foliage_world : FoliageWorld
## Clear this to carve out a chunk with no foliage (water, town, road). The
## fill still propagates through it -- it just does not emit there.
@export var foliage_enabled : bool = true:
	set(value):
		foliage_enabled = value
		if foliage_world and is_inside_tree():
			foliage_world.register_chunk(self)

@export_group("Lowest LOD")
@export var foliage_lowest_LOD_mesh : MeshInstance3D
@export var visibility_notifier : VisibleOnScreenNotifier3D

@export_group("Runtime Data - DO NOT EDIT MANUALLY")
@export var local_aabb : AABB = AABB()


func _ready() -> void:
	if not foliage_world:
		foliage_world = _find_world()
	if foliage_world:
		foliage_world.register_chunk(self)
		foliage_lowest_LOD_mesh.visible = true
	else:
		push_warning("FoliageChunk at %s found no FoliageWorld." % str(global_position))


func _exit_tree() -> void:
	if foliage_world:
		foliage_world.unregister_chunk(self)


func _find_world() -> FoliageWorld:
	var node : Node = get_parent()
	while node:
		if node is FoliageWorld:
			return node
		node = node.get_parent()
	return null


# ==========================================================================
# TOOLING
# ==========================================================================

func chunk_size() -> float:
	if foliage_world and foliage_world.settings_DA:
		return foliage_world.settings_DA.chunk_dimension_size_m
	return 256.0


# Builds the lowest LOD terrain copy from the manager's baked global height map
# rather than re-sampling the terrain per chunk. One source of truth, and the
# mesh lines up exactly with what the compute shader places grass on.
func generate_terrain_copy() -> void:
	if not foliage_world:
		foliage_world = _find_world()
	if not foliage_world or not foliage_world.height_map or not foliage_world.height_map.is_valid():
		push_error("FoliageChunk: bake the global height map on FoliageWorld first.")
		return

	var map : FoliageHeightMap = foliage_world.height_map
	var size_m : float = chunk_size()
	var cells : int = int(round(size_m / map.cell_size))
	var verts : int = cells + 1

	var base : Vector2 = Vector2(global_position.x, global_position.z) - Vector2.ONE * (size_m * 0.5)
	var base_vertex := Vector2i(
		int(round((base.x - map.origin.x) / map.cell_size)),
		int(round((base.y - map.origin.y) / map.cell_size)))

	var heights := PackedFloat32Array()
	heights.resize(verts * verts)

	var min_h : float = INF
	var max_h : float = -INF
	for row in verts:
		for col in verts:
			var h : float = map.height_at_vertex(base_vertex.x + row, base_vertex.y + col)
			heights[row * verts + col] = h
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)

	var mesh : Mesh = FoliageMeshBuilder.build_mesh(
		heights, verts, map.cell_size, Vector2(-size_m * 0.5, -size_m * 0.5))

	if mesh and foliage_lowest_LOD_mesh:
		if foliage_world.settings_DA and foliage_world.settings_DA.foliage_lowest_LOD_material:
			mesh.surface_set_material(0, foliage_world.settings_DA.foliage_lowest_LOD_material)
		foliage_lowest_LOD_mesh.mesh = mesh
		if foliage_world.settings_DA:
			foliage_lowest_LOD_mesh.position.y = foliage_world.settings_DA.foliage_lowest_LOD_mesh_offset

	const PAD : float = 5.0
	local_aabb = AABB(
		Vector3(-size_m * 0.5 - PAD * 0.5, min_h - PAD, -size_m * 0.5 - PAD * 0.5),
		Vector3(size_m + PAD, (max_h - min_h) + PAD * 2.0, size_m + PAD))

	if visibility_notifier:
		visibility_notifier.aabb = local_aabb


func toggle_mesh() -> void:
	if foliage_lowest_LOD_mesh:
		foliage_lowest_LOD_mesh.visible = not foliage_lowest_LOD_mesh.visible
