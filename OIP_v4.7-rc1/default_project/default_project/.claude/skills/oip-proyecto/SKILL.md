---
name: oip-proyecto
description: Contexto completo del estado actual del proyecto OIP (proyecto demo). Documenta qué hay en la escena Simulation.tscn (partes, posiciones, tags, waypoints), cómo funciona la línea controlada (flujo Node-RED func-control + apply_control_flow.js + control_config.json), y qué hay en el código de las partes (semántica de tags y handshakes de Gantry, Spawner, IndexingBelt, BeltConveyor, Maquina1, sensores). Usar cuando haya que entender, modificar o documentar la escena demo actual, su flujo de control desplegado, o el comportamiento de las partes y sus tags de comunicación — distinto de oip (contexto general del framework) y oip-nodered-comms (procedimiento para cambiar el flujo/sincronizar Node-RED).
---

# Contexto del proyecto OIP — estado actual (demo)

Skill de contexto sobre el **estado actual de la escena demo y su control**. Documenta lo que hay en la escena `Simulation.tscn`, cómo funciona la línea (sensores → cintas → spawners → gantries → indexing belt), y la semántica de cada parte en el código. Úsala para orientarte antes de tocar la escena, el flujo de control o el código de partes.

Relaciones con las otras skills OIP:
- `oip` → contexto general del framework (singletons, reglas de escenas, capas, etc.). Esta skill NO repite eso; asume que lo lees si hace falta.
- `oip-nodered-comms` → **procedimiento** para cambiar el flujo Node-RED, sincronizar `~/.node-red/flows.json`, regenerar con `apply_control_flow.js`. Esta skill documenta el **estado desplegado** de ese flujo.

## Qué hay en la escena (resumen)

`Simulation.tscn` = escena demo (root Node3D `Simulation`). Una línea de "celdas" (cajas) movidas por cintas, dos gantries con ventosa, y una indexing belt al final.

```
Simulation
├── Building (instancia parts/Building.tscn + 5 reglas de muro building_wall_rule)
│   └── ETAPA 1
│       ├── BeltConveyor        (4.37 m, tags BeltConveyor_Speed/_Running)
│       ├── BeltConveyor3       (2.63 m, 180°, tags BeltConveyor3_Speed/_Running)
│       ├── BeltConveyor4       (transferencia, comparte tags de BeltConveyor3)
│       ├── CeldaSpawner        (S1: 8 tags de estación)
│       ├── BeltConveyor2       (0.70 m, tags BeltConveyor2_Speed/_Running)
│       ├── CameraStreamer      (streaming desactivado)
│       ├── VastagoNeumatico    (tag Vastago_Extend)
│       ├── ColorSensor + ColorSensor2  (sin comms: enable_comms=false)
│       ├── DiffuseSensor       (Sensor1) + SensorCeldas + SensorPlacers
│       ├── IndexingBeltConveyor3 (step/running IndexingBelt3_*)
│       ├── Maquina1            (Maquina1_Cut/_Release/_Z/_Y/_Speed)
│       ├── PlacerSpawner       (S2: 8 tags de estación)
│       ├── Gantry              (Gantry1: Command/Execute/Done/Vacuum)
│       └── Gantry2             (Gantry2: Command/Execute/Done/Vacuum)
├── SandwichStation             (devoradora: despawn stacks + producto tejido; sin comms)
├── SandwichProduct             (CharacterBody3D persistente; unidades runtime)
├── Horno                       (H1: control térmico)
├── SixAxisRobot                (robot de lotes, Robot1_*)
├── SensorBatch / TopeBatch     (DiffuseSensor; ambos escriben 6axisSensor1)
├── TopeFisico                  (StaticBody3D capa 1: frena el batch en la salida)
└── ReleasedBatches             (runtime: cuerpos desmontados por el robot)
```

Detalle completo (posiciones, waypoints, escalas, transformaciones): leer [references/scene.md](references/scene.md).

## Tags OPC UA (tree Node-RED, grupo `PLCSIM`, ns=2;s=...)

