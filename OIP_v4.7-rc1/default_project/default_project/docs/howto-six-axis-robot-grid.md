# SixAxisRobot: Grilla de Deposito

## Alcance

Esta guia documenta la configuracion final del `SixAxisRobot` de
`Simulation.tscn`. El robot recoge un lote y lo deposita en ocho posiciones
rectangulares, `Point12` a `Point19`. La orientacion final esperada del objeto
es:

```text
Euler X = 0 grados
Euler Y = 90 grados
Euler Z = 0 grados
```

El objetivo no es solamente que la copa apunte hacia abajo. La cabeza de
succion es rectangular, por lo que tambien deben coincidir sus ejes X, Y y Z.
Usar solamente la posicion del centro de la copa deja libre la rotacion de la
cabeza y produce lotes girados.

## Escenas

### Simulation.tscn

Es la escena productiva y la escena principal del proyecto. El robot esta en
el nodo `Simulation/SixAxisRobot`. Sus waypoints de grilla son los que usa la
secuencia de control de la linea.

### TestRobotGrid.tscn

Es una escena auxiliar independiente ubicada en `parts/TestRobotGrid.tscn`.
Contiene ocho `TestBlock`, una camara voladora y una secuencia automatica de
recogida y deposito. Sus coordenadas de pickup son propias de esa escena; no
se deben copiar a `Simulation.tscn`, porque el `Point1` de Simulation tiene
otra configuracion.

Al ejecutar la escena auxiliar, `parts/TestRobotGrid.gd`:

1. Espera a que el robot termine de moverse.
2. Activa el vacuum y recoge el bloque mas cercano.
3. Espera a que termine el movimiento al destino.
4. Desactiva el vacuum y congela el bloque en el lugar de prueba.
5. Imprime posicion, Euler y estado del bloque.

Los `TestBlock` tienen tamaño `0.25 x 0.04 x 0.35` metros y
`gravity_scale = 0`, por lo que permanecen suspendidos despues de ser
liberados.

## Point1 de recogida

El `Point1` final de `Simulation.tscn` conserva la posicion necesaria para
recoger el objeto, pero corrige la orientacion del cabezal:

```text
[29.82666699, -2.90000000, 101.10000000,
 0.00000053, 81.79999916, 29.82665835]
```

La base ortonormal de `VacuumArea` en este punto queda alineada como:

```text
X = -X mundial
Y = -Y mundial  (direccion de succion hacia abajo)
Z =  Z mundial
```

Esto evita inclinacion y torsion del cabezal al tomar el objeto. No se debe
usar Euler `(0, 90, 0)` directamente para la copa de recogida: esa base no
representa una succion hacia abajo en esta cadena de transforms.

## Waypoints de grilla

Los valores siguientes son los waypoints finales de `Simulation.tscn`.
Cada array contiene `[J1, J2, J3, J4, J5, J6]` en grados. Regenerados el
2026-08-27 con `test_solve_grid_v47.gd` (LM de pose completa sobre los seis
joints): columnas `1.1 x unit_spacing = 0.1892 m` y filas
`6.3 x unit_spacing = 1.0836 m`, centro medido en
`(-8.9302, -12.7997)`.

| Waypoint | J1 | J2 | J3 | J4 | J5 | J6 |
|---|---:|---:|---:|---:|---:|---:|
| Point12 | 145.08504364 | -26.10700473 | 128.41104352 | -180 | -77.69596544 | -124.91497118 |
| Point13 | 150.73923546 | -15.04204045 | 121.67818285 | ~180 | -73.36385988 | -119.26077899 |
| Point14 | 154.92473791 | -4.26330351 | 112.91660103 | -180 | -71.34670350 | -115.07526980 |
| Point15 | 158.11616827 | 6.25368399 | 102.16041182 | -180 | -71.58590430 | -111.88385284 |
| Point16 | -144.41651682 | -26.12813430 | 128.42183301 | ~0 | 77.70630363 | 125.58348491 |
| Point17 | -150.16953682 | -15.05864555 | 121.68995648 | -180 | -73.36869227 | -60.16952902 |
| Point18 | -154.43134562 | -4.27678133 | 112.92897801 | ~0 | 71.34780471 | 115.56866262 |
| Point19 | -157.68263816 | 6.24223364 | 102.17330888 | ~0 | 71.58445562 | 112.31736899 |

La fila `Point12` a `Point15` usa la rama positiva de J1. La fila
`Point16` a `Point19` usa la rama negativa de J1. La separacion de la grilla
se conserva en la posicion cartesiana y no debe reemplazarse por una
separacion angular uniforme. Verificado tras guardar la escena: los tooltips
de los ocho waypoints miden separaciones exactas de `0.1892 m` entre
columnas y `1.0836 m` entre filas.

