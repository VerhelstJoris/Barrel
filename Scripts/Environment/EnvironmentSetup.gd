class_name EnvironmentSetup extends Node

@export var settings : EnvironmentSettings

func _ready() -> void:
	if(settings):
		EnvironmentManager._initalize(settings)
	else:
		push_error("Cannot initialize Environment because we have no settings asset")	
