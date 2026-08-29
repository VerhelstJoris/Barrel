@tool
class_name FoliageWorld extends Node3D

# Single owner of every foliage GPU resource in the scene.

const height_bake_vertical_slack : float = 1.0

# grass material uniforms
# Bare uniform names. ShaderMaterial.set() wants them prefixed; RenderingServer
# and Terrain3DMaterial want them bare, hence both forms.
const shader_param_prefix : String = "shader_parameter/"
const foliage_shader_blade_shaping : String = "enable_blade_shaping"
const foliage_shader_lod_divide : String = "enable_LOD_divide"
const foliage_shader_bend_mask : String = "bending_mask"
const foliage_shader_bend_origin_texel : String = "bend_window_origin_texel"
const foliage_shader_bend_res : String = "bend_res"
const foliage_shader_bend_texels_per_m : String = "bend_texels_per_m"
const foliage_shader_placement_mask : String = "foliage_placement_mask"
const foliage_shader_world_origin_xz : String = "foliage_world_origin_xz"
const foliage_shader_world_size_m : String = "foliage_world_size_m"
const foliage_shader_frontier_radius : String = "foliage_frontier_radius_m"

@export_tool_button("Bake Global Height Map", "Callable") var bake_height_action : Callable = _generate_height_data
@export_tool_button("Validate Setup", "Callable") var validate_action : Callable = _DEBUG_print_validation

# used to copy parameters over from the foliage material onto the terrain
@export_tool_button("Copy Shader Properties Onto Terrain", "Callable") var grass_shader_props_action : Callable = _assign_terrain_shader_properties
@export_group("Shader Property Manager")
@export var foliage_param_name : String = "foliage_"
@export var exempt_param_names : PackedStringArray = [
	"foliage_frontier_radius_m",
	"foliage_placement_mask",
	"foliage_world_origin_xz",
	"foliage_world_size_m",
	]



@export_tool_button("Diagnose Empty Fill", "Callable") var diagnose_action : Callable = _DEBUG_print_diagnosis

@export_group("Setup")
@export var settings_DA : FoliageWorldSettings
@export var height_map : FoliageHeightMap
@export var terrain_node : Terrain3D
@export var inverse_terrain_node : Terrain3D

@export_group("Bend Window")
@export var bender_mask_subviewport : SubViewport
@export var bender_mask_camera : Camera3D

@export_group("Bake Output")
@export_global_file("*.res") var height_map_save_path : String = "res://foliage_height_map.res"

# --- fill ----------------------------------------------------------------

var fill_grid : FoliageFillGrid
var vertex_spacing : float = 4.0

var player_transform_data_arr : PackedByteArray
var bend_float_param_arr : PackedByteArray
var active_segment_count_arr : PackedByteArray		# scratch for the per-frame active count
var DEBUG_head_segment_coords : PackedInt32Array	# first few drained global cells

var previous_camera_forward_flat : Vector2 = Vector2.ZERO
var current_yaw_rate : float = 0.0					# rad/s, signed, lightly smoothed
var current_predicted_yaw : float = 0.0

# --- bend window ---------------------------------------------------------

var current_bender_origin_texel : Vector2i = Vector2i.ZERO
var previous_bender_origin_texel : Vector2i = Vector2i.ZERO
var created_bender_image_RID : RID
var created_bender_tex_RD : Texture2DRD
var bender_subviewport_tex_RID : RID		# cached on the main thread, resolved on the render thread

# --- render device state -------------------------------------------------

var rd : RenderingDevice
var RID_arr : Array[RID] = []
var scenario_RID : RID

var compute_pos_shader_RID : RID
var transfer_shader_RID : RID
var bender_shader_RID : RID

var mm_pipeline_pos_calc_RID : RID
var mm_pipeline_pos_transfer_RID : RID
var pipeline_bender_RID : RID

var mm_high_uniform_set_pos_calc_RID : RID
var mm_low_uniform_set_pos_calc_RID : RID
var mm_high_uniform_set_pos_transfer_RID : RID
var mm_low_uniform_set_pos_transfer_RID : RID
var uniform_set_bender_RID : RID

var mm_high_RID : RID
var mm_high_instance_RID : RID
var mm_high_sparse_transform_buffer_rid : RID
var mm_high_packed_transform_buffer_rid : RID
var mm_high_command_buffer_rid : RID
var mm_high_instance_count_buffer_rid : RID

var mm_low_RID : RID
var mm_low_instance_RID : RID
var mm_low_sparse_transform_buffer_rid : RID
var mm_low_packed_transform_buffer_rid : RID
var mm_low_command_buffer_rid : RID
var mm_low_instance_count_buffer_rid : RID

var height_data_RID : RID
var segment_coord_data_mm_buffer_rid : RID
var iparameter_mm_high_buffer_rid : RID
var iparameter_mm_low_buffer_rid : RID
var player_transform_data_mm_high_buffer_rid : RID
var fparameter_buffer_bend_RID : RID
var foliage_mask_RID : RID
var current_bender_data_tex_RID : RID

var chunk_material_high_LOD_inst : Material
var chunk_material_low_LOD_inst : Material

var initialized : bool = false

# stats, handy on an overlay
var segments_filled : int = 0
var high_segments_drawn : int = 0
var low_segments_drawn : int = 0
var frontier_radius_m : float = 0.0

var DEBUG_reported_idle : bool = false

var terrain_material_linked : bool = false

# ==========================================================================
# LIFECYCLE
# ==========================================================================

func _ready() -> void:
	if not _verify_assignments():
		return

	var problems : PackedStringArray = settings_DA.validate()
	for p in problems:
		push_warning("FoliageWorld: " + p)

	# Run after gameplay and camera scripts, so the snapshot is this frame's
	# camera rather than last frame's. Higher priority means later in Godot.
	process_priority = settings_DA.process_priority
	vertex_spacing = _get_vertex_spacing()
	_intialize_segments_data()
	_initialize_bender_data()

	if Engine.is_editor_hint():
		return

	if not height_map or not height_map.is_valid():
		push_error("FoliageWorld: no baked height map. Run 'Bake Global Height Map'.")
		return

	RenderingServer.call_on_render_thread(_cleanup)
	RenderingServer.call_on_render_thread(_setup_compute_pipeline)


func _exit_tree() -> void:
	_cleanup()


