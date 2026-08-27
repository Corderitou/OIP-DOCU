class_name SceneRegistry
extends RefCounted

const TYPE_MAP: Dictionary = {
	"BeltConveyorAssembly": "res://parts/assemblies/BeltConveyorAssembly.tscn",
	"RollerConveyorAssembly": "res://parts/assemblies/RollerConveyorAssembly.tscn",
	"CurvedBeltConveyorAssembly": "res://parts/assemblies/CurvedBeltConveyorAssembly.tscn",
	"CurvedRollerConveyorAssembly": "res://parts/assemblies/CurvedRollerConveyorAssembly.tscn",
	"BeltSpurConveyorAssembly": "res://parts/assemblies/BeltSpurConveyorAssembly.tscn",
	"RollerSpurConveyorAssembly": "res://parts/assemblies/RollerSpurConveyorAssembly.tscn",
	"BeltConveyor": "res://parts/BeltConveyor.tscn",
	"RollerConveyor": "res://parts/RollerConveyor.tscn",
	"CurvedBeltConveyor": "res://parts/CurvedBeltConveyor.tscn",
	"CurvedRollerConveyor": "res://parts/CurvedRollerConveyor.tscn",
	"BeltSpurConveyor": "res://parts/BeltSpurConveyor.tscn",
	"RollerSpurConveyor": "res://parts/RollerSpurConveyor.tscn",
	"Box": "res://parts/Box.tscn",
	"Pallet": "res://parts/Pallet.tscn",
	"BoxSpawner": "res://parts/BoxSpawner.tscn",
	"PalletSpawner": "res://parts/PalletSpawner.tscn",
	"Despawner": "res://parts/Despawner.tscn",
	"DiffuseSensor": "res://parts/DiffuseSensor.tscn",
	"LaserSensor": "res://parts/LaserSensor.tscn",
	"ColorSensor": "res://parts/ColorSensor.tscn",
	"PushButton": "res://parts/PushButton.tscn",
	"StackLight": "res://parts/StackLight.tscn",
	"CameraStreamer": "res://parts/CameraStreamer.tscn",
	"SixAxisRobot": "res://parts/SixAxisRobot.tscn",
	"Gantry": "res://parts/Gantry.tscn",
	"BladeStop": "res://parts/BladeStop.tscn",
	"Diverter": "res://parts/Diverter.tscn",
	"ChainTransfer": "res://parts/ChainTransfer.tscn",
	"GenericData": "res://parts/GenericData.tscn",
	"Celda": "res://parts/Celda.tscn",
	"Placer": "res://parts/Placer.tscn",
	"Dispenser": "res://parts/Dispenser.tscn",
	"Stringer": "res://parts/Stringer.tscn",
	"Tira": "res://parts/Tira.tscn",
	"Maquina1": "res://parts/Maquina1.tscn",
}

const CATEGORIES: Dictionary = {
	"Assemblies": [
		"BeltConveyorAssembly", "RollerConveyorAssembly",
		"CurvedBeltConveyorAssembly", "CurvedRollerConveyorAssembly",
		"BeltSpurConveyorAssembly", "RollerSpurConveyorAssembly",
		"Maquina1",
	],
	"Conveyors": [
		"BeltConveyor", "RollerConveyor",
		"CurvedBeltConveyor", "CurvedRollerConveyor",
		"BeltSpurConveyor", "RollerSpurConveyor",
	],
	"Products": ["Box", "Pallet", "Celda", "Placer", "Tira"],
	"Spawners": ["BoxSpawner", "PalletSpawner", "Despawner", "Dispenser"],
	"Devices": ["DiffuseSensor", "LaserSensor", "ColorSensor", "PushButton", "StackLight", "CameraStreamer"],
	"Robots": ["SixAxisRobot", "Gantry", "Stringer"],
	"Accessories": ["BladeStop", "Diverter", "ChainTransfer", "GenericData"],
}

static func get_scene_path(type_name: String) -> String:
	return TYPE_MAP.get(type_name, "")

static func get_type_for_node(node: Node) -> String:
	var script: Script = node.get_script()
	if script:
		var global_name: String = script.get_global_name()
		if global_name in TYPE_MAP:
			return global_name
	var class_name_str: String = node.get_class()
	for key in TYPE_MAP:
		if key == class_name_str:
			return key
	return ""

static func get_all_types() -> Array:
	return TYPE_MAP.keys()

static func get_category_types(category: String) -> Array:
	return CATEGORIES.get(category, []) as Array

static func get_categories() -> Array:
	return CATEGORIES.keys()
