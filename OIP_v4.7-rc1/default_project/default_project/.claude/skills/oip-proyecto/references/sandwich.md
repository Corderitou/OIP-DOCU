# SandwichStation — etapa "devoradora" (2026-08)

Documenta la etapa de **sandwich** de la escena demo en su estado ACTUAL (post-rediseño).
La estación ya **no** suelda físicamente un sled: ahora es una estación **devoradora**
que despawna los stacks de entrada (Placer / 2 tiras / Celda / 2 tiras) y, por cada
stack consumido, **emite una unidad de producto tejido** (patrón `TIRADECELDAS.tscn`)
que avanza a la velocidad de la cinta. No usa cadenas físicas ni joints para las tiras,
pero cada producto sí tiene un cuerpo de transporte con colisión contra obstáculos estáticos.

> **ESTADO ACTUAL: el producto se genera en runtime.** La jerarquía de sus unidades se
> verifica durante Play en la pestaña **Remote** del Scene dock; el árbol Local solo
> contiene los contenedores persistentes.

## Qué es ahora la etapa

- **`parts/SandwichStation.tscn`** (`src/Sandwich/sandwich_station.gd`, `@tool`): estación
  fija sobre la `IndexingBeltConveyor3`. En `Simulation.tscn` en
  `(-12.724542, 1.0615056, -12.16)`.
  Tiene un `DetectArea` (Area3D, `collision_layer=0`, `collision_mask=10`) de caja `0.6×0.6×0.6`
  que detecta los cuerpos de las partes entrantes (layer 10: Celda, Placer, segmentos de Tira).
- **Entrada (despawn)**: poll de `DetectArea.get_overlapping_bodies()` → `_find_part_owner`
  (sube el árbol hasta `Celda`/`Placer`/`Tira`). El **gate de stack completo** (`_has_complete_stack`)
  exige **celda + placer + ≥2 tiras** (`min_tiras_first_stack=2`, `require_placer=true`). Al
  cumplirse → `queue_free()` de todas las partes de la zona (`_despawn`) y `_append_unit()`.
  Cooldown (`consume_cooldown=0.25s`) evita doble-consume del mismo stack.
- **Producto de salida**: nodo `SandwichProduct` (hermano de la estación, hijo de la
  escena raíz, con posición global independiente) que avanza con la cinta leyendo
  `BeltBody.constant_linear_velocity.x` o `fallback_belt_speed`. Es un `CharacterBody3D`;
  `_advance_product()` usa `move_and_collide(Vector3(vx * delta, 0, 0))`.
- **Collider de transporte**: cada producto tiene un `CollisionShape3D` llamado
  `TransportCollision`, creado dinámicamente y ajustado al tamaño del batch actual.
  El cuerpo usa `collision_layer=0` y `collision_mask=1`: puede chocar con cuerpos
  estáticos de la capa 1, pero no es detectado por sensores que consultan la capa 4
  mediante máscara `8`. Los productos no colisionan entre sí.
- **Jerarquía runtime**: cada stack agrega una unidad dentro de `ProductUnits/Batch_N`.
  Cada batch contiene `WovenBatch_N` (celdas, bundles y tiras visuales) y
  `PlacerBatch_N` (placers visuales y sus colisiones). Para verificar la conversión,
  ejecutar la escena y abrir **Remote**; expandir
  `Simulation/SandwichProduct/ProductUnits/Batch_0`. El árbol Local no muestra los
  nodos dinámicos generados durante Play.
- **Segmentos** (`_add_segment`/`_add_bundle`/`_add_tira_visuals`): cada stack consumido
  agrega 1 unidad = `Celda` (glb) + `Placer` (glb) + `TiraBundle`:
  - Segmento 1 (inicio): instancia **`res://1TiraBundle.tscn`** a `bundle1_offset=-0.101` de su celda.
  - Segmentos 2 (medio, repetibles): instancian **`res://2TiraBundle.tscn`** a `bundle2_offset=-0.189`.
  - Segmento 3 (final) **no se emite en runtime** — solo existe como ejemplo en `TIRADECELDAS.tscn`.
  - Cada `TiraBundle` lleva 2 tiras visuales (`parts/Tira.tscn`, placeholder de cobre,
    **sin física viva** — no se llama `build_chain`, los segmentos RigidBody no existen).