El J6 de `Point15` sale del solver como `248.1161471641` deg (misma pose
modulo 360); en la escena se normalizo a `-111.8838528359` deg restando 360
para que la interpolacion desde `Point14` no de casi una vuelta completa.
Al regenerar la grilla conviene revisar ese salto antes de pegar valores.

OJO (2026-08-26): la copa (`VacuumArea`) esta descentrada respecto de los
ejes de muneca: mover J4 ±45 grados corre el tooltip ~0.20 m y J5 ±20
grados ~0.09 m; solo J6 es neutral. Por eso orientacion y posicion NUNCA se
resuelven por etapas separadas ni con el CCD nativo (`solve_ik_pose` queda
atrapado en minimos locales); se usa el LM de seis joints de
`test_solve_grid_v47.gd`.

## Papel de cada articulacion

Los seis valores se expresan en grados y se aplican en este orden de la cadena
cinematica:

| Articulacion | Eje en el robot | Funcion en esta grilla |
|---|---|---|
| J1 | Y | Gira la base y selecciona la rama trasera. La primera fila usa valores positivos cercanos a 180 grados; la segunda usa valores negativos cercanos a -180 grados. |
| J2 | Z | Ajusta el hombro para llevar el centro de la copa a la altura y profundidad de la celda. |
| J3 | Z | Ajusta el codo y completa el alcance cartesiano junto con J2. |
| J4 | Y | Giro de la muneca. Corrige la orientacion alrededor del eje de la muneca. |
| J5 | Z | Inclinacion de la muneca. Mantiene la cara de succion perpendicular al plano del objeto. |
| J6 | Y | Giro final de la herramienta. Corrige la orientacion del rectangulo del EOAT, que no se puede validar mirando solo el centro de la copa. |

La posicion no se obtiene haciendo incrementos angulares iguales. El
procedimiento es:

1. Se define primero el rectangulo cartesiano usando el centro de cada grupo
   de producto. La referencia es `ProductUnit.unit_spacing`, no el tamaño de
   la forma de colision de una celda. En esta calibracion (2026-08-27),
   `unit_spacing = 0.172 m`, la separacion entre columnas es `1.1 x 0.172 =
   0.1892 m` y la separacion entre filas es `6.3 x 0.172 = 1.0836 m`. El
   centro del rectangulo se mide desde los tooltips actuales, no con una
   constante hardcodeada.
2. Se elige una rama de J1 para cada fila: valores positivos para la primera
   fila y negativos para la segunda. Esto evita que el robot deje las piezas
   en una trayectoria radial o en una circunferencia.
3. Se resuelven J1, J2 y J3 para llevar el `VacuumArea` a la posicion de cada
   centro. En los puntos finales, J2 y J3 se repiten entre filas porque ambas
   filas comparten las mismas posiciones de columna; J1 cambia de rama para
   separar las filas en el espacio trasero.
4. Se calcula la orientacion de recogida de Point1 y se mantienen sus tres
   ejes alineados. Luego se resuelven J4, J5 y J6 para cada destino, sin
   cambiar J1, J2 y J3 de ese destino.
5. Se verifica la orientacion resultante del objeto, no solamente la de la
   copa. El resultado debe ser `(0, 90, 0)` en Euler y los ejes X, Y y Z del
   rectangulo deben coincidir.

Por eso no existe una regla como "sumar cinco grados a J6 por cada columna".
J4, J5 y J6 dependen de J1, J2, J3 y de las transformaciones geometricas
locales del `EOAT`, `ToolPivot` y `VacuumArea`. Los valores finales se obtienen
con el Jacobiano numerico y se guardan por waypoint.

### Configuracion de Point1

En `Simulation.tscn`, Point1 fija la postura de recogida:

```text
J1 = 29.82666699
J2 = -2.90000000
J3 = 101.10000000
J4 = 0.00000053
J5 = 81.79999916
J6 = 29.82665835
```

J1, J2 y J3 ponen la copa en la posicion de recogida. J4, J5 y J6 dejan la
cara rectangular horizontal, con la succion hacia abajo y sin inclinacion.
Esta referencia es obligatoria: si se cambia Point1, hay que recalcular
Point12 a Point19 porque la orientacion relativa guardada al recoger tambien
cambia.

### Configuracion de los destinos

