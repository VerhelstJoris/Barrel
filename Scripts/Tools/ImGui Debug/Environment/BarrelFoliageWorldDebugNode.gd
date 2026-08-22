class_name BarrelFoliageWorldDebugNode extends BarrelSceneDebugNode

const MAX_TABLE_COLUMNS : int = 64

@export var foliage_world : FoliageWorld


# --- grid view state -----------------------------------------------------
enum ColourMode { STATUS, TIER, RING }

var colour_mode : int = ColourMode.TIER
var follow_player : bool = true
var table_half_span : Array[int] = [20]
var table_origin : Array[int] = [0, 0]		# local window coords, top-left of the view

var col_emitted : Array[float] = [1.0, 0.95, 0.3]
var col_gated : Array[float] = [1.0, 0.35, 1.0]
var draw_player : bool = true
var col_player : Array[float] = [1.0, 1.0, 1.0]

var col_high : Array[float] = [1.0, 0.45, 0.15]
var col_low : Array[float] = [0.35, 0.6, 1.0]
var col_dropped : Array[float] = [0.4, 0.4, 0.4]

# --- bend view state -----------------------------------------------------

var bend_img_scale : Array[float] = [0.4]
var bend_refresh_hz : Array[float] = [4.0]
var bend_unwrap : bool = true
var _bend_timer : float = 0.0
var _bend_cached_tex : ImageTexture
var _bend_readback_ms : float = 0.0

var _diagnosis : PackedStringArray = PackedStringArray()

var placement_check_high : bool = true
var _placement_samples : PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	if not foliage_world:
		queue_free()
		return

	super()
	BarrelDebugWindow.environment_node._register_environment_node(
		self, BarrelEnvironmentDebugNode.EDebugEnvNodeType.Foliage)

	# on from the start rather than from the first draw, otherwise the first
	# frame of the panel shows cells claimed but with no recorded provenance
	if foliage_world.fill_grid:
		foliage_world.fill_grid.DEBUG_capture_data = true


func _get_name() -> String:
	return "Foliage World"


func _exit_tree() -> void:
	# leave the grid paying nothing once the panel is gone
	if foliage_world and foliage_world.fill_grid:
		foliage_world.fill_grid.DEBUG_capture_data = false

func _draw_contents(_delta : float) -> void:
	if not foliage_world or not foliage_world.settings_DA:
		ImGui.TextColored(Color.ORANGE_RED, "No FoliageWorld assigned.")
		return

	var grid : FoliageFillGrid = foliage_world.fill_grid
	if not grid or grid.cells_per_dim == 0:
		ImGui.TextColored(Color.ORANGE_RED, "FoliageWorld has not built its fill grid yet.")
		return

	# provenance is only recorded while something is looking at it
	grid.DEBUG_capture_data = true

	if not foliage_world._DEBUG_is_initialized():
		ImGui.TextColored(Color.ORANGE_RED, "Compute pipeline not initialised (editor, or setup failed).")

	_draw_summary(grid)

	if ImGui.Button("Diagnose empty fill"):
		_diagnosis = foliage_world._DEBUG_diagnose()
	if _diagnosis.size() > 0:
		ImGui.SameLine()
		if ImGui.Button("Clear"):
			_diagnosis = PackedStringArray()
		ImGui.Separator()
		for line in _diagnosis:
			if line.begins_with("FAIL"):
				ImGui.TextColored(Color.ORANGE_RED, line)
			elif line.begins_with("WARN"):
				ImGui.TextColored(Color.ORANGE, line)
			elif line.begins_with("OK"):
				ImGui.TextColored(Color.LIME_GREEN, line)
			else:
				ImGui.TextColored(Color.LIGHT_GRAY, line)
		ImGui.Separator()

	if ImGui.CollapsingHeader("Fill Detail"):
		ImGui.Indent()
		_draw_fill_detail(grid)
		ImGui.Unindent()

	if ImGui.CollapsingHeader("Window Grid"):
		ImGui.Indent()
		_draw_window_grid(grid)
		ImGui.Unindent()

	if ImGui.CollapsingHeader("Chunk Gate"):
		ImGui.Indent()
		_draw_chunk_gate(grid)
		ImGui.Unindent()

	if ImGui.CollapsingHeader("Placement Check"):
		ImGui.Indent()
		_draw_placement_check(grid)
		ImGui.Unindent()

	if ImGui.CollapsingHeader("Bend Window"):
		ImGui.Indent()
		_draw_bend_window(_delta)
		ImGui.Unindent()


