class_name BarrelEquipmentPistolDebug extends BarrelEquipmentSceneDebug

@export var pistol : PlayerEquipmentPistol

@export var log_debug_info : bool = true
@export var shoot_with_invalid_bullets : bool = false

func _ready() -> void:
	super()
	if(pistol == null):
		push_error("Pistol not assigned in debug node!")
		return
	
	pistol.on_action_started.connect(_on_pistol_action_started)	
	
func _draw_contents(_delta: float) -> void:
	_draw_pistol_debug(_delta)
	ImGui.SeparatorText("Options")
	var log_info : Array[bool] = [log_debug_info]
	if(ImGui.Checkbox("Log Debug?", log_info)):
		log_debug_info = log_info[0]
		
	var invalid_allowed : Array[bool] = [pistol.debug_shot_valid]
	if(ImGui.Checkbox("Always Fire?", invalid_allowed)):
		pistol.debug_shot_valid = invalid_allowed[0]	

	ImGui.SeparatorText("Components")
	super(_delta)
	
func _draw_pistol_debug(_delta : float) -> void:
	ImGui.Text(_get_chamber_states())
	var time_since_last_action : float = Time.get_unix_time_from_system() - pistol.main_equipment_last_use_time
	var draw_col : Color = Color(1,0,0,1)
	if(time_since_last_action <= pistol.fan_hammer_max_delay):
		draw_col = Color(0,1,0,1)
	ImGui.TextColored(draw_col,(String("Time since last action : %f" % time_since_last_action)))
	ImGui.Text("Max Fan Hammer Delay %f" % pistol.fan_hammer_max_delay)
	


func _on_pistol_action_started(_new_action: int) -> void:
	if(_new_action == PlayerEquipmentPistol.EPistolActions.None):
		return
		
	if(log_debug_info):	
		print("Colt action started : ", PlayerEquipmentPistol.EPistolActions.keys()[_new_action])
		print(_get_chamber_states())

func _get_chamber_states() -> String:
	var builtStr : String = ""
	var index: int =  0
	for bullet in pistol.current_bullets:
		var bcurrent : bool = (index == pistol.current_chamber_id)
		if bcurrent:
			builtStr+="(("
		else:
			builtStr+="["

		if(bullet == null):
			builtStr+="0"
		else:
			if(bullet._can_be_fired()):
				builtStr+="1"
			else:
				builtStr+="X"

		if bcurrent:
			builtStr+="))"
		else:
			builtStr+="]"
		index +=1

	builtStr += " "	+ PlayerEquipmentPistol.EPistolState.keys()[pistol.current_state]
	builtStr += " Current Chamber: %d" % pistol.current_chamber_id
	return builtStr
	