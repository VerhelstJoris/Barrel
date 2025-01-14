extends Node

const FORMAT = '%s - %s - %s'
const DEBUG = 'debug'
const INFO = 'info'
const WARNING = 'warning'
const ERROR = 'error'

static func debug(message):
	if OS.is_debug_build():
		_log(DEBUG, message)

static func info(message):
	_log(INFO, message)

static func warning(message):
	_log(WARNING, message, true)

static func error(message):
	_log(ERROR, message, true)

static func _format_time():
	return Time.get_time_string_from_system()

static func _log(level, message, flush = false):
	var log_message = FORMAT % [_format_time(), level, message]
	print(log_message)
