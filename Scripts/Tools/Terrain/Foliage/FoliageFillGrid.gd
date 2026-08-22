class_name FoliageFillGrid extends RefCounted

const RING_SLACK : int = 6			# rings explored past the frontier before retightening
const MIN_RADIUS_HINT : int = 8

# SETUP
var cells_per_dim : int = 0
var cell_spacing : float = 1.0
var origin_cell : Vector2i			# cell offset that tconverts local to global cells space
var origin_world : Vector2			# world XZ of local (0,0)'s min corner

# Global grid extent in cells. Cells outside are skipped. 0 disables.
var world_cells : int = 0

#byte per chunk saying whether foliage is allowed there, with gate_stride and cells_per_gate describing its layout.
var gate : PackedByteArray
var gate_stride : int = 0
var cells_per_gate : int = 1

#outer padding so cells partly visible still count
var edge_pad_cells : float = 1.0

#how far the camera is expected to turn before this frame's grass reaches the screen.
var predict_yaw_rad : float = 0.0

# vertical slack that stops a hill poking into view from being clipped away.
var terrain_vertical_slack : float = 20.0

var DEBUG_capture_data : bool = false

enum CellStatus { UNVISITED = 0, EMITTED = 1, GATED = 2 }

# RESULTS
# cell the player is in aka the center of the window we're traversing
var player_cell : Vector2i
# amount of valid cells this iteration
var accepted : int = 0
#ring we ran out of budget
var frontier_ring : int = 0
var max_ring : int = 0

# WORK MEM
var out_arr : PackedInt32Array			# emitted global cells, 2 ints each, ring order
var status_arr : PackedByteArray		# per local cell, CellStatus
var index_arr : PackedInt32Array		# per local cell, emit index, -1 if not emitted


# ground plane contraints
var ca : PackedFloat32Array
var cb : PackedFloat32Array
var cc : PackedFloat32Array
const PREDICT_BASE : int = 8	#id of where in above arrays we go from current constraint to predicted constraints

var constraint_count : int = 0
var predict_active : bool = false

var cam_fwd : Vector2 = Vector2(0.0, -1.0)		# camera forward in XZ, for diagnostics
var player_sub : Vector2

# self-tuning search radius: no point walking rings the budget can never reach
var radius_hint : int = 0

func _initialize(p_dims : int, p_cell_size : float, budget : int) -> void:
	# force even so the camera lands exactly on the centre cell
	cells_per_dim = p_dims + (p_dims & 1)
	cell_spacing = p_cell_size
	max_ring = (cells_per_dim >> 1) + 2
	radius_hint = cells_per_dim >> 1

	out_arr.resize(maxi(budget, 1) * 2)
	status_arr.resize(cells_per_dim * cells_per_dim)
	status_arr.fill(0)
	index_arr.resize(cells_per_dim * cells_per_dim)
	index_arr.fill(-1)

	ca.resize(PREDICT_BASE * 2)
	cb.resize(PREDICT_BASE * 2)
	cc.resize(PREDICT_BASE * 2)

# slides window towards camera, snapped to whole cell_spacing to prevent jitter
func _centre_on(world_xz : Vector2, world_origin : Vector2) -> void:
	var cell : Vector2i = Vector2i(
		floori((world_xz.x - world_origin.x) / cell_spacing),
		floori((world_xz.y - world_origin.y) / cell_spacing))
	origin_cell = cell - Vector2i(cells_per_dim >> 1, cells_per_dim >> 1)
	origin_world = world_origin + Vector2(origin_cell) * cell_spacing

# convert world position X/Z to sub cell coords
func _world_to_sub(world_xz : Vector2) -> Vector2:
	return (world_xz - origin_world) / cell_spacing

# byte array copy of all accepted cells this frame
func _out_slice(cell_count : int) -> PackedByteArray:
	return out_arr.slice(0, cell_count * 2).to_byte_array()

# how far away is frontier of where we stop accepting cells
func _frontier_radius_m() -> float:
	return float(frontier_ring) * cell_spacing

