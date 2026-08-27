@tool
class_name FoliageWorldSettings extends Resource

@export_group("World")
## Side length of the whole world in metres. Must be a multiple of chunk size.
@export var world_size_m : float = 2048.0
## World XZ of the world's minimum corner.
@export var world_origin_xz : Vector2 = Vector2.ZERO
## Side length of one chunk in metres. Only used for the coarse gate now.
@export var chunk_dimension_size_m : float = 256.0

@export_group("Shaders")
@export var positions_compute_shader : RDShaderFile
@export var transfer_compute_shader : RDShaderFile
@export var bender_compute_shader : RDShaderFile

@export_group("Meshes and Materials")
@export var foliage_mesh_high_LOD : Mesh
@export var foliage_mesh_low_LOD : Mesh
@export var foliage_material : Material

@export_group("Budgets")
# High LOD dispatch shape. One work group handles one segment, so
# x * y is the high LOD segment budget.
@export var high_lod_num_work_groups : Vector2i = Vector2i(16, 16)
# Total segments the low LOD tier may cover.
@export var low_lod_segment_budget : int = 4096

@export_group("Fine Fill Window")
# Side length of the segment fill window in cells. Rounded up to even.
# Must comfortably exceed the radius the budget can actually cover, or the window clips the fill before the budget does.
@export var fine_window_cells : int = 160
# Constraints are dilated outward by this many cells, so a cell counts as visible if any part of it is in view rather than only its centre.
@export var view_edge_pad_cells : float = 1.0
# The frustum is clipped to a horizontal plane at the camera's ground height. This band lets a rise poke into view without being clipped away. 
@export var view_terrain_relief_m : float = 20.0

@export_group("Rotation Latency")
## How many frames the visible transforms lag the camera. The fill covers where
## the camera will be pointing this far ahead, so a fast turn does not outrun
## it. Roughly: 1 for single-threaded rendering, 2-3 for multi-threaded.
## Set to 0 to disable prediction entirely.
@export_range(0.0, 5.0, 0.25) var rotation_lead_frames : float = 2.0
## Ceiling on the predicted turn, so a snap or teleport cannot widen the filled
## region so far that the budget is spread uselessly thin.
@export_range(0.0, 90.0, 1.0) var rotation_lead_max_degrees : float = 40.0
## Process order for FoliageWorld. Higher runs later in the frame, so keep this
## above whatever moves your camera or the snapshot samples a stale transform.
@export var process_priority : int = 100

@export_group("Placement")
@export var target_density_sq_m_high_LOD : float = 16.0
@export var target_density_sq_m_low_LOD : float = 1.0
@export var max_foliage_individual_random_offset : float = 0.5
@export var max_foliage_tilt_degrees : float = 20.0
@export var foliage_cam_bias_degress_near_far : Vector2 = Vector2(0.0, 45.0)
@export var foliage_cam_bias_min_distance : float = 12.0
@export var min_grass_blade_scale : float = 0.5
@export var blade_width_far_mult : float = 2.0
@export var culling_distance_thresholds : Vector3 = Vector3(10.0, 25.0, 40.0)

@export_group("Terrain Material Link")
# link the material on the terrain to the foliage so the same shader settings will be pushed out to it
@export var link_terrain_material : bool = true

@export_group("Mask")
# Single world-wide placement mask. No slicing needed any more 
@export var global_mask : Texture2D
## Mask texels per metre. 1.0 over a 2 km world is a 2048x2048 R8, about 4 MB.
@export var mask_texels_per_m : float = 1.0

@export_group("Bend Window")
## Side length in metres of the player-following bend window. Size this to the
## distance bending is actually legible at, not to the terrain.
@export var bend_window_size_m : float = 64.0
## Resolution of the bend accumulator. MUST be a power of two -- the toroidal
## wrap uses a bitmask rather than a modulo, since GLSL integer % is undefined
## for negative operands.
@export var bend_mask_res : int = 1024
@export var unbend_rate_per_second : float = 1.5
## Vertical slack above and below the local terrain for the bend camera.
@export var bend_camera_vertical_padding : float = 10.0
@export var bend_flip_source_x : bool = true
@export var bend_flip_source_z : bool = true


# --- derived -------------------------------------------------------------

func high_segment_budget() -> int:
	return maxi(high_lod_num_work_groups.x * high_lod_num_work_groups.y, 1)


func total_segment_budget() -> int:
	return high_segment_budget() + maxi(low_lod_segment_budget, 0)


func instances_per_segment_high(cell_size : float) -> int:
	return maxi(int(target_density_sq_m_high_LOD * cell_size * cell_size), 1)


func instances_per_segment_low(cell_size : float) -> int:
	return maxi(int(target_density_sq_m_low_LOD * cell_size * cell_size), 1)


func world_cells_per_dim(cell_size : float) -> int:
	return int(round(world_size_m / cell_size))


func chunks_per_dim() -> int:
	return maxi(int(round(world_size_m / chunk_dimension_size_m)), 1)


func bend_texels_per_m() -> float:
	return float(bend_mask_res) / bend_window_size_m

func bend_flip_bits() -> int:
	return (1 if bend_flip_source_x else 0) | (2 if bend_flip_source_z else 0)

func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if bend_mask_res & (bend_mask_res - 1) != 0:
		problems.append("bend_mask_res (%d) must be a power of two." % bend_mask_res)
	if not positions_compute_shader or not transfer_compute_shader or not bender_compute_shader:
		problems.append("One or more compute shaders are unassigned.")
	if not foliage_mesh_high_LOD or not foliage_mesh_low_LOD:
		problems.append("One or more foliage meshes are unassigned.")
	if not global_mask:
		problems.append("global_mask is unassigned.")
	if absf(world_size_m / chunk_dimension_size_m - float(chunks_per_dim())) > 0.001:
		problems.append("world_size_m is not a whole multiple of chunk_dimension_size_m.")
	if(foliage_material == null):
		problems.append("foliage material is unassigned.")
	return problems
