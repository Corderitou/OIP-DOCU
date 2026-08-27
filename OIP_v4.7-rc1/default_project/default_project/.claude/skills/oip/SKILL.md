---
name: oip
description: Open Industry Project (OIP v4.7) — contexto esencial del proyecto para asistencia de desarrollo. Usa el índice para cargar solo la sección que necesitas en lugar de leer toda la documentación.
---

# OIP — Open Industry Project

**Framework libre y open-source de simulación industrial/warehouse construido sobre Godot 4.7 (fork custom con Jolt Physics), open62541 y libplctag.**

Repo: https://github.com/Open-Industry-Project/Open-Industry-Project | Licencia: MIT

---

## ÍNDICE DE SECCIONES

| Sección | Cuándo usarla |
|---|---|
| [overview] | Qué es OIP, pila tecnológica, estructura de directorios, autoloads y singletons |
| [partes] | Crear nuevas partes: script + escena + registro |
| [catalogo] | Las partes disponibles y sus tags de comunicación (resumen) |
| [fisica] | Collision layers, detección, cadenas físicas (Tira) |
| [comms] | Protocolos industriales, capas OIPComms/CommsHub/OIPCommsTag |
| [escenas] | Formatos de escena (nativo .tscn + scene.json interop), registro |
| [editor] | Plugins del editor Godot, gizmos y herramientas |
| [comandos] | Atajos de teclado, flujos de trabajo y comandos clave |
| [patrones] | Patrones clave: Simulation singleton, dual-mode, signal hub, null-safe |
| [deprecated] | Qué está deprecado y dónde vive el código antiguo |

---

## [overview]

**Stack:**
- Godot 4.7 **fork custom** (editor compilado a medida con singletons extra) — Forward Plus
- **Jolt Physics**: 120 ticks/s, 15 velocity steps, 20 position steps, `run_on_separate_thread = true`, penetration slop 0.002
- GDExtension `OIPComms` — C++ con open62541 (OPC UA) + libplctag (EIP/Modbus) + S7/ADS/RTDE/MQTT custom
- GDScript para toda la lógica de partes

**Singletons del fork (NO son autoloads):**
- `Simulation` (`Engine.get_singleton("Simulation")`) — control de simulación. Expone señales `started`, `stopped`, `pause_toggled` y método `stop()`. Todas las partes se conectan a `Simulation.started/stopped` en `_enter_tree()`.
- `OIPComms` (`Engine.get_singleton("OIPComms")`) — backend nativo de comunicación C++.

**Autoloads (definidos en `project.godot`):**
- `CommsHub` (`src/comms/oip_comms_stub.gd`) — facade GDScript null-safe hacia OIPComms
- `OIPCommsService` (`src/comms/oip_comms_service.gd`) — carga tag groups/settings de `oip_data/*.cfg` en runtime y enlaza señales de Simulation
- `SoftPlcBridge` (`src/comms/soft_plc_bridge.gd`) — PLC blando (protocolo `soft_plc`)
- `ConveyorSnapping` + `StructureSnapping` (`addons/oip_ui/Autoload/`) — snapping de conveyors y estructuras en el editor

**Estructura de directorios clave:**
```
src/             # Scripts GDScript de partes (@tool, class_name) — una carpeta por parte
parts/           # Escenas .tscn de partes (resource containers)
Simulation.tscn  # Escena ejemplo de simulación (root "Simulation" + Building + partes)
addons/          # 13 plugins del editor Godot habilitados (ver [editor])
docs/            # Documentación (Diátaxis: tutorial/howto/reference/explanation)
deprecated/      # runtime_editor + runtime-editor-bridge (NO MANTENER)
oip_data/        # tag_groups.cfg, comms_settings.cfg (runtime)
assets/          # Modelos 3D, texturas
```

**Config de proyecto clave (`project.godot`):**
- `import/fbx/enabled=false` y `import/blender/enabled=false` → importar modelos vía **glTF** (.glb)
- GDScript con warnings estrictos (`unsafe_*`, `missing_tool=2`)

---

## [partes]

Cada parte necesita 2 archivos: script + escena.

**Script mínimo** (`src/MiParta/mi_parta.gd`):
```gdscript
@tool
class_name MiParta
extends Node3D

func _enter_tree() -> void:
    Simulation.started.connect(_on_started)
    Simulation.stopped.connect(_on_stopped)
```
- `@tool` obligatorio (corre en editor)
- `class_name` obligatorio (usado por detección y registros)