# per-frame 
func _build(view : FoliageViewSnapshot, budget : int) -> int:
	#reset data
	accepted = 0
	frontier_ring = 0
	budget = clampi(budget, 1, out_arr.size() >> 1)

	if DEBUG_capture_data:
		status_arr.fill(0)
		index_arr.fill(-1)

	#gather current player data
	player_sub = _world_to_sub(Vector2(view.cam_origin.x, view.cam_origin.z))
	player_cell = Vector2i(floori(player_sub.x), floori(player_sub.y))

	var fwd_flat : Vector2 = Vector2(view.cam_forward.x, view.cam_forward.z)
	if fwd_flat.length_squared() > 0.000001:
		cam_fwd = fwd_flat.normalized()

	_setup_constraints(view)

	# put everything in local variables for easy lookups
	var px : int = player_cell.x
	var py : int = player_cell.y
	var ocx : int = origin_cell.x
	var ocy : int = origin_cell.y
	var wc : int = world_cells
	var gs : int = gate_stride
	var cpg : int = maxi(cells_per_gate, 1)
	var capture : bool = DEBUG_capture_data

	# world bounds expressed as local column/row limits, so the inner loop never has to test them per cell
	var col_min : int = 0
	var col_max : int = cells_per_dim - 1
	var row_min : int = 0
	var row_max : int = cells_per_dim - 1
	if wc > 0:
		col_min = maxi(col_min, -ocx)
		col_max = mini(col_max, wc - 1 - ocx)
		row_min = maxi(row_min, -ocy)
		row_max = mini(row_max, wc - 1 - ocy)

	var written : int = 0
	var search_radius : int = clampi(radius_hint, MIN_RADIUS_HINT, cells_per_dim >> 1)

	# walk outwards ring by ring until the budget fills
	for r in range(0, search_radius + 1):
		if written >= budget:
			break
		frontier_ring = r

		# --- the ring's two horizontal sides ------------------------------
		# Names are prefixed h_ / v_ throughout. The two side loops are
		# siblings, so reusing bare `row`, `col`, `span` across them is legal
		# block scoping but reads as a redeclaration and trips the shadowing
		# warning -- not worth the ambiguity in the one hot loop in the file.
		for h_side in 2:
			if r == 0 and h_side == 1:
				continue			# ring 0 is a single cell
			var h_row : int = py - r if h_side == 0 else py + r
			if h_row < row_min or h_row > row_max:
				continue

			var h_span : Vector2 = _clip_row(float(h_row) + 0.5)
			var h_c0 : int = maxi(px - r, col_min)
			var h_c1 : int = mini(px + r, col_max)
			if is_finite(h_span.x):
				h_c0 = maxi(h_c0, ceili(h_span.x - 0.5))
			if is_finite(h_span.y):
				h_c1 = mini(h_c1, floori(h_span.y - 0.5))
			if h_c0 > h_c1:
				continue

			var h_gate_row : int = ((ocy + h_row) / cpg) * gs
			var h_row_base : int = h_row * cells_per_dim
			var h_gy : int = ocy + h_row

			for h_col in range(h_c0, h_c1 + 1):
				if written >= budget:
					break
				var h_gx : int = ocx + h_col
				if gs > 0 and gate[h_gate_row + (h_gx / cpg)] == 0:
					if capture:
						status_arr[h_row_base + h_col] = 2
					continue
				out_arr[written * 2] = h_gx
				out_arr[written * 2 + 1] = h_gy
				if capture:
					status_arr[h_row_base + h_col] = 1
					index_arr[h_row_base + h_col] = written
				written += 1

		# --- the ring's two vertical sides, corners already covered above --
		if r > 0:
			for v_side in 2:
				var v_col : int = px - r if v_side == 0 else px + r
				if v_col < col_min or v_col > col_max:
					continue

				var v_span : Vector2 = _clip_col(float(v_col) + 0.5)
				var v_r0 : int = maxi(py - r + 1, row_min)
				var v_r1 : int = mini(py + r - 1, row_max)
				if is_finite(v_span.x):
					v_r0 = maxi(v_r0, ceili(v_span.x - 0.5))
				if is_finite(v_span.y):
					v_r1 = mini(v_r1, floori(v_span.y - 0.5))
				if v_r0 > v_r1:
					continue

				var v_gx : int = ocx + v_col
				var v_gate_col : int = v_gx / cpg

				for v_row in range(v_r0, v_r1 + 1):
					if written >= budget:
						break
					if gs > 0 and gate[((ocy + v_row) / cpg) * gs + v_gate_col] == 0:
						if capture:
							status_arr[v_row * cells_per_dim + v_col] = 2
						continue
					out_arr[written * 2] = v_gx
					out_arr[written * 2 + 1] = ocy + v_row
					if capture:
						status_arr[v_row * cells_per_dim + v_col] = 1
						index_arr[v_row * cells_per_dim + v_col] = written
					written += 1

	accepted = written

	# Retighten the search radius for next frame. If the budget filled there is
	# no reason to walk far past the ring it filled on; if it did not, widen and
	# try again. Converges in a frame or two and costs nothing.
	if written >= budget:
		radius_hint = frontier_ring + RING_SLACK
	else:
		radius_hint = mini((radius_hint * 5) / 4 + 4, cells_per_dim >> 1)

	return written

