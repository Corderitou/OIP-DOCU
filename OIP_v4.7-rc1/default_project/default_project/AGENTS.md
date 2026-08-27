# OIP v4.7 — Guía de desarrollo

Framework open-source de simulación industrial/warehouse sobre un **fork custom de Godot 4.7** (Forward Plus, Jolt Physics, 120 ticks/s). MIT. Para contexto completo de partes/comms/editor usar el skill `oip` (`.claude/skills/oip/SKILL.md`, con índice por secciones) y `docs/index.md`. Para flujos Node-RED/comms desplegados, skill `oip-nodered-comms`.

## Contexto clave (no obvio)

- **El binario Godot es un fork custom**: `..\..\OIP_v4.7-rc1.exe` (dos niveles arriba del project root). Expone singletons que NO están en `[autoload]` de `project.godot`: `Simulation` y `OIPComms` (vía `Engine.get_singleton("Simulation")`). El código GDScript los referencia directamente como `Simulation.` / `OIPComms.`.
- **`Simulation`** → señales `started`, `stopped`, `pause_toggled` y método `stop()`. Conectar SIEMPRE en `_enter_tree()` y desconectar en `_exit_tree()`, nunca en `_ready()`.
- **`Simulation.tscn` es la escena demo** (root Node3D "Simulation", igual que la que crea el botón "New Simulation" del addon `oip_ui`); la cargan los tests headless. No es el singleton.
- Autoloads reales (`project.godot`): `CommsHub` (stub null-safe → `src/comms/oip_comms_stub.gd`), `OIPCommsService`, `SoftPlcBridge`, `ConveyorSnapping`, `StructureSnapping`.
- GDScript warnings (`project.godot`): solo `missing_tool=2` es **error** (→ `@tool` obligatorio en scripts de partes). `untyped_declaration` y `unsafe_*` están a 1 (warnings, no rompen el parse). También son error: `integer_division`, `narrowing_conversion`, `redundant_await`, `int_as_enum_without_*`.
- Import de modelos: `import/fbx/enabled=false` y `import/blender/enabled=false` → usar **glTF (.glb)**.
- `trim.py` borra TODOS los `.glb` cuyo nombre no esté en su lista `KEEP` (actualmente vacía) — solo para reducir tamaño del proyecto; no correrlo si las escenas necesitan los .glb.
- Los archivos `.uid` (ej. `*.gd.uid`) los genera Godot al importar — no se editan a mano.
- **El DLL `OIPComms` tiene una carrera real** entre los writes del main thread y su thread de polling (la fuente del GDExtension NO está en el repo, solo binarios en `addons/oip_comms/bin/`). Ver "Comms: la carrera del DLL".

## Verificación sin abrir el editor

> **CONSULTAR ANTES DE VALIDAR (preferencia del usuario, 2026-08-26)**: cuando un cambio
> llega a la etapa de verificación, **preguntar primero** si lo valida uno mismo con tests
> headless o si prefiere validarlo el usuario manualmente (normalmente visual, con F5 en el
> editor). No lanzar validaciones headless por defecto.

```powershell
Get-Process OIP_v4.7-rc1 -ErrorAction SilentlyContinue | Stop-Process -Force   # siempre primero
& "..\..\OIP_v4.7-rc1.exe" --headless --path . --import                        # re-importar / parsear todo
& "..\..\OIP_v4.7-rc1.exe" --headless --path . --script res://test_repro8.gd   # correr un test
```

En tests que cargan `Simulation.tscn`, desactivar comms tras instanciar
(`for n in sim.find_children("*", "Node", true, false): if "enable_comms" in n: n.set("enable_comms", false)`)
antes de emitir `Simulation.started`: el flujo Node-RED desplegado está vivo (pulsa
`IndexingBelt3_Step`, cicla el Horno) y arrastra los stacks de la zona, haciendo el test
no determinista (ver `test_tope_batch.gd`).

