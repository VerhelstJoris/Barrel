class_name FoliageFillGrid extends RefCounted

const RING_SLACK : int = 6			# rings explored past the frontier before retightening
const MIN_RADIUS_HINT : int = 8

# Emitted cells are packed one int per cell: global x in the low 16 bits, global z
# in the high 16. Halves the stores in the ring walk, the byte conversion, the
# upload and the GPU buffer. Cells are clamped to [0, world_cells) so both halves
# are non-negative; world_cells must stay at or under PACK_LIMIT for this to hold.
# The shader unpacks with (v & 0xFFFF, (v >> 16) & 0xFFFF).
const PACK_SHIFT : int = 16
const PACK_STEP_Z : int = 1 << PACK_SHIFT	# adding this steps one cell in z
const PACK_LIMIT : int = 32768

# opt: finite stand-ins for an unbounded span, so ceili()/floori() stay safe and the ring walk needs no is_finite() branches
const SPAN_OPEN_LO : float = -1.0e9
const SPAN_OPEN_HI : float = 1.0e9
const SPAN_MISS : Vector2 = Vector2(1.0, -1.0)

# SETUP
var cells_per_dim : int = 0
var cell_spacing : float = 1.0
var origin_cell : Vector2i			# cell offset that tconverts local to global cells space
var origin_world : Vector2			# world XZ of local (0,0)'s min corner

# Global grid extent in cells. Cells outside are skipped. 0 disables.
var world_cells : int = 0


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
var out_arr : PackedInt32Array			# emitted global cells, 1 packed int each, ring order
var status_arr : PackedByteArray		# per local cell, CellStatus -- allocated lazily, debug only
var index_arr : PackedInt32Array		# per local cell, emit index, -1 if not emitted -- debug only


# ground plane contraints
# opt: float64 instead of float32 so the cached reciprocals below stay exact and no f32->double widening happens per access
var ca : PackedFloat64Array
var cb : PackedFloat64Array
var cc : PackedFloat64Array
# opt: 1/ca and 1/cb precomputed once per frame; the clip loops multiply instead of dividing, 0.0 flags a degenerate axis
var ca_inv : PackedFloat64Array
var cb_inv : PackedFloat64Array
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

	out_arr.resize(maxi(budget, 1))		# opt: one packed int per cell, not two loose ones

	# opt: debug buffers are no longer allocated up front (5 bytes per cell, ~1.3MB at 512 dims); _build sizes them on the first capture frame
	status_arr.resize(0)
	index_arr.resize(0)

	ca.resize(PREDICT_BASE * 2)
	cb.resize(PREDICT_BASE * 2)
	cc.resize(PREDICT_BASE * 2)
	ca_inv.resize(PREDICT_BASE * 2)
	cb_inv.resize(PREDICT_BASE * 2)

# slides window towards camera, snapped to whole cell_spacing to prevent jitter
func _centre_on(world_xz : Vector2, world_origin : Vector2) -> void:
	var inv_spacing : float = 1.0 / cell_spacing		# opt: one divide reused by both axes
	var cell : Vector2i = Vector2i(
		floori((world_xz.x - world_origin.x) * inv_spacing),
		floori((world_xz.y - world_origin.y) * inv_spacing))
	origin_cell = cell - Vector2i(cells_per_dim >> 1, cells_per_dim >> 1)
	origin_world = world_origin + Vector2(origin_cell) * cell_spacing

# convert world position X/Z to sub cell coords
func _world_to_sub(world_xz : Vector2) -> Vector2:
	return (world_xz - origin_world) / cell_spacing

# Byte array copy of all accepted cells this frame. May be LONGER than the live
# data: the caller passes its own byte count to buffer_update, which reads only
# that prefix, so there is no need to trim the tail off.
func _out_slice(cell_count : int) -> PackedByteArray:
	# opt: slicing first copies the used ints twice (slice, then widen to bytes) and
	# allocates twice; converting whole copies the buffer once and allocates once.
	# Whole wins as soon as more than half the buffer is live, which the budget
	# retightening makes the normal case.
	var used : int = cell_count			# opt: one packed int per cell
	if used * 2 >= out_arr.size():
		return out_arr.to_byte_array()
	return out_arr.slice(0, used).to_byte_array()

# opt: live byte count for the frame, so callers never have to trim the array itself
func _out_byte_size(cell_count : int) -> int:
	return cell_count * 4

# how far away is frontier of where we stop accepting cells
func _frontier_radius_m() -> float:
	return float(frontier_ring) * cell_spacing

