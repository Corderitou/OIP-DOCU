@tool
extends Node

## Toast notification stub.  In editor mode the RuntimeEditorBridge
## plugin delegates to EditorInterface.get_editor_toaster().
## In exported builds messages are printed to stdout and stored in
## a ring buffer for display in a future toast UI.

const SEVERITY_INFO: int = 0
const SEVERITY_WARNING: int = 1
const SEVERITY_ERROR: int = 2

const MAX_TOASTS: int = 50

signal toast_pushed(message: String, severity: int)

var _toasts: Array[Dictionary] = []
var _editor_toaster = null  # EditorToaster reference when in editor

func set_editor_toaster(toaster) -> void:
	_editor_toaster = toaster

func push_toast(message: String, severity: int = SEVERITY_INFO) -> void:
	if _editor_toaster:
		_editor_toaster.push_toast(message, severity)
		return

	var prefixes: Array[String] = ["[INFO]", "[WARN]", "[ERROR]"]
	var prefix: String = prefixes[mini(severity, 2)]
	print(prefix, " ", message)
	_toasts.append({"message": message, "severity": severity, "time": Time.get_ticks_msec()})
	if _toasts.size() > MAX_TOASTS:
		_toasts.pop_front()
	toast_pushed.emit(message, severity)
