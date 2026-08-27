---
name: oip-nodered-comms
description: "Procedimiento para modificar el flujo de Node-RED que conecta el simulador OIP (Godot) con OPC UA y para entender/cambiar los comms del simulador. Úsala cuando haya que: cambiar el flujo de Node-RED (leer/escribir variables del simulador), hacer que el flujo lea todas las variables, añadir una variable/tag nueva al server tree OPC UA (ns=2;s=...), programar la lógica de control de una línea (sensores → cintas/spawner/robot) en el flujo con apply_control_flow.js, sincronizar node-red/flows.json (template del proyecto) con ~/.node-red/flows.json (desplegado), configurar tag_name/tag_group_name/enable_comms de una parte en Simulation.tscn, entender cómo OIPCommsTag registra y lee/escribe tags, o recordar qué tags existen y en qué dirección va cada uno."
---

# OIP v4.7 — Flujo Node-RED y comms del simulador

Puente entre el simulador Godot y Node-RED: cómo está armado, cómo se modifica
y cómo desplegarlo. Todo lo de abajo está verificado contra el repo actual.

## Topología

```
 Godot simulador                          Node-RED (localhost:1880)
 ───────────────                          ─────────────────────────
 partes registran tags      opc.tcp://localhost:4840
 (OIPCommsTag, grupo        ──────────────►  nodo "opc-ua-server"  (puerto 4840)
  PLCSIM, protocol 2)                         │  define el address space:
     │                                         │  variable tree (JSON) → variables
     └────────────── CLIENTE OPC UA ──────────┘  nodeId = "ns=2;s=Nombre"
                                                                  │
                                nodos "opcua-server-io" del flujo │
                                (mode read / write) leen/escriben │
                                esas variables                    │
```

- El `tag_name` de cada parte del simulador **ES el NodeId completo** `ns=2;s=Nombre` y
  debe coincidir **EXACTO** con el `nodeId` de la variable del server tree de Node-RED.
- El namespace del server tree es `namespaceId: 2` → los NodeIds usan `ns=2;s=...`.
- Node-RED actúa como "PLC" compartido: el simulador y cualquier cliente OPC UA externo
  leen/escriben las mismas variables.

## Archivos clave

| Archivo | Rol |
|---|---|
| `node-red/flows.json` (proyecto) | **Template de referencia** (source of truth). Nodos: `oip-sim-tab`, `oip-sim-server`, `oip-sim-inject`, `oip-sim-func`, `oip-sim-io`, `oip-sim-debug`, `oip-sim-inject-loop`, `oip-sim-func-control`, `oip-sim-write-io` |
| `~/.node-red/flows.json` | Flujo **desplegado** en tu Node-RED (se carga al arrancar). Contiene además nodos propios (plca1, OPCLOCAL, opc1) que **NO borrar** |
| `oip_data/tag_groups.cfg` | Tag group del simulador: `PLCSIM`, `protocol="2"` (opc_ua), `gateway="opc.tcp://localhost:4840"`, `polling_rate="30"` |
| `oip_data/comms_settings.cfg` | `enable_comms=true`, `enable_logging=false` |
| `Simulation.tscn` | Config de tags por parte: `enable_comms`, `tag_group_name`, `tag_name` = `ns=2;s=...` |
| `src/comms/oip_comms_tag.gd` | Wrapper `OIPCommsTag` (`register`/`read_*`/`write_*`) |
| `node-red/node_modules/@vitormnm/node-red-simple-opcua/server/lib/opcua-server-runtime-child.js` | Runtime del nodo io: `readFromPayload`/`writeEventFromPayload`. Los tipos de nodo `opc-ua-server`/`opcua-server-io` vienen del paquete `@vitormnm/node-red-simple-opcua` |
| `scripts/apply_control_flow.js` | Genera la lógica de control de la línea (tree + func + máquina de estados). Idempotente. Ver `references/control-flow.md` |

## Mecánica del flujo de lectura

Cadena: `oip-sim-inject` (cada 3 s + `once`) → `oip-sim-func` → `oip-sim-io` (mode `read`,
`identifierType: nodeId`) → `oip-sim-debug`.