En Point12 a Point19, J1, J2 y J3 determinan la posicion del centro de cada
grupo. J4, J5 y J6 son la compensacion de orientacion. El solver no intenta
forzar la misma terna de muñeca en todos los puntos; calcula la terna que
compensa la rama de J1, la postura del brazo y los offsets propios de la
geometria del EOAT.

El hecho de que varios valores de J4 queden cercanos a cero no significa que
J4 se pueda eliminar. Forma parte de la solucion de pose y debe permanecer en
el array para que el resultado siga siendo reproducible si cambia cualquier
otra articulacion.

## Como se obtuvieron

Al recoger un objeto, `SixAxisRobot` guarda la orientacion relativa entre el
objeto y `VacuumArea`:

```text
held_object_basis = pickup_cup_basis.inverse() * object_basis
```

Al liberar, aplica esa relacion en el destino:

```text
object_basis_final = deposit_cup_basis * held_object_basis
```

Como el `WovenBatch` entra con base identidad, para obtener el objetivo
`(0, 90, 0)` se resuelve la copa de cada destino con:

```text
deposit_cup_basis = target_object_basis * pickup_cup_basis
```

El solver activo es `test_solve_grid_v47.gd`: LM de minimos cuadrados sobre
los SEIS joints con residuo mixto posicion+orientacion (peso de orientacion
`0.18`), sembrado por rama de J1 y restarts globales para la ultima columna.
Regenera la grilla completa, imprime `READY TO PASTE` y mide las
separaciones resultantes. Los waypoints se guardan con ocho decimales o
mas; redondearlos a cuatro decimales puede volver a introducir errores
visibles de centesimas de grado.

## Verificacion

### Validar serializacion de Simulation

Este test no inicia la linea ni modifica el editor:

```powershell
& "..\..\OIP_v4.7-rc1.exe" --headless --path . --script res://test_validate_grid_wp.gd
```

Resultado esperado:

```text
waypoints (11):
VALID_OK
```

### Ejecutar la prueba completa de bloques

`test_run_grid.gd` instancia `TestRobotGrid`, espera cada tween de movimiento
y termina cuando los ocho depositos concluyen:

```powershell
& "..\..\OIP_v4.7-rc1.exe" --headless --path . --script res://test_run_grid.gd
```

El resumen debe mostrar los ocho bloques con rotacion cercana a:

```text
rot=(0.000000, 90.000000, 0.000000) | OK
```

La diferencia residual es solamente la precision numerica de transforms de
Godot. El criterio del test es estricto: cada eje debe tener un error menor
que `0.001` grados.

### Prueba visual

Para abrir la escena auxiliar desde el editor, usar `F5` solo si se cambio
temporalmente la escena principal, o abrir `parts/TestRobotGrid.tscn` y usar
**Run Current Scene**. La camara voladora permite inspeccionar el robot:

| Control | Accion |
|---|---|
| W A S D | Mover la camara |
| Q / E | Bajar / subir |
| Mouse | Mirar |
| Shift | Acelerar |
| Escape | Liberar el mouse |

La escena principal permanente es `Simulation.tscn`.

## Archivos involucrados

| Archivo | Responsabilidad |
|---|---|
| `Simulation.tscn` | Robot productivo, Point1 y Point12-Point19 finales |
| `project.godot` | Define `Simulation.tscn` como escena principal |
| `parts/TestRobotGrid.tscn` | Fixture visual con robot, bloques, camara y luz |
| `parts/TestRobotGrid.gd` | Secuencia de prueba y resumen de transforms |
| `parts/FlyCamera.gd` | Camara WASD con vuelo y mouse look |
| `test_wrist_optimize.gd` | Recalculo historico de muñeca (solo J4-J6) |
| `test_solve_grid_v47.gd` | Regenerador activo de la grilla completa (LM 6 joints) |
| `test_probe_wrist_sensitivity.gd` | Diagnostico de acoplamiento tooltip-muñeca |
| `test_validate_grid_wp.gd` | Validacion de waypoints serializados |
| `test_run_grid.gd` | Ejecucion headless end-to-end de TestRobotGrid |

## Precauciones

- No usar el `Point1` de `TestRobotGrid` para recalcular `Simulation`.
- No validar solamente `cupYdotUP` o el centro del cabezal; comprobar X, Y y Z.
- No redondear los arrays de waypoints a cuatro decimales.
- No cambiar los waypoints durante una simulacion en ejecucion.
- Si un comando headless se cuelga, detener solamente el proceso de prueba
  despues de confirmar que no es el editor activo.
- Mantener `Simulation.tscn` como escena principal despues de terminar una
  prueba visual.
