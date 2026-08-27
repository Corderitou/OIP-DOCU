# Escena `Simulation.tscn` — detalle

Documenta el estado actual (visto en la escena guardada). `Simulation.tscn` es también la escena que carga el botón "New Simulation" del addon `oip_ui` y la que usan los tests headless.

- Formato: `[gd_scene format=3 uid="uid://du8q31sbxhd14"]`, 488 líneas.
- Root: `Node3D` name="Simulation" `unique_id=1483178388`.
- Instancia `parts/Building.tscn` con 5 sub-recursos `building_wall_rule.gd` (muros de la nave).

## Árbol de nodos

```
Simulation (Node3D)
├── Building (PackedScene parts/Building.tscn, rules=[5× Resource building_wall_rule])
│   └── ETAPA 1 (Node3D)
│       ├── BeltConveyor         (parts/BeltConveyor.tscn)
│       ├── BeltConveyor3        (parts/BeltConveyor.tscn)
│       ├── CeldaSpawner         (parts/CeldaSpawner.tscn)
│       ├── BeltConveyor2        (parts/BeltConveyor.tscn)
│       ├── CameraStreamer       (parts/CameraStreamer.tscn)
│       ├── VastagoNeumatico     (parts/VastagoNeumatico.tscn)
│       ├── ColorSensor          (parts/ColorSensor.tscn)
│       ├── ColorSensor2         (parts/ColorSensor.tscn)
│       ├── SensorCeldas         (parts/DiffuseSensor.tscn)
│       ├── SensorPlacers        (parts/DiffuseSensor.tscn)
│       ├── IndexingBeltConveyor3 (parts/IndexingBeltConveyor.tscn)
│       ├── IndexingBeltConveyor4 (parts/IndexingBeltConveyor.tscn)
│       ├── Maquina1             (parts/Maquina1.tscn)
│       ├── PlacerSpawner        (parts/PlacerSpawner.tscn)
│       ├── Gantry               (parts/Gantry.tscn)
│       └── Gantry2              (parts/Gantry.tscn)
├── SandwichStation              (parts/SandwichStation.tscn)
├── SandwichProduct              (CharacterBody3D persistente; unidades runtime)
├── Horno                        (parts/Horno.tscn)
├── SixAxisRobot                 (parts/SixAxisRobot.tscn)
├── SensorBatch                  (parts/DiffuseSensor.tscn, 6axisSensor1)
├── TopeBatch                    (parts/DiffuseSensor.tscn, 6axisSensor1)
├── TopeFisico                   (StaticBody3D capa 1: frena el batch tejido)
└── ReleasedBatches              (runtime: cuerpos desmontados por el robot)
```

## Partes por nodo

### Cintas (BeltConveyor / BeltConveyor2 / BeltConveyor3)

Todas con `enable_comms = true`, `speed = 0.0` (¡la velocidad la pone el PLC vía tag!), `legs_enabled = false`.

| Nodo | Posición | Rotación | Longitud | Ancho | Tags |
|---|---|---|---|---|---|
| BeltConveyor | `(-18.219, 1.06, -13.388)` | identidad | 4.365 | 0.6 | `ns=2;s=BeltConveyor_Speed`, `ns=2;s=BeltConveyor_Running` |
| BeltConveyor3 | `(-10.81, 1.06, -13.396)` | 180° sobre Y | 2.025 | 0.6 | `ns=2;s=BeltConveyor3_Speed`, `ns=2;s=BeltConveyor3_Running` |
| BeltConveyor2 | `(-13.854, 1.058, -13.388)` | identidad | 0.645 | 0.6 | `ns=2;s=BeltConveyor2_Speed`, `ns=2;s=BeltConveyor2_Running` |

 BeltConveyor conserva `side_guard_openings` (4 aberturas) y `metadata/_snap_transform`. BeltConveyor2/3 tienen los guards laterales desactivados (`left_side_guards_enabled=false`, `right_side_guards_enabled=false`).

Layout físico (eje X negativo → positivo): `BeltConveyor` (-18.2) → `BeltConveyor2` (-13.85) → `CeldaSpawner` (-15.0) → `BeltConveyor3` (-10.81). La rama de celdas usa `BeltConveyor` + `BeltConveyor2` y la rama de placers usa `BeltConveyor3`; cada rama se detiene en su sensor de toma.

