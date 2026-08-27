# Código de las partes — semántica de tags y comms

Documenta cómo cada parte de la escena lee/escribe sus tags y qué significan. Todas siguen el patrón: registran tags en `_on_simulation_started()` (conectado a `Simulation.started` en `_enter_tree`), escriben/leen en `_tag_group_polled(group)` (llamado por el grupo cuando hay polling), y resetean la caché de `OIPCommsTag` en `_tag_group_initialized`.

Reglas transversales (ver también `AGENTS.md`):
- `OIPCommsTag._should_write()` descarta writes con valor idéntico (write-on-change). `PlantComms.write_bit(tag, value, only_if_changed)` es el helper multi-tag.
- Nunca escribir tags en `_physics_process`; los writes van en handlers de estado/flanco o en `_tag_group_polled`.
- `tag_group_name` vacío → `OIPCommsSetup.default_tag_group()` lo resuelve al default.

## Gantry — `src/Gantry/gantry.gd`

4 tags (grupo `tag_group_name`, normalmente `PLCSIM`):
- `command_tag` → `TAG_TYPE_INT16`. **Semántica del comando**: `0` = home, `1..N` = waypoint, donde el índice es la posición de la key en `waypoints.keys()` (orden del diccionario: `"1: Point1"`, `"2: Point2"`, ...).

Handlers:
- `_on_simulation_started()` (línea 730): registra los 4 tags si `enable_comms && !tag_group_name.is_empty()`.
- `_tag_group_initialized()` (746): `on_group_initialized` de cada tag + `_write_status_tags()`.
- `_tag_group_polled()` (754): lee `vacuum` → `vacuum_on`; lee `execute`, y con **flanco ascendente** (si `not _is_moving`) llama a `_execute_command()`; después `_write_status_tags()`.
- `_execute_command()` (772): `cmd == 0` → `move_to_home()`; `cmd > 0` → `go_to_waypoint(waypoints.keys()[cmd-1])`.
- `_write_status_tags()` (791): `done = not _is_moving` (write-on-change interno del tag).

Dirección: PLC → simulador: `Command`, `Execute`, `Vacuum`. Simulador → PLC: `Done`.

## Spawner (CeldaSpawner S1, PlacerSpawner S2)

- CeldaSpawner: `src/CeldaSpawner/celda_spawner.gd`
- PlacerSpawner: `src/PlacerSpawner/placer_spawner.gd`

Ambos con 8 tags de estación tipo Maquina (grupo por defecto):
- `cmd_tag` Int32, `exec_tag` Bool, `done_tag` Bool, `running_tag` Bool, `ready_tag` Bool, `count_tag` Int32, `auto_enable_tag` Bool, `rate_tag` Float32.

Polling (celda_spawner.gd 88-113):
- `exec` flanco ascendente → `_start_command(cmd)`.
- `auto_enable == true` → arranca lote a `60 / rate` (intervalo en segundos).
- Escrituras (con `only_if_changed`): `running = _pending > 0`, `done = _done`, `ready = (scene != null)`.
- `count_tag` se escribe en `_on_spawn` (celda 221).

Dirección: PLC → simulador: `CMD`, `EXEC`, `AUTO_ENABLE`, `RATE`. Simulador → PLC: `DONE`, `RUNNING`, `READY`, `COUNT`.

## IndexingBeltConveyor — `src/IndexingBeltConveyor/indexing_belt_conveyor.gd`

Tags: `step_tag` Bool, `speed_tag` Float32 (override), `step_distance_tag` Float32 (override), `running_tag` Bool.

- `_tag_group_polled()` (281): **flanco ascendente** de `step` → `advance()` (suma `step_distance` a `_target_position`); `speed_tag` → `step_speed`; `step_distance_tag` → `step_distance`.
- `_physics_process()` (229): mueve `_current_position` hacia `_target_position` a `step_speed` (distancia medida localmente → la latencia OPC UA solo retrasa el arranque del paso, nunca su distancia); aplica velocidad al belt con `BeltSurface.apply_velocity`; escribe `running = moving` (write-on-change vía `OIPCommsTag`).
- `_on_simulation_started()` (248): registra los tags y resetea posiciones. `_on_simulation_stopped()` (264): resetea, frena el belt y pone `running = false`.

Dirección: PLC → simulador: `Step`, `Speed`, `StepDistance`. Simulador → PLC: `Running`.

## BeltConveyor — `src/Conveyor/belt_conveyor.gd`

Tags: `speed_tag_name` (`TAG_TYPE_FLOAT32`), `running_tag_name` (`TAG_TYPE_BOOL`).

- Registra ambos (814-815). Escribe `running = (speed != 0.0)` (283). En el polled lee `speed` del PLC → `speed = _speed_tag.read_float32()` (838).

Dirección: PLC → simulador: `Speed`. Simulador → PLC: `Running`.

## Maquina1 — `src/Maquina1/maquina1.gd`

Tags por defecto (la escena no los sobreescribe): `cut_tag = "ns=2;s=Maquina1_Cut"`, `release_tag = "ns=2;s=Maquina1_Release"` (Bool), `z_tag = "ns=2;s=Maquina1_Z"`, `y_tag = "ns=2;s=Maquina1_Y"`, `speed_tag = "ns=2;s=Maquina1_Speed"` (Float).

- `setup` en `_on_simulation_started` (168). Polling (118-138): lee `cut`, `release` (bit) y `z`, `y`, `speed` (float) → corta/suelta tiras y mueve.

Dirección: solo PLC → simulador (lecturas).

## VastagoNeumatico — `src/VastagoNeumatico/vastago_neumatico.gd`

- `tag_name` Bool (46). Registra en `_on_simulation_started` si `enable_comms` (115). En el polled (126-128): `_extended = _tag.read_bit()` → extiende/retrae.