#converts each of the cameras planes into 2D line
func _setup_constraints(view : FoliageViewSnapshot) -> void:
	constraint_count = 0
	predict_active = false
	if view.frustum.size() < 4:
		return					# no clipping; the ring walk fills a disc

	var y_lo : float = view.ground_y - terrain_vertical_slack
	var y_hi : float = view.ground_y + terrain_vertical_slack

	for plane in view.frustum:
		var n : Vector3 = plane.normal
		var d : float = plane.d

		# Godot does not promise which way these face or what order they come
		# in, so orient each one against a point known to be inside.
		if n.dot(view.inside_point) - d < 0.0:
			n = -n
			d = -d

		var a : float = n.x * cell_spacing
		var b : float = n.z * cell_spacing
		var len_sq : float = a * a + b * b

		# whichever height in the relief band makes this constraint loosest
		var k : float = y_hi if n.y > 0.0 else y_lo
		var c : float = n.x * origin_world.x + n.z * origin_world.y + n.y * k - d

		if len_sq < 0.000000001:
			if c < 0.0:
				constraint_count = 0
				return
			continue

		# dilate outward so a cell counts as visible if any part of it is
		cc[constraint_count] = c + edge_pad_cells * sqrt(len_sq)
		ca[constraint_count] = a
		cb[constraint_count] = b
		constraint_count += 1

		if constraint_count >= PREDICT_BASE:
			break

	_build_predicted_constraints()

# the predicted constrained are the current ones rotated about the camera by the amount we thinkg the camera will mvove
func _build_predicted_constraints() -> void:
	predict_active = false
	if constraint_count == 0 or absf(predict_yaw_rad) < 0.0005:
		return

	var cosa : float = cos(predict_yaw_rad)
	var sina : float = sin(predict_yaw_rad)
	var px : float = player_sub.x
	var pz : float = player_sub.y

	for i in constraint_count:
		var a : float = ca[i]
		var b : float = cb[i]
		# the constraint's value at the pivot is invariant under rotation about it
		var at_pivot : float = a * px + b * pz + cc[i]
		var a2 : float = a * cosa - b * sina
		var b2 : float = a * sina + b * cosa
		ca[PREDICT_BASE + i] = a2
		cb[PREDICT_BASE + i] = b2
		cc[PREDICT_BASE + i] = at_pivot - (a2 * px + b2 * pz)

	predict_active = true