### CeldaSpawner (S1)

- Posición: `(-15.001672, 1.4547727, -13.396449)` — encima de BeltConveyor.
- `spawn_offset = (0, -0.1, 0)`, `spawn_velocity = (0,0,0)`, `spawn_per_minute = 60` (por defecto de escena).
- `enable_comms = true`. Tags (grupo por defecto):

```
cmd_tag        = ns=2;s=S1_CMD          (Int32)
exec_tag       = ns=2;s=S1_EXEC         (Bool)
done_tag       = ns=2;s=S1_DONE         (Bool)
running_tag    = ns=2;s=S1_RUNNING      (Bool)
ready_tag      = ns=2;s=S1_READY        (Bool)
count_tag      = ns=2;s=S1_COUNT        (Int32)
auto_enable_tag= ns=2;s=S1_AUTO_ENABLE  (Bool)
rate_tag       = ns=2;s=S1_RATE         (Float32)
```

### CameraStreamer

- Posición: `(-14.16, 1.615, -13.568511)`, rotación mirando hacia la cinta (`Transform3D(1,0,0, 0,0,-1, 0,1,0)`).
- `streaming_enabled = false`, `jpeg_quality = 0.5`, `fov = 35.438`.

### VastagoNeumatico

- Posición: `(-14.154944, 1.1073663, -12.877878)`, rotación 180° sobre Y.
- `extend_time = 1.0`, `stroke_length = 0.655`, `cylinder_length = 0.37`, `cylinder_diameter = 0.05`, `rod_diameter = 0.015`.
- `enable_comms = true`, `tag_group_name = "PLCSIM"`, `tag_name = "ns=2;s=Vastago_Extend"` (Bool, leído → extiende/retrae).

### ColorSensor / ColorSensor2

- ColorSensor: `(-13.193624, 1.0260369, -13.4292555)`, ColorSensor2: `(-12.812705, 1.0260369, -13.433808)`. Escala 0.1739, `show_beam = false`.
- `tag_group_name = "PLCSIM"`. **Sin `enable_comms=true`** → `enable_comms=false` por defecto → **no registran tags** (no están en el tree, y no hace falta).

### SixAxisRobot

- Posición: `(-9.980649, 0, -12.79993)` (sin escala).
- `home_position = [29.826667, -2.9, 54.739522, 0, 81.3, 31.5]` (grados por articulación J1..J6).
- Tiene Point1, Point2 y Point3 para toma/entrega, más Point12..Point19 para la
  grilla posterior. El mapeo de comando usa el número de la clave del waypoint.
- Herramienta: `tool_size_x=1.428499`, `tool_size_z=0.10289`; el `VacuumArea` usa
  `collision_mask=10`.
- `enable_comms=true`, grupo `PLCSIM`: `Robot1_Command`, `Robot1_Execute`,
  `Robot1_Done` y `Robot1_Vacuum`.
- El robot selecciona el cuerpo `RigidBody3D` más cercano en la zona de vacío.
  Los cuerpos internos del producto (`PlacerBatch_*` y `WovenBatch_*`) se separan
  del producto al agarrarlos mediante `top_level=true` y se mueven con la copa.

### Sensores de toma

- SensorCeldas: `(-13.270951, 1.0153147, -13.777999)`, `show_beam = false`, `enable_comms = true`, `tag_name = "ns=2;s=SensorCeldas"` (nodo ex `DiffuseSensor2`, re-etiquetado desde `Sensor2`).
- SensorPlacers: `(-12.726395, 1.0183206, -13.80368)`, `max_range = 0.685`, `enable_comms = true`, `tag_name = "ns=2;s=SensorPlacers"` (nodo ex `DiffuseSensor`/Sensor1, movido al punto de toma de placers y re-etiquetado).
- Los tags `Sensor1` y `Sensor2` ya no los escribe ninguna parte: quedan solo como variables del tree sin uso (la lógica de control nueva no los referencia).
- SensorBatch: `(-10.649586, 0.94602454, -11.751952)`, `max_range=0.554`,
  `enable_comms=true`, `tag_name="ns=2;s=6axisSensor1"`.
- TopeBatch (ex "TOPE"): `(-10.611671, 0.94602454, -12.083578)`, `max_range=0.224`,
  `tag_group_name="PLCSIM"`, `tag_name="ns=2;s=6axisSensor1"`.
