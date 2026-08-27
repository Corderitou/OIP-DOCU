# Control de la línea — flujo Node-RED desplegado

El control del demo vive en Node-RED. Archivos relevantes en el repo:

| Archivo | Rol |
|---|---|
| `node-red/flows.json` | Flujo desplegado (template del proyecto; el desplegado real es `~/.node-red/flows.json`) |
| `node-red/control_config.json` | Config que alimenta al generador `apply_control_flow.js` |
| `.claude/skills/oip-nodered-comms/scripts/apply_control_flow.js` | Genera el flujo de control (tree + reads + `func-control` + escrituras) a partir de `control_config.json` |
| `.claude/skills/oip-nodered-comms/scripts/sync_deployed_flow.ps1` | Copia `node-red/flows.json` → `~/.node-red/flows.json` |

Para **cambiar** el flujo, seguir la skill `oip-nodered-comms`. Este archivo documenta el **estado desplegado** (lo que hace hoy la línea).

## Topología del flujo

1. **Server OPC UA** (endpoint del simulador) con un `tree` de **57 variables** `ns=2;s=...` (todas `readwrite`).
2. **Nodo read** (dispara cada 50 ms): lee las 57 variables → `msg.payload = [{name, path, value, status}]`.
3. **Nodo `func-control`**: función JS con la lógica de estados (generada por `apply_control_flow.js`) → `msg.payload = [{name, path, value}]` de escrituras.
4. **Nodo write**: escribe en el server OPC UA. Si no hay escrituras, `func-control` devuelve `null` y no se escribe nada.

## Variables del tree (las 57)

Cintas: `BeltConveyor_Speed/_Running`, `BeltConveyor2_Speed/_Running`, `BeltConveyor3_Speed/_Running`.
Otros: `Vastago_Extend`, `S1_CMD/EXEC/DONE/RUNNING/READY/COUNT/AUTO_ENABLE/RATE`, `Maquina1_Cut/Release/Z/Y/Speed`, `Sensor1`, `SensorCeldas`, `SensorPlacers`, `6axisSensor1`, `IndexingBelt3_Step/_Running`, `S2_CMD/EXEC/DONE/RUNNING/READY/COUNT/AUTO_ENABLE/RATE`, `Gantry1_Command/Execute/Done/Vacuum`, `Gantry2_Command/Execute/Done/Vacuum`, `Robot1_Command/Execute/Done/Vacuum` y tags H1.

Descripción en el tree indica el origen, p.ej. `"BeltConveyor.speed_tag_name (simulador OIP)"` o `"... (OIP, generado por apply_control_flow.js)"` para los generados.

## Lógica de `func-control`

Función JS con estado persistente en `context` (`state`, `rstep`, `execHigh[]`, `execLowSince[]`, `execHighSince[]`, caches de write-on-change). Input: mapa `v[name]=value`. Constants:

```
SPEED = 0.2          # velocidad de cintas en RUN (m/s)
REASSERT_MS = 5000   # re-assert de writes si no cambian (recuperación de server reiniciado)
EXEC_PULSE_MS = 400  # ancho de pulso LOW del Execute (handshake gantry)
VAC_DWELL_MS = 300   # espera tras cambiar vacuum
STEP_PULSE_MS = 200  # ancho del pulso de IndexingBelt3_Step
ROB_COUNT = 3
```

### Estados

**RUN**
- `SensorCeldas=false` → `BeltConveyor` y `BeltConveyor2` a 0.2 m/s + `S1_AUTO_ENABLE=true`.
- `SensorCeldas=true` → detiene esa rama y deshabilita S1 para dejar la celda en el punto de toma.
- `SensorPlacers=false` → `BeltConveyor3` a 0.2 m/s + `S2_AUTO_ENABLE=true`.
- `SensorPlacers=true` → detiene esa rama y deshabilita S2 para dejar el placer en el punto de toma.
- `indexingBeltsPulse(false)` → mantiene `IndexingBelt3_Step=false`.
- La disponibilidad de `SensorCeldas` arranca Gantry1 y la de `SensorPlacers` arranca Gantry2; no depende de un flanco descendente para alimentar ciclos sucesivos.
- El inicio de un gantry no detiene la rama independiente; cada rama se gobierna por su propio sensor.
- Cuando ambos sensores están activos, `nextRobot` alterna la prioridad para que una rama no monopolice el ciclo.