# Renaming an @export breaks its saved value: Godot keys exported data in the
# .tscn by property name, so a renamed property finds nothing to load and comes
# back null. That used to fail silently -- _process returns on its first line
# and you get no cells and no grass, with nothing in the log to say why.
func _verify_assignments() -> bool:
	var missing := PackedStringArray()
	if not settings_DA:
		missing.append("settings_DA")
	if not terrain_node:
		missing.append("terrain_node")
	if not height_map:
		missing.append("height_map")
	if not bender_mask_subviewport:
		missing.append("bender_mask_subviewport")
	if not bender_mask_camera:
		missing.append("bender_mask_camera")
	if not inverse_terrain_node:
		missing.append("inverse_terrain_node")

	if missing.is_empty():
		return true

	push_error("FoliageWorld: unassigned in the inspector -> %s. If these were set "
		% ", ".join(missing)
		+ "before a rename, the saved values were dropped when the property names "
		+ "changed -- reassign them on the node and save the scene.")
	return false


# Pushes the foliage uniforms onto the Terrain3D material so the terrain itself
# can draw the ground card, instead of every chunk carrying a baked copy of the
# terrain underneath it.
#
# Terrain3DMaterial does not derive from Godot's Material, so it will not accept
# a plain .set(). Which accessor it exposes varies by plugin version, so try the
# resource method first and fall back to RenderingServer on the material RID.
func _set_terrain_param(param_name : String, value : Variant) -> bool:
	if not terrain_node:
		return false
	var mat = terrain_node.get_material()
	if not mat:
		return false

	if mat.has_method("set_shader_param"):
		mat.call("set_shader_param", param_name, value)
		return true

	if mat.has_method("get_material_rid"):
		var mat_rid : RID = mat.call("get_material_rid")
		if mat_rid.is_valid():
			RenderingServer.material_set_param(mat_rid, param_name, value)
			return true

	return false


# Everything that only changes when the world is rebuilt. Re-pushed whenever
# Terrain3D regenerates its material, which drops any params we set.
func _push_static_terrain_params() -> void:
	if not settings_DA or not settings_DA.link_terrain_material:
		return

	var ok : bool = _set_terrain_param(foliage_shader_world_origin_xz, settings_DA.world_origin_xz)
	ok = _set_terrain_param(foliage_shader_world_size_m, settings_DA.world_size_m) and ok
	if settings_DA.global_mask:
		ok = _set_terrain_param(foliage_shader_placement_mask, settings_DA.global_mask) and ok
	if created_bender_tex_RD:
		ok = _set_terrain_param(foliage_shader_bend_mask, created_bender_tex_RD) and ok
		ok = _set_terrain_param(foliage_shader_bend_res, settings_DA.bend_mask_res) and ok
		ok = _set_terrain_param(foliage_shader_bend_texels_per_m, settings_DA.bend_texels_per_m()) and ok


	terrain_material_linked = ok
	if not ok:
		push_warning("FoliageWorld: could not push params to the Terrain3D material. "
			+ "The ground card will not react to bending or the LOD frontier. "
			+ "Check the terrain has a shader override including foliage_ground_card.gdshaderinc.")


func _link_terrain_material() -> void:
	if not settings_DA or not settings_DA.link_terrain_material or not terrain_node:
		return
	# a material rebuild wipes anything we set, so re-push on the signal
	if terrain_node.has_signal("material_changed") \
			and not terrain_node.is_connected("material_changed", _push_static_terrain_params):
		terrain_node.connect("material_changed", _push_static_terrain_params)
	_push_static_terrain_params()


func _get_vertex_spacing() -> float:
	if terrain_node:
		return terrain_node.vertex_spacing
	if height_map and height_map.is_valid():
		return height_map.cell_size
	push_warning("FoliageWorld: no terrain node, defaulting cell size to 4.0")
	return 4.0


func _intialize_segments_data() -> void:
	fill_grid = FoliageFillGrid.new()
	fill_grid._initialize(settings_DA.fine_window_cells, vertex_spacing, settings_DA.total_segment_budget())
	fill_grid.world_cells = settings_DA.world_cells_per_dim(vertex_spacing)
	fill_grid.edge_pad_cells = settings_DA.view_edge_pad_cells
	fill_grid.terrain_vertical_slack = settings_DA.view_terrain_relief_m

	player_transform_data_arr.resize(7 * 4)
	bend_float_param_arr.resize(8 * 4)
	active_segment_count_arr.resize(4)


func _initialize_bender_data() -> void:
	if inverse_terrain_node and inverse_terrain_node.material:
		inverse_terrain_node.material.show_checkered = false
	if bender_mask_subviewport:
		bender_mask_subviewport.size = Vector2i(settings_DA.bend_mask_res, settings_DA.bend_mask_res)
		bender_mask_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if bender_mask_camera:
		bender_mask_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		bender_mask_camera.size = settings_DA.bend_window_size_m
	if bender_mask_subviewport:
		# grabbed here rather than inside the render-thread setup, so no scene
		# tree access happens off the main thread
		bender_subviewport_tex_RID = bender_mask_subviewport.get_texture().get_rid()


# ==========================================================================
# MAIN THREAD FRAME
# ==========================================================================

