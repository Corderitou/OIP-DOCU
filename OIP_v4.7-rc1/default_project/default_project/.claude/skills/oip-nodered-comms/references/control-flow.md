# Control de línea en Node-RED — workflow

Programa la lógica de una línea OIP completa en Node-RED (sensores → cintas,
spawner y robot) **sin tocar GDScript**. Todo el control vive en el flujo.

## Flujo de trabajo (pocos pasos)

1. **Inventario de tags** — en `Simulation.tscn` (o la escena de la línea):
   - **Entradas**: `DiffuseSensor` → `tag_name` (BOOL, sim→PLC).
   - **Salidas**: `BeltConveyor*` → `speed_tag_name` (Float, PLC→sim);
     `SixAxisRobot` → `command_tag`/`execute_tag`/`done_tag`/`vacuum_tag`;
     `CeldaSpawner` → `cmd_tag`/`exec_tag`/`auto_enable_tag`/`rate_tag`.
   - El `tag_name` de la escena **ES** el `nodeId` (`ns=2;s=...`) y debe coincidir
     con el del server tree.
2. **Escena** — si la parte que hay que controlar no tiene
   `enable_comms = true` + `tag_group_name = "PLCSIM"`, añadirlo (ej.
   `CeldaSpawner`). Sin esto los tags no se registran y el flujo no la ve.
3. **Aplicar el control** al template:
   ```bash
   node .claude/skills/oip-nodered-comms/scripts/apply_control_flow.js
   # si la línea difiere de la demo:
   node .claude/skills/oip-nodered-comms/scripts/apply_control_flow.js --config node-red/control_config.json
   ```
   El script es **idempotente** (correrlo de nuevo no duplica) y hace todo:
   - añade al `tree` del server las variables que falten (entradas + salidas),
   - regenera `oip-sim-func` a partir del tree,
   - crea/actualiza `oip-sim-inject-loop` (inject 0.05 s + once) y
     `oip-sim-func-control` (máquina de estados),
   - cablea `oip-sim-io` (read) → `oip-sim-func-control` → `oip-sim-write-io`.
4. **Sincronizar al desplegado**:
   ```powershell
   powershell -File .claude/skills/oip-nodered-comms/scripts/sync_deployed_flow.ps1
   ```
   (el sync ya gestiona `oip-sim-inject-loop`, `oip-sim-func-control`,
   `oip-sim-io` y `oip-sim-write-io`).
5. **Reiniciar Node-RED** para que cargue el flujo. NO hacer Deploy desde el
   editor mientras esté corriendo (sobrescribe el archivo y pierde los cambios).

## Config (`--config`)

El script trae por defecto la **línea demo**: Sensor1 (pausa, `holdMs` 2000),
3 cintas y spawner S1 — **`robot: null`, el flujo NO toca el robot/gantry**. Para
controlar un manipulador (robot 6-ejes o gantry: home → waypoints con vacuum,
disparado por `robotSensor`) pasa un config con `robot` + `robotSensor` — ver
`node-red/control_config.json` como ejemplo completo (gantry con secuencia de 11
pasos). Para otra línea pasa un JSON:

```json
{
  "inputs": [
    { "name": "Sensor1", "nodeId": "ns=2;s=Sensor1", "type": "Boolean" }
  ],
  "pauseSensor": "Sensor1",
  "robotSensor": "Sensor2",
  "holdMs": 3000,
  "belts": {
    "speed": 0.5,
    "items": [
      { "name": "BeltConveyor_Speed", "path": "ns=2;s=BeltConveyor_Speed", "type": "Float" }
    ]
  },
  "spawners": [
    {
      "name": "S1",
      "rate": 60,
      "autoEnable": { "name": "S1_AUTO_ENABLE", "path": "ns=2;s=S1_AUTO_ENABLE" },
      "rateTag": { "name": "S1_RATE", "path": "ns=2;s=S1_RATE" }
    }
  ],
  "robot": {
    "command": { "name": "Gantry1_Command", "path": "ns=2;s=Gantry1_Command" },
    "execute": { "name": "Gantry1_Execute", "path": "ns=2;s=Gantry1_Execute" },
    "done": { "name": "Gantry1_Done", "path": "ns=2;s=Gantry1_Done" },
    "vacuum": { "name": "Gantry1_Vacuum", "path": "ns=2;s=Gantry1_Vacuum" },
    "sequence": [
      { "cmd": 1, "vacuum": true },
      { "cmd": 0 },
      { "cmd": 2 },
      { "cmd": 3, "vacuum": false },
      { "cmd": 2 },
      { "cmd": 4 },
      { "cmd": 5, "vacuum": true },
      { "cmd": 4 },
      { "cmd": 2 },
      { "cmd": 3, "vacuum": false, "indexingPulse": true },
      { "cmd": 0 }
    ]
  }
}
```