**Escena** (`parts/MiParta.tscn`):
```ini
[gd_scene load_steps=N format=4]
[ext_resource type="Script" path="res://src/MiParta/mi_parta.gd" id="1_xxx"]
[node name="MiParta" type="Node3D"]
script = ExtResource("1_xxx")
[node name="Hijo" type="Node3D" parent="."]
```
Reglas `.tscn`:
- `load_steps` = ext_resources + sub_resources (NO incluye nodos)
- `parent="."` o `parent="NombreNodo"` en CADA nodo hijo (obligatorio)
- `Color(r, g, b, a)` — siempre 4 argumentos (Godot 4.7)
- IDs: `id="1_xxx"`, referenciar con `SubResource("...")` / `ExtResource("1_xxx")`

**Registro para que aparezca en el Parts dock** (`addons/scene-library/scene_library.cfg`):
```json
{ "path": "res://parts/MiParta.tscn", "uid": "" }
```
> `deprecated/runtime/core/scene_registry.gd` es DEPRECATED — ignorar.

---

## [catalogo]

55 escenas en `parts/` + 9 assemblies (`parts/assemblies/`); 46 registradas en el Parts dock (el catálogo en `docs/` lista 34, desfasado). Categorías REALES de `scene_library.cfg`: **Equipment** (conveyors, robots, máquinas: 20), **Devices** (sensores, PushButton, StackLight: 5), **Products** (Box/Pallet/spawners/productos: 13), **Structure** (Building, Rack, vallas, escaleras: 8). No existe "Misc".

**Conveyors** (comms: `speed_tag_name` REAL + `running_tag_name` BOOL):
- BeltConveyor, RollerConveyor, BeltSpurConveyor, RollerSpurConveyor, CurvedBeltConveyor, CurvedRollerConveyor, BeltConveyorAssembly, RollerConveyorAssembly, TurntableConveyor, ChainTransfer (`speed`+`popup`), ConveyorLeg/ConveyorLegC, SideGuardsCBC
- Conveyors extienden `ResizableNode3D` → gismos de resize (rojo=X longitud, verde=Y altura, azul=Z ancho)

**Sensores / Devices:**
- DiffuseSensor — `tag_name` BOOL (write); raycast +Z, máscara 8, beam verde/rojo, `normally_closed`
- LaserSensor — `tag_name` REAL (write); distancia continua
- ColorSensor — `tag_name` DINT (write); mapea albedo→int via `color_map`
- PushButton — `pushbutton_tag_name` BOOL (write) + `lamp_tag_name` BOOL (read); momentary/toggle
- StackLight — `tag_name` BYTE (read); bitmask por segmento
- CameraStreamer — sin tags; **servidor HTTP MJPEG** embebido (puerto 8090, endpoints `/`, `/stream`, `/snapshot`); mira por +Z

**Robots** (comms: `command_tag` INT, `execute_tag` BOOL read, `done_tag` BOOL write, `vacuum_tag` BOOL):
- SixAxisRobot — 6 ejes, IK CCD (20 iter, tol 0.01m), waypoints, ventosa
- Gantry — 3 ejes cartesianos, frame procedural
- Stringer — 2 ejes (Z/Y), pick-and-place de tiras (ver [fisica] y `howto-stringer-dispenser.md`)
- AGV — AGV con waypoints y gizmo de path

**Spawners / Products:**
- BoxSpawner — `boxes_per_minute` (0-1000), `fixed_rate`, `random_size`, `conveyor` (pausa si para)
- PalletSpawner — `spawn_interval`
- Despawner — destruye solo objetos con `instanced == true`
- Dispenser — spawn de 2 Tiras paralelas (`tira_spacing`), `cut_trigger` one-shot
- CeldaSpawner — patrón Maquina (`cmd/exec/done/running/ready/count/auto_enable/rate` tags); los sufijos legacy `_CMD` solo valen para S7/EIP, en OPC UA el tag debe ser NodeId completo (ver skill `oip-nodered-comms` → sim-comms.md)
- Box — RigidBody3D resizable, `initial_linear_velocity`
- Pallet, Tira (cadena de cuerda, ver [fisica]), Celda, Placer, Maquina1, ContainerTrailer
- Productos solares: Vidrio, LaminaEVA, Backsheet, PanelProducto (+ JunctionBox)
- Máquinas de línea solar: Laminadora, Horno, VastagoNeumatico (`tag_name` BOOL read+write, extend)

