# Mapa de I/O — Línea de Paneles Solares (PLCSIM S7)

Mapa maestro de tags para la línea de 10 etapas. Godot es la **planta** (escribe PV/estados,
lee comandos); PLCSIM es el **cerebro** (PID reales + secuencia en SCL/LAD).

Cada estación registra su tag group en `oip_data/tag_groups.cfg` (único grupo `PLCSIM`,
protocolo `"3"` = S7 PUT/GET, `gateway` = IP del PLCSIM). La parte individual elige su
`tag_name` (la dirección S7). El prefijo `S#_` solo es una convención de nombre: **la
dirección real la decide el Comms dock / el tag_name de cada parte**.

## Convención de direcciones S7 (sugerencia)

| Tipo | Notación S7 | Uso |
|---|---|---|
| BOOL | `M<byte>.<bit>` | Handshake, estados, flags |
| DINT | `MD<n>` (4 bytes) | Comandos, contadores |
| REAL | `MD<n>` (4 bytes) | PV/MV analógicos (PID) |

> El tamaño del tag lo dicta la notación de dirección: una doble palabra `MD` puede
> transportar `REAL` (float32) o `DINT` (int32). Si el driver S7 no soporta float,
> usar `DINT` + `scale_factor` en la parte (fallback documentado en cada máquina).

## Patrón de handshake (todas las máquinas)

| Tag | Dir | Tipo | Descripción |
|---|---|---|---|
| `S#_CMD` | PLC→Planta | DINT | Código de comando (0=ninguno, 1=ciclo, 2=reset) |
| `S#_EXEC` | PLC→Planta | BOOL | Flanco ascendente dispara el comando |
| `S#_DONE` | Planta→PLC | BOOL | 1 = comando completado (el PLC lo baja escribiendo EXEC=0) |
| `S#_RUNNING` | Planta→PLC | BOOL | 1 = ciclo en ejecución |
| `S#_READY` | Planta→PLC | BOOL | 1 = máquina lista / modo automático |
| `S#_FAULT` | Planta→PLC | BOOL | 1 = alarma (temp fuera de rango, sin producto...) |
| `S#_IN_POS` | Planta→PLC | BOOL | 1 = producto presente en la estación |

## Analógicos PID (patrón)

| Tag | Dir | Tipo | Descripción |
|---|---|---|---|
| `S#_SETPOINT` | PLC→Planta | REAL | Consigna de temperatura (°C) — opcional |
| `S#_MV` | PLC→Planta | REAL | Salida del PID del PLC (0–100 %) → potencia del heater |
| `S#_PV` | Planta→PLC | REAL | Temperatura medida (primera planta térmica de 1er orden) |

> La simulación térmica es una primera planta `T(s) = K/(tau·s+1)` con ruido leve:
> Godot integra `dT/dt = (MV·K + Tamb·-T)/tau`. El PID (real, en PLCSIM) cierra el lazo.

---

## Etapa 1 — S1 CeldaSpawner (alimentación de vidrio)

Alimenta una pieza de vidrio (`Vidrio`) al inicio de línea por comando del PLC.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S1_CMD` | PLC→Planta | DINT | MD10 | 0=none, 1=alimentar 1 pieza, 2=alimentar N |
| `S1_EXEC` | PLC→Planta | BOOL | M10.0 | Dispara la alimentación |
| `S1_DONE` | Planta→PLC | BOOL | M10.1 | Pieza emitida |
| `S1_RUNNING` | Planta→PLC | BOOL | M10.2 | Emitiendo (pausa entre piezas) |
| `S1_READY` | Planta→PLC | BOOL | M10.3 | Stock disponible |
| `S1_COUNT` | Planta→PLC | DINT | MD14 | Piezas emitidas (contador) |
| `S1_AUTO_ENABLE` | PLC→Planta | BOOL | M10.4 | Modo automático (tasa fija) |
| `S1_RATE` | PLC→Planta | REAL | MD18 | Piezas/min en automático |

## Etapa 2 — H1 Horno (soldadura térmica con PID)

Calienta celdas y tiras con temperatura controlada por PID en el PLC.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `H1_CMD` | PLC→Planta | DINT | MD20 | 0=none, 1=ciclo horno |
| `H1_EXEC` | PLC→Planta | BOOL | M20.0 | Dispara ciclo |
| `H1_DONE` | Planta→PLC | BOOL | M20.1 | Calentamiento completado |
| `H1_RUNNING` | Planta→PLC | BOOL | M20.2 | Ciclo en curso |
| `H1_READY` | Planta→PLC | BOOL | M20.3 | Lista |
| `H1_FAULT` | Planta→PLC | BOOL | M20.4 | Temp fuera de rango |
| `H1_IN_POS` | Planta→PLC | BOOL | M20.5 | Producto detectado bajo el horno |
| `H1_SETPOINT` | PLC→Planta | REAL | MD24 | Consigna de temperatura (°C) |
| `H1_MV` | PLC→Planta | REAL | MD28 | Salida PID → heater (0–100 %) |
| `H1_PV` | Planta→PLC | REAL | MD32 | Temperatura medida (°C) |
| `H1_CYCLE_TIME` | Planta→PLC | REAL | MD36 | Tiempo de ciclo real (s) |

## Etapa 3 — S3 Layup (apilado de capas)

Ensambla vidrio + EVA + string + EVA + backsheet en un paquete.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S3_CMD` | PLC→Planta | DINT | MD40 | 0=none, 1=apilar, 2=expulsar paquete |
| `S3_EXEC` | PLC→Planta | BOOL | M40.0 | Dispara secuencia de apilado |
| `S3_DONE` | Planta→PLC | BOOL | M40.1 | Paquete completado |
| `S3_RUNNING` | Planta→PLC | BOOL | M40.2 | Apilando |
| `S3_READY` | Planta→PLC | BOOL | M40.3 | Lista |
| `S3_IN_POS` | Planta→PLC | BOOL | M40.4 | Materiales presentes |
| `S3_LAYERS` | Planta→PLC | DINT | MD44 | Capas actuales (1–5) |
| `S3_FAULT` | Planta→PLC | BOOL | M40.5 | Material faltante |

