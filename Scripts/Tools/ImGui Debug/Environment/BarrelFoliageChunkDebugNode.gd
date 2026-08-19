class_name BarrelFoliageChunkDebugNode extends BarrelSceneDebugNode

@export var chunk : FoliageChunk

var dummy_bender_tex : Texture2D

var left_copy_arr : Array[Vector2i]
var center_copy_arr : Array[Vector2i]
var right_copy_arr : Array[Vector2i]
var work_copy_arr : Array[Vector2i]

var segments_per_dim : int =0

var table_draw_left : bool = true
var table_draw_left_color : Array[float] = [1,0,0]
var table_draw_right : bool = true
var table_draw_right_color : Array[float] = [0,1,0]
var table_draw_center : bool = true
var table_draw_center_color : Array[float] = [1,0,1]

var table_draw_flood_fill : bool = true
var table_draw_fill_color : Array[float] = [1,1,0]
var table_draw_conflicts : bool = true
var table_draw_conflict_col : Array[float] = [0,1,1]
var table_draw_player : bool = true
var table_draw_player_col : Array[float] = [1,1,1]

var table_x_draw_range : Array[int] = [0,50]
var table_y_draw_range : Array[int] = [0,50]

var bender_img_scale : Array[float] = [0.75]
var bender_img_min_uv : Array[float] = [0.0,0.0]
var bender_img_max_uv : Array[float] = [1.0,1.0]

func _ready() -> void:
	if(!chunk):
		queue_free()
	
	super()
	BarrelDebugWindow.environment_node._register_environment_node(self, BarrelEnvironmentDebugNode.EDebugEnvNodeType.Foliage)
	
	segments_per_dim = int(chunk.settings_DA.chunk_dimenstion_size_m / chunk._get_vertex_spacing())
	table_x_draw_range[1] = segments_per_dim
	table_y_draw_range[1] = segments_per_dim
	left_copy_arr.resize(segments_per_dim*2)
	center_copy_arr.resize(segments_per_dim *4)
	right_copy_arr.resize(segments_per_dim*2)
	work_copy_arr.resize(segments_per_dim * segments_per_dim)
	
func _get_name() -> String:
	return chunk.name
	
func _draw_contents(_delta : float) -> void:
	_cache_current_data()
	
	if(ImGui.CollapsingHeader("Current Segment Data")):
		_draw_current_segment_data()

	if(ImGui.CollapsingHeader("Segment Display")):	
		ImGui.Indent()
		_draw_chunk_table()
		ImGui.Unindent()

	if(ImGui.CollapsingHeader("Current Bender Display")):
		ImGui.Indent()
		_draw_bender_data()
		ImGui.Unindent()

func _cache_current_data() -> void:
	left_copy_arr.fill(Vector2i.MIN)
	center_copy_arr.fill(Vector2i.MIN)
	right_copy_arr.fill(Vector2i.MIN)
	work_copy_arr.fill(Vector2i.MIN)
	_cache_copy_of_packed_int_array(chunk.segments_found_left,chunk.segment_found_edges_left, left_copy_arr)
	_cache_copy_of_packed_int_array(chunk.segments_found_right,chunk.segment_found_edges_right, right_copy_arr)
	_cache_copy_of_packed_int_array(chunk.segments_found_center,chunk.segment_center_edges, center_copy_arr)
	_cache_copy_of_packed_int_array(chunk.segment_work_filled_in, chunk.segment_work_data_arr, work_copy_arr)

