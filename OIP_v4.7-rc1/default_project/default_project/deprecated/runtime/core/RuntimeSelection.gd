@tool
extends Node

## Provides selection tracking for the runtime editor.
## In editor mode the RuntimeEditorBridge plugin forwards
## EditorInterface.get_selection() changes here.

signal selection_changed(selected: Array[Node])

var _selected_nodes: Array[Node] = []
var _active_node_3d: Node3D = null

func get_selected_nodes() -> Array[Node]:
	return _selected_nodes

func get_active_node_3d() -> Node3D:
	return _active_node_3d

func select_node(node: Node) -> void:
	_selected_nodes = [node]
	selection_changed.emit(_selected_nodes)

func select_nodes(nodes: Array[Node]) -> void:
	_selected_nodes = nodes
	selection_changed.emit(_selected_nodes)

func deselect_all() -> void:
	_selected_nodes.clear()
	selection_changed.emit(_selected_nodes)

func set_active_node_3d(node: Node3D) -> void:
	_active_node_3d = node