# ==========================================================================
# SUMMARY
# ==========================================================================

func _draw_summary(grid : FoliageFillGrid) -> void:
	var settings : FoliageWorldSettings = foliage_world.settings_DA
	var high_budget : int = settings.high_segment_budget()
	var total_budget : int = settings.total_segment_budget()
	var filled : int = foliage_world.segments_filled

	var frac : float = float(filled) / float(maxi(total_budget, 1))
	var budget_col : Color = Color.LIME_GREEN
	if frac >= 0.999:
		budget_col = Color.ORANGE		# budget saturated -- frontier is budget-bound
	elif frac < 0.25:
		budget_col = Color.SKY_BLUE		# barely using it -- window or gate is clipping

	ImGui.TextColored(budget_col, "segments  %d / %d   (high %d / %d, low %d / %d)"
		% [filled, total_budget,
			foliage_world.high_segments_drawn, high_budget,
			foliage_world.low_segments_drawn, settings.low_lod_segment_budget])

	ImGui.Text("frontier  ring %d  =  %.1f m      search radius %d rings"
		% [grid.frontier_ring, foliage_world.frontier_radius_m, grid._DEBUG_search_radius()])

	var window_radius : float = float(grid.cells_per_dim) * 0.5 * grid.cell_spacing
	var clipped : bool = grid.frontier_ring >= (grid.cells_per_dim >> 1) - 1
	if clipped:
		ImGui.TextColored(Color.ORANGE,
			"window is clipping the fill (radius %.0f m) -- raise fine_window_cells" % window_radius)
	else:
		ImGui.Text("window    %d cells  =  %.0f m radius,  cell %.2f m"
			% [grid.cells_per_dim, window_radius, grid.cell_spacing])

	var player_global : Vector2i = grid.origin_cell + grid.player_cell
	ImGui.Text("camera    global cell %s   local %s   window origin %s"
		% [str(player_global), str(grid.player_cell), str(grid.origin_cell)])


# ==========================================================================
# FILL DETAIL
# ==========================================================================

func _draw_fill_detail(grid : FoliageFillGrid) -> void:
	# The old panel listed the left/right/centre edge arrays, then a ring
	# occupancy histogram. Neither exists now: the fill walks rings outward and
	# writes straight to the output buffer, so there is nothing to bucket. What
	# is worth watching instead is how hard the ring walk is working.
	var settings : FoliageWorldSettings = foliage_world.settings_DA
	var budget : int = settings.total_segment_budget()
	var frontier : int = grid.frontier_ring
	var radius : int = grid._DEBUG_search_radius()

	ImGui.Text("frontier ring        %d   (%.0f m)" % [frontier, grid._frontier_radius_m()])
	ImGui.Text("search radius        %d rings   window allows %d" % [radius, grid.cells_per_dim >> 1])
	ImGui.Text("emitted / budget     %d / %d" % [foliage_world.segments_filled, budget])

	# The walk visits the ring perimeters out to the search radius, but only the
	# portion of each that survives the frustum clip. This is the ratio that
	# decides the cost.
	var perimeter_cells : int = (2 * radius + 1) * (2 * radius + 1)
	var emitted : int = maxi(foliage_world.segments_filled, 1)
	ImGui.TextColored(Color.DARK_GRAY,
		"cells in the search box %d, of which %d emitted (%.0f%% -- the frustum clip skips the rest)"
		% [perimeter_cells, foliage_world.segments_filled,
			100.0 * float(emitted) / float(maxi(perimeter_cells, 1))])

	if radius >= (grid.cells_per_dim >> 1):
		ImGui.TextColored(Color.ORANGE,
			"search radius is pinned to the window -- the budget cannot fill at this FOV.")
	if foliage_world.segments_filled < budget:
		ImGui.TextColored(Color.ORANGE,
			"budget not saturated; the radius will widen over the next frame or two.")

	# The filled angle should track the camera's real horizontal half-FOV. If the
	# filled one is narrower, cells are missing at the screen edges.
	ImGui.Separator()
	var filled_half : float = grid._DEBUG_filled_half_angle_deg()
	var cam : Camera3D = get_viewport().get_camera_3d()
	var cam_half : float = 0.0
	if cam:
		var aspect : float = cam.get_viewport().get_visible_rect().size.aspect()
		cam_half = rad_to_deg(atan(tan(deg_to_rad(cam.fov) * 0.5) * aspect))
	var angle_col : Color = Color.LIME_GREEN
	if cam_half > 0.0 and filled_half < cam_half - 5.0:
		angle_col = Color.ORANGE_RED
	ImGui.TextColored(angle_col, "filled half-angle    %.1f deg   camera half-FOV %.1f deg"
		% [filled_half, cam_half])
	ImGui.Text("ground constraints   %d%s"
		% [grid._DEBUG_constraint_count(), "  (+predicted set)" if grid._DEBUG_predicting() else ""])
	ImGui.Text("yaw rate             %.0f deg/s   leading by %.1f deg"
		% [foliage_world._DEBUG_yaw_rate_deg(), foliage_world._DEBUG_predicted_yaw_deg()])
	if grid._DEBUG_constraint_count() == 0:
		ImGui.TextColored(Color.ORANGE, "no frustum constraints -- filling unclipped in every direction.")

	if not grid.DEBUG_capture_data:
		ImGui.TextColored(Color.ORANGE, "debug_capture is off -- the grid view will be blank.")