func _process(delta : float) -> void:
	if not initialized or not settings_DA or not visible:
		# say why, once, rather than going quiet
		if not DEBUG_reported_idle:
			DEBUG_reported_idle = true
			var why : String = "settings_DA is null" if not settings_DA \
				else ("node is hidden" if not visible else "compute pipeline never initialised")
			push_warning("FoliageWorld is idle: %s. Nothing will be drawn." % why)
		return
	DEBUG_reported_idle = false
	var cam : Camera3D = _get_current_camera()
	if not cam:
		return

	var view : FoliageViewSnapshot = FoliageViewSnapshot.capture(cam, terrain_node)

	_update_bender_window(view)

	# --- fine fill, on the main thread ---------------------------------
	# It is pure CPU work on PackedArrays and it now runs once per frame
	# rather than once per chunk, so there is no reason to make the render
	# thread carry it. Move it to a WorkerThreadPool task if it ever shows up
	# in a profile -- the snapshot already decouples the sampling.
	fill_grid.predict_yaw_rad = _update_camera_yaw_prediction(view, delta)
	fill_grid._centre_on(Vector2(view.cam_origin.x, view.cam_origin.z), settings_DA.world_origin_xz)

	var budget : int = settings_DA.total_segment_budget()
	segments_filled = fill_grid._build(view, budget)
	frontier_radius_m = fill_grid._frontier_radius_m()

	var bytes : PackedByteArray = fill_grid._out_slice(segments_filled)

	# keep the head of the list so the debug panel can compare where a segment
	# was asked for against where its instances actually landed
	# opt: read straight from the fill buffer -- no decode_s32 per value. The fill packs
	# x into the low 16 bits and z into the high 16, so unpack them back into pairs here.
	var head_cells : int = mini(segments_filled, 4)
	DEBUG_head_segment_coords.resize(head_cells * 2)		# opt: fixed size, so no reallocation after frame one
	for i in head_cells:
		var packed : int = fill_grid.out_arr[i]
		DEBUG_head_segment_coords[i * 2] = packed & 0xFFFF
		DEBUG_head_segment_coords[i * 2 + 1] = packed >> 16

	var high_budget : int = settings_DA.high_segment_budget()
	high_segments_drawn = mini(segments_filled, high_budget)
	low_segments_drawn = maxi(segments_filled - high_budget, 0)

	_encode_player_data(view)
	_update_bender_data(delta)

	RenderingServer.call_on_render_thread(
		_update_compute_segments_data.bind(bytes, segments_filled, player_transform_data_arr.duplicate(), bend_float_param_arr.duplicate()))


# The fill runs on the main thread, the dispatch on the render thread, and the
# result is drawn a frame later still -- so the transforms on screen describe a
# camera orientation one to three frames old. Standing still that is invisible;
# spinning, it is a bald wedge on the leading edge. Measuring the turn rate and
# filling for where the camera is heading closes it, at the cost of some budget
# while the turn lasts.
func _update_camera_yaw_prediction(view : FoliageViewSnapshot, delta : float) -> float:
	var fwd : Vector2 = Vector2(view.cam_forward.x, view.cam_forward.z)
	if fwd.length_squared() < 0.000001:
		return 0.0
	fwd = fwd.normalized()

	if previous_camera_forward_flat != Vector2.ZERO and delta > 0.0:
		# light smoothing: mouse deltas are spiky, and an unsmoothed rate makes
		# the filled region jitter in width frame to frame
		var measured : float = previous_camera_forward_flat.angle_to(fwd) / delta
		current_yaw_rate = lerpf(current_yaw_rate, measured, 0.4)
	previous_camera_forward_flat = fwd

	var lead : float = delta * settings_DA.rotation_lead_frames
	current_predicted_yaw = clampf(current_yaw_rate * lead,
		-deg_to_rad(settings_DA.rotation_lead_max_degrees),
		deg_to_rad(settings_DA.rotation_lead_max_degrees))
	return current_predicted_yaw


func _DEBUG_yaw_rate_deg() -> float:
	return rad_to_deg(current_yaw_rate)


func _DEBUG_predicted_yaw_deg() -> float:
	return rad_to_deg(current_predicted_yaw)


func _get_current_camera() -> Camera3D:
	var viewport : Viewport
	if Engine.is_editor_hint():
		viewport = EditorInterface.get_editor_viewport_3d()
	else:
		viewport = get_viewport()
	if not viewport:
		return null
	return viewport.get_camera_3d()


func _update_bender_window(view : FoliageViewSnapshot) -> void:
	if not bender_mask_camera or not bender_mask_subviewport:
		return

	var texels_per_m : float = settings_DA.bend_texels_per_m()
	var res : int = settings_DA.bend_mask_res

	# Snap the window to whole texels. Without the snap the sub-texel offset
	# drifts every frame and the accumulator shimmers.
	previous_bender_origin_texel = current_bender_origin_texel
	current_bender_origin_texel = Vector2i(
		floori(view.cam_origin.x * texels_per_m) - (res >> 1),
		floori(view.cam_origin.z * texels_per_m) - (res >> 1))

	var origin_world : Vector2 = Vector2(current_bender_origin_texel) / texels_per_m
	var centre : Vector2 = origin_world + Vector2.ONE * (settings_DA.bend_window_size_m * 0.5)

	# local relief under the window, so near/far stay tight without clipping
	var low : float = view.ground_y
	var high : float = view.ground_y
	if terrain_node:
		var half : float = settings_DA.bend_window_size_m * 0.5
		for corner in [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half)]:
			var h : float = terrain_node.data.get_height(Vector3(centre.x + corner.x, 0.0, centre.y + corner.y))
			if not is_nan(h):
				low = minf(low, h)
				high = maxf(high, h)

	var pad : float = settings_DA.bend_camera_vertical_padding
	bender_mask_camera.size = settings_DA.bend_window_size_m
	bender_mask_camera.global_position = Vector3(centre.x, low - pad, centre.y)
	bender_mask_camera.far = (high - low) + pad * 2.0

	if chunk_material_high_LOD_inst:
		chunk_material_high_LOD_inst.set(shader_param_prefix + foliage_shader_bend_origin_texel, current_bender_origin_texel)
	if chunk_material_low_LOD_inst:
		chunk_material_low_LOD_inst.set(shader_param_prefix + foliage_shader_bend_origin_texel, current_bender_origin_texel)
	if terrain_material_linked:
		# the window moves every frame, and the frontier moves with the fill
		_set_terrain_param(foliage_shader_bend_origin_texel, current_bender_origin_texel)
		_set_terrain_param(foliage_shader_frontier_radius, frontier_radius_m)


func _encode_player_data(view : FoliageViewSnapshot) -> void:
	# world space now -- there is no chunk to be relative to. At 2 km, float
	# precision is well under a millimetre. Past ~50 km, switch to
	# window-relative transforms and move the multimesh instance instead.
	player_transform_data_arr.encode_float(0, view.cam_origin.x)
	player_transform_data_arr.encode_float(4, view.cam_origin.y)
	player_transform_data_arr.encode_float(8, view.cam_origin.z)

	var rot : Vector3 = view.cam_transform.basis.get_euler()
	player_transform_data_arr.encode_float(12, rot.x)
	player_transform_data_arr.encode_float(16, rot.y)
	player_transform_data_arr.encode_float(20, rot.z)
	player_transform_data_arr.encode_float(24, frontier_radius_m)



