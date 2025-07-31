class_name LineRenderer extends MeshInstance3D

@export var should_draw : bool = true
@export var points: Array[Vector3]
@export var use_global_coords:bool = true
@export var connect_polys : bool = true
@export var flip_y_uv : bool = true

@export_group("Line Thickness")
@export var use_precomputed_thickness_arr : bool = true
@export var pre_computed_thickness_arr : Array[float]
@export var start_thickness:float = 0.1
@export var growth_rate_per_unit_length : float = 2

var PrevBToAB : Vector3
var PrevBFromAB : Vector3

var global_scale : float 

var camera : Camera3D
var cameraOrigin : Vector3

var total_dist : float   = 0
var current_dist : float = 0
var next_dist : float    = 0

var max_thickness : float = 0

var current_alpha : float = 0
var next_alpha : float =0

func _enter_tree() -> void:
	mesh = ImmediateMesh.new()
	
func _ready() -> void:
	camera = get_tree().get_root().get_camera_3d()
	
func _process(_delta : float) -> void:
	if(!should_draw):
		return
	
	if points.size() < 2:
		return
		
	if camera == null:
		return

	if(use_precomputed_thickness_arr && pre_computed_thickness_arr.size() != points.size()):
		push_error("Line Renderer points Array (",points.size() , ") and Point Thickness Array (", pre_computed_thickness_arr.size(), ")are not the same size")
		return

	cameraOrigin = to_local(camera.get_global_transform().origin) 
	
	_reset_vars_for_drawing(_delta)
	
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	
	for i in range(points.size() - 1):
		_draw_next_poly(points[i],points[i+1], i)

	mesh.surface_end()
	
func _reset_vars_for_drawing(_delta : float)->void:
	current_alpha = 0
	if(flip_y_uv):
		next_alpha = 1
	else:
		next_alpha = 0
		
	var prev_total_dist: float = total_dist
	total_dist = 0
	for i in range(points.size() - 1):
		total_dist += points[i].distance_to(points[i + 1])
		
	total_dist = lerp(prev_total_dist, total_dist, 1 * _delta)	

	current_dist = 0
	next_dist = 0
	
	max_thickness = start_thickness + (start_thickness * (growth_rate_per_unit_length * total_dist))
	global_scale = get_global_transform().basis.get_scale().length()
	
func _draw_next_poly(A: Vector3, B : Vector3, index : int )	-> void:
	current_dist = next_dist
	next_dist += A.distance_to(B)
	current_alpha = next_alpha
	next_alpha = next_dist / total_dist
	if(flip_y_uv):
		next_alpha = 1 - next_alpha
		
	if use_global_coords:
		A = to_local(A)
		B = to_local(B)
		
	var current_thickness : float
	var next_thickness : float
	if(use_precomputed_thickness_arr):	
		current_thickness = pre_computed_thickness_arr[index] / global_scale
		next_thickness = pre_computed_thickness_arr[index + 1] / global_scale
	else:	
		current_thickness = lerp(max_thickness, start_thickness, current_alpha) / global_scale
		next_thickness = lerp(max_thickness, start_thickness, next_alpha) / global_scale
	
	var AB:Vector3 = B - A;
	var orthogonalABStart:Vector3 = (cameraOrigin - ((A + B) / 2)).cross(AB).normalized() * current_thickness;
	var orthogonalABEnd:Vector3 = (cameraOrigin - ((A + B) / 2)).cross(AB).normalized() * next_thickness;
	
	var AtoABStart:Vector3
	var AfromABStart:Vector3
	
	if(index != 0 && connect_polys):
		AtoABStart = PrevBToAB
		AfromABStart = PrevBFromAB
	else:
		AtoABStart   = A + orthogonalABStart
		AfromABStart = A - orthogonalABStart
	
	var BtoABEnd:Vector3  = B + orthogonalABEnd
	var BfromABEnd:Vector3 = B - orthogonalABEnd
	
	_add_vertex(AtoABStart,Vector2(0,current_alpha))
	_add_vertex(BtoABEnd,Vector2( 0, current_alpha))
	_add_vertex(AfromABStart,Vector2(1, next_alpha))
	
	_add_vertex(BtoABEnd,Vector2(0 , current_alpha))
	_add_vertex(BfromABEnd,Vector2(1, next_alpha))
	_add_vertex(AfromABStart,Vector2(1,next_alpha))
	
	PrevBToAB = BtoABEnd
	PrevBFromAB = BfromABEnd

func _add_vertex(pos : Vector3,   uv : Vector2) -> void:
	mesh.surface_set_uv(uv)
	mesh.surface_add_vertex(pos)
	