**57 variables** desplegadas, todas `readwrite`. Solo registran tags las partes con `enable_comms=true`; **toda parte que registra debe existir en el tree** (si no, aborto `BadNodeIdUnknown`). `ColorSensor` mantiene `enable_comms=false`; `Horno` y `SixAxisRobot` tienen comms activas en la escena.

| Grupo | Tags | Dirección |
|---|---|---|
| Cintas | `<Nombre>_Speed` (Float), `<Nombre>_Running` (Bool) | PLC escribe Speed; simulador escribe Running |
| CeldaSpawner S1 | `S1_CMD`(Int32), `S1_EXEC`, `S1_DONE`, `S1_RUNNING`, `S1_READY`(Bool), `S1_COUNT`(Int32), `S1_AUTO_ENABLE`(Bool), `S1_RATE`(Float) | estación tipo Maquina |
| PlacerSpawner S2 | `S2_CMD`, `S2_EXEC`, `S2_DONE`, `S2_RUNNING`, `S2_READY`, `S2_COUNT`, `S2_AUTO_ENABLE`, `S2_RATE` | estación tipo Maquina |
| Gantry1 / Gantry2 | `GantryN_Command`(Int16), `GantryN_Execute`(Bool), `GantryN_Done`(Bool), `GantryN_Vacuum`(Bool) | handshake robot |
| IndexingBelt3 | `IndexingBelt3_Step`(Bool), `IndexingBelt3_Running`(Bool) | pulso de paso |
| Maquina1 | `Maquina1_Cut`, `Maquina1_Release`(Bool), `Maquina1_Z`, `Maquina1_Y`, `Maquina1_Speed`(Float) | PLC escribe todo; corte de tiras |
| Vástago | `Vastago_Extend`(Bool) | PLC escribe (extiende/retrae) |
| Sensores | `Sensor1`, `SensorCeldas`, `SensorPlacers`, `6axisSensor1`(Bool) | simulador escribe (detección) |
| 6axisRobot | `Robot1_Command/Execute/Done/Vacuum` | handshake del robot de lotes |

## Cómo funciona la línea (control)

El control vive en Node-RED (flujo OPC UA, lectura cada 50 ms → `func-control` → escrituras). El archivo generado es `node-red/flows.json`; la lógica de control la genera `apply_control_flow.js` a partir de `node-red/control_config.json` (ver [references/control.md](references/control.md)).

Ciclo (`func-control`, estados `RUN` / `ROBOT`):
1. **RUN**: cada rama avanza a 0.2 m/s mientras su sensor está libre; al detectar producto se detiene su cinta y spawner.
2. **Robot start**: `SensorCeldas` dispara Gantry1; el nivel alto permite ciclos sucesivos.
3. **ROBOT** (máquina de estados `rstep` 0→15): Gantry1 toma la celda, ejecuta una etapa de `IndexingBelt3` + `Maquina1` + Horno, espera `SensorPlacers` y el fin del indexing, y Gantry2 toma el placer para cerrar la misma unidad.
4. Cada movimiento de gantry usa un **handshake command/execute/done**: pulso de `Execute` garantizado (LOW 400 ms → HIGH → espera done) para que el gantry, que sondea a 30 ms, siempre vea el flanco.
5. Escrituras con **write-on-change + re-assert cada 5000 ms** (recuperación si Node-RED o el server reinician).

Detalle del flujo, constantes y generador: [references/control.md](references/control.md).

## Qué hay en el código (semántica de partes)

Resumen de la semántica de tags de cada parte (registro en `_on_simulation_started`, polling en `_tag_group_polled`):