- **TopeFisico**: `StaticBody3D` con `collision_layer=1` + placa visible
  `(-10.621, 1.0, -12.16)`, caja `0.03×0.12×0.60`. Es el **tope físico del batch**: el
  shell `TransportCollision` del producto (mask 1) choca contra él y el batch queda
  retenido aunque la cinta siga empujando. Su cara −X queda ~2 mm aguas arriba de la cara
  −X del fotoojo de `TopeBatch` — ojo: el `StaticBody3D` interno de `DiffuseSensor` usa
  `collision_layer=3` (máscara de bits = capas 1 Y 2), así que el fotoojo por sí solo
  también frenaría el shell; el muro va delante para que el stop sea el muro.
- Grupo: `PLCSIM`. `SensorCeldas` y `SensorPlacers` gobiernan sus ramas de alimentación.
  `SensorBatch` y `TopeBatch` comparten actualmente el tag `6axisSensor1` para el ciclo del robot.
- `DiffuseSensor` hace raycast con `collision_mask=8` (capa 4). Por eso el collider
  de transporte del producto usa `collision_layer=0`: puede detenerse contra estáticos
  mediante su máscara, pero no mantiene activado `BatchSensor` cuando la unidad interna
  ya fue retirada.

### IndexingBeltConveyor3

- Posición: `(-13.310758, 0.98244756, -12.161912)` — superficie de cinta en `y ≈ 0.982`.
- `length = 2.695`, `height = 0.03`, `step_distance = 0.165`, `step_speed = 0.1`, `belt_color = Color(0.7258, 0.6837, 0.5951, 1)`.
- `enable_comms = true`, `tag_group_name = "PLCSIM"`.
- `step_tag = "ns=2;s=IndexingBelt3_Step"` (Bool), `running_tag = "ns=2;s=IndexingBelt3_Running"` (Bool). `speed_tag` y `step_distance_tag` vacíos.
- Cuerpo `BeltBody` (StaticBody3D): layer 1, mask 1; arrastra por `constant_linear_velocity`.

### IndexingBeltConveyor4

- Mismo `IndexingBeltConveyor.tscn`, transform `(-8.816082, 0.761607, -11.750714)` con
  rotación (transporte transversal hacia la grilla del robot 6 ejes). `length = 2.695`,
  `step_distance = 0.165`, `step_speed = 0.1`.
- `tag_group_name = "PLCSIM"` pero **sin `enable_comms`** → **no registra tags**. Sus
  `step_tag`/`running_tag` apuntan a `ns=2;s=IndexingBelt3_Step/_Running` (los de Belt3);
  si algún día se activa `enable_comms` registraría tags duplicados con Belt3 — mejor
  darle tags propios (`IndexingBelt4_*`) y añadirlos al tree.

### Maquina1

- Posición: `(-13.412, 0.998, -12.167)`, `z_position = 0.0`, `motion_speed = 0.0`.
- Contiene `Dispenser` (hijo) + `Stringer` (hijo). El Dispenser produce las tiras
  **bundleadas**: `tira_spacing = 0.06`, `tiras_por_ciclo = 2` (default) → crea un
  `TiraBundle` que agrupa las 2 tiras y las une con cross-joints (viajan como un
  solo objeto hasta la SandwichStation).
- `enable_comms = true`. Usa tags por defecto del script (no los sobreescribe la escena):
  - `cut_tag = "ns=2;s=Maquina1_Cut"` (Bool, leído)
  - `release_tag = "ns=2;s=Maquina1_Release"` (Bool, leído)
  - `z_tag = "ns=2;s=Maquina1_Z"` (Float, leído)
  - `y_tag = "ns=2;s=Maquina1_Y"` (Float, leído)
  - `speed_tag = "ns=2;s=Maquina1_Speed"` (Float, leído)

### PlacerSpawner (S2)

- Posición: `(-10.878136, 1.3340129, -13.395435)`.
- `spawn_offset = (0,0,0)`, `spawn_velocity = (0,0,0)`.
- `enable_comms = true`. Tags (grupo por defecto), idénticos en nombre a S1:

