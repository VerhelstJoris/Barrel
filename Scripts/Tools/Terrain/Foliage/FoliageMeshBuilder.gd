class_name FoliageMeshBuilder extends RefCounted

# Minimum triangle area (in world units^2) below which a triangle is
const MIN_TRIANGLE_AREA := 0.00001
 
# Builds an ArrayMesh from height data. Call this whenever you just want
# Any triangle touching a non-finite height (NaN/Inf) or that is 0 is simply left out of the mesh rather than drawn
static func build_mesh(height_data: PackedFloat32Array, grid_size: int, cell_size: float = 1.0, pos_offset : Vector2 = Vector2.ZERO) -> ArrayMesh:
	if height_data.size() != grid_size * grid_size:
		push_error("TerrainMeshBuilder: height_data size (%d) does not match grid_size*grid_size (%d)" % [height_data.size(), grid_size * grid_size])
		return null
 
	var skipped_count := 0
 
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
 
	for row in range(grid_size - 1):
		for col in range(grid_size - 1):
			var h_rc := height_data[row * grid_size + col]
			var h_rc1 := height_data[row * grid_size + col + 1]
			var h_r1c := height_data[(row + 1) * grid_size + col]
			var h_r1c1 := height_data[(row + 1) * grid_size + col + 1]
 
			var p_rc := Vector3(row * cell_size + pos_offset.x			, h_rc,   col * cell_size		+ pos_offset.y)
			var p_rc1 := Vector3(row * cell_size + pos_offset.x			, h_rc1, (col + 1) * cell_size  + pos_offset.y)
			var p_r1c := Vector3((row + 1) * cell_size + pos_offset.x	, h_r1c,  col * cell_size 		+ pos_offset.y)
			var p_r1c1 := Vector3((row + 1) * cell_size + pos_offset.x	, h_r1c1,(col + 1) * cell_size	+ pos_offset.y)
 
			var uv_rc := Vector2(float(row) / grid_size, float(col) / grid_size)
			var uv_rc1 := Vector2(float(row) / grid_size, float(col + 1) / grid_size)
			var uv_r1c := Vector2(float(row + 1) / grid_size, float(col) / grid_size)
			var uv_r1c1 := Vector2(float(row + 1) / grid_size, float(col + 1) / grid_size)
 
			# Triangle 1
			if _is_valid_triangle(p_rc, p_r1c, p_rc1):
				st.set_uv(uv_rc); st.add_vertex(p_rc)
				st.set_uv(uv_r1c); st.add_vertex(p_r1c)
				st.set_uv(uv_rc1); st.add_vertex(p_rc1)
			else:
				skipped_count += 1
 
			# Triangle 2
			if _is_valid_triangle(p_r1c, p_r1c1, p_rc1):
				st.set_uv(uv_r1c); st.add_vertex(p_r1c)
				st.set_uv(uv_r1c1); st.add_vertex(p_r1c1)
				st.set_uv(uv_rc1); st.add_vertex(p_rc1)
			else:
				skipped_count += 1
 
	if skipped_count > 0:
		push_warning("TerrainMeshBuilder: skipped %d triangle(s) with non-finite or degenerate geometry" % skipped_count)
 
	st.generate_normals()
	return st.commit()

 
# Rejects triangles that contain a non-finite vertex (from a NaN/Inf height)
# or that are degenerate (zero/near-zero area, which produces a zero-length  normal). 
# Either case is simply not drawn rather
static func _is_valid_triangle(a: Vector3, b: Vector3, c: Vector3) -> bool:
	if not (a.is_finite() and b.is_finite() and c.is_finite()):
		return false
	var area := (b - a).cross(c - a).length() * 0.5
	return area >= MIN_TRIANGLE_AREA
 