- **Gantry**: `Command` 0=home, 1..N=waypoint por orden de keys del diccionario; flanco ascendente de `Execute` ejecuta; `Done`= `not _is_moving`; `Vacuum` se lee → `vacuum_on`.
- **Spawner (S1/S2)**: flanco de `EXEC` → ejecuta `CMD`; `autoEnable` inicia lote a `60/RATE`; escribe `RUNNING`, `DONE`, `READY`, `COUNT`.
- **IndexingBelt**: flanco de `Step` avanza `step_distance` (distancia medida localmente, inmune a latencia OPC UA); `Running` = en movimiento; `Speed`/`StepDistance` opcionales sobreescriben.
- **BeltConveyor**: lee `Speed` del PLC; escribe `Running` = (speed ≠ 0).
- **Maquina1**: lee `Cut`, `Release` (Bool) y `Z`, `Y`, `Speed` (Float) → corta/suelta tiras.
- **VastagoNeumatico**: lee `tag_name` (Bool) → extiende/retrae.
- **DiffuseSensor**: escribe `tag_name` con la detección.
- **SixAxisRobot**: `enable_comms=true` en la escena y usa `Robot1_*`. Su vacío toma los cuerpos internos `PlacerBatch_*` y `WovenBatch_*`, no el root del producto; al agarrarlos los separa con `top_level=true`.
- **BatchSensor / TOPE1**: son `DiffuseSensor`; sus raycasts consultan la máscara `8` y publican `6axisSensor1` según la configuración actual.
- **SandwichStation (devoradora)**: detecta los stacks (Placer/Celda/Tira) que llegan sobre la indexing belt, los **despawna** al completarse (celda + placer + ≥2 tiras) y emite producto tejido por stack. Cada batch runtime se separa en `WovenBatch` y `PlacerBatch`. El root es `CharacterBody3D` con `TransportCollision` (`collision_layer=0`, `collision_mask=1`) y avanza con `move_and_collide()`; **el nodo de escena `SandwichProduct` debe ser `CharacterBody3D`** (si es `Node3D`, el primer producto atraviesa los topes). El **`TopeFisico`** (StaticBody3D capa 1) retiene el batch al final de la cinta aunque esta siga empujando (choca el shell, no el WovenBatch congelado); batches independientes (sin cola). Cuando el robot desmonta todos los cuerpos de un lote (`top_level`), la estación los pasa a `ReleasedBatches` y retira el shell vacío. Para verificarla durante Play hay que usar el árbol **Remote**, no Local. Las tiras no tienen cadenas físicas ni joints. Sin comms (`enable_comms=false`). Ver [references/sandwich.md](references/sandwich.md).

Semántica detallada por archivo (con rutas y números de línea): [references/code.md](references/code.md).

## Referencias

| Archivo | Contenido |
|---|---|
| [references/scene.md](references/scene.md) | Escena `Simulation.tscn` al detalle: nodos, transformaciones, waypoints, tags por parte. |
| [references/control.md](references/control.md) | Flujo Node-RED desplegado: topología, `func-control` (estados, rstep, constantes), `control_config.json`, `apply_control_flow.js`. |
| [references/code.md](references/code.md) | Semántica del código de las partes y sus handlers de comms, con rutas de archivo. |
| [references/sandwich.md](references/sandwich.md) | Etapa Sandwich/SandwichStation "devoradora": despawn de stacks, batches de producto, collider de transporte, movimiento con colisión, preview, sensores y 6axisRobot. |

## Reglas de oro que aplicar siempre

1. **Los tags registrados por la escena deben existir en el tree OPC UA** (aborto `BadNodeIdUnknown` si no). Tras editar la escena: regenerar con `apply_control_flow.js` + `sync_deployed_flow.ps1` + reiniciar Node-RED (procedimiento en la skill `oip-nodered-comms`).
2. **Nunca escribir tags a 60 Hz** (carrera del DLL): escribir solo en cambios de estado; `OIPCommsTag._should_write()` ya descarta valores idénticos.
3. **La escena y el flujo evolucionan juntos**: si cambias partes o tags en la escena, este documento queda obsoleto — actualízalo.
4. **CONSULTAR ANTES DE VALIDAR** (preferencia del usuario): al llegar a la etapa de verificación, preguntar si se corre uno mismo el test headless o si el usuario prefiere validar manualmente (visual, F5). No lanzar validaciones por defecto. En tests que cargan `Simulation.tscn`, desactivar comms en toda la escena (el flujo Node-RED desplegado interfiere).