# The x interval of a horizontal line that satisfies every constraint. Returns
# (lo, hi), either bound possibly infinite; lo > hi means the row misses.
# Called four times per ring rather than once per cell, which is why it can
# afford to be a function call at all.
func _clip_row(z : float) -> Vector2:
	var span : Vector2 = _clip_row_set(z, 0)
	if not predict_active:
		return span
	return _hull(span, _clip_row_set(z, PREDICT_BASE))

func _clip_row_set(z : float, base : int) -> Vector2:
	var lo : float = -INF
	var hi : float = INF

	for i in constraint_count:
		var a : float = ca[base + i]
		var rhs : float = -(cb[base + i] * z + cc[base + i])
		if absf(a) < 0.000001:
			if rhs > 0.0:
				return Vector2(1.0, -1.0)
		elif a > 0.0:
			lo = maxf(lo, rhs / a)
		else:
			hi = minf(hi, rhs / a)

	return Vector2(lo, hi)


# The z interval of a vertical line that satisfies every constraint.
func _clip_col(x : float) -> Vector2:
	var span : Vector2 = _clip_col_set(x, 0)
	if not predict_active:
		return span
	return _hull(span, _clip_col_set(x, PREDICT_BASE))


func _clip_col_set(x : float, base : int) -> Vector2:
	var lo : float = -INF
	var hi : float = INF

	for i in constraint_count:
		var b : float = cb[base + i]
		var rhs : float = -(ca[base + i] * x + cc[base + i])
		if absf(b) < 0.000001:
			if rhs > 0.0:
				return Vector2(1.0, -1.0)
		elif b > 0.0:
			lo = maxf(lo, rhs / b)
		else:
			hi = minf(hi, rhs / b)

	return Vector2(lo, hi)


# Smallest interval containing both. A union of two overlapping intervals is one
# interval; if a turn is fast enough to make them disjoint the hull bridges the
# gap, which over-includes a little rather than leaving a hole.
func _hull(p : Vector2, q : Vector2) -> Vector2:
	if p.x > p.y:
		return q
	if q.x > q.y:
		return p
	return Vector2(minf(p.x, q.x), maxf(p.y, q.y))


#region DEBUG

# All take LOCAL window coordinates, and are meaningful only for the most recent
# _build, and only when DEBUG_capture_data was on for it.
func _DEBUG_status_at(local : Vector2i) -> int:
	if local.x < 0 or local.y < 0 or local.x >= cells_per_dim or local.y >= cells_per_dim:
		return CellStatus.UNVISITED
	return status_arr[local.x + local.y * cells_per_dim]

func _DEBUG_is_emitted(local : Vector2i) -> bool:
	return _DEBUG_status_at(local) == CellStatus.EMITTED

# Position in the emit order, so index_arr < high_segment_budget means this cell got
# high LOD. -1 means not emitted.
func _DEBUG_rank_at(local : Vector2i) -> int:
	if local.x < 0 or local.y < 0 or local.x >= cells_per_dim or local.y >= cells_per_dim:
		return -1
	return index_arr[local.x + local.y * cells_per_dim]


func _DEBUG_ring_at(local : Vector2i) -> int:
	return maxi(absi(local.x - player_cell.x), absi(local.y - player_cell.y))

func _DEBUG_search_radius() -> int:
	return radius_hint

func _DEBUG_constraint_count() -> int:
	return constraint_count

func _DEBUG_predicting() -> bool:
	return predict_active

# Half-width of the region actually being filled, measured by sweeping rays out_arr from the camera and asking the constraints
func _DEBUG_filled_half_angle_deg() -> float:
	if constraint_count == 0:
		return 180.0

	var probe : float = float(maxi(radius_hint, 8)) * 0.5
	var widest : float = 0.0

	for step in 181:
		var deg : float = float(step - 90)
		var dir : Vector2 = cam_fwd.rotated(deg_to_rad(deg))
		var p : Vector2 = player_sub + dir * probe
		var ok : bool = true
		for i in constraint_count:
			if ca[i] * p.x + cb[i] * p.y + cc[i] < 0.0:
				ok = false
				break
		if ok:
			widest = maxf(widest, absf(deg))

	return widest

#endregion