```
cmd_tag        = ns=2;s=S2_CMD          (Int32)
exec_tag       = ns=2;s=S2_EXEC         (Bool)
done_tag       = ns=2;s=S2_DONE         (Bool)
running_tag    = ns=2;s=S2_RUNNING      (Bool)
ready_tag      = ns=2;s=S2_READY        (Bool)
count_tag      = ns=2;s=S2_COUNT        (Int32)
auto_enable_tag= ns=2;s=S2_AUTO_ENABLE  (Bool)
rate_tag       = ns=2;s=S2_RATE         (Float32)
```

### Gantry (Gantry1)

- Posición: `(-14.29692, 0, -12.748)`. Escala uniforme `0.45`. Marco: `frame_length=4.95`, `frame_width=5.6`, `frame_height=4.29`.
- `home_position = [2.315, -1.426, 1.214]` (X, Y, Z en metros dentro del marco).
- `waypoints` (clave `"N: Nombre"` ordena el índice de comando):
  - `1: Point1` = `[2.315, -1.426, 1.634]`
  - `2: Point2` = `[2.315, 1.294, 1.129]`
  - `3: Point3` = `[2.359, 1.294, 2.244]`
- `selected_waypoint = "3: Point3"`, `new_waypoint_name = "Point4"`.
- `enable_comms = true`, `tag_group_name = "PLCSIM"`:
  - `command_tag = "ns=2;s=Gantry1_Command"` (Int16)
  - `execute_tag = "ns=2;s=Gantry1_Execute"` (Bool)
  - `done_tag = "ns=2;s=Gantry1_Done"` (Bool)
  - `vacuum_tag = "ns=2;s=Gantry1_Vacuum"` (Bool)

### Gantry2

- Posición: `(-12.78, 0, -12.748)`. Escala `0.45`. Marco: `frame_length=1.44`, `frame_width=5.6`, `frame_height=4.29`. `motion_speed=10.0`.
- `home_position = [0.025, -1.43, 1.214]`.
- `waypoints`:
  - `1: Point1` = `[0.025, -1.43, 1.669]`
  - `2: Point2` = `[-2.355, 1.294, 1.261]`
  - `3: Point3` = `[-2.23, 1.294, 1.659]`
- `enable_comms = true`, `tag_group_name = "PLCSIM"`:
  - `command_tag = "ns=2;s=Gantry2_Command"` (Int16)
  - `execute_tag = "ns=2;s=Gantry2_Execute"` (Bool)
  - `done_tag = "ns=2;s=Gantry2_Done"` (Bool)
  - `vacuum_tag = "ns=2;s=Gantry2_Vacuum"` (Bool)

### SandwichStation

- Posición: `(-12.724542, 1.0615056, -12.16)` — sobre la `IndexingBeltConveyor3` (superficie en `y≈0.982`).
- `tag_group_name = "PLCSIM"`, `enable_comms` = false por defecto → **no registra tags**. `belt_path = "../Building/ETAPA 1/IndexingBeltConveyor3/BeltBody"`.
- **Estación devoradora**: detecta con `DetectArea` (caja `0.6×0.6×0.6`, `collision_mask=10`) las partes `Placer`/`Celda`/`Tira` (cuerpos layer 10). Al completarse el stack (celda + placer + ≥2 tiras) **despawna** las partes y **emite una unidad de producto tejido** por stack consumido.
- **Producto de salida**: nodo persistente `SandwichProduct` de tipo `CharacterBody3D`
  (**obligatorio**: si queda como `Node3D`, `_configure_transport_body()` no crea el
  `TransportCollision` y el primer producto atraviesa los topes avanzando con
  `position.x +=`), hermano de la estación. En runtime crea `ProductUnits/Batch_N`; cada
  batch separa `WovenBatch_N` (celdas, bundles y tiras visuales) de `PlacerBatch_N`
  (placers y colisiones). Verificar estas ramas en **Remote** durante Play; Local solo
  muestra los contenedores persistentes. Cada producto (raíz) tiene su PROPIO
  `ProductUnits/Batch_0` — nunca buscar batches por nombre global, iterar `_products`.
- El producto crea dinámicamente un `TransportCollision` que cubre el batch actual.
  Usa `collision_layer=0` y `collision_mask=1`, y avanza con `move_and_collide()` a
  la velocidad X de `IndexingBeltConveyor3`. La máscara 1 permite el choque contra
  obstáculos estáticos (por eso `TopeFisico` lo detiene); la layer 0 evita que
  `BatchSensor` lo confunda con una celda.