1. `oip-sim-func` arma `msg.payload = [ {name, path}, ... ]` con `path` = `ns=2;s=...`.
2. El runtime child ve que `payload` es un array → `payload.map(readPayloadItem)` lee
   **cada** tag por `item.path` → emite `msg.payload = [{name, path, value, status}, ...]`.
3. Si alguno falla: status `yellow` + emite `partialError`, pero los tags OK igual se
   envían por el wire (no se aborta la lectura).
4. **Escribir** = misma estructura con `value` en un io `mode: write`:
   `msg.payload = [{name, path, value}, ...]`.

## Latencia de control (dónde vive y cómo ajustarla)

El retardo sensor→cintas **no es un bug**: es la suma de tres cadencias de muestreo:

- **Bucle de control Node-RED** = `oip-sim-inject-loop.repeat` (default `0.05` s = 50 ms).
  El read es in-process (server y lector en el mismo proceso Node-RED) y el control usa
  write-on-change → se puede bajar a 30-50 ms sin coste.
- **Poll del simulador** = `polling_rate` en `oip_data/tag_groups.cfg` (default `30` ms).
  Los reads son seguros a cualquier ritmo; los writes siguen siendo on-change (no dispara
  la carrera del DLL).
- Total con los defaults: **~110 ms peor caso** (~50 ms típico). Si notas retardo, revisar
  primero que `oip-sim-inject-loop` esté a `0.05` y el `.cfg` a `30` tras un sync/restart.

Detalle, tabla de cadencias y "gotchas" al regenerar: `references/control-flow.md` →
"Latencia de control".

## Botones de velocidad de conveyors (escritura)

Los 3 conveyors (`BeltConveyor{,_2,_3}_Speed`) se controlan desde Node-RED con
botones `inject` (`oip-sim-inject-speed-c1|2|3-05|10|20`, presets 0.5/1.0/2.0 m/s)
que escriben a `oip-sim-write-io` (`opcua-server-io` `mode: write`). Ver
`references/node-red-flow.md` para el detalle y cómo añadir presets nuevos.
`sync_deployed_flow.ps1` sincroniza estos nodos automáticamente.

## Añadir una variable nueva (end-to-end, 3 sitios)

1. **Simulador** — en `Simulation.tscn`, en la parte correspondiente:
   `enable_comms = true`, `tag_group_name = "PLCSIM"`, y la prop de tag
   (`tag_name`/`speed_tag_name`/`cmd_tag`/...) = `ns=2;s=Nombre`.
2. **Server tree (Node-RED)** — en el nodo `opc-ua-server`, dentro de su propiedad `tree`
   (string JSON), añadir la variable: `nodeId: "ns=2;s=Nombre"` (idéntico al simulador),
   `namespaceId: 2`, `type` acorde, `access: "readwrite"`.
3. **Func node** — añadir `{ "name": "Nombre", "path": "ns=2;s=Nombre" }` al array de
   `oip-sim-func`.

Tipos OPC UA ↔ simulador: `Float`=REAL (float32), `Boolean`=BOOL, `Int16`=INT (int16),
`Int32`=DINT (int32), `UInt8`=BYTE.

> Los pasos 2 y 3 los hace solo `apply_control_flow.js` (ver la sección siguiente).

## Programar la lógica de control de una línea (workflow)

Cuando el usuario pide el ciclo completo (sensores → cintas/spawner/robot), NO se
escribe GDScript: todo el control vive en el flujo Node-RED. Detalle completo en
`references/control-flow.md`.

1. **Leer el inventario de tags** en `Simulation.tscn`: entradas = `DiffuseSensor`
   (`tag_name`, BOOL); salidas = `BeltConveyor*` (`speed_tag_name`, Float),
   `CeldaSpawner`/`PlacerSpawner` (`auto_enable_tag`/`rate_tag`); manipulador
   opcional = `SixAxisRobot` o `Gantry` (`command_tag`/`execute_tag`/`done_tag`/`vacuum_tag`).
