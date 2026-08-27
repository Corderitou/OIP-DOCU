@tool
extends Node3D

## Objetivo de IK del SixAxisRobot: se mueve/rota con el gizmo nativo del
## editor y el robot resuelve sus juntas para alcanzar la POSE completa
## (posicion del tooltip + orientacion de la copa) via solve_ik_pose.
## Nodo transitorio creado por six_axis_robot.gd con owner=null: nunca se
## guarda en la escena ni existe en runtime.

var robot: Node3D = null


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED:
		return
	if robot == null or not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		return

	var target_pos := global_position
	var target_basis := global_transform.basis.orthonormalized()
	if robot.has_method("solve_ik_pose"):
		robot.call("solve_ik_pose", target_pos, target_basis)
	else:
		robot.call("solve_ik", target_pos)

	set_notify_transform(false)
	global_transform = robot.call("get_tool_tip_transform")
	set_notify_transform(true)
