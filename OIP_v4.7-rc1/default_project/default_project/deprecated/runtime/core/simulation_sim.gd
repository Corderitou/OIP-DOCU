@tool
extends Node

## Simulation singleton bridge.
## When registered as autoload (project.godot), this OVERRIDES the GDExtension's
## Simulation singleton and forwards to/from RuntimeSimulationBus.
## This makes all parts (Box, Pallet, Conveyors, etc.) work with the runtime editor.

signal started
signal stopped
signal pause_toggled(paused: bool)


func _ready() -> void:
	call_deferred("_bridge_runtime_simulation_bus")
	call_deferred("_autostart_in_game_scenes")


func _bridge_runtime_simulation_bus() -> void:
	if not RuntimeSimulationBus:
		return
	RuntimeSimulationBus.simulation_started.connect(_on_rsb_started)
	RuntimeSimulationBus.simulation_stopped.connect(_on_rsb_stopped)
	RuntimeSimulationBus.simulation_pause_toggled.connect(_on_rsb_paused)


## Auto-start the simulation when a scene runs as a game (Godot Play button,
## standalone scene like Simulation.tscn, or exported build). Physics parts
## (Box, Pallet, Placer, Celda, ...) freeze whenever the bus is not running,
## and in these contexts nothing else calls start_simulation(), so bodies
## would stay frozen forever. The runtime editor drives the simulation itself
## through its Play/Pause/Stop UI and its root is a Control, so it is
## excluded here.
func _autostart_in_game_scenes() -> void:
	if Engine.is_editor_hint():
		return
	if not RuntimeSimulationBus or RuntimeSimulationBus.is_simulation_running():
		return
	var scene := get_tree().current_scene
	if scene is Control:
		return
	RuntimeSimulationBus.start_simulation()


func _on_rsb_started() -> void:
	started.emit()


func _on_rsb_stopped() -> void:
	stopped.emit()


func _on_rsb_paused(paused: bool) -> void:
	pause_toggled.emit(paused)


func is_running() -> bool:
	return RuntimeSimulationBus.is_simulation_running() if RuntimeSimulationBus else false


func is_paused() -> bool:
	return RuntimeSimulationBus.is_simulation_paused() if RuntimeSimulationBus else false


func stop() -> void:
	if RuntimeSimulationBus:
		RuntimeSimulationBus.stop_simulation()