**Accesorios / Entorno:**
- BladeStop — `tag_name` BOOL read/write (parada neumática animada)
- Diverter — `tag_name` BOOL read (nivel sostenido; `divert()`/`retract()` por código o tecla `C` = `use()`)
- SafetyGate, DockDoor (tecla `C`), Building (reglas de muros `building_wall_rule.gd`), Fence, GuardRail, FloorMarking, Platform, Rack, Stairs, AutoLeveler, EOATSuction, FlowDirectionArrow, GenericData
- `use()` (tecla `C` con la parte seleccionada, shortcut "Open Industry Project/Use") permite interactuar: DockDoor toggle, etc.

---

## [fisica]

### Collision Layers

| Layer | Nombre | Usado por |
|---|---|---|
| 1 | Static | Building, ContainerTrailer |
| 2 | Dynamic | Diverter, SafetyGate |
| 3 | Belt | Sensores, belt conveyors |
| 4 | Box | Items físicos (detección) |
| 5 | SimpleConveyorShape | Roller conveyors |
| 6 | — | Dispenser/Stringer bodies |
| 8 | — | Pallet, cargo (Despawner) |
| 10 | — | Box, Celda, Tira (RigidBody3D) |
| 15 | — | Mask para física de items |
| 18 | — | ChainTransfer |

### Detección (runtime)
Usar `body_entered` (no `area_entered`). Area3D con `collision_mask` apropiado + StaticBody3D con `collision_layer`:
```gdscript
func _ready() -> void:
    _detect_area = get_node_or_null("Head/GrabArea") as Area3D
    if _detect_area:
        _detect_area.body_entered.connect(_on_body_entered)
```

### Detección en editor (@tool)
En editor NO corre física → `body_entered` no dispara. Usar **polling de distancia** desde setters export:
```gdscript
@export_range(0.0, 2.0, 0.001) var z_position: float = 0.0:
    set(value):
        z_position = value
        _update_position()
        if Engine.is_editor_hint():
            _poll_detection()  # distancia < umbral → grab()
```
Guard `is_inside_tree()` en setters (se disparan antes de entrar al árbol).

### Cadenas físicas (Tira)
Cadena de `RigidBody3D` + `Generic6DOFJoint3D` (perfil de cinta metálica: flexiona solo en un plano) con dos `PinJoint3D` al mundo (`PinAnchor` en seg 0 → SpawnPoint del Dispenser, `PinHead` en último seg → cabezal del Stringer). Configuración de segmento:
```gdscript
seg.freeze = true; seg.gravity_scale = 0; seg.can_sleep = true
seg.continuous_cd = true
seg.angular_damp = 3.0; seg.linear_damp = 0.5   # Jolt ignora springs del 6DOF
seg.collision_layer = 10; seg.collision_mask = 15; seg.mass = 0.005
# shape = BoxShape3D 0.006 x 0.002 x (seg_len*0.95) → huecos, sin self-overlap
```

**Reglas críticas de joints (orden importa):**
1. Posicionar joint ANTES de asignar `node_a`/`node_b` (si se mueve después, el solver explota con NaN: `renderer_scene_cull !v.is_finite()`)
2. `_sync_joints()` en cada reposicionamiento: limpiar paths → reposicionar → reasignar
3. `reparent` ANTES de `unfreeze_chain()` (si al revés, los paths de joints quedan inválidos y la cadena cae entera)
4. No compartir arrays por referencia: usar `.duplicate()` al pasar `_spawned_tiras`
5. Siempre sync + zero velocities antes de `unfreeze_chain()`; hacer `sleeping = false` EXPLICITO tras re-parent
6. Guardas NaN: `_safe(v)` en toda escritura de posición; `_safe_basis()`/`_chain_basis()` para transforms. **6DOF frame orientation obligatoria**: todos los segmentos/joints con la misma `Basis.looking_at(dir, up)` (con fallback para cadenas casi verticales), o los límites angulares no significan nada.
7. Histéresis en `place_chain()`: reconstruir solo si `absi(needed - size) > 2`; si no, re-escalar `seg_len` (evita parpadeo)

**Estados de Tira:**
| Estado | held | _dynamic | Descripción |
|---|---|---|---|
| taut | true | false | Congelada, entre SpawnPoint y cabezal; `place_chain()` la reposiciona entera |
| hanging | true | true | Física viva, cuelga del PinHead; `place_chain()` solo mueve el head pin |
| free | false | false | Física viva sin anclas, cae |