func _update_bender_data(delta : float) -> void:
	bend_float_param_arr.encode_float(0, settings_DA.unbend_rate_per_second)
	bend_float_param_arr.encode_float(4, delta)
	bend_float_param_arr.encode_s32(8, settings_DA.bend_mask_res)
	bend_float_param_arr.encode_s32(12, current_bender_origin_texel.x)
	bend_float_param_arr.encode_s32(16, current_bender_origin_texel.y)
	bend_float_param_arr.encode_s32(20, previous_bender_origin_texel.x)
	bend_float_param_arr.encode_s32(24, previous_bender_origin_texel.y)
	bend_float_param_arr.encode_s32(28, settings_DA.bend_flip_bits())


#region render_setup

func _setup_compute_pipeline() -> void:
	if get_world_3d() == null:
		push_error("FoliageWorld: no World3D at render setup.")
		return

	rd = RenderingServer.get_rendering_device()
	if rd == null:
		push_error("FoliageWorld: no RenderingDevice (running on a non-Vulkan renderer?).")
		return

	scenario_RID = get_world_3d().scenario
	if not scenario_RID.is_valid():
		push_error("FoliageWorld: world scenario is invalid.")
		return

	if not _load_shaders():
		push_error("FoliageWorld: shader compilation failed -- see errors above.")
		return

	var high_per_segment : int = settings_DA.instances_per_segment_high(vertex_spacing)
	var low_per_segment : int = settings_DA.instances_per_segment_low(vertex_spacing)
	var high_segments : int = settings_DA.high_segment_budget()
	var low_segments : int = maxi(settings_DA.low_lod_segment_budget, 1)

	var high_instances : int = high_segments * high_per_segment
	var low_instances : int = low_segments * low_per_segment

	_try_assign_chunk_material_instances()
	_setup_multimesh_data(high_instances, low_instances)
	_setup_shared_buffers(high_segments, low_segments)
	_setup_setting_buffers(high_per_segment, low_per_segment, high_segments, low_segments)
	_setup_foliage_bender_pipeline()

	mm_pipeline_pos_calc_RID = rd.compute_pipeline_create(compute_pos_shader_RID)
	RID_arr.append(mm_pipeline_pos_calc_RID)
	mm_pipeline_pos_transfer_RID = rd.compute_pipeline_create(transfer_shader_RID)
	RID_arr.append(mm_pipeline_pos_transfer_RID)

	initialized = true
	set_process(true)

	print("FoliageWorld ready: %d high segments (%d instances), %d low segments (%d instances)"
		% [high_segments, high_instances, low_segments, low_instances])


func _load_shaders() -> bool:
	compute_pos_shader_RID = _load_shader_from_file(settings_DA.positions_compute_shader)
	transfer_shader_RID = _load_shader_from_file(settings_DA.transfer_compute_shader)
	bender_shader_RID = _load_shader_from_file(settings_DA.bender_compute_shader)
	return compute_pos_shader_RID.is_valid() and transfer_shader_RID.is_valid() and bender_shader_RID.is_valid()

func _load_shader_from_file(file : RDShaderFile) -> RID:
	if not file:
		push_error("FoliageWorld: compute shader file missing.")
		return RID()
	var spirv : RDShaderSPIRV = file.get_spirv()
	if not spirv:
		push_error("FoliageWorld: failed to get SPIRV for " + str(file))
		return RID()
	var rid : RID = rd.shader_create_from_spirv(spirv)
	if rid.is_valid():
		RID_arr.append(rid)
	return rid

func _try_assign_chunk_material_instances() -> void:
	if settings_DA.foliage_material:
		chunk_material_high_LOD_inst = settings_DA.foliage_material.duplicate()
		chunk_material_low_LOD_inst = settings_DA.foliage_material.duplicate()
		
		chunk_material_low_LOD_inst.set(shader_param_prefix + foliage_shader_blade_shaping, false)	
		chunk_material_low_LOD_inst.set(shader_param_prefix + foliage_shader_lod_divide, false)	

func _get_world_AABB() -> AABB:
	var low : float = height_map.min_height - 50.0
	var high : float = height_map.max_height + 50.0
	return AABB(
		Vector3(settings_DA.world_origin_xz.x, low, settings_DA.world_origin_xz.y),
		Vector3(settings_DA.world_size_m, high - low, settings_DA.world_size_m))

func _setup_multimesh_data(high_instances : int, low_instances : int) -> void:
	var aabb : AABB = _get_world_AABB()

	mm_high_instance_RID = RenderingServer.instance_create()
	RID_arr.append(mm_high_instance_RID)
	mm_high_RID = RenderingServer.multimesh_create()
	RID_arr.append(mm_high_RID)
	_init_new_multimesh(mm_high_RID, mm_high_instance_RID, high_instances, settings_DA.foliage_mesh_high_LOD, aabb, chunk_material_high_LOD_inst)
	mm_high_packed_transform_buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm_high_RID)
	mm_high_command_buffer_rid = RenderingServer.multimesh_get_command_buffer_rd_rid(mm_high_RID)

	mm_low_instance_RID = RenderingServer.instance_create()
	RID_arr.append(mm_low_instance_RID)
	mm_low_RID = RenderingServer.multimesh_create()
	RID_arr.append(mm_low_RID)
	_init_new_multimesh(mm_low_RID, mm_low_instance_RID, low_instances, settings_DA.foliage_mesh_low_LOD, aabb, chunk_material_low_LOD_inst)
	mm_low_packed_transform_buffer_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm_low_RID)
	mm_low_command_buffer_rid = RenderingServer.multimesh_get_command_buffer_rd_rid(mm_low_RID)

func _init_new_multimesh(mm : RID, instance : RID, count : int, mesh : Mesh, aabb : AABB, material : Material) -> void:
	RenderingServer.multimesh_allocate_data(mm, count, RenderingServer.MULTIMESH_TRANSFORM_3D, false, false, true)
	if mesh:
		RenderingServer.multimesh_set_mesh(mm, mesh.get_rid())

	RenderingServer.instance_set_transform(instance, Transform3D.IDENTITY)
	RenderingServer.multimesh_set_custom_aabb(mm, aabb)
	RenderingServer.instance_set_custom_aabb(instance, aabb)
	RenderingServer.instance_set_scenario(instance, scenario_RID)
	RenderingServer.instance_set_base(instance, mm)
	RenderingServer.instance_geometry_set_flag(instance, RenderingServer.INSTANCE_FLAG_USE_DYNAMIC_GI, true)
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	if material:
		RenderingServer.instance_geometry_set_material_override(instance, material.get_rid())

