class_name PlayerWorldCameraDebug extends BarrelSceneDebugNode

var player : Player
@export var world_camera : Camera3D
var fp_camera : Camera3D

var draw_wireframe : bool = false

func _get_name() -> String:
	return "PlayerWorldCameraDebug"

func _ready() -> void:
	super()
	await owner.ready
	player = owner as Player
	fp_camera = player.arms.FP_camera
	
func _draw_contents(_delta : float) -> void:
	super(_delta)
	
	ImGui.BeginTable("cam comparison", 3)
	ImGui.TableSetupColumn("Property")
	ImGui.TableSetupColumn("World")
	ImGui.TableSetupColumn("FP")
	ImGui.TableHeadersRow()
	
	ImGui.TableNextColumn()
	ImGui.Text("World Pos")
	var pos_color : Color = Color.RED
	if(world_camera.get_global_position() == fp_camera.get_global_position()):
		pos_color = Color.GREEN
	ImGui.TableNextColumn()
	ImGui.TextColored(pos_color, "%s" % world_camera.get_global_position())
	ImGui.TableNextColumn()
	ImGui.TextColored(pos_color, "%s" % fp_camera.get_global_position())
	ImGui.TableNextRow()

	ImGui.TableNextColumn()
	ImGui.Text("World Rot")
	var rot_color : Color = Color.RED
	if(world_camera.get_global_rotation() == fp_camera.get_global_rotation()):
		rot_color = Color.GREEN
	ImGui.TableNextColumn()
	ImGui.TextColored(rot_color, "%s" % world_camera.get_global_rotation())
	ImGui.TableNextColumn()
	ImGui.TextColored(rot_color, "%s" % fp_camera.get_global_rotation())
	ImGui.TableNextRow()
	
	ImGui.EndTable()

	_draw_render_mode_options()

func _draw_render_mode_options() -> void:
	var render_mode : Array[bool] = [draw_wireframe]
	if(ImGui.Checkbox("Show Wireframe?", render_mode)):
		draw_wireframe = render_mode[0]
		if(draw_wireframe):
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
		else:
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED

