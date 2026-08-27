@tool
extends Node3D

## Arranque automatico para ejecutar Simulation.tscn con el Play normal de Godot.
## El fork puede emitir estas señales desde su barra propia; la guarda evita
## duplicar el arranque cuando esa barra ya esta activa.

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not Simulation.is_running():
		for method_name in ["start", "run", "start_simulation", "begin_simulation"]:
			if Simulation.has_method(method_name):
				Simulation.call(method_name)
				return
		push_warning("Simulation singleton no expone un metodo publico de inicio")


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if Simulation.is_running():
		Simulation.stop()
