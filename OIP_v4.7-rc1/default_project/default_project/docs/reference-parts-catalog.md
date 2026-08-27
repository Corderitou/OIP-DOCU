# Reference: Industrial Parts Catalog

All 34 parts available in the Parts browser, with properties, communication tags, and physics behavior.

## Parts by Category

### Conveyors

| Part | Description | Resizable | Comms Tags |
|---|---|---|---|
| [BeltConveyor](#beltconveyor) | Belt conveyor with animated UV surface | Yes (X/Y/Z) | speed (REAL), running (BOOL) |
| [RollerConveyor](#rollerconveyor) | Roller conveyor with skew angle support | Yes (X/Y/Z) | speed (REAL), running (BOOL) |
| BeltSpurConveyor | Belt conveyor with side spur | Yes | speed (REAL), running (BOOL) |
| RollerSpurConveyor | Roller conveyor with side spur | Yes | speed (REAL), running (BOOL) |
| CurvedBeltConveyor | 90° curved belt conveyor | No | speed (REAL), running (BOOL) |
| CurvedRollerConveyor | 90° curved roller conveyor | No | speed (REAL), running (BOOL) |

### Assemblies

| Part | Description | Resizable | Comms Tags |
|---|---|---|---|
| BeltConveyorAssembly | Belt conveyor + legs + side guards | Yes (X/Z) | speed (REAL), running (BOOL) |
| RollerConveyorAssembly | Roller conveyor + legs + side guards | Yes (X/Z) | speed (REAL), running (BOOL) |

### Products

| Part | Description | Resizable | Comms Tags |
|---|---|---|---|
| [Box](#box) | Rigid body box | Yes (X/Y/Z) | None |
| [Pallet](#pallet) | Fixed-size pallet | No | None |
| [Tira](#tira) | Thin tinned-copper strip for cell stringing | No | None |

### Spawners & Despawners

| Part | Description | Resizable | Comms Tags |
|---|---|---|---|
| [BoxSpawner](#boxspawner) | Spawns boxes at configurable rate | No | None |
| [PalletSpawner](#palletspawner) | Spawns pallets at fixed interval | No | None |
| [Despawner](#despawner) | Destroys objects entering its area | No | None |
| [Dispenser](#dispenser) | Spawns tinned-copper strips on trigger | No | None |

### Devices (Sensors & Input)

| Part | Description | Resizable | Comms Tags |
|---|---|---|---|
| [DiffuseSensor](#diffusesensor) | Photoelectric sensor (BOOL output) | No | output (BOOL) |
| [LaserSensor](#lasersensor) | Distance measurement sensor | No | distance (REAL) |
| [ColorSensor](#colorsensor) | Color detection sensor | No | color_value (DINT) |
| [PushButton](#pushbutton) | Momentary/toggle push button | No | pushbutton (BOOL), lamp (BOOL) |
| [StackLight](#stacklight) | Multi-segment stack light | No | light_value (BYTE) |
| [CameraStreamer](#camerastreamer) | Live MJPEG video stream to the network | No | None |

### Robots

| Part | Description | Resizable | Comms Tags |
|---|---|---|---|
| [SixAxisRobot](#sixaxisrobot) | 6-axis articulated robot with vacuum gripper | No | command (INT), execute (BOOL), done (BOOL), vacuum (BOOL) |
| [Gantry](#gantry) | 3-axis Cartesian robot with vacuum gripper | No | command (INT), execute (BOOL), done (BOOL), vacuum (BOOL) |
| [Stringer](#stringer) | 2-axis pick-and-place for cell stringing strips | No | None |

### Accessories

| Part | Description | Resizable | Comms Tags |
|---|---|---|---|
| [BladeStop](#bladestop) | Pneumatic stop blade | No | active (BOOL) |
| [ChainTransfer](#chaintransfer) | Chain transfer conveyor (cross-flow) | No | speed (REAL), popup (BOOL) |
| [Diverter](#diverter) | Diverts products to a side lane | No | trigger (BOOL) |
| SideGuardsCBC | Side guards for curved belt conveyor | No | None |
| ConveyorLeg | Conveyor support leg | No | None |

---

## BeltConveyor

**File:** `src/Conveyor/belt_conveyor.gd`
**Extends:** `ResizableNode3D`

A belt conveyor with animated UV-scrolling belt surface. Supports speed control, color customization, and frame rail generation.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `belt_color` | Color | White | Belt surface color |
| `belt_texture` | Enum | STANDARD | STANDARD or ALTERNATE texture |
| `speed` | float | 2.0 | Belt speed in m/s |
| `belt_physics_material` | PhysicsMaterial | null | Friction/roughness for belt surface |
| `size` | Vector3 | (4, 0.5, 1.524) | Length/height/width in meters |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `speed_tag_name` | REAL | Read | Belt speed from PLC |
| `running_tag_name` | BOOL | Read | Running state from PLC |

### Behavior

- Belt surface animates via UV scrolling at `speed` m/s
- `StaticBody3D` child applies `constant_linear_velocity` for physics movement
- Frame rails are procedurally generated and anchored to conveyor edges
- Minimum length constrained by frame rail geometry

---

## RollerConveyor

**File:** `src/RollerConveyor/roller_conveyor.gd`
**Extends:** `ResizableNode3D`

A roller conveyor with adjustable skew angle for angled product transfer.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `speed` | float | 1.0 | Roller speed in m/s |
| `skew_angle` | float | 0.0 | Roller skew angle (-60° to 60°) |
| `size` | Vector3 | (4, 0.5, 1.524) | Length/height/width |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `speed_tag_name` | REAL | Read | Roller speed from PLC |
| `running_tag_name` | BOOL | Read | Running state from PLC |

### Behavior

- Skew angle rotates the velocity vector for diagonal product movement
- Transfer plates are generated at corners when skew angle is active
- Rollers animate via material UV offset
- Velocity compensated by `1/cos(skew_angle)` for consistent visual speed

---

## DiffuseSensor

**File:** `src/DiffuseSensor/diffuse_sensor.gd`
**Extends:** `Node3D`

Photoelectric proximity sensor. Detects objects via raycasting and outputs a boolean.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `max_range` | float | 1.524 | Detection range in meters (0-100) |
| `show_beam` | bool | true | Show/hide detection beam |
| `normally_closed` | bool | false | Inverts output logic |
| `detected` | bool | false | Read-only: true when object in range |
| `output` | bool | false | Read-only: final output after NC logic |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `tag_name` | BOOL | Write | Sensor output to PLC |

### Behavior

- Raycasts from local position `(0, 0.25, 0.42)` along +Z
- Uses collision mask 8 (layer 4) for detection
- Beam color: GREEN (no hit) or RED (hit)
- Beam rendered via `RenderingServer` (not scene tree)

---

## LaserSensor

**File:** `src/LaserSensor/laser_sensor.gd`
**Extends:** `Node3D`

Distance measurement sensor. Outputs continuous distance to the nearest object.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `max_range` | float | 1.524 | Maximum range in meters (0-100) |
| `show_beam` | bool | true | Show/hide laser beam |
| `distance` | float | max_range | Read-only: distance to target |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `tag_name` | REAL | Write | Distance value to PLC |

### Behavior

- Raycasts from `global_position` along +Z
- Outputs continuous float (distance in meters)
- Writes to PLC tag on every value change

---

## ColorSensor

**File:** `src/ColorSensor/color_sensor.gd`
**Extends:** `Node3D`

Reads the albedo color of objects in range and maps to integer values.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `max_range` | float | 1.524 | Detection range |
| `show_beam` | bool | true | Show/hide beam |
| `color_detected` | Color | BLACK | Currently detected color |
| `color_map` | Dictionary | {RED:1, GREEN:2, BLUE:3} | Color-to-integer mapping |
| `color_value` | int | 0 | Read-only: mapped integer |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `tag_name` | DINT | Write | Color value to PLC |

### Behavior

- Reads `StandardMaterial3D.albedo_color` from hit object's mesh
- Maps color to integer via `color_map` dictionary
- Beam color matches detected color (GREEN if nothing detected)

---

## SixAxisRobot

**File:** `src/SixAxisRobot/six_axis_robot.gd`
**Extends:** `Node3D`

6-axis articulated robot arm with procedural mesh, IK solver, and vacuum gripper.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `j1_angle` through `j6_angle` | float | various | Joint angles in degrees |
| `home_position` | Array[float] | [0,-45,90,25,75,0] | Home pose |
| `waypoints` | Dictionary | {} | Named poses |
| `motion_speed` | float | 45.0 | Joint speed in deg/s |
| `robot_scale` | float | 3.0 | Visual scale (0.1-10) |
| `vacuum_on` | bool | false | Gripper active |
| `holding_object` | bool | false | Read-only: holding something |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `command_tag` | INT | Read | Command from PLC (0=home, 1+=waypoint index) |
| `execute_tag` | BOOL | Read | Rising edge triggers movement |
| `done_tag` | BOOL | Write | True when not moving |
| `vacuum_tag` | BOOL | Read | Gripper control from PLC |

### Behavior

- All geometry is procedural (no imported meshes)
- CCD IK solver: up to 20 iterations, 0.01m tolerance
- Vacuum gripper uses Area3D for range detection
- Held objects have gravity disabled and are kinematically positioned

---

## Gantry

**File:** `src/Gantry/gantry.gd`
**Extends:** `Node3D`

3-axis Cartesian robot (linear actuator) with procedural frame and vacuum gripper.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `x_position` | float | 0.0 | X axis position (clamped to frame) |
| `y_position` | float | 0.0 | Y axis position (clamped to frame) |
| `z_position` | float | 0.0 | Z axis (extends downward) |
| `frame_length` | float | 2.0 | Frame length (0.5-20m) |
| `frame_width` | float | 1.0 | Frame width (0.3-10m) |
| `frame_height` | float | 1.5 | Frame height (0.5-10m) |
| `motion_speed` | float | 1.0 | Axis speed in m/s |
| `vacuum_on` | bool | false | Gripper active |
| `holding_object` | bool | false | Read-only |

### Communication Tags

Same as SixAxisRobot: command, execute, done, vacuum.

### Behavior

- All geometry procedural (cylinders for posts, boxes for beams/rails)
- Z extends downward like a piston
- Same vacuum gripper pattern as SixAxisRobot

---

## Box

**File:** `src/Box/Box.gd`
**Extends:** `ResizableNode3D`

Rigid body box product. Sized via the `size` property.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `size` | Vector3 | (0.6, 0.4, 0.4) | Dimensions in meters |
| `color` | Color | WHITE | Box color |
| `initial_linear_velocity` | Vector3 | ZERO | Starting velocity |

### Behavior

- RigidBody3D with dynamic mesh scaling
- Spawned boxes (from BoxSpawner) self-destruct on simulation end
- Supports freeze/unfreeze via `use()` method

---

## Pallet

**File:** `src/Pallet/pallet.gd`
**Extends:** `Node3D`

Fixed-size pallet product. Not resizable.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `color` | Color | WHITE | Pallet color |
| `initial_linear_velocity` | Vector3 | ZERO | Starting velocity |

### Behavior

- RigidBody3D, restores initial transform on simulation end
- Spawned pallets self-destruct on simulation end

---

## BoxSpawner

**File:** `src/BoxSpawner/box_spawner.gd`
**Extends:** `Node3D`

Spawns box instances at a configurable rate.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `disable` | bool | false | Stop spawning |
| `box_color` | Color | WHITE | Spawned box color |
| `random_size` | bool | false | Randomize box dimensions |
| `random_size_min/max` | Vector3 | (0.5,0.5,0.5)/(1,1,1) | Size range |
| `initial_linear_velocity` | Vector3 | ZERO | Starting velocity |
| `boxes_per_minute` | int | 45 | Spawn rate (0-1000) |
| `fixed_rate` | bool | true | Fixed vs random timing |
| `conveyor` | Node3D | null | Pause when conveyor speed=0 |

### Behavior

- First box spawns immediately on simulation start
- Fixed rate: interval = 60 / boxes_per_minute seconds
- Random rate: interval randomized by 0.5x-1.5x

---

## PalletSpawner

**File:** `src/PalletSpawner/pallet_spawner.gd`
**Extends:** `Node3D`

Spawns pallet instances at a fixed interval.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `disable` | bool | false | Stop spawning |
| `spawn_interval` | float | 1.0 | Seconds between spawns |

---

## Despawner

**File:** `src/Despawner/despawner.gd`
**Extends:** `Node3D`

Destroys spawned objects (Box, Pallet) that enter its Area3D.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `monitoring` | bool | true | Enable area detection |

### Behavior

- Only despawns objects with `instanced == true` (from spawners)
- Does not affect manually placed parts

---

## BladeStop

**File:** `src/BladeStop/blade_stop.gd`
**Extends:** `Node3D`

Pneumatic stop blade that raises/lowers to block product flow.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `active` | bool | false | Blade raised (true) or lowered (false) |
| `air_pressure_height` | float | 0.0 | Vertical offset for blade base |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `tag_name` | BOOL | Read/Write | Bidirectional active state |

### Behavior

- Animated via parallel tweens (0.15s duration)
- Bidirectional comms: reads and writes the same tag

---

## ChainTransfer

**File:** `src/ChainTransfer/chain_transfer.gd`
**Extends:** `Node3D`

Chain transfer conveyor for cross-flow product movement.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `chains` | int | 3 | Number of chain lanes (2-6) |
| `distance` | float | 0.33 | Chain spacing in meters |
| `speed` | float | 2.0 | Chain speed in m/s |
| `popup_chains` | bool | false | Raise chains to lift products |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `speed_tag_name` | REAL | Read | Chain speed from PLC |
| `popup_tag_name` | BOOL | Read | Popup control from PLC |

---

## Diverter

**File:** `src/Diverter/diverter.gd`
**Extends:** `Node3D`

Diverter arm that pushes products to a side lane.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `divert_time` | float | 0.25 | Arm travel duration |
| `divert_distance` | float | 0.75 | Arm travel distance |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `tag_name` | BOOL | Read | Trigger input from PLC |

### Behavior

- Rising-edge triggered (auto-resets after 0.3s)
- Comms is read-only (receives trigger from PLC)

---

## StackLight

**File:** `src/StackLight/stack_light.gd`
**Extends:** `Node3D`

Multi-segment stack light with bitmask control.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `segments` | int | 1 | Number of light segments (1-8) |
| `light_value` | int | 0 | Bitmask (bit 0 = segment 1) |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `tag_name` | BYTE | Read | Light bitmask from PLC |

### Behavior

- Segments dynamically spawned/removed
- Each segment clickable to toggle its bit
- Y-axis scale locked to X-axis (uniform)

---

## PushButton

**File:** `src/PushButton/push_button.gd`
**Extends:** `Node3D`

Industrial push button with momentary/toggle modes and lamp control.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `text` | String | "STOP" | Button label |
| `toggle` | bool | false | Toggle mode (vs momentary) |
| `normally_closed` | bool | false | Inverts output |
| `pressed` | bool | false | Current state |
| `output` | bool | false | Read-only: final output |
| `lamp` | bool | false | Lamp illumination |
| `button_color` | Color | RED | Button color |

### Communication Tags

| Tag | Data Type | Direction | Description |
|---|---|---|---|
| `pushbutton_tag_name` | BOOL | Write | Button output to PLC |
| `lamp_tag_name` | BOOL | Read | Lamp control from PLC |

### Behavior

- Momentary mode: auto-resets after 0.3s
- Two separate tag groups: one for button output, one for lamp
- Material made unique per instance for per-button coloring

---

## CameraStreamer

**File:** `src/CameraStreamer/camera_streamer.gd`
**Extends:** `Node3D`

Live streaming camera. Serves the view of its internal camera over HTTP as an MJPEG stream so any device on the local network (VLC, a phone browser) can watch the simulation live. See [How-to: Stream the Simulation Live](howto-camera-streaming.md).

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `streaming_enabled` | bool | true | Start/stop the HTTP server |
| `port` | int | 8090 | TCP port (auto-increments if busy) |
| `resolution` | Vector2i | (640, 360) | Stream resolution |
| `stream_fps` | int | 15 | Frames per second (1-30) |
| `jpeg_quality` | float | 0.7 | JPEG quality (0.1-1.0) |
| `fov` | float | 70.0 | Camera field of view in degrees |
| `show_preview` | bool | true | Live preview screen on camera body |
| `stream_url` | String | — | Read-only: stream URL |
| `clients_connected` | int | 0 | Read-only: connected clients |

### Communication Tags

None (network output via HTTP, not PLC tags).

### Behavior

- Internal `Camera3D` renders to an offscreen `SubViewport`; looks along the part's +Z axis (lens side)
- Embedded `TCPServer` serves `/` (HTML viewer), `/stream` (MJPEG), `/snapshot` (single JPEG)
- Binds on all interfaces — reachable via the machine's LAN IP
- Frames captured only while clients are connected; slow clients dropped automatically
- Max 8 simultaneous clients; `use()` (click during simulation) toggles streaming

---

## Tira

**File:** `src/Tira/tira.gd`
**Extends:** `Node3D`

A thin tinned-copper strip used as the raw material for cell stringing. Spawned in pairs by the [Dispenser](#dispenser) and carried by the [Stringer](#stringer). Not a single rigid box — it is a **rope chain** of small `RigidBody3D` segments joined by `Generic6DOFJoint3D` (metal-strip bend profile) with two world-anchored `PinJoint3D` pins, built procedurally at runtime. See [How to: Grab, Cut and Release Tiras](howto-stringer-dispenser.md).

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `held` | bool | false | True while the Stringer owns this tira (set by `grab()`). Guards `_on_simulation_started` against unfreezing a taut chain |
| `fall_gravity_scale` | float | 1.0 | Gravity applied to segments after `unfreeze_chain()` (tuning knob; last resort vs. the joint limits/damping) |

All other state is internal (`_segments`, `_joints`, `_anchor_joint`, `_head_joint`, `_dynamic`); segments and joints are created in `build_chain()`.

### Methods

| Method | Description |
|---|---|
| `build_chain(start_pos, end_pos, x_offset)` | Rebuilds the chain between two world points (clears previous chain first); creates both `PinAnchor` (segment 0) and `PinHead` (last segment) |
| `place_chain(start_pos, end_pos, x_offset)` | Taut state: re-positions segments along the line + re-syncs joints. Hanging state (`_dynamic`): only moves the head pin to `end_pos` |
| `cut_chain()` | Frees the anchor `PinJoint3D` — detaches the chain from the `SpawnPoint` |
| `detach_after_reparent()` | Unfreezes the chain + re-syncs all joints (call **after** reparenting to root) |
| `release_from_stringer()` | Clears `held`, frees the head pin, `_dynamic = false`, unfreezes → full fall |
| `freeze_chain()` | Freezes segments, zeroes velocities, disables gravity |
| `unfreeze_chain()` | Syncs joints, zeroes velocities, wakes segments (`sleeping = false`), enables gravity |
| `has_chain()` | True if segments exist |
| `clear_chain()` | Frees all segments and joints |

### Behavior

- Rope physics: `RigidBody3D` segments (`SEGMENT_LENGTH = 0.02`, mass 0.005) linked with `Generic6DOFJoint3D` at segment midpoints (bend ±15° on X, lateral ±3° on Y, twist ±2° on Z, linear ±0.001 m anti-stretch), plus **two** world pins (`PinJoint3D`): `PinAnchor` (segment 0 → Dispenser `SpawnPoint`) and `PinHead` (last segment → Stringer head position)
- Three states driven by `held` + `_dynamic`: **taut** (held, frozen, `place_chain()` stretches it), **hanging** (held + cut, physics-live, hangs from `PinHead`, `place_chain()` only drags the head pin), **free** (released, no pins, falls). See [How to: Grab, Cut and Release Tiras](howto-stringer-dispenser.md)
- Segment collision: layer **10**, mask **15** (Static, Dynamic, Belt, Box); shape `0.006 × 0.002 × seg_len*0.95` (no segment-to-segment overlap)
- Segments are `freeze = true` in the editor and only simulate after `unfreeze_chain()`
- Body damping (`angular_damp = 3.0`, `linear_damp = 0.5`) replaces the 6DOF's angular springs (Jolt ignores them); `can_sleep = true` lets settled chains sleep (no jitter); `continuous_cd = true` reduces floor tunneling
- Segments and joints are oriented along the chain with a shared basis (`_chain_basis`, `up` fallback for near-vertical chains) — without it the 6DOF angular limits are meaningless
- Joints are re-synced (`_sync_joints()`) on every placement and before unfreezing — every `Joint3D` captures its anchor when `node_a`/`node_b` are assigned, so stale anchors caused physics explosions and `NaN` renderer errors (`renderer_scene_cull`)
- All position writes pass through a `_safe()` NaN guard (non-finite vectors clamp to `Vector3.ZERO`); basis writes through `_safe_basis()`/`_chain_basis()`
- Two parallel chains (spawned by the Dispenser) do not collide with each other
- `place_chain()` rebuilds only when `absi(needed - size) > 2`, otherwise rescales segment length in place (no flicker at thresholds)
- `_on_simulation_started` unfreezes everything except **taut** chains (`held && not _dynamic`)

---

## Dispenser

**File:** `src/Dispenser/dispenser.gd`
**Extends:** `Node3D`

Dispenses Tira strips on demand. Stationary — no movement. Triggered programmatically by the [Stringer](#stringer).

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `scene` | PackedScene | — | The Tira scene to spawn (`Tira.tscn`) |
| `initial_linear_velocity` | Vector3 | ZERO | Starting velocity for spawned strips |
| `tira_spacing` | float | 0.02 | Lateral spacing between the two parallel tiras (0.08 in `Simulation.tscn`) |
| `cut_trigger` | bool | false | Set `true` to cut the spawned tiras free (auto-resets to `false`) |

### Methods

| Method | Returns | Description |
|---|---|---|
| `set_detected(detected)` | void | Green highlight override while the Stringer is grabbing |
| `spawn_tira()` | Array[Node3D] | Instantiates **2 parallel Tiras** at the SpawnPoint (offset ±`tira_spacing/2`) |
| `cut()` | void | Finds live Tiras with chains anywhere in the scene (`find_children` recursive, no `held` filter), frees their `PinAnchor`, reparents to root, then unfreezes (hanging or full fall) |

### Behavior

- `spawn_tira()` instantiates the assigned `scene` twice (X offset ±`tira_spacing/2`), positions them at the `SpawnPoint` child (`(0, -0.1, 0)`), and sets `owner` for editor persistence
- `cut_trigger` is a one-shot: setting it to `true` triggers `cut()` and immediately resets to `false`
- `cut()` does **not** rely on `_spawned_tiras` (wiped by re-grabs and scene reloads) — it scans children for live `Tira` nodes with chains. For each: frees `PinAnchor`, marks `_dynamic` if still held by a Stringer, reparents to the scene root, then calls `detach_after_reparent()` (reparent **before** unfreeze so joint paths resolve)
- Cutting a held tira makes it hang from the Stringer head (dispenser side falls); cutting a released one drops it completely
- The part's `Body` StaticBody3D is on layer **6** (mask 0); it does not collide with tira segments (mask 15)
- Does not auto-spawn — only creates Tiras when `spawn_tira()` is called

---

## Stringer

**File:** `src/Stringer/stringer.gd`
**Extends:** `Node3D`

2-axis Cartesian pick-and-place machine for positioning tinned-copper strips on solar cells. Moves in Z (forward/backward) and Y (up/down). Used in conjunction with a [Dispenser](#dispenser) to grab Tiras and place them on [Celdas](#celda). See [How to: Grab, Cut and Release Tiras](howto-stringer-dispenser.md).

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `z_position` | float | 0.0 | Forward/backward position (clamped to z_range) |
| `y_position` | float | 0.0 | Vertical position (clamped to y_range) |
| `z_range` | Vector2 | (0, 1.5) | Min/max Z travel limits |
| `y_range` | Vector2 | (0, 1.0) | Min/max Y travel limits |
| `motion_speed` | float | 1.0 | Axis movement speed in m/s |
| `release_trigger` | bool | false | Set `true` to release the held tiras (auto-resets to `false`) |

### Methods

| Method | Returns | Description |
|---|---|---|
| `move_to(z, y)` | void | Tween-driven movement to target Z/Y position |
| `is_moving()` | bool | True while a movement tween is active |
| `get_head_position()` | Vector3 | Global position of the head |
| `grab(dispenser)` | bool | Spawns 2 tiras from dispenser and builds their chains (SpawnPoint → head) |
| `release()` | Node3D | Drops the held chains (`release_from_stringer()` on each) and marks them `top_level = true` |
| `stop_motion()` | void | Kills the active movement tween |

### Behavior

- Head moves along Z (forward/back) and Y (up/down) via tweens; no lateral (X) movement
- **Editor detection by distance polling** (`_detect_distance = 0.6`): `z_position`/`y_position` setters and `_ready()` poll for the nearest Dispenser within range. Area3D signals are not used because physics does not run in the editor
- On detection, `grab()` spawns the tiras via `Dispenser.spawn_tira()` and calls `Tira.build_chain()` for each (SpawnPoint → head, X offset per chain); subsequent position changes call `place_chain()` to keep the chains taut between dispenser and head
- `grab()` stores `_held_tiras = tiras.duplicate()` — **never the dispenser's array by reference**, or `cut()` clearing `_spawned_tiras` would wipe the held list too
- After `release()`, `_can_regrab = false` prevents an instant re-grab while the head is still within range; it re-arms only when the head leaves the 0.6 m radius
- `release_trigger` is a one-shot: setting it to `true` triggers `release()` and immediately resets to `false`
- `release()` calls `Tira.release_from_stringer()` (held → free) and sets `top_level = true` so world transforms survive after leaving the Stringer's control
- If the tiras were **not** cut first, they remain anchored to the Dispenser's `SpawnPoint` and hang from it; the Stringer only drops its own grip