**ROBOT** (máquina de estados `rstep` 0→15)
- Mantiene el control por ramas mediante `SensorCeldas`/`SensorPlacers`.
- Gantry1 ejecuta la celda y, al soltarla, dispara una etapa compuesta: `IndexingBelt3_Step`, `Maquina1` y Horno.
- El estado `WAIT_ROBOT` conserva esa misma unidad mientras espera `SensorPlacers=true` y `IndexingBelt3_Running=false`; después arranca Gantry2.
- Solo al terminar Gantry2 finaliza la unidad y el flujo vuelve a `RUN`, por lo que indexing/Maquina1/Horno se repiten una vez por ciclo completo.
- `indexingBeltsPulse(true)` SOLO mientras `now < stepPulseUntil` (pulso de 200 ms).
- Pasos:
  - 0: `robotMove(0, 1)` — Gantry1 → Point1. Al completar → 1.
  - 1: `Gantry1_Vacuum = true`, `vacDwellUntil = now + 300` → 2.
  - 2: espera a `now >= vacDwellUntil` → 3.
  - 3: `robotMove(0, 0)` — Gantry1 → home → 4.
  - 4: `robotMove(0, 2)` — Gantry1 → Point2 → 5.
  - 5: `robotMove(0, 3)` — Gantry1 → Point3 → 6.
  - 6: `Gantry1_Vacuum = false`, `vacDwellUntil = now + 300` → 7.
  - 7: espera; al cumplirse fija `stepPulseUntil = now + 200` → 8. Si hay horno, `hornoFire()` arranca un ciclo termico en paralelo.
  - 8: `robotMove(1, 1)` — Gantry2 → Point1 → 9.
  - 9: `Gantry2_Vacuum = true`, dwell → 10.
  - 10: espera → 11.
  - 11: `robotMove(1, 0)` — Gantry2 → home → 12.
  - 12: `robotMove(1, 2)` — Gantry2 → Point2 → 13.
  - 13: `robotMove(1, 3)` — Gantry2 → Point3 → 14.
  - 14: `Gantry2_Vacuum = false`, dwell → 15.
  - 15: espera → vuelve a `RUN`.

### Handshake de robot (`robotMove(ri, cmd)`)

1. Escribe `Command = cmd`.
2. Fuerza `Execute = false` durante `EXEC_PULSE_MS` (400 ms) — el gantry sondea a ~30 ms y SIEMPRE ve el LOW.
3. Pone `Execute = true` durante otros `EXEC_PULSE_MS`.
4. Cuando `Done == true` (el gantry escribe `Done = not _is_moving` al llegar), da el movimiento por completado y resetea el handshake.

Con esto el flanco ascendente de `Execute` está garantizado → el gantry nunca se cuelga.

### 6axisRobot

- Es un robot de disparo directo por `6axisSensor1`; no participa en la alternancia
  de turnos de los gantries.
- `oneShot=true`: un haz bloqueado produce un solo ciclo. El flujo se desarma al
  disparar y se rearma cuando vuelve a leer el sensor en LOW.
- Cada ciclo trabaja con un lote de 6. En el primer viaje ejecuta `Point1` para tomar
  los placers y `Point3` para entregarlos. En el segundo vuelve a `Point1` para tomar
  las celdas y las entrega en el siguiente waypoint de `gridCmds`.
- `gridCmds=[4,5,6,7,8,9,10,11]` corresponde a `Point12`..`Point19`. El índice de
  grilla solo avanza cuando `Robot1_Done` confirma la llegada.
- La secuencia usa `Robot1_Command`, `Robot1_Execute`, `Robot1_Done` y
  `Robot1_Vacuum`, con el mismo handshake LOW/HIGH de 400 ms que los gantries.
- Si se dispara mientras un gantry está en `WAIT_ROBOT`, el flujo guarda ese estado
  en `waitingRobot6ax` y lo retoma después de completar el ciclo del 6axis.

### Horno (fire-and-forget por paso del indexing belt)

- **Disparo**: `hornoFire()` se llama en el paso 7→8 (cada vez que el indexing belt pulsa `stepPulseUntil`). Si el horno ya está armado (ciclo anterior sin terminar), no re-dispara.
- **Ciclo**: `hornoRun()` se ejecuta **cada tick en todos los estados** (RUN y ROBOT). Escribe `H1_CMD=1` + pulso garantizado de `H1_EXEC` (LOW→HIGH, igual que `robotMove`), y mientras el horno está armado escribe `H1_MV=100` (heater al 100%) y `H1_SETPOINT=150`.
- **Fin**: al leer `H1_DONE=true` (el horno terminó su ciclo de 3 s), resetea el armado y escribe `H1_MV=0`.
- **Comportamiento**: paralelo — la línea no se detiene; el cabezal baja, calienta y sube mientras Gantry2 trabaja. Un ciclo por paso del indexing belt.
- **Estado de la demo**: el nodo `Horno` tiene `enable_comms=true` y usa las tags
  `H1_*`. `hornoFire()` dispara un ciclo térmico por cada paso del indexing belt;
  `hornoRun()` mantiene la potencia y el setpoint mientras el ciclo está armado.