# per-frame 
func _build(view : FoliageViewSnapshot, budget : int) -> int:
	#reset data
	accepted = 0
	frontier_ring = 0
	budget = clampi(budget, 1, out_arr.size())

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
	var cpd : int = cells_per_dim		# opt: hoisted, it is used in every row-base and debug index
	var wc : int = world_cells
	var capture : bool = DEBUG_capture_data

	# packing puts z in the high 16 bits, so a world wider than this would overflow
	assert(wc <= PACK_LIMIT, "FoliageFillGrid: world_cells must be <= %d for 16:16 coord packing" % PACK_LIMIT)

	# opt: debug buffers sized and cleared only on frames that actually capture, not on every _initialize
	if capture:
		var cell_total : int = cpd * cpd
		if status_arr.size() != cell_total:
			status_arr.resize(cell_total)
			index_arr.resize(cell_total)
		status_arr.fill(0)
		index_arr.fill(-1)

	# world bounds expressed as local column/row limits, so the inner loop never has to test them per cell
	var col_min : int = 0
	var col_max : int = cpd - 1
	var row_min : int = 0
	var row_max : int = cpd - 1
	if wc > 0:
		col_min = maxi(col_min, -ocx)
		col_max = mini(col_max, wc - 1 - ocx)
		row_min = maxi(row_min, -ocy)
		row_max = mini(row_max, wc - 1 - ocy)

	# opt: one packed int per cell, so the cursor is the cell count and needs no doubling
	var w : int = 0
	var fr : int = 0					# opt: local mirror of frontier_ring, stored back once at the end
	var search_radius : int = clampi(radius_hint, MIN_RADIUS_HINT, cpd >> 1)

	# walk outwards ring by ring until the budget fills
	for r in search_radius + 1:			# opt: int iteration, no range() object in the loop header
		if w >= budget:
			break
		fr = r

		# opt: once every side of the ring has left the world box no larger ring can re-enter it, so stop walking
		if py - r < row_min and py + r > row_max and px - r < col_min and px + r > col_max:
			fr = search_radius			# report the same frontier the un-broken walk would have
			break

		# --- the ring's two horizontal sides ------------------------------
		# Names are prefixed h_ / v_ throughout. The two side loops are
		# siblings, so reusing bare `row`, `col`, `span` across them is legal
		# block scoping but reads as a redeclaration and trips the shadowing
		# warning -- not worth the ambiguity in the one hot loop in the file.
		var h_sides : int = 1 if r == 0 else 2		# opt: ring 0 handled by the bound, not by a per-iteration continue
		for h_side in h_sides:
			if w >= budget:
				break					# opt: budget tested per side instead of per cell
			var h_row : int = py - r if h_side == 0 else py + r
			if h_row < row_min or h_row > row_max:
				continue

			var h_span : Vector2 = _clip_row(float(h_row) + 0.5)
			# opt: sentinel spans fold straight into maxi/mini, replacing the is_finite() tests
			var h_c0 : int = maxi(maxi(px - r, col_min), ceili(h_span.x - 0.5))
			var h_c1 : int = mini(mini(px + r, col_max), floori(h_span.y - 0.5))
			h_c1 = mini(h_c1, h_c0 + (budget - w) - 1)		# opt: span pre-clamped to the remaining budget
			if h_c0 > h_c1:
				continue

			# opt: z is fixed across the row, so its high half is packed once here and
			# stepping x by one cell is just an increment of the packed value
			var h_packed : int = ((ocy + h_row) << PACK_SHIFT) | (ocx + h_c0)
			var h_left : int = h_c1 - h_c0 + 1
			while h_left > 0:					# opt: one store per cell, no budget test, no capture branch
				out_arr[w] = h_packed
				w += 1
				h_packed += 1
				h_left -= 1

		# --- the ring's two vertical sides, corners already covered above --
		if r > 0:
			for v_side in 2:
				if w >= budget:
					break
				var v_col : int = px - r if v_side == 0 else px + r
				if v_col < col_min or v_col > col_max:
					continue

				var v_span : Vector2 = _clip_col(float(v_col) + 0.5)
				var v_r0 : int = maxi(maxi(py - r + 1, row_min), ceili(v_span.x - 0.5))
				var v_r1 : int = mini(mini(py + r - 1, row_max), floori(v_span.y - 0.5))
				v_r1 = mini(v_r1, v_r0 + (budget - w) - 1)		# opt: same budget pre-clamp as the rows
				if v_r0 > v_r1:
					continue

				# opt: x is fixed down the column, so stepping z by one cell is one add of 1 << 16
				var v_packed : int = ((ocy + v_r0) << PACK_SHIFT) | (ocx + v_col)
				var v_left : int = v_r1 - v_r0 + 1
				while v_left > 0:
					out_arr[w] = v_packed
					w += 1
					v_packed += PACK_STEP_Z
					v_left -= 1

	frontier_ring = fr
	var written : int = w					# opt: cursor is already the cell count
	accepted = written

	# opt: debug bookkeeping lifted out of both hot loops into one pass over what was actually emitted
	if capture:
		for i in w:
			var v : int = out_arr[i]
			var idx : int = ((v >> PACK_SHIFT) - ocy) * cpd + ((v & 0xFFFF) - ocx)
			status_arr[idx] = 1
			index_arr[idx] = i

	# Retighten the search radius for next frame. If the budget filled there is
	# no reason to walk far past the ring it filled on; if it did not, widen and
	# try again. Converges in a frame or two and costs nothing.
	if written >= budget:
		radius_hint = fr + RING_SLACK
	else:
		radius_hint = mini((radius_hint * 5) / 4 + 4, cpd >> 1)

	return written