func _setup_shared_buffers(high_segments : int, low_segments : int) -> void:
	# global height, one buffer for the whole world
	var height_bytes : PackedByteArray = height_map.to_byte_array()
	height_data_RID = rd.storage_buffer_create(height_bytes.size(), height_bytes)
	RID_arr.append(height_data_RID)

	var mask_image : Image = settings_DA.global_mask.get_image()
	mask_image.decompress()
	mask_image.convert(Image.FORMAT_R8)
	if mask_image.has_mipmaps():
		mask_image.clear_mipmaps()
	foliage_mask_RID = _init_existing_image_data(mask_image, RenderingDevice.DATA_FORMAT_R8_UNORM, false)

	# global priority-ordered segment list: high LOD reads the front of it,
	# low LOD reads the rest
	var segment_bytes := PackedByteArray()
	segment_bytes.resize(settings_DA.total_segment_budget() * 4)	# opt: one packed int per segment
	segment_coord_data_mm_buffer_rid = rd.storage_buffer_create(segment_bytes.size(), segment_bytes)
	RID_arr.append(segment_coord_data_mm_buffer_rid)

	var player_bytes := PackedByteArray()
	player_bytes.resize(7 * 4)
	player_transform_data_mm_high_buffer_rid = rd.storage_buffer_create(player_bytes.size(), player_bytes)
	RID_arr.append(player_transform_data_mm_high_buffer_rid)

	mm_high_instance_count_buffer_rid = rd.storage_buffer_create(high_segments * 4)
	RID_arr.append(mm_high_instance_count_buffer_rid)
	mm_low_instance_count_buffer_rid = rd.storage_buffer_create(low_segments * 4)
	RID_arr.append(mm_low_instance_count_buffer_rid)

	var high_per_segment : int = settings_DA.instances_per_segment_high(vertex_spacing)
	var low_per_segment : int = settings_DA.instances_per_segment_low(vertex_spacing)

	# 48 bytes = 12 floats of a 3D transform
	mm_high_sparse_transform_buffer_rid = rd.storage_buffer_create(high_segments * high_per_segment * 48, PackedByteArray())
	RID_arr.append(mm_high_sparse_transform_buffer_rid)
	mm_low_sparse_transform_buffer_rid = rd.storage_buffer_create(low_segments * low_per_segment * 48, PackedByteArray())
	RID_arr.append(mm_low_sparse_transform_buffer_rid)

func _setup_setting_buffers(high_per_segment : int, low_per_segment : int, high_segments : int, low_segments : int) -> void:
	var height_u := _create_storage_uniform(0, height_data_RID)
	var mask_u := _create_image_uniform(5, foliage_mask_RID)
	var player_u := _create_storage_uniform(6, player_transform_data_mm_high_buffer_rid)
	var segments_u := _create_storage_uniform(7, segment_coord_data_mm_buffer_rid)

	var high_sparse_u := _create_storage_uniform(1, mm_high_sparse_transform_buffer_rid)
	var low_sparse_u := _create_storage_uniform(1, mm_low_sparse_transform_buffer_rid)
	var high_counts_u := _create_storage_uniform(2, mm_high_instance_count_buffer_rid)
	var low_counts_u := _create_storage_uniform(2, mm_low_instance_count_buffer_rid)

	var high_floats := _create_float_params_array(settings_DA.target_density_sq_m_high_LOD, settings_DA.culling_distance_thresholds)
	var low_floats := _create_float_params_array(settings_DA.target_density_sq_m_low_LOD, settings_DA.culling_distance_thresholds)
	var buf_high_floats : RID = rd.storage_buffer_create(high_floats.size(), high_floats)
	RID_arr.append(buf_high_floats)
	var buf_low_floats : RID = rd.storage_buffer_create(low_floats.size(), low_floats)
	RID_arr.append(buf_low_floats)

	# [instances_per_segment, height_stride, segment_read_offset, dispatch_width,
	#  world_cells_per_dim, mask_res, active_segments]
	#
	# active_segments is rewritten every frame. The high tier always dispatches
	# its full work group grid, so when the fill comes back short the tail
	# groups would otherwise read stale segment coordinates and scatter grass
	# somewhere it was last frame.
	var high_ints := PackedInt32Array([
		high_per_segment,
		height_map.stride,
		0,
		settings_DA.high_lod_num_work_groups.x,
		settings_DA.world_cells_per_dim(vertex_spacing),
		settings_DA.global_mask.get_width(),
		0]).to_byte_array()
		
	var low_ints := PackedInt32Array([
		low_per_segment,
		height_map.stride,
		high_segments,
		low_segments,
		settings_DA.world_cells_per_dim(vertex_spacing),
		settings_DA.global_mask.get_width(),
		0]).to_byte_array()

	iparameter_mm_high_buffer_rid = rd.storage_buffer_create(high_ints.size(), high_ints)
	RID_arr.append(iparameter_mm_high_buffer_rid)
	iparameter_mm_low_buffer_rid = rd.storage_buffer_create(low_ints.size(), low_ints)
	RID_arr.append(iparameter_mm_low_buffer_rid)

	mm_high_uniform_set_pos_calc_RID = rd.uniform_set_create([
		height_u, high_sparse_u, high_counts_u,
		_create_storage_uniform(3, buf_high_floats), _create_storage_uniform(4, iparameter_mm_high_buffer_rid),
		mask_u, player_u, segments_u], compute_pos_shader_RID, 0)
	RID_arr.append(mm_high_uniform_set_pos_calc_RID)

	mm_low_uniform_set_pos_calc_RID = rd.uniform_set_create([
		height_u, low_sparse_u, low_counts_u,
		_create_storage_uniform(3, buf_low_floats), _create_storage_uniform(4, iparameter_mm_low_buffer_rid),
		mask_u, player_u, segments_u], compute_pos_shader_RID, 0)
	RID_arr.append(mm_low_uniform_set_pos_calc_RID)

	mm_high_uniform_set_pos_transfer_RID = rd.uniform_set_create([
		_create_storage_uniform(0, mm_high_packed_transform_buffer_rid), high_sparse_u, high_counts_u,
		_create_storage_uniform(3, mm_high_command_buffer_rid), _create_storage_uniform(4, iparameter_mm_high_buffer_rid)], transfer_shader_RID, 0)
	RID_arr.append(mm_high_uniform_set_pos_transfer_RID)

	mm_low_uniform_set_pos_transfer_RID = rd.uniform_set_create([
		_create_storage_uniform(0, mm_low_packed_transform_buffer_rid), low_sparse_u, low_counts_u,
		_create_storage_uniform(3, mm_low_command_buffer_rid), _create_storage_uniform(4, iparameter_mm_low_buffer_rid)], transfer_shader_RID, 0)
	RID_arr.append(mm_low_uniform_set_pos_transfer_RID)