### Write-on-change

`belts()`, `spawners()` e `indexingBeltsPulse()` solo escriben si el valor cambió o si pasaron `REASSERT_MS` desde la última escritura (`c.set('belt:'+name, ...)`, `c.set('beltTs:'+name, now)`, etc.). `robotMove` y vacuum escriben en cada tick mientras están activos (el vacuum se mantiene en true durante el transporte; es un write de estado, no de alta frecuencia).

## `control_config.json` (estado actual)

```json
{
  "inputs": [ SensorCeldas, SensorPlacers, Sensor1, 6axisSensor1 ],
  "robotSensor": null,                       // cada robot declara su sensor
  "belts": { "groups": [ celdas: [BeltConveyor, BeltConveyor2], placers: [BeltConveyor3] ] },
  "feeds": [ { celdas: SensorCeldas -> S1 }, { placers: SensorPlacers -> S2 } ],
  "spawners": [ { "name": "S1", rate 30 }, { "name": "S2", rate 30 } ],
  "robots": [
    Gantry1 { robotSensor: SensorCeldas, cycleNext: Gantry2, sequence: [ {cmd:1,vacuum:true}, {cmd:0}, {cmd:2}, {cmd:3,vacuum:false,indexingPulse:true} ] },
    Gantry2 { robotSensor: SensorPlacers, waitForIndexing: true, sequence: [ {cmd:1,vacuum:true}, {cmd:0}, {cmd:2}, {cmd:3,vacuum:false} ] },
    6axisRobot { robotSensor: 6axisSensor1, oneShot: true, gridCmds: [4,5,6,7,8,9,10,11], sequence: [ {cmd:1,vacuum:true}, {cmd:2}, {cmd:3,vacuum:false,gate:false}, {cmd:1,vacuum:true}, {gridNext:true,vacuum:false,gate:false} ] }
  ],
  "indexingBelts": [ IndexingBelt3_Step/Running ],
  "maquina1": { zMoves: [...], cut, release, cutMs, releaseMs, moveMs, pulseMs },
  "machines": [ { name: "H1" } ],
  "horno": { command: H1_CMD, execute: H1_EXEC, done: H1_DONE, running: H1_RUNNING,
             mv: H1_MV, setpoint: H1_SETPOINT, mvValue: 100, setpointValue: 150 }
}
```

El `indexingPulse: true` en el paso de soltar de Gantry1 genera el pulso de `IndexingBelt3_Step` (el flujo lo materializa en el paso 7→8 fijando `stepPulseUntil`). Gantry2 no lleva `indexingPulse`.

Nota: con `pauseSensor = null`, el ciclo no se pausa por otro sensor; cada gantry arranca por disponibilidad de su sensor.

## `apply_control_flow.js`

Generador que a partir de `control_config.json` produce el JSON del flujo (`flows.json`): construye el `tree` (variables por sección, con descripciones), el nodo read y el `func-control` con grupos de cintas, feeds sensor→spawner, `feedControl()`, `robotMove()`, `maquinaRun()`, `indexingBeltsPulse()`, `hornoFire()`/`hornoRun()` y la máquina de estados derivada de las secuencias de robots.

- Multi-robot: genera un array `ROB` con los robots del config y una máquina `rstep` por robot (secuencia plana 0..N-1).
- **Detalle latente**: en `robotMove`, la rama `ri === 2` referencia `robotDone2`, que solo existe si hay 3+ robots. Con `ROB_COUNT=2` esa rama es código muerto e inofensiva.
- Tras regenerar: correr `sync_deployed_flow.ps1` y reiniciar Node-RED (ver skill `oip-nodered-comms`).

## Regenerar / validar

- Cambiar el control → editar `node-red/control_config.json` → `node apply_control_flow.js` → `node-red/flows.json` → `sync_deployed_flow.ps1` → reiniciar Node-RED → probar en el simulador.
- Si se añade una parte con tags nuevos en la escena, añadir sus tags al config/`apply_control_flow.js` para que estén en el tree (regla de oro: todo tag registrado debe existir).