#converts each of the cameras planes into 2D line
func _setup_constraints(view : FoliageViewSnapshot) -> void:
	constraint_count = 0
	predict_active = false
	var frustum := view.frustum			# opt: one property fetch instead of one per loop entry
	if frustum.size() < 4:
		return					# no clipping; the ring walk fills a disc

	# opt: every member and view property the plane loop touches is read once here
	var inside : Vector3 = view.inside_point
	var spacing : float = cell_spacing
	var ox : float = origin_world.x
	var oz : float = origin_world.y
	var pad : float = edge_pad_cells
	var y_lo : float = view.ground_y - terrain_vertical_slack
	var y_hi : float = view.ground_y + terrain_vertical_slack
	var count : int = 0					# opt: local counter, written back to the member once

	for plane in frustum:
		var n : Vector3 = plane.normal
		var d : float = plane.d

		# Godot does not promise which way these face or what order they come
		# in, so orient each one against a point known to be inside.
		if n.dot(inside) - d < 0.0:
			n = -n
			d = -d

		var a : float = n.x * spacing
		var b : float = n.z * spacing
		var len_sq : float = a * a + b * b

		# whichever height in the relief band makes this constraint loosest
		var k : float = y_hi if n.y > 0.0 else y_lo
		var c : float = n.x * ox + n.z * oz + n.y * k - d

		if len_sq < 0.000000001:
			if c < 0.0:
				constraint_count = 0
				return
			continue

		# dilate outward so a cell counts as visible if any part of it is
		cc[count] = c + pad * sqrt(len_sq)
		ca[count] = a
		cb[count] = b
		# opt: the two divides the clip loops used to do per constraint per ring are paid once here
		ca_inv[count] = 0.0 if absf(a) < 0.000001 else 1.0 / a
		cb_inv[count] = 0.0 if absf(b) < 0.000001 else 1.0 / b
		count += 1

		if count >= PREDICT_BASE:
			break

	constraint_count = count
	_build_predicted_constraints()

# the predicted constrained are the current ones rotated about the camera by the amount we thinkg the camera will mvove
func _build_predicted_constraints() -> void:
	predict_active = false
	var n : int = constraint_count		# opt: member read once, not once per loop test
	if n == 0 or absf(predict_yaw_rad) < 0.0005:
		return

	var cosa : float = cos(predict_yaw_rad)
	var sina : float = sin(predict_yaw_rad)
	var px : float = player_sub.x
	var pz : float = player_sub.y

	for i in n:
		var a : float = ca[i]
		var b : float = cb[i]
		# the constraint's value at the pivot is invariant under rotation about it
		var at_pivot : float = a * px + b * pz + cc[i]
		var a2 : float = a * cosa - b * sina
		var b2 : float = a * sina + b * cosa
		var j : int = PREDICT_BASE + i	# opt: one add shared by all five stores
		ca[j] = a2
		cb[j] = b2
		cc[j] = at_pivot - (a2 * px + b2 * pz)
		ca_inv[j] = 0.0 if absf(a2) < 0.000001 else 1.0 / a2	# opt: predicted set gets cached reciprocals too
		cb_inv[j] = 0.0 if absf(b2) < 0.000001 else 1.0 / b2

	predict_active = true

