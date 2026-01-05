class_name InputActionInfo extends  Resource

#the literal input string in the project settings this corresponds with
@export	var input_string : String

@export var trigger_on_started : bool = true
@export var trigger_on_down : bool = false
@export var trigger_on_released : bool = false
@export var trigger_on_hold_time_reached : bool = false
@export var hold_time : float = 0.3