2. Si una parte a controlar no tiene `enable_comms = true` + `tag_group_name = "PLCSIM"`
   (ej. `CeldaSpawner`), añadirlo en `Simulation.tscn`.
3. **Editar el template** (idempotente). Config default = línea demo con pausa por
   `Sensor1` (`holdMs` = 2000 ms, sin robot — el flujo no toca el robot):
   ```bash
   node .claude/skills/oip-nodered-comms/scripts/apply_control_flow.js
   # otra línea: --config node-red/control_config.json
   ```
   (Para controlar el robot, pasar un config con `robot` + `robotSensor` — ver
   `references/control-flow.md`.)
   Cada spawner del config genera en el tree sus **tags de estación** `<P>_CMD/_EXEC/_DONE/
   _RUNNING/_READY/_COUNT` además de `autoEnable`/`rateTag`. Son imprescindibles: si faltan
   el simulador aborta con `BadNodeIdUnknown` al registrar el grupo.
4. **Sincronizar al desplegado**:
   ```powershell
   powershell -File .claude/skills/oip-nodered-comms/scripts/sync_deployed_flow.ps1
   ```
5. Avisar al usuario: **reiniciar Node-RED** (NO Deploy desde el editor mientras corre:
   pisa `flows.json`).

Solo editar y leer — **NO verificar**:
- No validar el output de los scripts, no leer `~/.node-red/flows.json` después del
  sync, no comprobar sintaxis/JS generado, no comprobar que Node-RED responde, y no
  re-ejecutar los scripts.
- El sync ya escribe lo que corresponde. El usuario reinicia Node-RED y prueba.
- **No correr la verificación headless de Godot** (`OIP_v4.7-rc1.exe --headless --import`)
  por este workflow: no es necesaria, tarda y deja procesos zombie. El editor recarga
  y parsea los cambios por sí solo al abrirlo.


## Sincronizar template → desplegado

Usa `scripts/sync_deployed_flow.ps1` (Windows). Hace backup, copia el `tree` del template,
**regenera `oip-sim-func` a partir del tree** (nunca queda desfasado) y opcionalmente borra
nodos de prueba conocidos:

```powershell
powershell -File .claude/skills/oip-nodered-comms/scripts/sync_deployed_flow.ps1
# o con rutas custom:
powershell -File ...sync_deployed_flow.ps1 -Template .\node-red\flows.json -Deployed "$env:USERPROFILE\.node-red\flows.json" -RemoveTestNodes
```

## Desplegar en Node-RED

- Node-RED lee `flows.json` **al arrancar**. Tras editar el archivo hay que reiniciar el
  servicio Node-RED (o desde el editor: reiniciar/recargar).
- Si Node-RED está corriendo y haces **Deploy** en el editor, Node-RED **sobrescribe** el
  archivo → no edites el desplegado a mano; edita el template y luego ejecuta el sync.
- Verificación: el debug node "Tags simulador" imprime el array con `value` + `status`
  de todas las variables.

## Troubleshooting

- **`OIPComms: Stopping simulation: OPC UA tag 'ns=2;s=...' in group 'PLCSIM' is invalid
  (BadNodeIdUnknown)`** → el tag existe en la escena (se registra en OIPComms) pero NO en el
  `tree` del server. Suele acompañarse de 3 errores de hilo del stub
  (`The caller thread can't call the function Node::emit_signalp()...`). Fix: re-ejecutar
  `apply_control_flow.js` (los spawners generan sus tags de estación `_CMD/_EXEC/...`) +
  `sync_deployed_flow.ps1` + reiniciar Node-RED. Regla de oro: **todo tag registrado por la
  escena debe existir en el tree**.

## Referencias

- `references/node-red-flow.md` — anatomía completa del flujo (nodos, props, tree),
  lista de las 57 variables actuales, runtime child read/write.
- `references/sim-comms.md` — cómo registran tags las partes (OIPCommsTag), tipos,
  y la tabla parte → propiedades de tag → tipo → dirección read/write.
- `references/control-flow.md` — workflow para programar el control de la línea en
  el flujo (config schema, máquina de estados RUN/HOLD/ROBOT, handshake del robot).