# ==========================================================================
# WINDOW GRID
# ==========================================================================

func _draw_window_grid(grid : FoliageFillGrid) -> void:
	_draw_grid_controls(grid)
	ImGui.Separator()

	var span : int = clampi(table_half_span[0], 1, MAX_TABLE_COLUMNS / 2)
	table_half_span[0] = span
	var side : int = span * 2

	var origin : Vector2i
	if follow_player:
		origin = grid.player_cell - Vector2i(span, span)
	else:
		origin = Vector2i(table_origin[0], table_origin[1])
	origin.x = clampi(origin.x, 0, maxi(grid.cells_per_dim - side, 0))
	origin.y = clampi(origin.y, 0, maxi(grid.cells_per_dim - side, 0))
	table_origin[0] = origin.x
	table_origin[1] = origin.y

	var high_budget : int = foliage_world.settings_DA.high_segment_budget()
	var frontier : int = maxi(grid.frontier_ring, 1)

	var player_c : Color = _col(col_player)

	ImGui.SetWindowFontScale(0.925)
	if ImGui.BeginTable("FoliageWindow", side,
			ImGui.TableFlags_SizingFixedFit | ImGui.TableFlags_ScrollX):
		for row in range(origin.y, origin.y + side):
			for col in range(origin.x, origin.x + side):
				var local := Vector2i(col, row)

				if draw_player and local == grid.player_cell:
					ImGui.TextColored(player_c, "P")
				elif grid._DEBUG_status_at(local) == FoliageFillGrid.CellStatus.UNVISITED:
					ImGui.Text("-")
				else:
					_draw_cell(grid, local, high_budget, frontier)

				ImGui.TableNextColumn()
			ImGui.TableNextRowEx(0, 0)
		ImGui.EndTable()
	ImGui.SetWindowFontScale(1.0)


func _draw_cell(grid : FoliageFillGrid, local : Vector2i, high_budget : int, frontier : int) -> void:
	var status : int = grid._DEBUG_status_at(local)
	var rank : int = grid._DEBUG_rank_at(local)

	match colour_mode:
		ColourMode.TIER:
			if rank < 0:
				ImGui.TextColored(_col(col_dropped), "x")
			elif rank < high_budget:
				ImGui.TextColored(_col(col_high), "H")
			else:
				ImGui.TextColored(_col(col_low), "L")

		ColourMode.RING:
			var ring : int = grid._DEBUG_ring_at(local)
			var t : float = clampf(float(ring) / float(frontier), 0.0, 1.0)
			var ring_col : Color = _col(col_high).lerp(_col(col_low), t)
			if rank < 0:
				ring_col = _col(col_dropped)
			ImGui.TextColored(ring_col, str(ring % 10))

		_:
			match status:
				FoliageFillGrid.CellStatus.EMITTED:
					ImGui.TextColored(_col(col_emitted), "E")
				FoliageFillGrid.CellStatus.GATED:
					ImGui.TextColored(_col(col_gated), "g")
				_:
					ImGui.Text("-")