Patrón de test del repo (`test_validate_019fc55b.gd`, `test_repro*.gd`): script `extends SceneTree` con lógica en `_init()` (vía `call_deferred`) y `quit(0 | 1)`. Validar scripts/escenas con `load()` + `instantiate()` sin GUI.

> **IMPORTANTE — procesos colgados**: tras cada corrida headless (o editor cerrado a medias) puede quedar un `OIP_v4.7-rc1` zombie: el thread worker del DLL no es daemon y mantiene vivo el proceso. Ese zombie **bloquea el DLL** y el siguiente `--import` falla con `Can't open GDExtension dynamic library` + cascade `Invalid access to property 'tag_group_initialized'` (soft_plc_bridge). Matar el proceso antes de importar. Además, el editor **auto-ejecuta la simulación durante `--import`** (lógica del fork, no del repo), así que errores de escritura en el log de import son la carrera real del DLL, no un problema del import.

> **IMPORTANTE — NO borrar la cache de Godot** (`res://.godot/` o `%APPDATA%/Godot/`): el fork tarda muchísimo en reimportar/reinicializar desde cero. Si se borra, el siguiente arranque (editor o `--import`) se demora varios minutos y puede parecer colgado. Usar siempre la cache existente; si hace falta limpiar algo, borrar solo archivos puntuales (ej. `.import` corruptos), nunca la carpeta `.godot/` entera.

## Comms: la carrera del DLL (write-on-change)

El DLL `libOIP-COMMS` corrompe su registro interno (grupo/tag de nombre vacío) si se escriben tags a **alta frecuencia (60Hz)** aunque el valor no cambie. Síntomas: `OIPComms: Failed to write tag: ` (tag vacío), 3 errores de thread del stub `CommsHub`, luego `POLL ''` a ~12Hz + `comms_error` → `Simulation.stop()`. Estocástico (1-9s según rate y nº de tags); los writes de CeldaSpawner (3 bits × 60Hz) eran el detonante en la escena demo.

Reglas:

1. **Nunca escribir tags en `_physics_process`** — escribir solo en cambios de estado (flancos). Las **lecturas** a cualquier ritmo son seguras.
2. **Write-on-change ya está en la base**: `OIPCommsTag._should_write()` (`src/comms/oip_comms_tag.gd`) descarta writes con valor idéntico; `PlantComms.write_bit(tag, value, only_if_changed)` (`src/comms/plant_comms.gd`) es el helper multi-tag. Las partes nuevas no necesitan nada extra, pero deben evitar el patrón "escribir cada frame".
3. La caché de `OIPCommsTag` se resetea en `register()` y `on_group_initialized()` para forzar un write tras cada init de grupo.
4. **El bug NO se puede parchear en el binario** (no hay fuente). La mitigación es reducir writes.
5. Validar con `test_repro8.gd` (carga `Simulation.tscn`, grupo OPC UA `PLCSIM`, 8s): criterio = 0 líneas `Failed to write` / `POLL ''` / `comms_error` y polls normales a 1Hz. `test_repro9-12.gd` son variantes parametrizadas del stress test; `test_repro_comms.gd` es el repro mínimo.
6. **Otro abort con causa distinta**: `OIPComms: Stopping simulation: OPC UA tag 'ns=2;s=...' is invalid (BadNodeIdUnknown)` → el tag está registrado en la escena pero NO existe en el `tree` del server OPC UA de Node-RED (los spawners tipo Maquina necesitan sus tags de estación `<P>_CMD/_EXEC/_DONE/_RUNNING/_READY/_COUNT` además de `autoEnable`/`rate`). Fix: regenerar con `apply_control_flow.js` (genera los tags de estación por spawner) + `sync_deployed_flow.ps1` + reiniciar Node-RED. Va acompañado de 3 errores de hilo del stub (`emit_signalp`). Regla de oro: **todo tag que la escena registra debe existir en el tree**.