Dirección: PLC → simulador.

## DiffuseSensor — `src/DiffuseSensor/diffuse_sensor.gd`

- `tag_name` Bool (60). Registra en `_on_simulation_started` (188). Escribe `output` (detección) en el tag (193); `_tag.write_bit(value)` en 36.
- El sensor usa un raycast con `collision_mask = 8`, es decir, consulta la capa 4
  (items). `BatchSensor` usa esta misma lógica para publicar `6axisSensor1`.

Dirección: simulador → PLC.

## SixAxisRobot — `src/SixAxisRobot/six_axis_robot.gd`

Misma API de 4 tags que Gantry (`command_tag` Int16, `execute_tag`, `done_tag`, `vacuum_tag`).
En la escena actual `enable_comms = true` y usa los tags `Robot1_*` del grupo `PLCSIM`.

- `VacuumArea` detecta cuerpos de la máscara `10` y mantiene una lista de objetos en rango.
- Con vacío activado, `_try_pick_up()` selecciona el cuerpo `RigidBody3D` más cercano.
- Los cuerpos `WovenBatch_*` y `PlacerBatch_*` tienen metadata
  `oip_vacuum_detach=true`. `_attach_object()` conserva su transformada global, establece
  `top_level=true` y congela el cuerpo en modo cinemático para separarlo del movimiento
  del `SandwichProduct`.
- `_update_held_object()` coloca el cuerpo agarrado en la posición y orientación de la
  copa en cada frame. `_release_object()` lo descongela y pone ambas velocidades en cero.
- El nodo raíz `SandwichProduct` no se agarra: su cuerpo de transporte es un
  `CharacterBody3D`, no un `RigidBody3D`.

## ColorSensor — `src/ColorSensor/color_sensor.gd`

- `tag_name` Int32 (64), registra en `_on_simulation_started` (192) y escribe `color_value` (197). **En la escena `enable_comms = false`** → no registra.

## SandwichStation — `src/Sandwich/sandwich_station.gd`

**Sin comms**: `enable_comms=false`, no registra ningún tag. Lógica local. Ver detalle completo en `references/sandwich.md`.

- `_physics_process`: poll de `DetectArea.get_overlapping_bodies()` → `_find_part_owner` (sube por el árbol hasta `Placer`/`Celda`/`Tira`). Al completarse el stack (`_has_complete_stack`: celda + placer + ≥2 tiras) → `_despawn` (queue_free de todas las partes de la zona) + `_append_unit` (1 unidad de producto). Cooldown `consume_cooldown` evita doble-consume.
- `_create_product` crea o reutiliza un `SandwichProduct` hermano de la estación, hijo de la
  raíz, con posición global independiente. El producto es `CharacterBody3D` y cada stack
  se agrega bajo `ProductUnits/Batch_N`.
- Cada batch contiene `WovenBatch_N` (celdas, bundles y tiras visuales) y `PlacerBatch_N`
  (placers visuales y sus `CollisionShape3D`). Los dos cuerpos internos son
  `RigidBody3D` congelados, layer `10`, mask `0`, y son los cuerpos que puede tomar el
  vacío del `6axisRobot`.
- `_configure_transport_body()` crea `TransportCollision`. `_update_transport_collision()`
  recalcula una caja que cubre el batch conforme se agregan unidades. El cuerpo usa
  `collision_layer=0` y `collision_mask=1`: colisiona con obstáculos estáticos de capa 1,
  pero no entra en los raycasts de sensores con máscara `8`.
- `_advance_product()` lee `BeltBody.constant_linear_velocity.x` o `fallback_belt_speed`
  y llama `move_and_collide()`. Cada producto se mueve por separado y se detiene al
  encontrar un obstáculo compatible, sin habilitar colisiones entre productos.
- Las tiras del producto son visuales puras: `parts/Tira.tscn` con `Placeholder` de cobre,
  sin `build_chain()` ni joints.
- **Preview en editor**: export `preview_units` (0-12) + `_rebuild_preview()`/`_clear_preview()`
  genera N unidades temporales bajo `PreviewSandwichProduct`; no se guarda y se limpia al
  volver a 0 o al iniciar la simulación.
- **`TiraBundleExample`** (`src/Tira/tira_bundle_example.gd`): variante persistente de `TiraBundle` para escenas de ejemplo. `tira.gd:_on_simulation_ended()` con guard `_inside_example_bundle()` → la tira bajo un `TiraBundleExample` nunca se auto-elimina al parar.
- Exports: `debug`, `min_tiras_first_stack=2`/`require_placer`/`consume_cooldown` (gate), `unit_spacing`/`tira_z_offset`/`bundle1_offset=-0.101`/`bundle2_offset=-0.189` (producto), `belt_path`/`fallback_belt_speed` (avance), `remove_on_stop=false` en la demo (persistencia visual), `preview_units` (preview editor).
- Conexión a `Simulation.started/stopped` en `_enter_tree`, desconexión en `_exit_tree`. Al `stopped` con `remove_on_stop` → `_cleanup()` (queue_free del producto + reset contador).

## Resumen de direcciones por grupo

| Parte | PLC → Sim | Sim → PLC |
|---|---|---|
| BeltConveyor | Speed | Running |
| CeldaSpawner/PlacerSpawner | CMD, EXEC, AUTO_ENABLE, RATE | DONE, RUNNING, READY, COUNT |
| Gantry | Command, Execute, Vacuum | Done |
| SixAxisRobot | Command, Execute, Vacuum | Done |
| IndexingBelt | Step, Speed, StepDistance | Running |
| Maquina1 | Cut, Release, Z, Y, Speed | — |
| VastagoNeumatico | Extend | — |
| DiffuseSensor | — | detección |
