@tool
extends Node

## Provides simulation_started/stopped/pause_toggled signals.
## In editor mode the RuntimeEditorBridge plugin forwards EditorInterface
## simulation events here.  In exported builds the runtime UI calls
## start/stop/pause/resume directly.

signal simulation_started
signal simulation_stopped
signal simulation_pause_toggled(paused: bool)

var _running: bool = false
var _paused: bool = false

func is_simulation_running() -> bool:
	return _running

func is_simulation_paused() -> bool:
	return _paused

func start_simulation() -> void:
	if _running:
		return
	_running = true
	_paused = false
	simulation_started.emit()

func stop_simulation() -> void:
	if not _running:
		return
	# First pause (freeze physics), then stop (restore initial state)
	_paused = true
	simulation_pause_toggled.emit(true)
	_running = false
	_paused = false
	simulation_stopped.emit()

func pause_simulation() -> void:
	if not _running or _paused:
		return
	_paused = true
	simulation_pause_toggled.emit(true)

func resume_simulation() -> void:
	if not _running or not _paused:
		return
	_paused = false
	simulation_pause_toggled.emit(false)

func set_paused(paused: bool) -> void:
	if not _running:
		return
	_paused = paused
	simulation_pause_toggled.emit(_paused)
