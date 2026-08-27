@tool
class_name TiraBundleExample
extends TiraBundle

## Variante del TiraBundle que PERSISTE al parar la simulacion: al parar solo
## hace unbind() de los cross-joints y NO se auto-elimina, y tampoco elimina
## sus tiras hijas (fuerza remove_on_stop=false). Para usar en escenas de
## ejemplo/referencia (tiras visibles tras play+stop).

func _ready() -> void:
	# Reutiliza el fix de editor de la base (top_level=false en tiras hijas).
	super._ready()
	# Las tiras hijas persisten tras el stop (el default de Tira es remove_on_stop=true).
	_mark_tiras_persistent()


func _mark_tiras_persistent() -> void:
	for t in find_children("*", "Tira", true, false):
		if t is Tira:
			t.remove_on_stop = false


func _on_simulation_stopped() -> void:
	unbind()
	_mark_tiras_persistent()