- **Stop**: en la demo `remove_on_stop=false` para que el `SandwichProduct` convertido
  permanezca visible aunque el simulador se detenga. Al iniciar una nueva simulación se
  vacían sus hijos y se vuelve a ocultar antes de aceptar otro stack. El collider de
  transporte también se elimina durante la limpieza y se recrea al generar el siguiente batch.
- **Debug**: export `debug` (por defecto `false`). Imprime despawn de cada parte, unidad generada,
  bundles creados con su posición, y el nº de hijos del producto. Apagar (`false`) para consola limpia.

## Preview en el editor (vista temporal)

- Export **`preview_units`** (0-12). Con el script `@tool`, al cambiarlo en el Inspector (sin play)
  la estación genera N unidades bajo **`PreviewSandwichProduct`** como hijos temporales del nodo
  (mismo patrón 1→2→2…), para inspeccionar el tejido en el árbol de la escena.
- **Vista temporal**: no se guarda con la escena; `_clear_preview()` la borra al volver a `0`
  o al correr la simulación (`Simulation.started`).
- Refactor de generación: `_add_segment`/`_add_bundle`/`_add_celda_placer`/`_make_model` aceptan
  `parent` + `consumed` explícito → reutilizados por runtime (`_product`) y preview (`PreviewSandwichProduct`).

## Transporte, sensores y 6axisRobot

- La cinta de indexado aplica su velocidad en `BeltBody.constant_linear_velocity`. La
  `SandwichStation` lee ese valor y mueve cada `SandwichProduct` de forma independiente.
- El collider `TransportCollision` no es un cuerpo de producto detectable por los sensores:
  su layer es `0`; solo su máscara `1` se usa para consultar obstáculos estáticos.
- `BatchSensor` es un `DiffuseSensor` con raycast de `collision_mask=8` (capa 4, items).
  Por eso detecta los cuerpos internos `WovenBatch`/`PlacerBatch`, que permanecen en
  `collision_layer=10`, pero ignora el shell de transporte.
- El `6axisRobot` recibe el disparo de `6axisSensor1` mediante Node-RED. Su `VacuumArea`
  usa máscara `10` y selecciona el cuerpo `RigidBody3D` más cercano. Al tomar un batch
  con metadata `oip_vacuum_detach`, guarda su transformada global, lo hace `top_level=true`
  y lo congela en modo cinemático. Desde entonces el batch deja de seguir al producto y
  se actualiza cada frame hasta la copa de vacío.
- Al liberar el vacío, el batch se descongela y sus velocidades lineal y angular se ponen
  en cero. El nodo sigue dentro del árbol del producto para permitir la limpieza normal.
- En `node-red/control_config.json`, `6axisRobot` trabaja con lotes de 6: el primer viaje
  lleva placers a `Point3`; el segundo lleva celdas al siguiente waypoint de la grilla
  (`gridCmds=[4..11]`). `oneShot=true` garantiza un ciclo por detección continua del sensor.

## Tope físico del batch (TopeFisico) — 2026-08-26

El producto tejido avanza para siempre con la cinta y pasaba de largo del `Point1` del
robot. Ahora un **tope físico lo retiene** en la salida de la `IndexingBeltConveyor3`:

- **`TopeFisico`** (`Simulation.tscn`, hermano de `TopeBatch`): `StaticBody3D` con
  `collision_layer=1` + `CollisionShape3D` (caja `0.03×0.12×0.60`) + placa visible gris.
  Posición `(-10.621, 1.0, -12.16)` → cara −X en `x=-10.636`, ~2 mm aguas arriba de la
  cara −X del fotoojo de `TopeBatch` (x=-10.6117).
- **Mecanismo**: el `WovenBatch_N` NO puede colisionar directamente (es `RigidBody3D`
  congelado cinemático arrastrado por el root). Quien choca es el **shell
  `TransportCollision` del producto** (`collision_mask=1`) contra el estático de capa 1,
  vía `move_and_collide()`. La cinta sigue empujando cada frame y el batch queda apoyado.