func _create_float_params_array(density : float, thresholds : Vector3) -> PackedByteArray:
	return PackedFloat32Array([
		vertex_spacing,
		sqrt(density),
		settings_DA.max_foliage_individual_random_offset,
		deg_to_rad(settings_DA.max_foliage_tilt_degrees),
		deg_to_rad(settings_DA.foliage_cam_bias_degress_near_far.x),
		deg_to_rad(settings_DA.foliage_cam_bias_degress_near_far.y),
		settings_DA.foliage_cam_bias_min_distance,
		settings_DA.min_grass_blade_scale,
		thresholds.x, thresholds.y, thresholds.z,
		settings_DA.world_origin_xz.x,
		settings_DA.world_origin_xz.y,
		settings_DA.mask_texels_per_m,
		settings_DA.lod_skip_fade_m,
		settings_DA.frontier_fade_m]).to_byte_array()

func _setup_foliage_bender_pipeline() -> void:
	if not bender_mask_subviewport:
		return

	if not bender_subviewport_tex_RID.is_valid():
		return
	current_bender_data_tex_RID = RenderingServer.texture_get_rd_texture(bender_subviewport_tex_RID)

	var res : int = settings_DA.bend_mask_res
	var blank : Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
	created_bender_image_RID = _init_existing_image_data(blank, RenderingDevice.DATA_FORMAT_R32_SFLOAT, true)

	created_bender_tex_RD = Texture2DRD.new()
	created_bender_tex_RD.texture_rd_rid = created_bender_image_RID

	for mat in [chunk_material_high_LOD_inst, chunk_material_low_LOD_inst]:
		if mat:
			mat.set(shader_param_prefix + foliage_shader_bend_mask, created_bender_tex_RD)
			mat.set(shader_param_prefix + foliage_shader_bend_res, res)
			mat.set(shader_param_prefix + foliage_shader_bend_texels_per_m, settings_DA.bend_texels_per_m())
			mat.set(shader_param_prefix + foliage_shader_bend_origin_texel, current_bender_origin_texel)

	_link_terrain_material()

	var params := PackedByteArray()
	params.resize(8 * 4)
	fparameter_buffer_bend_RID = rd.storage_buffer_create(params.size(), params)
	RID_arr.append(fparameter_buffer_bend_RID)

	uniform_set_bender_RID = rd.uniform_set_create([
		_create_image_uniform(0, current_bender_data_tex_RID),
		_create_image_uniform(1, created_bender_image_RID),
		_create_storage_uniform(2, fparameter_buffer_bend_RID)], bender_shader_RID, 0)
	RID_arr.append(uniform_set_bender_RID)

	pipeline_bender_RID = rd.compute_pipeline_create(bender_shader_RID)
	RID_arr.append(pipeline_bender_RID)