## Etapa 4 — S4 Estación de limpieza (superficie)

Sopla/limpia la superficie del vidrio antes de laminar.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S4_CMD` | PLC→Planta | DINT | MD50 | 0=none, 1=ciclo limpieza |
| `S4_EXEC` | PLC→Planta | BOOL | M50.0 | Dispara ciclo |
| `S4_DONE` | Planta→PLC | BOOL | M50.1 | Limpieza completada |
| `S4_RUNNING` | Planta→PLC | BOOL | M50.2 | Soplando |
| `S4_READY` | Planta→PLC | BOOL | M50.3 | Lista |
| `S4_IN_POS` | Planta→PLC | BOOL | M50.4 | Pieza presente |
| `S4_BLOW_MV` | PLC→Planta | REAL | MD54 | Presión de aire del PLC (0–100 %) |

## Etapa 5 — S5 Laminadora (PID temperatura + vacío)

Laminación en caliente con control PID de temperatura y vacío.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S5_CMD` | PLC→Planta | DINT | MD60 | 0=none, 1=ciclo laminación |
| `S5_EXEC` | PLC→Planta | BOOL | M60.0 | Dispara ciclo |
| `S5_DONE` | Planta→PLC | BOOL | M60.1 | Laminación completada |
| `S5_RUNNING` | Planta→PLC | BOOL | M60.2 | Laminando |
| `S5_READY` | Planta→PLC | BOOL | M60.3 | Lista |
| `S5_FAULT` | Planta→PLC | BOOL | M60.4 | Temp/vacío fuera de rango |
| `S5_IN_POS` | Planta→PLC | BOOL | M60.5 | Paquete en plato |
| `S5_SETPOINT` | PLC→Planta | REAL | MD64 | Consigna de temperatura (°C) |
| `S5_MV` | PLC→Planta | REAL | MD68 | Salida PID → heater (0–100 %) |
| `S5_PV` | Planta→PLC | REAL | MD72 | Temperatura medida (°C) |
| `S5_VACUUM_MV` | PLC→Planta | REAL | MD76 | Vacío del PLC (0–100 %) |
| `S5_VACUUM_PV` | Planta→PLC | REAL | MD80 | Vacío real (mbar) |
| `S5_CYCLE_TIME` | Planta→PLC | REAL | MD84 | Tiempo de ciclo (s) |

## Etapa 6 — S6 Enmarcado / PrensaNeumatica

Cierra y prensa el marco de aluminio del panel.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S6_CMD` | PLC→Planta | DINT | MD90 | 0=none, 1=cierre marco, 2=prensa |
| `S6_EXEC` | PLC→Planta | BOOL | M90.0 | Dispara |
| `S6_DONE` | Planta→PLC | BOOL | M90.1 | Marco cerrado |
| `S6_RUNNING` | Planta→PLC | BOOL | M90.2 | Prensando |
| `S6_READY` | Planta→PLC | BOOL | M90.3 | Lista |
| `S6_FAULT` | Planta→PLC | BOOL | M90.4 | Falla de presión |
| `S6_IN_POS` | Planta→PLC | BOOL | M90.5 | Panel presente |
| `S6_PRESS_MV` | PLC→Planta | REAL | MD94 | Presión del pistón (0–100 %) |
| `S6_PRESS_PV` | Planta→PLC | REAL | MD98 | Fuerza medida (kN) |

## Etapa 7 — S7 JunctionBox

Aplica la caja de conexiones (JunctionBox) en el reverso del panel.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S7_CMD` | PLC→Planta | DINT | MD100 | 0=none, 1=aplicar caja |
| `S7_EXEC` | PLC→Planta | BOOL | M100.0 | Dispara |
| `S7_DONE` | Planta→PLC | BOOL | M100.1 | Caja aplicada |
| `S7_RUNNING` | Planta→PLC | BOOL | M100.2 | Aplicando |
| `S7_READY` | Planta→PLC | BOOL | M100.3 | Lista |
| `S7_IN_POS` | Planta→PLC | BOOL | M100.4 | Panel en posición |
| `S7_FAULT` | Planta→PLC | BOOL | M100.5 | Sin caja disponible |