Semántica cut/release: `cut_trigger` (Dispenser) libera `PinAnchor` + reparent + unfreeze → hanging si la sostiene el Stringer, sino free. `release_trigger` (Stringer) → `held=false`, libera `PinHead`, `_dynamic=false` → free. **Si no se cortó, la tira sigue anclada al SpawnPoint** (el ancla vive en la Tira, no en el Stringer). `Simulation.started` descongela todo excepto las **taut** (`held && !_dynamic`).

---

## [comms]

**Tres capas:**
1. `OIPComms` (C++ GDExtension, singleton del fork) — polling nativo en hilo, buffer thread-safe
2. `CommsHub` (`src/comms/oip_comms_stub.gd`, autoload) — facade GDScript null-safe
3. `OIPCommsTag` — wrapper por tag en cada parte

**Uso típico en una parte:**
```gdscript
var _tag: OIPCommsTag

func _on_simulation_started():
    _tag = OIPCommsTag.new()
    _tag.register(tag_group_name, tag_name, 1)

func _physics_process(delta):
    if _tag.is_ready():
        speed = _tag.read_float32()
```

**Thread-safety:** lectura = el hilo de polling escribe el buffer; el game thread solo lee el buffer (nunca toca el PLC). Escritura = encolada y ejecutada ASAP; si hay un poll en curso, la escritura espera a que termine.

> **CARRERA DEL DLL (¡IMPORTANTE!):** `libOIP-COMMS` corrompe su registro interno (grupo/tag vacío) si se escriben tags a 60Hz aunque el valor no cambie → `OIPComms: Failed to write tag: ` (vacío) + `POLL ''` + `comms_error` → `Simulation.stop()`. La fuente del GDExtension NO está en el repo (solo binarios) → el bug no se parchea. **Mitigación: write-on-change.** `OIPCommsTag.write_*` descarta writes con valor idéntico automáticamente (todas las partes protegidas; caché reseteada en `register()`/`on_group_initialized()`); `PlantComms.write_bit(tag, value, only_if_changed)` añade lo mismo a nivel multi-tag. **Regla: nunca escribir tags en `_physics_process`** — escribir solo en flancos/cambios de estado. Las lecturas a cualquier ritmo son seguras. Validar con `test_repro8.gd` (0 líneas de error = OK).

**Protocolos y código numérico** (usado en `oip_data/tag_groups.cfg`, campo `protocol`):

| # | Protocolo | Formato de Tag Name |
|---|---|---|
| 0 | `ab_eip` (EtherNet/IP, libplctag) | CIP: `MyTag`, `Program:Main.MyTag`, `myUDT.field`, `myArray[0]` |
| 1 | `modbus_tcp` (libplctag) | `hr0`, `co21`, `ir64000` (prefijo co/di/hr/ir + número) |
| 2 | `opc_ua` (open62541) | NodeId: `ns=2;s=MyVariable` o `ns=2;i=12345` |
| 3 | `s7` (Siemens PUT/GET) | `I0.0`, `Q0.1`, `M0.5`, `IBx`, `QBx`, `MBx`, `IWx`, `MDx`, `QLx` |
| 4 | `ads` (Beckhoff, TwinCAT 2&3) | `MAIN.fbMotor.bRunning` |
| 5 | `rtde` (UR cobots, puerto 30004) | `actual_q[0]`, `runtime_state` |
| 6 | `mqtt` (Paho, MQTT 3.1.1 plaintext) | topic exacto: `sensors/temp1` (sin wildcards) |
| 7 | `soft_plc` (SoftPlcBridge autoload) | PLC blando interno |

**Campos de config por protocolo:** EIP → Gateway+Path+CPU (ControlLogix, PLC5, SLC500, Micro800...); Modbus → Gateway+Unit ID; OPC UA → solo Endpoint (`opc.tcp://ip:4840`); S7 → solo IP.

**Persistencia:**
- `oip_data/tag_groups.cfg` — definición de grupos (carga vía `OIPCommsService.register_tag_groups()`)
- `oip_data/comms_settings.cfg` — enable/logging
- (`user://comms_config.json` solo lo usa el COMMS panel del runtime editor — DEPRECATED)

**Soft PLC (`soft_plc`, protocol 7):** grupo interno (nombre por defecto `ST`) que ejecuta un programa IEC ST dentro del simulador. El programa vive en la metadata `oip_st_program` del root de la escena (lo edita el dock `st_editor`, Check/Apply con hot-swap); el runtime es el bundle JS `res://oip-plc.js` (campo "gateway" del grupo); `SoftPlcBridge` lo registra y alimenta (`set_soft_plc_program`).