func _create_storage_uniform(binding : int, rid : RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(rid)
	return uniform

func _create_image_uniform(binding : int, rid : RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(rid)
	return uniform

func _init_existing_image_data(img : Image, format : RenderingDevice.DataFormat, updateable : bool) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = img.get_width()
	fmt.height = img.get_height()
	fmt.format = format
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		+ RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		+ RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	if updateable:
		fmt.usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var rid : RID = rd.texture_create(fmt, RDTextureView.new(), [img.get_data()])
	RID_arr.append(rid)
	return rid

#endregion

#region render_frame

func _update_compute_segments_data(segment_bytes : PackedByteArray, segment_count : int,
		player_bytes : PackedByteArray, bend_bytes : PackedByteArray) -> void:
	if not initialized:
		return

	rd = RenderingServer.get_rendering_device()

	rd.buffer_update(player_transform_data_mm_high_buffer_rid, 0, player_bytes.size(), player_bytes)
	if segment_count > 0:
		rd.buffer_update(segment_coord_data_mm_buffer_rid, 0, segment_count * 4, segment_bytes)	# opt: 4 bytes per packed segment

	# bend first, so this frame's grass reads this frame's bend state
	if uniform_set_bender_RID.is_valid():
		rd.buffer_update(fparameter_buffer_bend_RID, 0, bend_bytes.size(), bend_bytes)
		var groups : int = settings_DA.bend_mask_res / 8
		var bend_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(bend_list, pipeline_bender_RID)
		rd.compute_list_bind_uniform_set(bend_list, uniform_set_bender_RID, 0)
		rd.compute_list_dispatch(bend_list, groups, groups, 1)
		rd.compute_list_end()

	var high_count : int = mini(segment_count, settings_DA.high_segment_budget())
	var low_count : int = maxi(segment_count - settings_DA.high_segment_budget(), 0)

	_dispatch_position_compute_list(mm_high_instance_count_buffer_rid, settings_DA.high_segment_budget() * 4, mm_high_command_buffer_rid,
		iparameter_mm_high_buffer_rid, mm_high_uniform_set_pos_calc_RID, mm_high_uniform_set_pos_transfer_RID,
		Vector2i(settings_DA.high_lod_num_work_groups.x, settings_DA.high_lod_num_work_groups.y), high_count)

	_dispatch_position_compute_list(mm_low_instance_count_buffer_rid, maxi(settings_DA.low_lod_segment_budget, 1) * 4, mm_low_command_buffer_rid,
		iparameter_mm_low_buffer_rid, mm_low_uniform_set_pos_calc_RID, mm_low_uniform_set_pos_transfer_RID,
		Vector2i(low_count, 1), low_count)

func _dispatch_position_compute_list(counts_buffer : RID, counts_bytes : int, command_buffer : RID, int_params : RID,
		pos_set : RID, transfer_set : RID, groups : Vector2i, segment_count : int) -> void:
	# Zero the instance count every frame, or last frame's counts persist and
	# the multimesh keeps drawing stale transforms. This is the TODO the old
	# code left behind ("set the instance count to 0 on the low LOD").
	# The command buffer is a draw-indirect struct -- only instanceCount, at
	# byte offset 4, may be cleared; wiping the whole thing would zero the
	# index count too.
	if command_buffer.is_valid():
		rd.buffer_clear(command_buffer, 4, 4)
	if segment_count <= 0:
		return
	if counts_buffer.is_valid():
		rd.buffer_clear(counts_buffer, 0, counts_bytes)

	if not pos_set.is_valid() or not transfer_set.is_valid():
		return

	# active_segments lives at int index 6
	active_segment_count_arr.encode_s32(0, segment_count)
	rd.buffer_update(int_params, 6 * 4, 4, active_segment_count_arr)

	var list : int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, mm_pipeline_pos_calc_RID)
	rd.compute_list_bind_uniform_set(list, pos_set, 0)
	rd.compute_list_dispatch(list, maxi(groups.x, 1), 1, maxi(groups.y, 1))

	rd.compute_list_add_barrier(list)

	rd.compute_list_bind_compute_pipeline(list, mm_pipeline_pos_transfer_RID)
	rd.compute_list_bind_uniform_set(list, transfer_set, 0)
	rd.compute_list_dispatch(list, maxi(groups.x, 1), 1, maxi(groups.y, 1))
	rd.compute_list_end()

#endregion

# ==========================================================================
# CLEANUP
# ==========================================================================

func _cleanup() -> void:
	if mm_high_RID.is_valid():
		RenderingServer.multimesh_allocate_data(mm_high_RID, 0, RenderingServer.MULTIMESH_TRANSFORM_3D, false, false, true)
	if mm_low_RID.is_valid():
		RenderingServer.multimesh_allocate_data(mm_low_RID, 0, RenderingServer.MULTIMESH_TRANSFORM_3D, false, false, true)

	if rd:
		for rid in RID_arr:
			if rid.is_valid():
				rd.free_rid(rid)
	RID_arr.clear()

	created_bender_tex_RD = null
	initialized = false
	set_process(false)


#region tooling
func _assign_terrain_shader_properties() -> void:
	
	if(!settings_DA || !terrain_node):
		return
	
	var mat : ShaderMaterial = settings_DA.foliage_material
	if(!mat):
		return
	
	var shader_rid : RID = mat.shader.get_rid()	
	var uniform_list = mat.shader.get_shader_uniform_list()	
		
	for	uniform in uniform_list:
		var param_name : String = str(uniform.get("name", ""))
		if(!param_name.begins_with(foliage_param_name)):
			continue
			
		if(exempt_param_names.has(param_name)):
			continue	
			
		#get the value to copy over	
		var value : Variant = mat.get_shader_parameter(param_name)
		if value == null:
			value = RenderingServer.shader_get_parameter_default(shader_rid, param_name)
	
		_set_terrain_param(param_name, value)	
		
func _generate_height_data() -> void:
	if not settings_DA or not terrain_node:
		push_error("FoliageWorld: assign settings_DA and terrain_node before baking.")
		return

	var cell_size : float = terrain_node.vertex_spacing
	var cells : int = int(round(settings_DA.world_size_m / cell_size))
	var stride : int = cells + 1

	var map := FoliageHeightMap.new()
	map.stride = stride
	map.cell_size = cell_size
	map.origin = settings_DA.world_origin_xz
	map.data.resize(stride * stride)

	var min_h : float = INF
	var max_h : float = -INF

	for vz in stride:
		for vx in stride:
			var world := Vector3(
				settings_DA.world_origin_xz.x + float(vx) * cell_size,
				0.0,
				settings_DA.world_origin_xz.y + float(vz) * cell_size)
			var h : float = terrain_node.data.get_height(world)
			# NaN never equals anything, itself included -- the old
			# `found_height == NAN` check could never fire
			if is_nan(h):
				h = 0.0
			map.data[vx + vz * stride] = h
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
		if vz % 64 == 0:
			print("baking height map... row %d / %d" % [vz, stride])

	map.min_height = min_h - height_bake_vertical_slack
	map.max_height = max_h + height_bake_vertical_slack

	var err : int = ResourceSaver.save(map, height_map_save_path)
	if err != OK:
		push_error("FoliageWorld: failed to save height map (%d)" % err)
		return

	height_map = load(height_map_save_path)
	print("FoliageWorld: baked %d x %d height map (%.2f MB), range %.1f .. %.1f"
		% [stride, stride, float(stride * stride * 4) / 1048576.0, min_h, max_h])
#endregion

#region DEBUG

func _DEBUG_is_initialized() -> bool:
	return initialized


func _DEBUG_vertex_spacing() -> float:
	return vertex_spacing


func _DEBUG_bender_origin_texel() -> Vector2i:
	return current_bender_origin_texel


func _DEBUG_bender_image_RID() -> RID:
	return created_bender_image_RID


# ==========================================================================
# PLACEMENT CHECK
# ==========================================================================

# The world position a global cell is supposed to resolve to. The compute
# shader must arrive at the same answer from the same cell index; if it does
# not, the difference is the bug.
func _DEBUG_expected_world_xz(cell : Vector2i) -> Vector2:
	return settings_DA.world_origin_xz + Vector2(cell) * vertex_spacing


func _DEBUG_head_segment_coords() -> PackedInt32Array:
	return DEBUG_head_segment_coords


# Pulls transforms back out of the multimesh's packed buffer. A 3D multimesh
# transform is three rows of four floats, so translation sits at float 3, 7 and
# 11 -- byte offsets 12, 28 and 44.
func _DEBUG_read_instance_positions(high_tier : bool, count : int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not initialized:
		return out

	var buffer : RID = mm_high_packed_transform_buffer_rid if high_tier else mm_low_packed_transform_buffer_rid
	if not buffer.is_valid():
		return out

	var device : RenderingDevice = RenderingServer.get_rendering_device()
	var bytes : PackedByteArray = device.buffer_get_data(buffer, 0, count * 48)
	if bytes.size() < count * 48:
		return out

	for i in count:
		var base : int = i * 48
		out.append(Vector3(
			bytes.decode_float(base + 12),
			bytes.decode_float(base + 28),
			bytes.decode_float(base + 44)))
	return out

# ==========================================================================
# DIAGNOSTIC
# ==========================================================================

# Walks the chain from "is anything running" down to "why did the fill emit
# nothing", and bisects the three rejections in FoliageFillGrid._claim by
# rebuilding with them switched off one at a time. Whichever count first goes
# from non-zero to zero is the cause.
#
# Safe to run any time, including in the editor before the compute pipeline
# exists -- it drives the fill directly and leaves it in its normal state.
func _DEBUG_diagnose() -> PackedStringArray:
	var out := PackedStringArray()

	if not settings_DA:
		out.append("FAIL  no settings_DA assigned.")
		return out
	for problem in settings_DA.validate():
		out.append("WARN  " + problem)

	# --- is anything running at all ------------------------------------
	if not height_map or not height_map.is_valid():
		out.append("FAIL  no baked height map -- run 'Bake Global Height Map'.")
	if not initialized:
		out.append("FAIL  compute pipeline not initialised (nothing will draw regardless of the fill).")
	if not visible:
		out.append("FAIL  FoliageWorld node is hidden; _process returns early.")

	if not fill_grid or fill_grid.cells_per_dim == 0:
		out.append("FAIL  fill grid not configured.")
		return out

	var cam : Camera3D = _get_current_camera()
	if not cam:
		out.append("FAIL  no active Camera3D found.")
		return out

	# --- coordinate frame ----------------------------------------------
	var world_min : Vector2 = settings_DA.world_origin_xz
	var world_max : Vector2 = world_min + Vector2.ONE * settings_DA.world_size_m
	out.append("world spans X %.0f..%.0f  Z %.0f..%.0f  (world_origin_xz is the MIN corner)"
		% [world_min.x, world_max.x, world_min.y, world_max.y])

	var cam_xz : Vector2 = Vector2(cam.global_position.x, cam.global_position.z)
	var cam_cell := Vector2i(
		floori((cam_xz.x - world_min.x) / vertex_spacing),
		floori((cam_xz.y - world_min.y) / vertex_spacing))
	var world_cells : int = settings_DA.world_cells_per_dim(vertex_spacing)
	var cam_in_world : bool = cam_cell.x >= 0 and cam_cell.y >= 0 \
		and cam_cell.x < world_cells and cam_cell.y < world_cells
	out.append("camera at %.0f, %.0f -> global cell %s of 0..%d  %s"
		% [cam_xz.x, cam_xz.y, str(cam_cell), world_cells - 1,
			"OK" if cam_in_world else "OUTSIDE THE WORLD BOUNDS"])

	# --- bisect the fill -----------------------------------------------
	var view : FoliageViewSnapshot = FoliageViewSnapshot.capture(cam, terrain_node)
	var budget : int = settings_DA.total_segment_budget()

	out.append("camera y %.1f, sampled ground y %.1f" % [view.cam_origin.y, view.ground_y])
	out.append("filled half-angle %.1f deg from %d frustum constraints"
		% [fill_grid._DEBUG_filled_half_angle_deg(), fill_grid._DEBUG_constraint_count()])

	var saved_gate : int = fill_grid.gate_stride
	var saved_cells : int = fill_grid.world_cells

	fill_grid._centre_on(cam_xz, world_min)

	fill_grid.gate_stride = 0
	fill_grid.world_cells = 0
	var raw : int = fill_grid._build(view, budget)

	fill_grid.world_cells = saved_cells
	var bounded : int = fill_grid._build(view, budget)

	fill_grid.gate_stride = saved_gate
	var full : int = fill_grid._build(view, budget)

	out.append("fill: %d cells in view  ->  %d after world bounds  ->  %d after the gate"
		% [raw, bounded, full])

	if raw == 0:
		out.append("FAIL  the fill finds nothing before any rejection applies. The problem is")
		out.append("      the view rays or the window, not the gate. Check terrain_node is")
		out.append("      assigned and that the camera is above the terrain looking at it.")
	elif bounded == 0:
		out.append("FAIL  every cell is outside the world grid. world_origin_xz and/or")
		out.append("      world_size_m do not describe where the camera actually is.")
	elif full == 0:
		out.append("FAIL  every cell is gated out. Chunks are either unregistered, mapped to")
		out.append("      the wrong grid cell, or all out of reach of the window.")
	else:
		out.append("OK    the fill emits %d segments (budget %d)." % [full, budget])

	return out


func _DEBUG_print_diagnosis() -> void:
	print("--- FoliageWorld diagnosis ---")
	for line in _DEBUG_diagnose():
		print(line)


func _DEBUG_print_validation() -> void:
	if not settings_DA:
		print("FoliageWorld: no settings_DA assigned.")
		return
	var problems : PackedStringArray = settings_DA.validate()
	if not height_map or not height_map.is_valid():
		problems.append("No baked height map.")
	if not terrain_node:
		problems.append("terrain_node is unassigned.")
	if not bender_mask_subviewport or not bender_mask_camera:
		problems.append("Bend viewport/camera unassigned.")

	var cell_size : float = _get_vertex_spacing()
	var window_radius : float = float(settings_DA.fine_window_cells) * 0.5 * cell_size
	print("--- FoliageWorld ---")
	print("cell size            : %.2f m" % cell_size)
	print("world cells per dim  : %d" % settings_DA.world_cells_per_dim(cell_size))
	print("high segments        : %d (%d instances)"
		% [settings_DA.high_segment_budget(), settings_DA.high_segment_budget() * settings_DA.instances_per_segment_high(cell_size)])
	print("low segments         : %d (%d instances)"
		% [settings_DA.low_lod_segment_budget, settings_DA.low_lod_segment_budget * settings_DA.instances_per_segment_low(cell_size)])
	print("fine window radius   : %.1f m" % window_radius)
	print("bend window          : %.1f m at %d px (%.1f texels/m)"
		% [settings_DA.bend_window_size_m, settings_DA.bend_mask_res, settings_DA.bend_texels_per_m()])
	if problems.is_empty():
		print("no problems found.")
	else:
		for p in problems:
			print("PROBLEM: " + p)

#endregion