func _draw_grid_controls(grid : FoliageFillGrid) -> void:
	if ImGui.RadioButton("Status", colour_mode == ColourMode.STATUS):
		colour_mode = ColourMode.STATUS
	ImGui.SameLine()
	if ImGui.RadioButton("Tier", colour_mode == ColourMode.TIER):
		colour_mode = ColourMode.TIER
	ImGui.SameLine()
	if ImGui.RadioButton("Ring", colour_mode == ColourMode.RING):
		colour_mode = ColourMode.RING

	if colour_mode == ColourMode.STATUS:
		ImGui.TextColored(_col(col_emitted), "E = emitted")
		ImGui.SameLine()
		ImGui.TextColored(_col(col_gated), "g = gated out")
		ImGui.SameLine()
		draw_player = _swatch_toggle("Player", col_player, draw_player)
	else:
		ImGui.TextColored(_col(col_high), "H = high LOD")
		ImGui.SameLine()
		ImGui.TextColored(_col(col_low), "L = low LOD")
		ImGui.SameLine()
		ImGui.TextColored(_col(col_dropped), "x = claimed but past budget")

	var follow_arr : Array[bool] = [follow_player]
	if ImGui.Checkbox("Follow camera", follow_arr):
		follow_player = follow_arr[0]

	ImGui.SameLine()
	ImGui.PushItemWidth(75)
	ImGui.InputInt("Half span", table_half_span)
	if not follow_player:
		ImGui.SameLine()
		ImGui.InputInt2("Origin", table_origin)
	ImGui.PopItemWidth()

	var origin_world : Vector2 = grid.origin_world + Vector2(table_origin[0], table_origin[1]) * grid.cell_spacing
	ImGui.TextColored(Color.DARK_GRAY, "view top-left world XZ  %.1f, %.1f" % [origin_world.x, origin_world.y])


# ==========================================================================
# CHUNK GATE
# ==========================================================================

func _draw_chunk_gate(grid : FoliageFillGrid) -> void:
	var settings : FoliageWorldSettings = foliage_world.settings_DA
	var per_dim : int = settings.chunks_per_dim()
	var gate : PackedByteArray = foliage_world._DEBUG_chunk_gate_arr()
	var enabled : PackedByteArray = foliage_world._DEBUG_chunk_enabled_arr()

	if gate.size() != per_dim * per_dim or enabled.size() != per_dim * per_dim:
		ImGui.TextColored(Color.ORANGE_RED, "gate arrays not sized yet")
		return

	ImGui.Text("%d registered chunks over a %dx%d grid" % [foliage_world._DEBUG_chunk_count(), per_dim, per_dim])
	ImGui.TextColored(Color.DARK_GRAY, "#  emitting     o  authored but out of reach     .  no foliage")

	var player_global : Vector2i = grid.origin_cell + grid.player_cell
	var cells_per_chunk : int = maxi(grid.cells_per_gate, 1)
	var player_chunk := Vector2i(player_global.x / cells_per_chunk, player_global.y / cells_per_chunk)

	var columns : int = mini(per_dim, MAX_TABLE_COLUMNS)
	ImGui.SetWindowFontScale(0.925)
	if ImGui.BeginTable("FoliageGate", columns,
			ImGui.TableFlags_SizingFixedFit | ImGui.TableFlags_ScrollX):
		for row in per_dim:
			for col in columns:
				var index : int = col + row * per_dim
				if Vector2i(col, row) == player_chunk:
					ImGui.TextColored(_col(col_player), "@")
				elif gate[index] != 0:
					ImGui.TextColored(_col(col_emitted), "#")
				elif enabled[index] != 0:
					ImGui.TextColored(_col(col_dropped), "o")
				else:
					ImGui.Text(".")
				ImGui.TableNextColumn()
			ImGui.TableNextRowEx(0, 0)
		ImGui.EndTable()
	ImGui.SetWindowFontScale(1.0)


# ==========================================================================
# PLACEMENT CHECK
# ==========================================================================