**Datos tipo por tag:** BOOL(bit), REAL(float32), INT(int16), DINT(int32), BYTE(uint8).

---

## [escenas]

- **Workflow activo**: editor nativo de Godot + Parts dock. `Ctrl+N`/botón **New Simulation** (plugin `oip_ui`) crea root `Simulation` (Node3D) + `Building` (nada más).
- **Interop web** (plugin `scene_interop`, activo): `Import/Export Web Scene (scene.json)` en el menú Tool — formato JSON legible por herramientas externas.
- **`.oip_scene.json` y SceneRegistry: DEPRECATED** (runtime editor), solo referencia histórica. El formato nativo `.tscn` es el activo.

---

## [editor]

**Plugins activos** (13 en `[editor_plugins]` de `project.godot`):
- `oip_ui` — botón "New Simulation", live snap de conveyors (toggle `N` / botón SnapGrid; `Alt` escapa el snap durante un drag), tecla `C` = `use()` sobre la selección
- `scene-library` — Parts dock (arrastrar partes al viewport), thumbnails multithread
- `oip_comms` — Comms dock inferior (tag groups, enable comms, console, export Node-RED)
- `tag_groups` — Inspector dropdowns para selección de tags
- `opc_ua_browser` — Browsing de address space OPC UA (Copy Node ID)
- `conveyor_gizmo` — resize handles + sideguards (`G`), flow arrows (`.`)
- `robot_gizmo` — arcos de joints + IK end effector del SixAxisRobot
- `gantry_gizmo` — crosshair para posicionar el efector del Gantry
- `agv_gizmo` — path verde + waypoints del AGV
- `dock_door_tool` — tecla `C` alterna puertas de DockDoor
- `scene_interop` — import/export scene.json
- `st_editor` — dock "ST": escribir y hot-swap Structured Text en la simulación (Check/Apply)
- `editor-pilot-mode` — walkthrough primera persona (`Shift+R`, `E` interactuar)
- (`runtime-editor-bridge` NO está habilitado — vive en `deprecated/`, ver [deprecated])

---

## [comandos]

**Flujo de trabajo típico:**
1. Abrir `Simulation.tscn` (o crear con **New Simulation**).
2. Arrastrar partes desde el Parts dock (categorías Equipment/Devices/Products/Structure).
3. Configurar tamaño, color y tags de comms en el Inspector.
4. `F5` para correr/parar la simulación (los spawners se limpian solos al parar).
5. Para comms: Comms dock → Add Tag Group → protocolo → Enable Comms.

**Atajos clave (plugins nativos, válidos):**

| Atajo | Acción |
|---|---|
| `F5` | Play/Stop simulación |
| `Ctrl+Shift+C` | Snap de conveyors (autoload ConveyorSnapping) |
| `N` | Toggle live snap (oip_ui; `Alt` durante un drag lo escapa puntualmente) |
| `G` | Toggle sideguard gizmo |
| `.` | Toggle flechas de dirección de flujo |
| `Shift+R` | Toggle pilot mode |
| `E` (pilot) | Interactuar (coger cajas, empujar pallets) |
| `C` | `use()` sobre los nodos seleccionados (DockDoor: alternar puerta) |

**Atajos del editor Godot nativo:** `Ctrl+Z/Y` undo/redo, `Ctrl+D` duplicar, `F` focus, `1-5` vistas, `Q/W/E/R` select/move/rotate, `Space` subir, `Shift` boost.

**Headless / CLI** (tests y builds):
```powershell
# SIEMPRE matar procesos colgados primero (el thread del worker del DLL no es daemon
# y deja un zombie que bloquea el DLL → el import falla con "Can't open GDExtension")
Get-Process OIP_v4.7-rc1 -ErrorAction SilentlyContinue | Stop-Process -Force
# El fork vive dos niveles arriba del project root:
# Importar el proyecto headless (fuerza re-importación). OJO: el editor auto-ejecuta la
# simulación durante el import (lógica del fork) — los errores de escritura que
# aparezcan son la carrera real del DLL, no del import.
& "..\..\OIP_v4.7-rc1.exe" --headless --path . --import
# Correr un test (extends SceneTree, quit(0|1)):
& "..\..\OIP_v4.7-rc1.exe" --headless --path . --script res://test_repro8.gd
# Exportar
& "..\..\OIP_v4.7-rc1.exe" --headless --path . --export-release <preset> out.exe
```