## Config de comms y Soft PLC

- El Comms dock (addon `oip_comms`) persiste en **`oip_data/tag_groups.cfg` + `oip_data/comms_settings.cfg`** (lo crea en runtime; también los leen `OIPCommsService` y `SoftPlcBridge`).
- **Soft PLC**: un tag group con protocolo `soft_plc` (valor `"7"` en tag_groups.cfg, nombre por defecto `ST`) ejecuta un programa IEC ST dentro del propio simulador. `SoftPlcBridge` lo registra y alimenta: el programa vive en la metadata `oip_st_program` del **root de la escena**, y el runtime es el bundle JS `res://oip-plc.js` (campo "gateway" del grupo). Se edita con el dock del addon `st_editor`.

## Crear una Parte

### Archivos

```
src/MiParta/mi_parta.gd      # Script (@tool + class_name obligatorios)
parts/MiParta.tscn            # Escena
```

(Algunas escenas viejas — `building.gd`, `dock_door.gd`, `generic_data.gd`, `hydraulic_controller.gd`, `UVStretch.gd` — tienen el script suelto en `parts/` junto al .tscn. Para partes nuevas usar el split `src/` + `parts/`.)

### Script

```gdscript
@tool
class_name MiParta
extends Node3D

func _enter_tree() -> void:
    Simulation.started.connect(_on_started)
    Simulation.stopped.connect(_on_stopped)

func _exit_tree() -> void:
    Simulation.started.disconnect(_on_started)
    Simulation.stopped.disconnect(_on_stopped)
```

- `@tool` obligatorio (corre en editor; `missing_tool=2` es error) + `class_name` obligatorio (detección y registros).
- Desconectar en `_exit_tree()` para no dejar conexiones huérfanas en el editor.

### Escena (.tscn)

Reglas (verificadas en `parts/Celda.tscn`, `parts/Maquina1.tscn`):
- `load_steps` = ext_resources + sub_resources (NO incluye nodos).
- **`parent="."` o `parent="NombreNodo"` en CADA nodo hijo** (obligatorio).
- **`Color(r, g, b, a)` siempre con 4 argumentos** (Godot 4.7).
- Si la escena se guardó desde el editor puede traer `format=3` y/o sin `load_steps`; ambas cargan.
- IDs de recursos: `id="1_xxx"`, referenciar con `SubResource("...")` / `ExtResource("1_xxx")`.

### Registro en el Parts dock

El **único registro activo** es `addons/scene-library/scene_library.cfg` (formato Godot serializado, agrupado por categorías `Equipment` / `Devices` / `Products` / `Structure`):

```
library=Array[Dictionary]([{
"assets": Array[Dictionary]([{
"path": "res://parts/MiParta.tscn",
"uid": "uid://..."
}]),
"name": "Products"
}])
```

El `uid` debe coincidir con el de la escena. `parts/assemblies/` contiene las escenas de conjuntos de conveyors (mismo registro).

> `deprecated/runtime/core/scene_registry.gd` es **DEPRECATED** — no registrar partes ahí.

## Colisiones y Detección

### Layers

| Layer | Nombre | Usado por |
|---|---|---|
| 1 | Static | Building, ContainerTrailer |
| 2 | Dynamic | Diverter, SafetyGate |
| 3 | Belt | Sensores, belt conveyors |
| 4 | Box | Items físicos (detección) |
| 5 | SimpleConveyorShape | Roller conveyors |
| 6 | — | Dispenser/Stringer bodies |
| 8 | — | Pallet, cargo |
| 10 | — | Box, Celda, Tira (RigidBody3D) |
| 15 | — | Mask para física de items |
| 18 | — | ChainTransfer |

(Layers 1-5 tienen nombre en `project.godot`; el resto son convención del código.)

### Detección en runtime