# The x interval of a horizontal line that satisfies every constraint. Returns
# (lo, hi), either bound possibly the open sentinel; lo > hi means the row misses.
# Called four times per ring rather than once per cell, which is why it can
# afford to be a function call at all.
func _clip_row(z : float) -> Vector2:
	var span : Vector2 = _clip_row_set(z, 0)
	if not predict_active:
		return span
	return _hull(span, _clip_row_set(z, PREDICT_BASE))

func _clip_row_set(z : float, base : int) -> Vector2:
	var lo : float = SPAN_OPEN_LO
	var hi : float = SPAN_OPEN_HI

	for i in constraint_count:
		var j : int = base + i			# opt: index computed once instead of three times
		var inv : float = ca_inv[j]		# opt: 0.0 already means "degenerate", so no absf() call per constraint
		var rhs : float = -(cb[j] * z + cc[j])
		if inv == 0.0:
			if rhs > 0.0:
				return SPAN_MISS
		else:
			var v : float = rhs * inv	# opt: multiply by the cached reciprocal instead of dividing
			if inv > 0.0:				# opt: sign of the reciprocal matches the sign of the coefficient
				if v > lo:				# opt: plain compare instead of a maxf() utility call
					lo = v
			elif v < hi:				# opt: plain compare instead of a minf() utility call
				hi = v

	return Vector2(lo, hi)


# The z interval of a vertical line that satisfies every constraint.
func _clip_col(x : float) -> Vector2:
	var span : Vector2 = _clip_col_set(x, 0)
	if not predict_active:
		return span
	return _hull(span, _clip_col_set(x, PREDICT_BASE))


func _clip_col_set(x : float, base : int) -> Vector2:
	var lo : float = SPAN_OPEN_LO
	var hi : float = SPAN_OPEN_HI

	for i in constraint_count:
		var j : int = base + i
		var inv : float = cb_inv[j]		# opt: same cached-reciprocal path as the row clip
		var rhs : float = -(ca[j] * x + cc[j])
		if inv == 0.0:
			if rhs > 0.0:
				return SPAN_MISS
		else:
			var v : float = rhs * inv
			if inv > 0.0:
				if v > lo:
					lo = v
			elif v < hi:
				hi = v

	return Vector2(lo, hi)


# Smallest interval containing both. A union of two overlapping intervals is one
# interval; if a turn is fast enough to make them disjoint the hull bridges the
# gap, which over-includes a little rather than leaving a hole.
func _hull(p : Vector2, q : Vector2) -> Vector2:
	if p.x > p.y:
		return q
	if q.x > q.y:
		return p
	# opt: ternaries instead of minf()/maxf() utility calls
	return Vector2(p.x if p.x < q.x else q.x, p.y if p.y > q.y else q.y)


#region DEBUG

# All take LOCAL window coordinates, and are meaningful only for the most recent
# _build, and only when DEBUG_capture_data was on for it.
func _DEBUG_status_at(local : Vector2i) -> int:
	if status_arr.is_empty():			# opt: buffers are lazily allocated, so guard before indexing
		return CellStatus.UNVISITED
	if local.x < 0 or local.y < 0 or local.x >= cells_per_dim or local.y >= cells_per_dim:
		return CellStatus.UNVISITED
	return status_arr[local.x + local.y * cells_per_dim]

func _DEBUG_is_emitted(local : Vector2i) -> bool:
	return _DEBUG_status_at(local) == CellStatus.EMITTED

# Position in the emit order, so index_arr < high_segment_budget means this cell got
# high LOD. -1 means not emitted.
func _DEBUG_rank_at(local : Vector2i) -> int:
	if index_arr.is_empty():			# opt: same lazy-allocation guard
		return -1
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

	# opt: scan inwards from +-90 and return on the first hit -- it is the widest by definition, so a typical FOV costs ~30 probes instead of 181
	for step in 91:
		var deg : float = float(90 - step)
		var rad : float = deg_to_rad(deg)
		for sign_idx in 2:
			if sign_idx == 1 and deg == 0.0:
				continue				# opt: +0 and -0 are the same ray, do not probe it twice
			var p : Vector2 = player_sub + cam_fwd.rotated(rad if sign_idx == 0 else -rad) * probe
			var ok : bool = true
			for i in constraint_count:
				if ca[i] * p.x + cb[i] * p.y + cc[i] < 0.0:
					ok = false
					break
			if ok:
				return deg

	return 0.0

#endregion
