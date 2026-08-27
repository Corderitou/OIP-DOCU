# How to: Grab, Cut and Release Tiras (Dispenser + Stringer)

Workflow for the solar stringing cell: the [Stringer](#stringer) reaches the [Dispenser](#dispenser), extends two parallel tira ropes to its head, cuts them free from the dispenser, carries them to the cell, and releases them so they fall (as a rope chain) onto the cell/belt.

## Prerequisites

- A `Dispenser` part with its `scene` property pointing to `Tira.tscn`
- A `Stringer` part placed near the dispenser (head within ~0.6 m of the dispenser origin)
- Both parts inside the same scene (e.g. `Simulation.tscn`), edit mode (tool scripts)

## Steps

### 1. Grab — extend the tiras

Move the Stringer's **`z_position`** (or `y_position`) in the inspector. When the head is within `_detect_distance` (0.6 m) of the Dispenser:

1. The Dispenser highlights **green** (`set_detected(true)`).
2. `Stringer.grab()` calls `Dispenser.spawn_tira()`, which spawns **2 Tira instances** in parallel (offset X = ±`tira_spacing / 2`).
3. Each Tira builds a rope chain from the Dispenser's `SpawnPoint` to the Stringer head via `Tira.build_chain()`.

Every subsequent `z_position`/`y_position` change re-places the chains (`place_chain()`) so they stay connected between dispenser and head.

> Note: detection works by **distance polling** from the `z_position`/`y_position` setters and `_ready()`, not by Area3D signals — physics (and therefore `area_entered`/`body_entered`) does not run in the editor, so polling is used instead.

### 2. Cut — detach from the dispenser

Set the Dispenser's **`cut_trigger`** export to `true` (it auto-resets to `false`). This:

1. Frees the **anchor pin** (`PinAnchor`) of each tira (`Tira.cut_chain()`).
2. Reparents each Tira from the Dispenser to the scene root (preserving its global transform).
3. **Only after reparenting**, unfreezes the chain (`Tira.detach_after_reparent()` → `unfreeze_chain()`), which re-syncs every joint to the new tree path.

What happens to the chain depends on whether the Stringer still holds it:

- **Held by the Stringer** (`Tira.held == true`): the tira becomes **hanging** — the dispenser-side end falls under gravity, while the head-side end stays pinned to the Stringer head via the **head pin** (`PinHead`, a world-anchored `PinJoint3D` on the last segment). Moving the Stringer drags the hanging chain along.
- **Already released** (`held == false`): the tira is fully free and falls completely.

The chains are now free pieces held only by the Stringer.

### 3. Release — let the chains fall

Set the Stringer's **`release_trigger`** export to `true`. This calls `Stringer.release()`, which:

1. Marks each Tira `top_level = true` **preserving its global transform** (no teleport).
2. Calls `Tira.release_from_stringer()`: clears `held`, frees the head pin, and unfreezes the chain — gravity takes over.

The chains fall as ropes onto the floor/cell. If they had never been cut, they instead hang from the Dispenser's `SpawnPoint` (the anchor pin is still alive).

> Note: after `release()`, the Stringer does **not** re-grab the Dispenser automatically — the head must leave the 0.6 m detection range first (`_can_regrab` re-arms when no Dispenser is in range). This prevents `release` → `cut` from silently spawning a fresh pair of held (frozen) tiras and cutting those instead of the released ones.

### 4. Run the simulation

Press **Start** in the Simulation panel. `Simulation.started` unfreezes every chain in the scene except those in the **taut** state (`held == true && _dynamic == false`, i.e. a chain currently stretched between dispenser and head). Chains hanging from the head (`held && _dynamic`) and free chains are unfrozen. `Simulation.stopped` freezes all chains again with zeroed velocities.

## State model (how it works)

A Tira chain is a `Node3D` with two world-anchored `PinJoint3D` pins and a `RigidBody3D` chain between them (segments joined by `Generic6DOFJoint3D` with a metal-strip bend profile):

- **`PinAnchor`** — pins segment **0** to the Dispenser's `SpawnPoint` (world anchor). Freed by `cut_chain()`.
- **`PinHead`** — pins the **last segment** to a world point at the Stringer head. Created in `build_chain()`, dragged by `_move_head_pin()` on every `place_chain()` call while hanging, freed by `release_from_stringer()`.

Two flags drive the behavior:

| Flag | Meaning |
|---|---|
| `held` | The Stringer owns this tira (`grab()` set it). `release()` clears it. |
| `_dynamic` | The chain is physics-live and hangs from the head pin (`cut()` set it when the tira was held). |

Three observable states:

| State | `held` | `_dynamic` | What the chain does |
|---|---|---|---|
| **taut** | true | false | Frozen; `place_chain()` repositions the whole chain between SpawnPoint and head; both pins inert |
| **hanging** | true | true | Unfrozen; gravity pulls the dispenser-side end down; the head end follows the Stringer head (head pin); `place_chain()` only moves the head pin |
| **free** | false | false | Unfrozen, no pins; falls completely |

Transitions:

- `grab()` → spawns tiras, builds chains, `held = true` (**taut**).
- `cut()` (Dispenser) → frees `PinAnchor`; if `held`, sets `_dynamic = true` (**hanging**); reparents to root; unfreezes.
- `release()` (Stringer) → `held = false`, frees `PinHead`, `_dynamic = false` (**free**); unfreezes.
- `release()` without a previous `cut()` → `held = false`, but `PinAnchor` is still alive → the chain hangs from the SpawnPoint (**free**, dispenser-anchored).
- `Simulation.started` → unfreezes everything except **taut** chains.
- `Simulation.stopped` → freezes everything (velocities zeroed).

## Cut vs. Release semantics

| Scenario | Result |
|---|---|
| Cut + Release | Chains are free and fall to the floor |
| Release **without** cut | Chains are unfrozen but **stay anchored** to the Dispenser's `SpawnPoint` (the anchor joint is still alive) — they hang from the dispenser |
| Cut without Release | Chains detach from the dispenser, hang from the Stringer head (dispenser-side end falls); `release()` drops them fully |

The connection to the Dispenser is owned by the **anchor joint**, not by the Stringer. Releasing from the Stringer never detaches the tiras from the dispenser — and cutting from the dispenser never detaches them from the Stringer.

## Rope physics details

| Parameter | Value | Notes |
|---|---|---|
| `SEGMENT_LENGTH` | 0.02 m | Segment size (0.05 → 0.02: ~2.5× more segments, smoother curve) |
| Segment mass | 0.005 kg | Total strip mass stays similar vs. old 0.02 kg per 0.05 m segment |
| Segment collision | layer **10**, mask **15** (1,2,3,4) | Collides with Static, Dynamic, Belt, Box |
| Segment shape | 0.006 × 0.002 × `seg_len*0.95` | 95% length leaves gaps (no self-overlap) |
| Body damping | `angular_damp = 3.0`, `linear_damp = 0.5` | Dampens oscillation/flare. **Jolt ignores the 6DOF's angular springs** — the damping lives on the body, not the joint |
| Body flags | `can_sleep = true`, `continuous_cd = true` | Sleep when settled (no jitter); continuous CCD reduces floor tunneling |
| Joints between segments | `Generic6DOFJoint3D` per pair | Metal-strip profile: bend ±15° (X), lateral ±3° (Y), twist ±2° (Z), linear ±0.001 m (anti-stretch) |
| World pins | `PinJoint3D` (`PinAnchor`, `PinHead`) | Anchor seg 0 to `SpawnPoint`; head pin holds last segment to the head. Unchanged from the original design |
| Freeze | `freeze = true` in editor | Bodies never move until simulation/release |

**6DOF frame orientation is mandatory.** The angular/linear limits are expressed in the joint's frame. Every segment and every joint must be oriented with a shared `Basis.looking_at(chain_dir, up)` (with an `up` fallback for near-vertical chains), otherwise the twist/bend/lateral limits are meaningless and the strip twists like a rope. All of `build_chain`, `place_chain` and `_sync_joints` write full `Transform3D` (basis + origin), not just position.

Segments of the two parallel chains do **not** collide with each other (layer 10 is not in mask 15).

`place_chain()` rebuilds only when the required segment count differs by more than 2 (`absi(needed - size) > 2`); within that band it rescales the existing segments' length instead of destroying/recreating nodes, avoiding flicker when the head crosses a 0.02 m threshold.

## Joint syncing and the NaN fix

Every `Joint3D` (`PinJoint3D` and `Generic6DOFJoint3D`) captures its anchor point in each body's local frame **when `node_a`/`node_b` are assigned**, not when the body moves. This caused the chains to explode ("sale volando") with non-finite (`NaN`) transforms, which triggered `renderer_scene_cull.cpp: Condition "!v.is_finite()"`.

The current `Tira` implementation avoids this:

1. Every joint gets its full `global_transform` (basis + origin) set **before** `node_a`/`node_b` are assigned, so the first physics configuration is already correct.
2. `_sync_joints()` **forces** a reconfiguration (clears node paths, repositions, reassigns) on every `place_chain()` and right before `unfreeze_chain()`, so anchors and the 6DOF frame always match the current body positions and chain direction.
3. `_safe()` clamps any non-finite vector to `Vector3.ZERO` in all position writes (segments, joints, chain endpoints); `_safe_basis()` and `_chain_basis()` guard the full transform writes.

If the chains still explode after manual position edits, check that the joints were synced (re-apply `z_position`) before starting the simulation.

## Pitfalls learned the hard way

1. **Reparent before unfreeze.** `unfreeze_chain()` re-assigns every joint's `node_a`/`node_b` from the node's **current** tree path. If the tira is still a child of the Dispenser when unfrozen and only then reparented to the root, the joints keep the stale path (`Dispenser/Tira/Seg...`) which no longer resolves — the chain falls entirely. Correct order in `Dispenser.cut()`: `cut_chain()` → reparent to root → `detach_after_reparent()` (which unfreezes and re-syncs).
2. **Never share arrays by reference.** `Dispenser.spawn_tira()` returns its internal `_spawned_tiras` array. If the Stringer stores it directly (`_held_tiras = tiras`), both nodes share the same array, and `cut()` clearing `_spawned_tiras` silently empties `_held_tiras` too — `release()` then finds "nothing held". Copy it: `_held_tiras = tiras.duplicate()`.
3. **Don't trust `_spawned_tiras` for `cut()`.** It is wiped by any re-grab and resets on scene reload. `Dispenser.cut()` instead finds live chains with `find_children("*", "Tira", ...)` and cuts those that still have a chain (`has_chain()`), regardless of which Stringer holds them.
4. **Auto-regrab confusion.** After `release()` the head is still inside the detection range, so any position change used to re-trigger `grab()` and spawn a fresh (frozen) pair of tiras — the dispenser lit green again and `cut()` silently targeted the new pair. Fix: `_can_regrab` only re-arms once the head leaves the 0.6 m range.
5. **`sleeping = false` after unfreeze.** Re-registered bodies (post-reparent) can start asleep; `unfreeze_chain()` explicitly wakes every segment.

## Known issues

- **Tunneling through the floor:** the segments are very thin (0.002 m) and can fall through thin floor colliders when released from a height. Mitigations in place:
  - `continuous_cd = true` is enabled on every segment in `Tira.build_chain()`.
  - Segments are now 0.02 m long (was 0.05 m), which also reduces tunneling.
  - Use a thicker floor collider (the GridMap floor in `Building.tscn` is a `GridMap` with `collision_mask = 8` — verify segment mask includes the floor layer).

## Files

| File | Role |
|---|---|
| `src/Tira/tira.gd` | Rope chain: build/place/cut/freeze/unfreeze + joint sync + NaN guards |
| `src/Tira/tira_bundle.gd` | `TiraBundle`: agrupa las N tiras de un ciclo bajo un único padre y las une físicamente con cross-joints entre segmentos homólogos |
| `src/Dispenser/dispenser.gd` | Spawns 2 parallel tiras, `cut_trigger`/`cut()`, green detection highlight |
| `src/Stringer/stringer.gd` | Distance-poll detection, `grab()`/`release()`, `release_trigger` |
| `parts/Tira.tscn` | Empty Node3D container + script (segments are procedural) |
| `parts/Dispenser.tscn` | `Body` StaticBody3D (layer 6) + `SpawnPoint` at `(0, -0.1, 0)` |
| `parts/Stringer.tscn` | `Head` Node3D + `GrabArea` Area3D (mask 6) |
| `Simulation.tscn` | Example wiring: `Dispenser.scene = Tira.tscn`, `tira_spacing = 0.08` |

## TiraBundle — las tiras del ciclo cuentan como UN objeto

Cuando `tiras_por_ciclo >= 2`, `Dispenser.spawn_tira()` crea un **`TiraBundle`**
(Node3D) bajo el `SpawnPoint` y mete las 2 (o más) tiras dentro: en el tree son
un **único objeto** con 2 cadenas hijas. `Dispenser.cut()` reparentea el **bundle
completo** a la raíz (no cada tira por separado), conservando la agrupación.

- Cuando ambas tiras quedan **libres** (post `cut()` + `release()`: `held=false`,
  sin anclajes, `has_chain()`), el bundle crea un `Generic6DOFJoint3D` rígido
  entre cada par de segmentos homólogos (`segA[i] ↔ segB[i]`) → las dos cadenas
  forman una "escalera" que se dobla como cinta doble pero **no se separa**
  lateralmente. Límites: lineal ±0.0015 m, angular ±0.001 rad.
- Los cross-joints son hijos del **bundle**, no de la tira → `_sync_joints()` /
  `clear_chain()` de `Tira` no los tocan.
- `Simulation.stopped` → `unbind()` + `queue_free()` del bundle (respeta
  `remove_on_stop`: si alguna tira debe persistir, el bundle permanece).

### Interacción con la SandwichStation

En la escena demo las tiras bundleadas viajan sobre la IndexingBelt y llegan a la
SandwichStation **dentro del bundle**. La estación detecta cada `Tira` hija del
bundle (su `_find_part_owner` sube hasta `Tira`, ignorando el `TiraBundle`) y al
soldarla la reparentea bajo el sled con `set_composite_mode(true)` (congela y
descolisiona los segmentos). Consecuencias:

- Los cross-joints del bundle quedan **huérfanos** (paths a nodos reparenteados →
  inertes), pero los segmentos ya están congelados en el composite → inofensivo.
- El bundle permanece en el tree hasta `Simulation.stopped`, que lo limpia
  (`unbind()` + `queue_free()`).
- Validado end-to-end con `test_integration_bundle.gd` (Maquina1 real → estación,
  11/11 PASS, sin errores de física ni de script).

Validación: `test_tira_bundle.gd` (grab → release → cut, comprueba padre común,
`is_bound()`, cross-joints creados, separación entre segmentos homólogos ≈
`tira_spacing` y ausencia de NaN).