- **Batches independientes** (decisión del usuario): el producto siguiente sigue
  avanzando aunque el anterior esté detenido en `TopeFisico` — sin cola ni gap; los
  shells no colisionan entre sí (layer 0). Reposo del batch:
  `origen.x = cara_−X_TopeFisico − 0.083`.
- **Liberación de shells vacíos**: cuando el robot desmonta (`top_level=true`) TODOS los
  cuerpos de un lote, la estación los reparenta al contenedor `ReleasedBatches`
  (hermano, transform global preservado — seguro aunque el robot los siga cargando) y
  retira el shell vacío (el de escena se limpia y oculta; los dinámicos se `queue_free`).
  `ReleasedBatches` se vacía en cada arranque y en cada parada con `remove_on_stop`.
- `remove_on_stop=false` en la instancia demo → el producto convertido permanece visible al detener; al iniciar otra simulación se vacían las unidades y se reposiciona el contenedor.
- **Preview en editor**: export `preview_units` (0-12), script `@tool` → genera N unidades como hijos temporales (`PreviewSandwichProduct`) sin play. Vista temporal y no se guarda.

### Ejecución y Remote

- `Simulation.tscn` tiene `MainCamera` (`current=true`) para que F5/F6 no arranquen con el viewport gris.
- `src/Simulation/simulation_scene.gd` intenta iniciar el singleton `Simulation` al ejecutar la escena normalmente; evita emitir solo la señal `started`, porque eso no actualiza `Simulation.is_running()`.
- Para inspeccionar unidades generadas: ejecutar, abrir la pestaña **Remote** del Scene dock y expandir `Simulation/SandwichProduct/ProductUnits/Batch_0`.
- Formación física de cada stack (top→bottom): **Placer → 2 tiras → Celda → 2 tiras**. Las tiras llegan bundleadas (TiraBundle) desde Maquina1. Ver `references/sandwich.md`.

### Horno (`Horno`, `src/Horno/horno.gd`)

- Extiende `MaquinaTermica`. `enable_comms=true` (control por Node-RED vía `H1_CMD`/`H1_EXEC`).
- Transform: `Transform3D(0.35, 0, 0, 0, 0.26, 0, 0, 0, 0.275, -12.095593, 1.0305746, -12.16)` — sobre `IndexingBeltConveyor3`, aguas abajo de `SandwichStation`.
- **Tags PLC** (`H1_*`): `CMD`, `EXEC`, `DONE`, `RUNNING`, `READY`, `FAULT`, `IN_POS`, `SETPOINT`, `MV`, `PV`, `CYCLE_TIME`; `enable_comms=true`.
- **Cabezal procedural**: nodo `Head` (MeshInstance3D) con placa calefactora `HeaterVisual`. Baja/sube según `_cycle_active`; `head_up_y=0.3`, `head_down_y=-0.15`, `head_move_time=0.3`, `thermal_tau=3.0`.
- **Detección**: polling de distancia (producto visual, sin bodies). `detect_half_width=0.35` m; al detectar → `IN_POS=true`. El flujo Node-RED dispara el ciclo con `hornoFire()` en cada paso del indexing belt.
- `cycle_time=3.0` s; `mvValue=100` (heater al 100% durante el ciclo).

## Notas sobre los tags y el tree

- Solo las partes con `enable_comms=true` registran tags en `_on_simulation_started()`. En esta escena registran las cintas configuradas, CeldaSpawner, VastagoNeumatico, SensorCeldas, SensorPlacers, IndexingBeltConveyor3, Maquina1, PlacerSpawner, Gantry, Gantry2, Horno, SixAxisRobot, SensorBatch y TopeBatch.
- **Todas esas tags existen en el tree Node-RED** (57 variables `ns=2;s=...`, ver `references/control.md`). Si en el futuro se activa `enable_comms` en ColorSensor o SixAxisRobot, hay que añadir sus tags al tree o el sim abortará con `BadNodeIdUnknown`.
- El grupo de todas las partes es `PLCSIM` (o el por defecto que resuelve `OIPCommsSetup.default_tag_group`); los spawners no fijan `tag_group_name` y usan el default.