func _draw_chunk_table() -> void:
	var draw_left_arr : Array[bool] = [table_draw_left]
	ImGui.ColorEdit3("Left",table_draw_left_color, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	var left_col : Color = Color(table_draw_left_color[0],table_draw_left_color[1],table_draw_left_color[2],1)

	ImGui.SameLine()
	if(ImGui.Checkbox("Left   ", draw_left_arr)):
		table_draw_left = draw_left_arr[0]
	ImGui.SameLine()
	ImGui.Spacing()
	ImGui.SameLine()

	ImGui.ColorEdit3("Right",table_draw_right_color, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	var right_col : Color = Color(table_draw_right_color[0],table_draw_right_color[1],table_draw_right_color[2],1)

	ImGui.SameLine()
	var draw_right_arr : Array[bool] = [table_draw_right]
	if(ImGui.Checkbox("Right   ", draw_right_arr)):
		table_draw_right = draw_right_arr[0]
	ImGui.SameLine()
	
	ImGui.ColorEdit3("Center",table_draw_center_color, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	var center_col : Color = Color(table_draw_center_color[0],table_draw_center_color[1],table_draw_center_color[2],1)

	ImGui.SameLine()
	var draw_center_arr : Array[bool] = [table_draw_center]
	if(ImGui.Checkbox("Center   ", draw_center_arr)):
		table_draw_center = draw_center_arr[0]	
		
	ImGui.SameLine()
	ImGui.ColorEdit3("Flood",table_draw_fill_color, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	var fill_col : Color = Color(table_draw_fill_color[0],table_draw_fill_color[1],table_draw_fill_color[2],1)

	ImGui.SameLine()
	var draw_fill_arr : Array[bool] = [table_draw_flood_fill]
	if(ImGui.Checkbox("Fill   ", draw_fill_arr)):
		table_draw_flood_fill = draw_fill_arr[0]	
		
	ImGui.SameLine()
	ImGui.ColorEdit3("Conflict",table_draw_conflict_col, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	var conflict_col : Color = Color(table_draw_conflict_col[0],table_draw_conflict_col[1],table_draw_conflict_col[2],1)

	ImGui.SameLine()
	var table_draw_conflict_arr : Array[bool] = [table_draw_conflicts]
	if(ImGui.Checkbox("Conflict   ", table_draw_conflict_arr)):
		table_draw_conflicts = table_draw_conflict_arr[0]
		
	ImGui.SameLine()
	ImGui.ColorEdit3("Player", table_draw_player_col, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)	
	var player_col : Color = Color(table_draw_player_col[0],table_draw_player_col[1],table_draw_player_col[2],1)

	ImGui.SameLine()
	var table_draw_player_arr : Array[bool] = [table_draw_player]
	if(ImGui.Checkbox("Player   ", table_draw_player_arr)):
		table_draw_player = table_draw_player_arr[0]

	_draw_table_range()
	ImGui.Separator()
	
	ImGui.SetWindowFontScale(0.925)
	ImGui.BeginTable("Segments", segments_per_dim, ImGui.TableFlags_SizingFixedFit | ImGui.TableFlags_ScrollX)
	var current_cell : Vector2i = Vector2i.ZERO
	for row in range(table_y_draw_range[0] ,table_y_draw_range[1],):
		for col in range(table_x_draw_range[0],table_x_draw_range[1]):
			current_cell = Vector2i(col, row)
			var in_left : bool = false
			var in_right : bool = false
			var in_center : bool = false
			var in_amount : int = 0
			
			if(table_draw_left && left_copy_arr.has(current_cell)):
				in_left = true
				in_amount +=1
				
			if(table_draw_right && right_copy_arr.has(current_cell)):
				in_right = true
				in_amount +=1
					
			if(table_draw_center && center_copy_arr.has(current_cell)):
				in_center = true
				in_amount +=1
					

			if(table_draw_conflicts && in_amount > 1):
				ImGui.TextColored(conflict_col ,"!")
			elif(table_draw_player && (chunk.current_projected_player_segment == current_cell || chunk.current_player_segment == current_cell)):
				if(chunk.current_projected_player_segment == current_cell):
					ImGui.TextColored(player_col, "P")
				elif( chunk.current_player_segment == current_cell):
					ImGui.TextColored(player_col, "C")
			elif(in_left):
				ImGui.TextColored(left_col, "L")
			elif(in_right):
				ImGui.TextColored(right_col, "R")
			elif(in_center):
				ImGui.TextColored(center_col, "C")
			elif(table_draw_flood_fill && work_copy_arr.has(current_cell)):
				ImGui.TextColored(fill_col, "F")
			else:
				ImGui.Text("-")	
				
			ImGui.TableNextColumn()
		ImGui.TableNextRowEx(0,0)	
	ImGui.EndTable()
	ImGui.SetWindowFontScale(1.0)

func _draw_table_range() -> void:
	ImGui.PushItemWidth(75)
	ImGui.InputInt2("X: ",table_x_draw_range)
	ImGui.SameLine()
	ImGui.InputInt2("Y: ",table_y_draw_range)
	ImGui.PopItemWidth()
	
func _cache_copy_of_packed_int_array(amount : int, copy_from_arr : PackedInt32Array, copy_to_arr : Array[Vector2i]) -> void:
	for id in range(amount):
		copy_to_arr[id] = Vector2i(copy_from_arr[2* id], copy_from_arr[(2*id) +1])
	
func _cache_copy_of_packed_byte_array(amount : int, copy_from_arr : PackedByteArray, copy_to_arr : Array[Vector2i]) -> void:
	for id in range(amount):
		copy_to_arr[id] = Vector2i(copy_from_arr.decode_s32(id *8), copy_from_arr.decode_s32(id *8 +4))

func _draw_current_segment_data() -> void:
	_draw_found_arr(chunk.segments_found_left,left_copy_arr, "L" , Color(table_draw_left_color[0],table_draw_left_color[1],table_draw_left_color[2],1))
	_draw_found_arr(chunk.segments_found_right,right_copy_arr, "R" , Color(table_draw_right_color[0],table_draw_right_color[1],table_draw_right_color[2],1))
	_draw_found_arr(chunk.segments_found_center,center_copy_arr, "C",Color(table_draw_center_color[0],table_draw_center_color[1],table_draw_center_color[2],1) )
	
func _draw_found_arr(found_amount : int, arr : Array[Vector2i], prepend : String, color: Color) -> void:
	var segments : String = ""
	for id in range(0,found_amount):
		segments += str(arr[id])

	ImGui.PushStyleColor(ImGui.Col_Text, color)	
	ImGui.TextWrapped("{} : {} == {}".format([prepend, found_amount, segments], "{}"))
	ImGui.PopStyleColor()
	
var dummy_texture : Texture2D
	
func _draw_bender_data() -> void:
	ImGui.TextColored(Color.CHOCOLATE, "Note that the X will be flipped as the render tex camera is underneath the world")
	
	var tex : Texture = chunk.bender_mask_subviewport.get_texture()
	ImGui.Text("Image Size {}".format([tex.get_size()], "{}") )
	ImGui.PushItemWidth(100)
	ImGui.SliderFloat("Img Size", bender_img_scale, 0.0,1.0)
	
	ImGui.SameLine()
	ImGui.InputFloat2("Min UV", bender_img_min_uv)
	ImGui.SameLine()
	ImGui.InputFloat2("Max UV", bender_img_max_uv)

	ImGui.ImageEx(tex , tex.get_size() * bender_img_scale[0],Vector2(bender_img_min_uv[0], bender_img_min_uv[1]), Vector2(bender_img_max_uv[0], bender_img_max_uv[1]) )
	ImGui.SameLine()
	
	var rd := RenderingServer.get_rendering_device()
	var created_tex_arr : PackedByteArray = rd.texture_get_data(chunk.created_bender_image_RID,0)
	var created_image : Image = Image.create_from_data(chunk.bender_mask_res, chunk.bender_mask_res, false, Image.FORMAT_RF, created_tex_arr)
	var imagetex : ImageTexture = ImageTexture.create_from_image(created_image)

	dummy_texture = imagetex

	ImGui.ImageEx(dummy_texture , dummy_texture.get_size() * bender_img_scale[0],Vector2(bender_img_min_uv[0], bender_img_min_uv[1]), Vector2(bender_img_max_uv[0], bender_img_max_uv[1]) )