---

## [patrones]

### Simulation singleton (fork)
El fork de Godot expone el singleton `Simulation`. Conectar SIEMPRE en `_enter_tree()` (no `_ready()`) y desconectar en `_exit_tree()`:
```gdscript
func _enter_tree() -> void:
    Simulation.started.connect(_on_started)
    Simulation.stopped.connect(_on_stopped)
```

### Dual-mode (@tool)
El mismo script debe funcionar en editor Y en runtime:
```gdscript
if Engine.is_editor_hint():
    # comportamiento editor (polling de distancia, no física)
else:
    # comportamiento runtime (señales, física)
```

### Signal hub (desacoplamiento)
Componentes emiten señales sin conocer consumidores; el controlador central conecta en `_ready()`. No usar referencias directas entre partes peer.

### Null-safe facade
Todos los métodos de `CommsHub` retornan safe defaults si `_backend == null`. Las partes nunca verifican si OIPComms está disponible — simplemente llaman y reciben 0/false sin conexión.

### Geometría procedural
Conveyors, robots, gantries, chain transfers y máquinas construyen sus meshes en código → redimensionado dinámico sin assets pre-authored.

### Tag helper de Inspector (`src/comms/oip_comms_setup.gd`)
`OIPCommsSetup.validate_tag_property(property, "tag_group_name", "tag_groups", "tag_name") -> bool` (static) oculta/muestra las props de tag según el enable_comms GLOBAL (`OIPComms.get_enable_comms()`), llamado desde `_validate_property`. Los helpers `OIPCommsSetup.connect_comms(node, on_initialized, on_polled)` / `disconnect_comms(...)` cablean las señales de OIPComms y el re-draw del Inspector — usarlos en `_enter_tree()`/`_exit_tree()` en vez de conectar a mano.

### Persistencia de escena
Las partes deben respetar `owner` en nodos creados proceduralmente para que se guarden en `.tscn`. Reparents con `top_level = true` preservan el transform global.

---

## [deprecated]

Todo lo siguiente está en `deprecated/` y **NO debe modificarse**:

| Componente | Ubicación | Reemplazo activo |
|---|---|---|
| Runtime Editor | `deprecated/runtime/runtime_editor.gd` | Editor nativo Godot + addons |
| Runtime Editor Bridge | `deprecated/runtime-editor-bridge/` | — |
| SceneRegistry | `deprecated/runtime/core/scene_registry.gd` | `addons/scene-library/scene_library.cfg` |
| `.oip_scene.json` format | — | Escenas nativas Godot (`.tscn`) + `scene_interop` |
| SceneManager | `deprecated/runtime/` | — |
| DebugServer HTTP API | `deprecated/runtime/` | — |
| Autoloads RuntimeSimulationBus, RuntimeSelection, RuntimeUndoRedo, RuntimeEditorToaster | `deprecated/` | Singleton `Simulation` del fork |

**Regla:** Si un doc dice "Ver RuntimeEditor" o "SceneRegistry.gd (runtime)" o "COMMS panel" (full-screen), ignorarlo — es deprecated. Los docs `tutorial-communication-setup.md`, `howto-opc-ua-configuration.md`, `howto-conveyor-snapping.md`, `howto-node-red-export.md`, `reference-debug-server.md`, `RUNTIME_EDITOR.md`, `explanation-architecture.md` y `reference-scene-format.md` documentan el runtime editor deprecated; la config de comms hoy vive en el **Comms dock** (addon `oip_comms`).

---

## Fuentes (docs/ y AGENTS.md)

- Tutorials: `tutorial-getting-started.md`, `tutorial-communication-setup.md` *(comms deprecated)*
- How-to: `howto-stringer-dispenser.md`, `howto-camera-streaming.md`, `howto-import-models.md`, `howto-robot-gizmos.md`, `howto-opc-ua-configuration.md` *(deprecated)*, `howto-conveyor-snapping.md` *(deprecated)*, `howto-node-red-export.md` *(deprecated)*
- Reference: `reference-parts-catalog.md`, `reference-protocols.md`, `reference-plugins.md`, `reference-shortcuts.md`
- Explanation: `explanation-comms-architecture.md`, `explanation-scene-format.md` *(deprecated)*, `explanation-architecture.md` *(deprecated)*