Usar `body_entered` (no `area_entered`). Detector: `Area3D` con `collision_layer = 0` y `collision_mask` = layers de los targets, + `CollisionShape3D` hijo. Detectable: `StaticBody3D` con `collision_layer` acorde y `collision_mask = 0`. Conectar de forma defensiva: `get_node_or_null(...) as Area3D` + `is_connected()` antes de `connect()`.

### SandwichProduct y colisión de transporte

- `SandwichStation` genera cada producto como `CharacterBody3D` persistente o dinámico,
  con un `CollisionShape3D` llamado `TransportCollision` que se ajusta al batch actual.
- **El nodo de escena `Simulation/SandwichProduct` DEBE ser `CharacterBody3D`** (llegó a
  quedar como `Node3D` y el primer producto atravesaba los topes: `_configure_transport_body()`
  hace cast a `CharacterBody3D`, con `Node3D` nunca se crea el `TransportCollision` y
  `_advance_product()` lo mueve con `position.x +=`, sin colisión).
- El cuerpo de transporte usa `collision_layer = 0` y `collision_mask = 1`: se mueve con
  `move_and_collide()` y puede chocar contra obstáculos estáticos de la capa 1, pero no
  debe aparecer en sensores que usan raycast con máscara `8`.
- **Tope físico del batch (`TopeFisico` en `Simulation.tscn`)**: `StaticBody3D` con
  `collision_layer=1` + placa visible, bajo el root; su cara −X queda ~2 mm aguas arriba
  de la cara −X del fotoojo de `TopeBatch`. El shell del producto choca y el batch queda
  apoyado aunque la cinta siga empujando. Reposo determinista:
  `origen_producto.x = cara_−X_del_muro − 0.083` (frente del shell = `max_x 0.078 + 0.005`).
  OJO: el `StaticBody3D` interno de `DiffuseSensor` usa `collision_layer=3` y **3 es una
  máscara de bits = capas 1 Y 2**, así que el fotoojo por sí solo también frena el shell;
  por eso el muro va apenas aguas arriba, para que el stop real sea el muro (ancho y visible).
- **Liberación de shells vacíos** (`_release_empty_products()`): cuando el robot desmonta
  (`top_level=true`) TODOS los cuerpos de un lote, la estación los reparenta al contenedor
  `ReleasedBatches` (hermano de la estación, transform global preservado — el robot puede
  seguir cargándolos) y retira el shell vacío (el de escena se limpia y oculta; los
  dinámicos se `queue_free`). Limpieza de `ReleasedBatches` en cada arranque/parada con
  `remove_on_stop`.
- Los batches son **independientes** (decisión del usuario): el producto siguiente sigue
  avanzando aunque el anterior esté detenido en el tope — no hay cola ni gap mínimo, y los
  shells no colisionan entre sí (layer 0).
- No reutilizar `WovenBatch`/`PlacerBatch` como collider de transporte. Esos son cuerpos
  `RigidBody3D` congelados, layer `10`, mask `0`, reservados para que el vacío del
  `SixAxisRobot` los tome de forma independiente.
- `DiffuseSensor` consulta la capa 4 con `collision_mask = 8`. Cambiar la layer del
  `TransportCollision` a `10` hace que `BatchSensor` detecte el producto completo y
  permanezca activo aunque la unidad interna ya haya sido retirada.
- Cada producto se mueve de forma independiente y no se habilitan colisiones entre
  productos; la colisión de transporte es únicamente contra obstáculos estáticos.

### Detección en editor (@tool)

En el editor NO corre física → `body_entered` no dispara. Para partes `@tool` que interactúan en editor usar **polling de distancia** desde setters export + `_ready()` (ej. `if Engine.is_editor_hint(): _poll_detection()`), con guard `is_inside_tree()` (los setters se disparan antes de entrar al árbol).

## Patrón: Cadena física (cuerda) — Tira