# Compares where a segment was asked for against where its blades actually
# landed. The delta is the whole answer: a constant offset means the shader and
# the CPU disagree about how a cell index becomes a world position, and the
# value of the offset says which term is missing.
func _draw_placement_check(grid : FoliageFillGrid) -> void:
	var settings : FoliageWorldSettings = foliage_world.settings_DA
	var head : PackedInt32Array = foliage_world._DEBUG_head_segment_coords()

	if head.size() < 2:
		ImGui.TextColored(Color.ORANGE, "no segments drained yet")
		return

	var cell := Vector2i(head[0], head[1])
	var expected : Vector2 = foliage_world._DEBUG_expected_world_xz(cell)
	ImGui.Text("segment[0]  global cell %s  ->  expected world  %.1f, %.1f"
		% [str(cell), expected.x, expected.y])

	var high_arr : Array[bool] = [placement_check_high]
	if ImGui.Checkbox("High LOD tier", high_arr):
		placement_check_high = high_arr[0]
	ImGui.SameLine()
	if ImGui.Button("Read instances"):
		_placement_samples = foliage_world._DEBUG_read_instance_positions(placement_check_high, 4)

	if _placement_samples.is_empty():
		ImGui.TextColored(Color.DARK_GRAY, "press Read instances (stalls the GPU for a small buffer read)")
		return

	var first : Vector3 = _placement_samples[0]
	ImGui.Text("instance[0] actual world  %.1f, %.1f, %.1f" % [first.x, first.y, first.z])

	# blades are scattered inside their segment, so anything under a cell or so
	# is just placement jitter rather than a real offset
	var delta := Vector2(first.x - expected.x, first.z - expected.y)
	var offset_col : Color = Color.LIME_GREEN if delta.length() < grid.cell_spacing * 2.0 else Color.ORANGE_RED
	ImGui.TextColored(offset_col, "delta  %.1f, %.1f  (cell size %.1f)"
		% [delta.x, delta.y, grid.cell_spacing])

	var origin : Vector2 = settings.world_origin_xz
	if delta.distance_to(-origin) < grid.cell_spacing * 2.0:
		ImGui.TextColored(Color.ORANGE_RED,
			"delta matches -world_origin_xz: the shader is not adding world_origin")
		ImGui.TextWrapped("It is reconstructing world position as seg * cell_size, the way the "
			+ "per-chunk version did. See float params [10] and [11] in SHADER_CHANGES.md.")
	elif delta.length() >= grid.cell_spacing * 2.0:
		ImGui.TextWrapped("Offset does not match -world_origin_xz, so something else is wrong: "
			+ "check height_stride, dispatch_width, and that segment coords are read as "
			+ "global cells rather than chunk-local ones.")

	for i in range(1, _placement_samples.size()):
		var pos : Vector3 = _placement_samples[i]
		ImGui.TextColored(Color.DARK_GRAY, "instance[%d]  %.1f, %.1f, %.1f" % [i, pos.x, pos.y, pos.z])


# ==========================================================================
# BEND WINDOW
# ==========================================================================

