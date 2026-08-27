# How to Use Robot & Gantry Gizmos

Position 6-axis robots and gantry (Cartesian) robots using visual handles and inverse kinematics.

## Prerequisites

- A SixAxisRobot or Gantry placed in the scene from the Parts browser

## Six-Axis Robot

### Joint rotation gizmos

1. Select the robot in the viewport.
2. Six colored arc handles appear at each joint:
   - **Red** — Joint 1 (base rotation, Y-axis)
   - **Orange** — Joint 2 (shoulder, Z-axis)
   - **Yellow** — Joint 3 (elbow, Z-axis)
   - **Green** — Joint 4 (wrist rotation, Y-axis)
   - **Blue** — Joint 5 (wrist pitch, Z-axis)
   - **Purple** — Joint 6 (tool rotation, Y-axis)
3. Click and drag an arc to rotate that joint. The angle is displayed in the Inspector.

### Joint limits

| Joint | Min | Max |
|---|---|---|
| J1 (base) | -180° | 180° |
| J2 (shoulder) | -135° | 135° |
| J3 (elbow) | -160° | 160° |
| J4 (wrist rot) | -180° | 180° |
| J5 (wrist pitch) | -120° | 120° |
| J6 (tool) | -360° | 360° |

### End effector positioning (IK)

1. Click the **crosshair** at the tool tip (cyan marker).
2. Drag to move the tool tip in 3D space.
3. The robot solves inverse kinematics (CCD algorithm) to position all joints.
4. The solver runs up to 20 iterations with 0.01m tolerance.

### Waypoints

1. Position the robot joints or end effector.
2. Enter a name in the Inspector (e.g., "PickPosition").
3. Click **Train Waypoint** (tool button or Inspector).
4. To move to a waypoint: select it and click **Go To Waypoint**.
5. Click **Set Home** to save the current pose as home.
6. Click **Go Home** to return to the home pose.

### Vacuum gripper

Toggle `vacuum_on` in the Inspector during simulation. When activated:
- The gripper detects nearby RigidBody3D objects (Box, Pallet)
- Picks up the closest object by disabling its gravity
- Releases when `vacuum_on` is turned off

## Gantry Robot

### End effector positioning

1. Select the gantry in the viewport.
2. A **cyan crosshair** appears at the tool tip.
3. Click and drag to move the tool tip. Movement maps to:
   - Local X → `x_position`
   - Local Z → `y_position`
   - Local -Y → `z_position` (extends downward like a piston)

### Frame size

Adjust `frame_length`, `frame_width`, and `frame_height` in the Inspector to resize the gantry structure. All geometry rebuilds procedurally.

### Axis positions

Each axis (X, Y, Z) is clamped to the frame dimensions. Set exact positions in the Inspector or via the gizmo.

### Waypoints and vacuum

Same workflow as SixAxisRobot: train, go to, set home, go home. Vacuum gripper works identically.

## Undo/Redo

All gizmo operations support undo/redo (`Ctrl+Z` / `Ctrl+Y`). Joint rotations, end effector movements, and gantry positioning are all captured.

## See also

- [Parts Catalog](reference-parts-catalog.md) — SixAxisRobot and Gantry properties
- [Editor Plugins](reference-plugins.md) — How the gizmo addons work
- [Keyboard Shortcuts](reference-shortcuts.md) — All shortcuts
