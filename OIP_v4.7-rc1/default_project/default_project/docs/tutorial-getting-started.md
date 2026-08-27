# Tutorial: Getting Started

Build a working conveyor simulation from scratch in under 10 minutes. You'll place a belt conveyor, add a diffuse sensor, run the physics simulation, and watch boxes move.

## What you'll need

- The Open Industry Project release package (includes the custom Godot 4.7 editor)
- Basic familiarity with 3D editors (navigating a viewport, selecting objects)

## Step 1: Open the project

1. Download the latest release from [GitHub Releases](https://github.com/Open-Industry-Project/Open-Industry-Project/releases).
2. Extract the archive and launch the included Godot editor.
3. In the Project Manager, click **Import** and navigate to the extracted project folder.
4. Click **Import & Edit**.

The editor opens with the Runtime Editor as the main scene. *(DEPRECATED: the runtime editor is no longer the active component; its code is in `deprecated/runtime/` for historical reference only.)*

## Step 2: Create a new simulation

Click **New Simulation** in the 3D viewport welcome panel. This creates:

- A root `Simulation` node
- A `Building` child (floor, walls, roof)
- A `SceneRoot` node where all parts will live

Alternatively: **File > New** or `Ctrl+N`.

## Step 3: Place a conveyor

1. In the **Parts** panel (left side), find **BeltConveyor** under the Conveyors category.
2. Drag it into the 3D viewport. A green ghost preview follows your mouse.
3. Click to place it. The conveyor appears with a white belt and metal frame.

The conveyor is 4m long, 1.524m wide by default. You can resize it using the gizmo handles (see Step 6).

## Step 4: Add a sensor

1. In the Parts panel, find **DiffuseSensor** under Devices.
2. Drag it into the viewport and place it near the conveyor, facing the belt.
3. Select the sensor and look at the **Inspector** panel (right side).
4. The sensor emits a visible beam (green line). When a box passes through, it turns red.

## Step 5: Add a box spawner

1. Find **BoxSpawner** in Parts and drag it to the start of the conveyor.
2. In the Inspector, set `boxes_per_minute` to `30`.
3. Set `initial_linear_velocity` to `Vector3(0, 0, 0)` (the conveyor will push the box).

## Step 6: Run the simulation

Press `F5` or click the **Play** button in the toolbar.

The simulation starts:
- The BoxSpawner creates boxes on the conveyor
- Boxes ride the belt at the configured speed (default 2 m/s)
- The DiffuseSensor beam turns red when a box passes

Press `F5` again to stop. All spawned boxes are cleaned up automatically.

## Step 7: Resize the conveyor

1. Stop the simulation (`F5`).
2. Select the conveyor.
3. Drag the colored handles on each axis to resize:
   - **Red (X)**: Length
   - **Green (Y)**: Height
   - **Blue (Z)**: Width
4. Minimum length is constrained by the frame rail geometry.

You can also type exact values in the Inspector under the `size` property.

## Step 8: Navigate the viewport

| Action | How |
|---|---|
| Orbit | Hold **right mouse button** + drag |
| Pan (Walk mode) | **WASD** keys while holding right-click |
| Zoom | **Mouse wheel** |
| Switch Walk/Fly | Press **B** |
| Focus on selection | Press **F** |
| Front view | Press **1** |
| Top view | Press **5** |

In Walk mode, the camera stays at eye height (1.7m). In Fly mode, you move freely in 3D.

## Step 9: Save your scene

`Ctrl+S` saves the scene as a `.oip_scene.json` file. This is OIP's custom scene format — not a Godot `.tscn`. See [Scene File Format](reference-scene-format.md) for details.

## What you built

A basic conveyor line with:
- A belt conveyor carrying products
- A diffuse sensor detecting objects
- A box spawner generating traffic

## Next steps

- [Connect to a PLC](tutorial-communication-setup.md) to control the conveyor speed from external software
- [Use conveyor snapping](howto-conveyor-snapping.md) to build multi-conveyor layouts
- [Import custom models](howto-import-models.md) to add your own equipment
- Browse the [Parts Catalog](reference-parts-catalog.md) to see all 34 available components