- `sequence`: pasos `{cmd, vacuum?, indexingPulse?, gate?}`. `cmd 0` = HOME, `cmd N` =
  waypoint N (en orden de `waypoints` del manipulador). Cada paso: mover a `cmd`
  (handshake `done`), y si tiene `vacuum` se escribe tras llegar con un dwell de
  `VAC_DWELL_MS` (300 ms) para que agarre/suelte antes de continuar. `indexingPulse`
  dispara el pulso de `STEP_PULSE_MS` en el indexing belt al soltar (última vez).
  Las sueltas (`vacuum:false`) del ÚLTIMO robot esperan a que Maquina1 termine
  (`mqDone`); un paso puede salir de esa compuerta con `gate: false`.
  Tras el último paso → `RUN`.
- `wps` (legacy): `[1,2,3]` equivale a secuencia simple home → wp[0] → … →
  vacuum OFF → vuelta a `wps[0]`.
- `spawners`: array (uno por spawner; el script también acepta `spawner` singular
  legacy). `spawners: []` omite los spawners del control. Además de `autoEnable` y
  `rateTag`, cada spawner genera en el tree sus **tags de estación** (protocolo
  Maquina): `<NAME>_CMD/_EXEC/_DONE/_RUNNING/_READY/_COUNT`. Son obligatorios: el
  spawner los registra en OIPComms y si no existen en el server tree el simulador
  aborta con `BadNodeIdUnknown` (grupo `PLCSIM`).
- `type` por defecto: Boolean para entradas, Float para cintas, Int16 para
  `command`. `nodeId`/`path`/`name` deben coincidir con los `tag_name` de la escena.

## Lógica de la función de control

Estado persistente en `context` del nodo:

| Estado | Qué hace |
|---|---|
| `RUN` | cintas a `belts.speed`, spawners en auto (su `rate` celdas/min) |
| `HOLD` | cintas a 0 + spawners off durante `holdMs` (flanco de `pauseSensor`) |
| `ROBOT` | cintas a 0 + spawners off; secuencia del robot/gantry (flanco de `robotSensor`) |

Robot/gantry: `command` + pulso de `execute` (flanco), espera `done` false→true
(handshake robusto: arrancó y llegó). Escribe solo en cambios/estado, nunca en
cada frame → compatible con la carrera del DLL. Al entrar en `ROBOT` se escribe
vacuum OFF para garantizar estado limpio.

Ajustes típicos desde el config: `speed` (m/s en marcha), `holdMs` (pausa
sensor 1), `rate` (celdas/min por spawner), `sequence` (pasos del manipulador,
con `vacuum` por paso y `indexingPulse` al soltar en el stringer).

## Latencia de control

El retardo sensor→cintas es la suma de **tres cadencias de muestreo** (no hay camino
event-driven en este montaje):

| Etapa | Cadencia | Dónde |
|---|---|---|
| Sensor → server OPC UA (write del sim) | `polling_rate` del grupo | `oip_data/tag_groups.cfg` |
| Node-RED ve el sensor (read in-process) | `oip-sim-inject-loop.repeat` | `node-red/flows.json` |
| Sim lee velocidad de cintas | `polling_rate` del grupo | `oip_data/tag_groups.cfg` |

Con los valores actuales (**poll 30 ms + bucle 50 ms**) el peor caso es ~110 ms
(~50 ms típico). Reglas para ajustar:

- El bucle de control (`oip-sim-inject-loop`, `repeat`) se puede bajar a 30-50 ms sin
  problema: el read es in-process (server y lector viven en el mismo proceso Node-RED) y
  `oip-sim-func-control` usa **write-on-change**, así que no satura el server. El default
  generado por `apply_control_flow.js` es `0.05` s.
- El `polling_rate` del grupo se puede bajar a ~30 ms: los reads son seguros a cualquier
  ritmo (la carrera del DLL es solo de writes) y los writes siguen siendo on-change.
- **Ojo al re-generar**: si se re-ejecuta `apply_control_flow.js`, la cadencia del bucle se
  regenera con el default del script (`0.05`); el `polling_rate` del `.cfg` no lo toca el
  script — hay que editarlo a mano en `oip_data/tag_groups.cfg` (y reiniciar la simulación
  para que lo recargue).
- Tras tocar el bucle: sync (`sync_deployed_flow.ps1`) + reiniciar Node-RED.

## Verificación (mínima)

- El debug "Tags simulador" muestra `Sensor1` con `value` true al detectar.
- El server tree contiene **todos** los tags que la escena registra (los spawners añaden
  sus `_CMD/_EXEC/...` al re-ejecutar el script; si falta alguno la simulación aborta con
  `BadNodeIdUnknown`).
- Observar en el simulador: las cintas y el spawner se detienen `holdMs` ms al
  dispararse el sensor de pausa. Con config de robot: al dispararse
  `robotSensor`, el robot hace home→wp1→wp2→wp3 con vacuum y vuelve.