Para materiales tipo cuerda/cinta (Tira): cadena de `RigidBody3D` pequeños + `Generic6DOFJoint3D` entre segmentos; anclajes al mundo (`PinAnchor`, `PinHead`) son `PinJoint3D` con `node_b` vacío. Modelo de estados: **taut** (agarrada, congelada) → **hanging** (cortada, cuelga del PinHead) → **free** (suelta, cae). Detalles completos en `docs/howto-stringer-dispenser.md`.

**TiraBundle** (`src/Tira/tira_bundle.gd`): el Dispenser agrupa las N tiras de un ciclo (`tiras_por_ciclo>=2`) bajo un `TiraBundle` que las une con cross-joints rígidos entre segmentos homólogos → caen/viajan como un solo objeto ("escalera"). Cuando la SandwichStation suelda una `Tira` hija del bundle, la reparentea fuera de él (los cross-joints quedan inertes por path roto; inofensivo, los segmentos ya están congelados); el bundle se limpia en `Simulation.stopped`.

Segmento típico: `freeze=true`, `gravity_scale=0`, `can_sleep=true`, `continuous_cd=true`, `angular_damp=3.0` (Jolt ignora springs del 6DOF), `collision_layer=10`, `collision_mask=15`, shape `BoxShape3D` a 0.95×seg_len (huecos → sin self-overlap).

Reglas críticas (bugs reales ya resueltos — no reintroducir):

1. **El ancla se captura al asignar `node_a`/`node_b`** — posicionar la joint ANTES de asignar los paths; moverla después puede explotar el solver (NaN: `renderer_scene_cull !v.is_finite()`). En cada reposicionamiento: limpiar paths, mover, reasignar (`_sync_joints()`).
2. **El frame del joint define los ejes de los límites 6DOF**: orientar segmentos y joints con la misma basis a lo largo de la cadena (`Basis.looking_at(dir, up)` con `up` alternativo si `absf(dir.dot(UP)) > 0.98`).
3. **Siempre sync + velocidades a cero antes de `unfreeze_chain()`**, que además hace `seg.sleeping = false` explícito (bodies re-registrados post-reparent pueden arrancar dormidos).
4. **Reparent ANTES de unfreeze**: `cut_chain()` → reparent a raíz → `unfreeze_chain()`. Si se descongela antes del reparent, los `node_a`/`node_b` quedan con paths viejos que no resuelven → la cadena cae entera.
5. **No compartir arrays por referencia**: `Dispenser.spawn_tira()` retorna su array interno; el Stringer debe hacer `tiras.duplicate()` o `_spawned_tiras.clear()` vacía también `_held_tiras`.
6. `cut()` del Dispenser busca tiras con `find_children("*", "Tira", ...)` (no confiar en `_spawned_tiras`, que se pierde al recargar escena o tras re-grab).
7. **Guardas NaN** (`if not v.is_finite(): return Vector3.ZERO`) en TODA escritura de posición/basis; histéresis en `place_chain()` (reconstruir solo si `abs(needed - size) > 2`) para evitar parpadeo al cruzar umbrales.

## Deprecated — no tocar

`deprecated/` (runtime editor + bridge) es código histórico. No modificar. Tampoco confiar en los docs que lo documentan: `RUNTIME_EDITOR.md`, `explanation-architecture.md`, `reference-scene-format.md`, `reference-debug-server.md`, `tutorial-communication-setup.md`, `howto-opc-ua-configuration.md`, `howto-conveyor-snapping.md`, `howto-node-red-export.md`. El reemplazo activo es el editor nativo de Godot + addons (comms = Comms dock del addon `oip_comms`).

## Housekeeping (qué ignorar)

- `mi-servidor/` — hello-world Node.js suelto, sin relación con el simulador.
- `backup-*/` — backups del usuario.
- `*.oip_scene.json` (raíz) — exports del formato de escena JSON de interop (addon `scene_interop` / `src/interop/`), no escenas nativas.
- `node-red/` — template del flujo Node-RED (`flows.json`, `control_config.json`); sincronizar con `~/.node-red/flows.json` vía el skill `oip-nodered-comms`.

