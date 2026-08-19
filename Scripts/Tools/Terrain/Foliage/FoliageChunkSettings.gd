class_name FoliageChunkSettings extends Resource

@export var chunk_dimenstion_size_m : float = 200.0

@export_group("Shaders")
@export var positions_compute_shader : RDShaderFile
@export var transfer_compute_shader : RDShaderFile
@export var bender_compute_shader : RDShaderFile

@export_group("High LOD")
@export var target_density_sq_m_high_LOD : float = 80
@export var distance_thresholds_high_lod : Vector3 = Vector3(8,16,32)
@export var foliage_mesh_high_LOD : Mesh
@export var foliage_material_high_LOD :Material
@export var high_lod_num_work_groups : Vector2i = Vector2i(8,8)

@export_group("Low LOD")
@export var target_density_sq_m_low_LOD : float = 10
@export var distance_thresholds_low_lod : Vector3 = Vector3(32,32,32)
@export var foliage_mesh_low_LOD : Mesh
@export var foliage_material_low_LOD :Material

@export_group("Lowest LOD")
@export var foliage_lowest_LOD_material : Material
@export var foliage_lowest_LOD_mesh_offset : float = 1.0
@export var foliage_lowest_LOD_distance_activation : float = 250.0 

@export_group("Foliage Bending")
@export var bender_mask_res : int = 512
@export var unbend_rate_per_second : float = 0.05

@export_group("Customizable Parameters")
@export var max_foliage_individual_random_offset : float = 0.2
@export var foliage_cam_bias_degress_near_far : Vector2 = Vector2(30.0, 70.0)
@export var max_foliage_tilt_degrees : float = 15.0

# In ascending order, at what distances from the player should a segment of grass blades draw 1/2/3 blades less per 4
@export var min_grass_blade_scale : float = 0.2