func _draw_bend_window(delta : float) -> void:
	var settings : FoliageWorldSettings = foliage_world.settings_DA
	var res : int = settings.bend_mask_res
	var origin : Vector2i = foliage_world._DEBUG_bender_origin_texel()

	ImGui.TextColored(Color.CHOCOLATE,
		"Source is mirrored (camera renders from below); bend_flip_source_x/z undo it.")
	ImGui.Text("%.0f m window at %d px  (%.1f texels/m)   origin texel %s"
		% [settings.bend_window_size_m, res, settings.bend_texels_per_m(), str(origin)])

	ImGui.PushItemWidth(100)
	ImGui.SliderFloat("Scale", bend_img_scale, 0.05, 1.0)
	ImGui.SameLine()
	ImGui.SliderFloat("Readback Hz", bend_refresh_hz, 0.0, 30.0)
	ImGui.PopItemWidth()

	ImGui.SameLine()
	var unwrap_arr : Array[bool] = [bend_unwrap]
	if ImGui.Checkbox("Unwrap", unwrap_arr):
		bend_unwrap = unwrap_arr[0]

	ImGui.SameLine()
	var force : bool = ImGui.Button("Refresh")

	# texture_get_data stalls the GPU for a full res^2 readback -- 4 MB at
	# 1024 RF. Throttled, and at 0 Hz it only updates on the button.
	_bend_timer -= delta
	if force or (bend_refresh_hz[0] > 0.0 and _bend_timer <= 0.0):
		_bend_timer = 1.0 / maxf(bend_refresh_hz[0], 0.001)
		_refresh_bend_readback(res)

	ImGui.TextColored(Color.DARK_GRAY, "last readback %.2f ms" % _bend_readback_ms)

	var scale : float = bend_img_scale[0]

	if foliage_world.bender_mask_subviewport:
		var source : Texture = foliage_world.bender_mask_subviewport.get_texture()
		ImGui.Text("Source (this frame's benders)")
		ImGui.ImageEx(source, source.get_size() * scale, Vector2.ZERO, Vector2.ONE)
		ImGui.SameLine()

	if _bend_cached_tex:
		ImGui.Text("Accumulator%s" % ("  [unwrapped]" if bend_unwrap else "  [raw, toroidal]"))
		if bend_unwrap:
			_draw_unwrapped(_bend_cached_tex, res, origin, scale)
		else:
			ImGui.ImageEx(_bend_cached_tex, _bend_cached_tex.get_size() * scale, Vector2.ZERO, Vector2.ONE)
	else:
		ImGui.TextColored(Color.ORANGE, "no accumulator readback yet")


func _refresh_bend_readback(res : int) -> void:
	var rid : RID = foliage_world._DEBUG_bender_image_RID()
	if not rid.is_valid():
		return

	var start : int = Time.get_ticks_usec()
	var rd : RenderingDevice = RenderingServer.get_rendering_device()
	var raw : PackedByteArray = rd.texture_get_data(rid, 0)
	if raw.size() < res * res * 4:
		return

	var img : Image = Image.create_from_data(res, res, false, Image.FORMAT_RF, raw)
	_bend_cached_tex = ImageTexture.create_from_image(img)
	_bend_readback_ms = float(Time.get_ticks_usec() - start) / 1000.0


# The accumulator is world-anchored and addressed toroidally, so window-local
# (0,0) sits at accumulator texel (origin & (res-1)) and the image is torn into
# up to four pieces. Reassemble them with UV sub-rects rather than shuffling
# pixels -- a res^2 pixel roll in GDScript would be unusable.
func _draw_unwrapped(tex : Texture2D, res : int, origin : Vector2i, scale : float) -> void:
	var mask : int = res - 1
	var off := Vector2i(origin.x & mask, origin.y & mask)
	var span_a := Vector2i(res - off.x, res - off.y)

	var base : Vector2 = ImGui.GetCursorPos()
	var inv : float = 1.0 / float(res)

	var pieces : Array = [
		[Vector2i(off.x, off.y), span_a, Vector2i(0, 0)],
		[Vector2i(0, off.y), Vector2i(off.x, span_a.y), Vector2i(span_a.x, 0)],
		[Vector2i(off.x, 0), Vector2i(span_a.x, off.y), Vector2i(0, span_a.y)],
		[Vector2i(0, 0), off, span_a],
	]

	for piece in pieces:
		var src : Vector2i = piece[0]
		var size : Vector2i = piece[1]
		if size.x <= 0 or size.y <= 0:
			continue
		var dst : Vector2i = piece[2]
		ImGui.SetCursorPos(base + Vector2(dst) * scale)
		ImGui.ImageEx(tex, Vector2(size) * scale,
			Vector2(src) * inv, Vector2(src + size) * inv)

	# park the cursor below the reassembled image so later widgets lay out right
	ImGui.SetCursorPos(base + Vector2(0.0, float(res) * scale))


# ==========================================================================
# HELPERS
# ==========================================================================

func _col(components : Array[float]) -> Color:
	return Color(components[0], components[1], components[2], 1.0)


# Swatch plus checkbox on one line. The original repeated this block six times;
# it is the same widget every time.
func _swatch_toggle(label : String, components : Array[float], enabled : bool) -> bool:
	ImGui.ColorEdit3("##col_" + label, components,
		ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	ImGui.SameLine()
	var arr : Array[bool] = [enabled]
	if ImGui.Checkbox(label, arr):
		return arr[0]
	return enabled