## Checklist

1. `@tool` + `class_name` en el script; señales `Simulation` en `_enter_tree()`/`_exit_tree()`.
2. Escena con `parent` en cada nodo; `load_steps` = ext + sub resources; `Color` con 4 args.
3. Registrar solo en `addons/scene-library/scene_library.cfg` (categoría correcta, uid coincidente).
4. Detección runtime: Area3D + `body_entered` + StaticBody3D; en editor: polling de distancia.
5. Validar sin GUI: matar proceso → `--headless --import` → test `extends SceneTree`.
6. Comms: escribir solo en cambios de estado (nunca cada frame); el write-on-change ya lo aplica `OIPCommsTag`.

## INFORMES — Proyecto APT actual

- El proyecto APT actualmente definido consiste en traer a Chile una empresa dedicada al ensamblaje de paneles solares.
- La empresa objetivo confirmada por el usuario es Mondragon Assembly. Su información oficial la presenta como especialista en automatización, maquinaria y líneas llave en mano para fabricación de módulos fotovoltaicos; no asumir todavía que el proyecto será una filial, una planta operada directamente, una alianza o solo una transferencia tecnológica.
- El proyecto considera exclusivamente el ensamblaje de módulos fotovoltaicos; no incluye la fabricación de celdas solares.
- La ubicación preliminar confirmada es el sector El Salto, Viña del Mar, elegido por su carácter industrial y disponibilidad prevista de espacio para maquinaria, almacenamiento y operación. La dirección exacta y la superficie aún no están definidas.
- El sector se encuentra próximo a la Subestación Miraflores. No asumir todavía su capacidad disponible, distancia exacta ni condiciones de conexión.
- El punto 2, `INFORMES/introduccion.md`, corresponde a la ingeniería conceptual de la fábrica e incluye infraestructura, proyecto eléctrico, automatización, proceso de ensamblaje, almacenamiento y distribución.
- La problemática base es la creciente demanda nacional de energías renovables, especialmente energía solar, junto con la dependencia de paneles fabricados y ensamblados en el extranjero.
- El análisis debe enfocarse en la disponibilidad continua y rápida de paneles solares en Chile, considerando importación, transporte internacional, tiempos de abastecimiento, costos logísticos y desarrollo de una cadena de valor local.
- No asumir cifras, dirección exacta, superficie, capacidad productiva, inversión, tecnología específica, marca de componentes ni condiciones eléctricas hasta que el usuario las confirme o se verifiquen técnicamente.
- Los archivos `INFORMES/introduccion.md`, `INFORMES/problematica.md`, `INFORMES/antecedentes.md` y `INFORMES/objetivos.md` contienen las primeras redacciones de los puntos 2, 3, 4 y 5, respectivamente.
- Los objetivos generales y específicos deben mantenerse en nivel de ingeniería conceptual y seguir el formato SMART, usando entregables verificables y plazos ligados a la etapa de ingeniería conceptual cuando todavía no existan fechas académicas confirmadas. No incorporar metas numéricas de producción, inversión, ahorro o capacidad que no hayan sido confirmadas o verificadas técnicamente.
- Los objetivos específicos del punto 5 deben seguir el formato SMART, usando entregables verificables y plazos ligados a la etapa de ingeniería conceptual cuando todavía no existan fechas académicas confirmadas.
- El punto 4, `INFORMES/antecedentes.md`, debe abordar por qué el proyecto es necesario, su posible impacto en la zona de instalación y los beneficios esperados.
- La problemática específica debe considerar modelo de entrada, viabilidad comercial y económica, ubicación e infraestructura, importación de componentes, integración de automatización, personal especializado, normativa, calidad, impacto territorial, continuidad operacional y soporte posterior.
- `INFORMES/SOLUCIONES EXAMEN.md` es una referencia del semestre anterior y no describe necesariamente el proyecto APT actual.