- **Reposo determinista**: el frente del shell está a `max_x 0.078 + 0.005 = 0.083` del
  origen del producto → `origen.x = cara_−X_del_muro − 0.083` (medido: error < 0.5 mm).
  Para calibrar contra `Point1`, mover `TopeFisico` en X (desplaza el reposo 1:1) —
  manteniendo su cara aguas arriba de la del fotoojo.
- **Gotcha de capas**: el `StaticBody3D` interno de `DiffuseSensor` usa
  `collision_layer=3` — 3 es **máscara de bits = capas 1 Y 2**, así que el fotoojo de
  `TopeBatch` por sí solo también frena el shell (por eso antes "nadie" lo detenía y de
  golpe frenaba 23 mm antes de lo esperado). El muro va apenas delante para que el stop
  sea el muro (contacto ancho, visible y calibrable).
- **`SandwichProduct` debe ser `CharacterBody3D`** en la escena: llegó a quedar como
  `Node3D` y el primer producto (el persistente) atravesaba el tope sin colisión —
  `_configure_transport_body()` hace cast y con `Node3D` nunca crea el shell, y
  `_advance_product()` lo mueve con `position.x +=`. Corregido 2026-08-26.
- **Batches independientes** (decisión del usuario): NO hay cola ni gap mínimo — el
  producto siguiente sigue avanzando aunque el anterior esté detenido en el tope (los
  shells, layer 0, no colisionan entre sí; el seguidor atraviesa al detenido y también
  queda apoyado en el muro).
- **Liberación de shells vacíos** (`_release_empty_products()` en
  `sandwich_station.gd`, cada `_physics_process`): cuando el robot ha desmontado
  (`top_level=true`) TODOS los cuerpos (`WovenBatch_*` + `PlacerBatch_*`) de un producto,
  la estación los reparenta al contenedor **`ReleasedBatches`** (hermano de la estación;
  `top_level` preserva el transform global, seguro incluso mientras el robot carga un
  cuerpo) y retira el shell vacío para que no se acumule en el tope: el de escena se
  limpia con `_clear_product()` y se oculta; los dinámicos se `queue_free()`.
  `ReleasedBatches` se vacía en cada `Simulation.started` y en `_cleanup()`.
- **Naming**: cada producto raíz (`SandwichProduct`, `SandwichProduct_1`, …) tiene su
  PROPIO `ProductUnits/Batch_0` (`_append_unit()` rebasa `consumed` por producto). No es
  un bug de nombres; toda lógica debe iterar `_products[]`, nunca buscar `Batch_0` por
  ruta global.

## Tiras del producto (sin física)

- Las tiras del producto son **visuales puras**: `parts/Tira.tscn` instanciado con su
  `Placeholder` (BoxMesh cobre `0.006×0.002×0.2`) visible, sin `build_chain()` ni joints.
- `tira.gd:_show_placeholder()/_hide_placeholder()` solo actúan con `Engine.is_editor_hint()`:
  en runtime sin cadena el placeholder queda visible (la tira se ve).
- **`TiraBundleExample`** (`src/Tira/tira_bundle_example.gd`, `class_name TiraBundleExample`,
  extiende `TiraBundle`): variante para escenas de ejemplo/referencia que **persiste tras el stop**
  (solo `unbind()` de cross-joints, no `queue_free`). `tira.gd:_on_simulation_ended()` tiene un
  guard `_inside_example_bundle()` → si la tira vive bajo un `TiraBundleExample` **nunca** se
  auto-elimina (freeze_chain y return), solo desaparece si alguien la despawna explícitamente.
  Es el fix del bug "al dar play+stop desaparecen las tiras" del bundle copiado en la escena.

## Archivos y escenas de referencia

- `TIRADECELDAS.tscn` — patrón de ejemplo del tejido final (1 = inicio, 2 = medio repetible,
  3 = final). Celdas espaciadas `0.172`, `1TiraBundle` a `-0.101` de su celda, `2TiraBundle`
  a `-0.189`. Los bundles usan `tira_bundle_example.gd`.
