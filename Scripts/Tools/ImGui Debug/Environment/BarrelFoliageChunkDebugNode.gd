class_name BarrelFoliageChunkDebugNode extends BarrelSceneDebugNode

@export var chunk : FoliageChunk

var left_copy_arr : Array[Vector2i]
var center_copy_arr : Array[Vector2i]
var right_copy_arr : Array[Vector2i]

var segments_per_dim : int =0

var table_draw_left : bool = true
var table_draw_left_color : Array[float] = [1,0,0]
var table_draw_right : bool = true
var table_draw_right_color : Array[float] = [0,1,0]
var table_draw_center : bool = true
var table_draw_center_color : Array[float] = [1,0,1]

var table_x_draw_range : Array[int] = [0,50]
var table_y_draw_range : Array[int] = [0,50]

func _ready() -> void:
	super()
	BarrelDebugWindow.environment_node._register_environment_node(self, BarrelEnvironmentDebugNode.EDebugEnvNodeType.Foliage)
	
	segments_per_dim = int(chunk.chunk_dimenstion_size_m / chunk._get_vertex_spacing())
	table_x_draw_range[1] = segments_per_dim
	table_y_draw_range[1] = segments_per_dim
	left_copy_arr.resize(segments_per_dim)
	center_copy_arr.resize(segments_per_dim *2)
	right_copy_arr.resize(segments_per_dim)
	
func _get_name() -> String:
	return chunk.name
	
func _draw_contents(_delta : float) -> void:
	_cache_current_data()
	
	if(ImGui.CollapsingHeader("Current Data")):
		_draw_current_data()

	if(ImGui.CollapsingHeader("Display")):	
		ImGui.Indent()
		_draw_chunk_table()
		ImGui.Unindent()

func _cache_current_data() -> void:
	left_copy_arr.fill(Vector2i.MIN)
	center_copy_arr.fill(Vector2i.MIN)
	right_copy_arr.fill(Vector2i.MIN)
	_cache_copy_of_array(chunk.segments_found_left,chunk.segment_found_edges_left, left_copy_arr)
	_cache_copy_of_array(chunk.segments_found_right,chunk.segment_found_edges_right, right_copy_arr)
	_cache_copy_of_array(chunk.segments_found_center,chunk.segment_center_edges, center_copy_arr)

func _draw_chunk_table() -> void:
	var draw_left_arr : Array[bool] = [table_draw_left]
	ImGui.ColorEdit3("Left",table_draw_left_color, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	var left_col : Color = Color(table_draw_left_color[0],table_draw_left_color[1],table_draw_left_color[2],1)

	ImGui.SameLine()
	if(ImGui.Checkbox("Show Left", draw_left_arr)):
		table_draw_left = draw_left_arr[0]
	ImGui.SameLine()
	
	ImGui.ColorEdit3("Right",table_draw_right_color, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	var right_col : Color = Color(table_draw_right_color[0],table_draw_right_color[1],table_draw_right_color[2],1)

	ImGui.SameLine()
	var draw_right_arr : Array[bool] = [table_draw_right]
	if(ImGui.Checkbox("Show Right", draw_right_arr)):
		table_draw_right = draw_right_arr[0]
	ImGui.SameLine()
	
	ImGui.ColorEdit3("Center",table_draw_center_color, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel)
	var center_col : Color = Color(table_draw_center_color[0],table_draw_center_color[1],table_draw_center_color[2],1)

	ImGui.SameLine()
	var draw_center_arr : Array[bool] = [table_draw_center]
	if(ImGui.Checkbox("Show Center", draw_center_arr)):
		table_draw_center = draw_center_arr[0]
		
	ImGui.PushItemWidth(75)	
	ImGui.InputInt2("X: ",table_x_draw_range)
	ImGui.SameLine()
	ImGui.InputInt2("Y: ",table_y_draw_range)
	ImGui.PopItemWidth()
	ImGui.Separator()
	
	ImGui.BeginTable("Segments", segments_per_dim)
	var current_cell : Vector2i = Vector2i.ZERO
	for row in range(table_y_draw_range[1],table_y_draw_range[0] -1,-1):
		for col in range(table_x_draw_range[0] -1,table_x_draw_range[1]):
			current_cell = Vector2i(row, col)
			if(table_draw_left && left_copy_arr.has(current_cell)):
				ImGui.TextColored(left_col, "L")
			elif(table_draw_right && right_copy_arr.has(current_cell)):
				ImGui.TextColored(right_col, "R")
			elif(table_draw_center && center_copy_arr.has(current_cell)):
				ImGui.TextColored(center_col, "C")
			else:
				ImGui.Text(".")	
			ImGui.TableNextColumn()
		ImGui.TableNextRow()
	ImGui.EndTable()

func _cache_copy_of_array(amount : int, copy_from_arr : PackedInt32Array, copy_to_arr : Array[Vector2i]) -> void:
	for id in range(amount):
		copy_to_arr[id] = Vector2i(copy_from_arr[2* id], copy_from_arr[(2*id) +1])
	
func _draw_current_data() -> void:
	_draw_found_arr(chunk.segments_found_left,left_copy_arr, "L" )
	_draw_found_arr(chunk.segments_found_right,right_copy_arr, "R" )
	_draw_found_arr(chunk.segments_found_center,center_copy_arr, "C" )
	
func _draw_found_arr(found_amount : int, arr : Array[Vector2i], prepend : String) -> void:
	var segments : String = ""
	for id in range(0,found_amount):
		segments += str(arr[id])

	ImGui.Text("{} : {} == {}".format([prepend, found_amount, segments], "{}"))
	
