@tool
extends Node

## Stub for EditorInterface editor-specific signals and methods
## that don't fit in the other stubs.
## In editor mode the RuntimeEditorBridge plugin forwards the real
## EditorInterface events here.  In exported builds everything is
## a no-op.

signal transform_requested(data: Dictionary)
signal transform_commited

func mark_scene_as_unsaved() -> void:
	pass  # No-op in runtime

func mark_scene_as_saved() -> void:
	pass  # No-op in runtime
