@tool
extends Node

## Lightweight undo/redo wrapper.
## In editor mode the RuntimeEditorBridge plugin swaps the internal
## UndoRedo for EditorInterface.get_editor_undo_redo() so actions
## appear in the editor's history panel.
## In exported builds a plain UndoRedo is used.

var _undo_redo = UndoRedo.new()

func _ready() -> void:
	# In editor, try to use editor's undo/redo if bridge hasn't set it yet
	if Engine.is_editor_hint() and EditorInterface.has_method("get_editor_undo_redo"):
		var editor_ur = EditorInterface.get_editor_undo_redo()
		if editor_ur:
			_undo_redo = editor_ur

func use_editor_undo_redo(editor_undo_redo) -> void:
	_undo_redo = editor_undo_redo

func create_action(action_name: String, merge_mode: int = 0) -> void:
	_undo_redo.create_action(action_name, merge_mode)

func commit_action(execute: bool = true) -> void:
	_undo_redo.commit_action(execute)

func add_do_property(object: Object, property: StringName, value: Variant) -> void:
	_undo_redo.add_do_property(object, property, value)

func add_undo_property(object: Object, property: StringName, value: Variant) -> void:
	_undo_redo.add_undo_property(object, property, value)

func add_do_reference(object: Object) -> void:
	_undo_redo.add_do_reference(object)

## Supports both Callable syntax and (Object, method, args...) syntax.
func add_do_method(arg1, arg2 = null, arg3 = null) -> void:
	if arg1 is Callable:
		_undo_redo.add_do_method(arg1)
	elif arg1 is Object and arg2 is String:
		var callable := Callable(arg1, arg2)
		if arg3 != null:
			if arg3 is Array:
				callable = callable.bindv(arg3)
			else:
				callable = callable.bind(arg3)
		_undo_redo.add_do_method(callable)

## Supports both Callable syntax and (Object, method, args...) syntax.
func add_undo_method(arg1, arg2 = null, arg3 = null) -> void:
	if arg1 is Callable:
		_undo_redo.add_undo_method(arg1)
	elif arg1 is Object and arg2 is String:
		var callable := Callable(arg1, arg2)
		if arg3 != null:
			if arg3 is Array:
				callable = callable.bindv(arg3)
			else:
				callable = callable.bind(arg3)
		_undo_redo.add_undo_method(callable)
