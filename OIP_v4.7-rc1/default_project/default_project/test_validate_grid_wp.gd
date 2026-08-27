extends SceneTree

# Validacion sin instanciar: carga el PackedScene y lee la propiedad waypoints
# del nodo SixAxisRobot directamente del estado serializado.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps: PackedScene = load("res://Simulation.tscn")
	if ps == null:
		push_error("No se pudo parsear Simulation.tscn")
		quit(1)
		return
	var st := ps.get_state()
	var found := false
	for i in st.get_node_count():
		if st.get_node_name(i) == "SixAxisRobot":
			found = true
			for p in st.get_node_property_count(i):
				if st.get_node_property_name(i, p) == "waypoints":
					var wp: Dictionary = st.get_node_property_value(i, p)
					print("waypoints (%d):" % wp.size())
					for k in wp.keys():
						print("  ", k, " -> ", wp[k])
				elif st.get_node_property_name(i, p) == "selected_waypoint":
					print("selected = ", st.get_node_property_value(i, p))
				elif st.get_node_property_name(i, p) == "new_waypoint_name":
					print("next name = ", st.get_node_property_value(i, p))
	if not found:
		push_error("SixAxisRobot no encontrado")
		quit(1)
		return
	print("VALID_OK")
	quit(0)