- `1TiraBundle.tscn` / `2TiraBundle.tscn` — templates de bundle (root `Node3D` + hijo
  `TiraBundle` con `tira_bundle.gd`); la estación los instancia por segmento.
- `backup-sandwich-assembly/` — ensamblado viejo (sled físico) retirado, NO tocar.

## Notas de la escena real

 - `IndexingBeltConveyor3` en `(-13.310758, 0.98244756, -12.161912)`,
  `height=0.03`, `step_distance=0.165`, `step_speed=0.1` → superficie en `y≈0.982`.
- `SandwichStation` **no tiene comms**: sin overrides de tags en `Simulation.tscn`, no registra
  nada → no toca el tree OPC UA. El `belt_path` apunta a
  `../Building/ETAPA 1/IndexingBeltConveyor3/BeltBody` (o fallback: busca cualquier `IndexingBeltConveyor`).

## Verificación

> **CONSULTAR ANTES DE VALIDAR (preferencia del usuario, 2026-08-26)**: al llegar a la
> etapa de verificación, preguntar primero si se valida con tests headless o si el usuario
> prefiere validar manualmente (normalmente visual, F5 en el editor). No lanzar validaciones
> headless por defecto. El usuario eliminó `test_sandwich_devour.gd` (2026-08-26) porque
> prefiere validación manual de la etapa sandwich.

- `test_tope_batch.gd` (tope físico): batch se detiene con el frente contra `TopeFisico`
  y no se mueve con la cinta empujando; batch 2 avanza independiente mientras el 1 está
  detenido; tras desmontar ambos cuerpos (`top_level`) el shell se libera y los cuerpos
  sobreviven bajo `ReleasedBatches`; el batch 2 sigue hasta el tope. **14/14 ALL_OK**
  (2026-08-26).
- En tests que cargan `Simulation.tscn`, desactivar comms tras instanciar
  (`enable_comms=false` en toda la escena) antes de emitir `Simulation.started`: el flujo
  Node-RED desplegado está vivo (pulsa `IndexingBelt3_Step`, cicla el Horno) y arrastra
  los stacks, haciendo el test no determinista.
- `test_sandwich_preview.gd` (preview editor): `_rebuild_preview()` crea 1 y 3 unidades como
  hijos temporales, `_clear_preview()` los borra y no toca el producto runtime. **6/6 PASS.**
- `test_tira_bundle.gd` (bundle de tiras runtime): grab → release → cut, cross-joints,
  separación homóloga, cleanup al parar. **14/14 PASS.**
- `test_tira_bundle_example.gd` (bundle persistente): script correcto, tiras hijas
  `remove_on_stop=false`, bundle + 2 tiras persisten tras stop. **5/5 PASS.**
- Comando: `& "..\..\OIP_v4.7-rc1.exe" --headless --path . --script res://test_<name>.gd`
  (matar primero el proceso zombie: `Get-Process OIP_v4.7-rc1 | Stop-Process -Force`).

## Problemas conocidos / pendientes

1. **Las unidades generadas son runtime.** Deben comprobarse en **Remote** durante Play;
   el árbol Local solo contiene `SandwichProduct` y `ProductUnits` como contenedores.
2. **Crecimiento hacia atrás ilimitado**: con muchos stacks el producto se aleja de la estación
   (en el log se vio bundles hasta `x≈-21`). Si se retoma, limitar el span o el nº de unidades
   (`MAX_UNITS=60` hoy) para que no se desborde visualmente.
3. El `TransportCollision` requiere que el obstáculo estático use la capa 1. No cambiar
   `collision_layer=0` del producto a `10`, porque `BatchSensor` usa máscara `8` y volvería
   a detectar el producto completo aunque la celda ya hubiera sido retirada.
4. Las escenas `1/2TiraBundle.tscn` y `TIRADECELDAS.tscn` fueron ajustadas por el usuario
   (root `Node3D` + hijo `TiraBundle`, reposicionado); revisar que sigan coherentes con la
   estación al retomar.
