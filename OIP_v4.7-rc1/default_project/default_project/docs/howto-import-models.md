# How to Import Custom 3D Models

Add third-party CAD models (robot arms, custom machines, sensors) to your OIP simulation.

## Prerequisites

- A 3D model file (STEP, FBX, OBJ, glTF, or Blender file)
- Blender (recommended for conversion) or another 3D editor

## Steps

### 1. Export from CAD to a mesh format

Most industrial CAD software exports to STEP format. OIP does not import STEP directly.

1. Open the STEP file in your CAD software (FreeCAD, Fusion 360, SolidWorks, etc.).
2. Export as **FBX** or **glTF 2.0** for best compatibility with Godot.
3. If exporting to FBX, include embedded textures.

### 2. Clean up in Blender (recommended)

1. Open the exported file in Blender.
2. Check the model scale. OIP uses meters as the unit — a 1m model in real life should be 1 Blender unit.
3. Apply transforms: `Ctrl+A` > All Transforms.
4. Remove unnecessary geometry (hidden faces, internal structures).
5. Export as **glTF 2.0 (.glb)** for single-file convenience, or **FBX**.

### 3. Import into Godot

1. Copy the model file into the `assets/3DModels/` directory (or a subdirectory).
2. Godot automatically imports the file. Check the Import dock for settings.
3. For FBX imports: OIP has Blender/FBX import **disabled** in `project.godot`. Use glTF or convert via Blender first.

For detailed import settings, see the [Godot 3D scene import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html).

### 4. Create a scene

1. Create a new scene (`Ctrl+N`).
2. Add a **Node3D** as the root.
3. Instance your imported model as a child.
4. Add a **StaticBody3D** child with a **CollisionShape3D** for physics interaction.
5. Optionally add a **Script** extending `Node3D` with `@tool` for editor behavior.

### 5. Register in SceneRegistry

To make your part appear in the Parts browser:

1. Add the scene path to `deprecated/runtime/core/scene_registry.gd` in the `_type_map` dictionary. *(Note: `SceneRegistry` belongs to the DEPRECATED runtime editor — its code lives in `deprecated/runtime/` for historical reference only.)*
2. Assign it to a category (Assemblies, Conveyors, Devices, Robots, etc.).

```gdscript
"MyCustomPart": {
    "path": "res://parts/MyCustomPart.tscn",
    "category": "Devices"
}
```

### 6. Add communication tags (optional)

To bind your part to PLC tags, add the standard OIPComms properties:

```gdscript
@export var enable_comms: bool = false
@export var tag_group_name: String = ""
@export var tag_name: String = ""
```

See [Communications Architecture](explanation-comms-architecture.md) for the full pattern.

## Recommended Resources

- [3dfindit](https://www.3dfindit.com/en/) — Large library of free industrial CAD models
- Most manufacturers provide CAD files directly on their websites

## Troubleshooting

| Problem | Fix |
|---|---|
| Model appears too large/small | Check scale in Blender; 1 unit = 1 meter in OIP |
| No collision | Add a StaticBody3D with CollisionShape3D child |
| Model not in Parts browser | Register the path in `scene_registry.gd` |
| FBX not importing | OIP disables FBX import; use glTF instead |