## Etapa 8 — S8 FlashTester (prueba eléctrica)

Mide Isc/Voc bajo iluminación (flash).

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S8_CMD` | PLC→Planta | DINT | MD110 | 0=none, 1=flash |
| `S8_EXEC` | PLC→Planta | BOOL | M110.0 | Dispara flash |
| `S8_DONE` | Planta→PLC | BOOL | M110.1 | Medición completada |
| `S8_RUNNING` | Planta→PLC | BOOL | M110.2 | Midiendo |
| `S8_READY` | Planta→PLC | BOOL | M110.3 | Lista |
| `S8_IN_POS` | Planta→PLC | BOOL | M110.4 | Panel en tester |
| `S8_IRRADIANCE` | PLC→Planta | REAL | MD114 | Irradiancia W/m² |
| `S8_POWER_PV` | Planta→PLC | REAL | MD118 | Potencia pico medida (Wp) |
| `S8_PASS` | Planta→PLC | BOOL | M110.5 | 1 = pasa, 0 = rechazo |
| `S8_GRADE` | Planta→PLC | DINT | MD122 | Bin de potencia (1–5) |

## Etapa 9 — S9 Etiquetadora

Etiqueta el panel con serial/QR.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S9_CMD` | PLC→Planta | DINT | MD130 | 0=none, 1=etiquetar |
| `S9_EXEC` | PLC→Planta | BOOL | M130.0 | Dispara |
| `S9_DONE` | Planta→PLC | BOOL | M130.1 | Etiqueta aplicada |
| `S9_RUNNING` | Planta→PLC | BOOL | M130.2 | Etiquetando |
| `S9_READY` | Planta→PLC | BOOL | M130.3 | Lista |
| `S9_IN_POS` | Planta→PLC | BOOL | M130.4 | Panel presente |
| `S9_SERIAL` | Planta→PLC | DINT | MD134 | Último serial asignado |
| `S9_FAULT` | Planta→PLC | BOOL | M130.5 | Sin etiqueta/impresora |

## Etapa 10 — S10 CamaraIR / Inspección final + Descarga

Inspección termográfica final y descarga del panel terminado.

| Tag | Dir | Tipo | Dir. S7 sug. | Descripción |
|---|---|---|---|---|
| `S10_CMD` | PLC→Planta | DINT | MD140 | 0=none, 1=inspección, 2=descargar |
| `S10_EXEC` | PLC→Planta | BOOL | M140.0 | Dispara |
| `S10_DONE` | Planta→PLC | BOOL | M140.1 | Inspección/descarga completada |
| `S10_RUNNING` | Planta→PLC | BOOL | M140.2 | Inspeccionando |
| `S10_READY` | Planta→PLC | BOOL | M140.3 | Lista |
| `S10_IN_POS` | Planta→PLC | BOOL | M140.4 | Panel presente |
| `S10_IR_TEMP_PV` | Planta→PLC | REAL | MD144 | Temp media del panel (°C) |
| `S10_IR_HOTSPOT` | Planta→PLC | BOOL | M140.5 | Hotspot detectado (rechazo) |
| `S10_SHIPPED` | Planta→PLC | DINT | MD148 | Paneles descargados |

---

## Direcciones y categorías

- Las direcciones S7 de la columna "Dir. S7 sug." son una **sugerencia sin solapamientos**
  (bloques de 10 bytes por estación, área M). El usuario puede remapearlas libremente en el
  Comms dock; la parte solo necesita `tag_name` = dirección, `tag_group_name` = `PLCSIM`.
- Categoría de registro en `addons/scene-library/scene_library.cfg`:
  - `Vidrio`, `LaminaEVA`, `Backsheet`, `JunctionBox`, `PanelProducto` → **Products**
  - `CeldaSpawner`, `Laminadora`, `Horno` → **Equipment**
- Productos: RigidBody3D en layer 10, mask 15 (igual que `Box`/`Celda`); detectables por
  sensores con mask hacia layer 10.
