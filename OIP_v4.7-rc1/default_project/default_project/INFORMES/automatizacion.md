# 6. Descripcion del proyecto de automatizacion

## 6.1. Alcance de la automatizacion

El proyecto considera una fabrica dedicada exclusivamente al ensamblaje de modulos fotovoltaicos. No se contempla la fabricacion de celdas solares, por lo que las celdas y los demas componentes ingresan a la planta como materiales comprados a proveedores nacionales o internacionales.

La automatizacion propuesta tiene como finalidad coordinar el flujo de materiales, controlar las estaciones de ensamblaje, reducir la intervencion manual en las operaciones repetitivas, asegurar la trazabilidad de los productos y detectar oportunamente las condiciones que puedan afectar la seguridad o la calidad del modulo.

En esta etapa de ingenieria conceptual no se fija una capacidad de produccion, una superficie definitiva ni una tecnologia especifica de celda o modulo. La seleccion final de equipos, setpoints, niveles de produccion y proveedores debera realizarse durante la ingenieria basica y de detalle.

## 6.2. Descripcion general del proceso

El proceso comienza con la recepcion e inspeccion de los componentes. Las celdas solares, el vidrio, los materiales encapsulantes, el backsheet o segundo vidrio, las cintas conductoras, los marcos y las cajas de conexion se identifican y almacenan de acuerdo con sus condiciones de manejo. La automatizacion registra el ingreso, el lote y la disponibilidad de cada material antes de liberarlo para produccion.

La secuencia conceptual del ensamblaje es la siguiente:

1. **Recepcion y almacenamiento:** se reciben los componentes, se verifican sus cantidades y condiciones generales, y se asigna una identificacion de lote.
2. **Preparacion de materiales:** se entregan a la linea las celdas, cintas conductoras, vidrio y materiales encapsulantes requeridos para la orden de produccion.
3. **Alimentacion de celdas:** un sistema automatico posiciona las celdas sobre la linea. Los sensores de presencia confirman que la posicion de toma este disponible y que no exista acumulacion de material.
4. **Interconexion de celdas:** una maquina tabber/stringer coloca y suelda las cintas conductoras sobre las celdas, formando strings o conjuntos de celdas interconectadas.
5. **Inspeccion de strings:** se verifica visualmente y, segun la tecnologia seleccionada, mediante inspeccion electrica o electroluminiscente, que las interconexiones no presenten defectos evidentes antes de continuar.
6. **Lay-up o conformacion del modulo:** se posicionan el vidrio, el material encapsulante, los strings y la cubierta posterior en el orden definido por la receta del modulo. La posicion, separacion y orientacion de cada elemento deben ser controladas.
7. **Interconexion y preparacion termica:** se completan las conexiones entre strings y se traslada el conjunto a la estacion termica. Las condiciones de temperatura, tiempo y, cuando corresponda, vacio se controlan desde el sistema de automatizacion.
8. **Laminacion:** el conjunto se somete a un ciclo termico y de vacio para consolidar las capas del modulo. El ciclo solo se habilita cuando el producto esta presente, la maquina esta cerrada y las variables de seguridad se encuentran dentro de sus rangos permitidos.
9. **Terminacion mecanica:** se retira el excedente de material, se instala el marco y se realiza el sellado o curado requerido por la tecnologia seleccionada.
10. **Instalacion de caja de conexion y etiquetado:** se instala la caja de conexion, se verifican sus conexiones y se incorpora la identificacion del modulo para mantener la trazabilidad.
11. **Pruebas de calidad:** se realizan las inspecciones visuales y las pruebas electricas definidas para la aceptacion del producto, tales como electroluminiscencia, aislamiento y caracterizacion electrica, cuando correspondan.
12. **Clasificacion, embalaje y despacho:** los modulos aprobados se clasifican, embalan y trasladan al almacenamiento de productos terminados. Los modulos rechazados se separan y se envian a retrabajo o disposicion segun el procedimiento de calidad.

Las operaciones de fabricacion de obleas y celdas quedan fuera del alcance. El proyecto se concentra en el manejo de componentes y en el ensamblaje del modulo fotovoltaico terminado.

## 6.3. Representacion del proceso en Open Industry Project

La simulacion desarrollada en Open Industry Project representa una celda automatizada de la linea, no la totalidad de la fabrica. Su objetivo es demostrar la coordinacion entre sensores, transportadores, alimentadores, robots y estaciones de proceso.

La correspondencia entre la simulacion y el proceso conceptual es la siguiente:

| Elemento en OIP | Funcion representada |
|---|---|
| `CeldaSpawner` S1 | Alimentacion automatica de celdas a la linea |
| `PlacerSpawner` S2 | Alimentacion de elementos auxiliares de manipulacion |
| `BeltConveyor`, `BeltConveyor2` y `BeltConveyor3` | Transporte continuo de materiales entre estaciones |
| `SensorCeldas` y `SensorPlacers` | Deteccion de disponibilidad y posicion de material |
| `Gantry` y `Gantry2` | Manipulacion cartesiana mediante ventosa |
| `Dispenser` y `Stringer` dentro de `Maquina1` | Dispensing, tensionado, corte y liberacion de tiras conductoras |
| `IndexingBeltConveyor3` | Avance indexado de la unidad de ensamblaje |
| `SandwichStation` | Formacion de una unidad compuesta a partir de celdas, placers y tiras |
| `Horno` | Representacion de una etapa termica controlada |
| `PlacerExtractor` | Retiro de elementos auxiliares del producto ensamblado |
| `SixAxisRobot` y `6axisDiffuseSensor` | Manipulacion de lotes y posicionamiento en puntos programados |

Durante la ejecucion, el flujo de control realiza las siguientes acciones:

1. En el estado normal, Node-RED habilita los alimentadores y establece la velocidad de las cintas cuando los sensores de toma se encuentran libres.
2. Cuando `SensorCeldas` detecta una celda, la rama correspondiente se detiene y `Gantry1` recibe un comando de movimiento. El movimiento utiliza las señales `Command`, `Execute`, `Done` y `Vacuum`.
3. `Gantry1` toma la celda, la traslada y la libera en la zona de ensamblaje. Luego se genera un pulso de avance del transportador indexado.
4. `Maquina1` recibe las posiciones de sus ejes y las ordenes de corte y liberacion. De esta forma, el `Dispenser` y el `Stringer` preparan y colocan las tiras conductoras.
5. El `Horno` puede ejecutar su ciclo termico en paralelo con la secuencia de transporte. El ciclo se inicia mediante una orden `CMD/EXEC` y utiliza las variables de setpoint, variable manipulada y variable de proceso.
6. El flujo espera que la rama de placers este disponible y que el transportador indexado termine su movimiento. Posteriormente, `Gantry2` toma el elemento auxiliar y completa la secuencia de manipulacion.
7. `SandwichStation` identifica la presencia conjunta de una celda, un placer y las tiras requeridas. Cuando el conjunto esta completo, lo convierte en una unidad de producto y lo desplaza con la velocidad de la cinta.
8. `PlacerExtractor` retira los placers que forman parte del ensamblaje y los reemplaza por placers fisicos que continuan por la linea.
9. El robot de seis ejes puede trabajar con lotes de seis unidades. Una deteccion del sensor inicia un ciclo de toma, traslado y deposito en los puntos programados.

La simulacion actual demuestra principalmente el control secuencial y la coordinacion de movimientos. La laminacion completa, las pruebas finales, el framing, el etiquetado y el embalaje se mantienen como etapas de la propuesta conceptual y deberan desarrollarse posteriormente en la simulacion y en la ingenieria basica.

## 6.4. Arquitectura de automatizacion

La arquitectura propuesta se divide en tres niveles:

### Nivel de campo

Incluye sensores de presencia, posicion, temperatura, vacio, presion, corriente y calidad. Tambien considera motores con variador de frecuencia, servomotores, actuadores neumaticos, bombas de vacio, calefactores, ventosas y actuadores de las estaciones de ensamblaje.

Los sensores de presencia habilitan o detienen el movimiento de los materiales. Los sensores analogicos entregan las variables necesarias para regular la temperatura, el vacio, la velocidad y la presion. Los actuadores deben incorporar realimentacion de estado cuando la funcion lo requiera.

### Nivel de control

En la planta real, un PLC de gama media o alta ejecutara la secuencia, los enclavamientos, los lazos de control y la comunicacion con los equipos. El PLC recibira las señales de campo, verificara los permisos de marcha y enviara las ordenes a transportadores, robots, estaciones termicas y sistemas de manipulacion.

En la simulacion OIP, esta funcion se representa mediante Node-RED y un servidor OPC UA. Las partes del simulador intercambian variables con el grupo `PLCSIM` utilizando NodeId del tipo `ns=2;s=Nombre`. Node-RED lee los sensores y estados de la simulacion, ejecuta la maquina de estados y escribe las ordenes de movimiento y proceso.

La logica de la simulacion se ejecuta con un ciclo de control de referencia de 50 ms en Node-RED y un sondeo de comunicaciones del simulador configurado en aproximadamente 30 ms. Estos valores son propios del entorno de demostracion y no constituyen aun una especificacion definitiva para la planta real.

### Nivel de supervision y gestion

Un sistema SCADA permitira visualizar el estado de la linea, las variables de proceso, las alarmas, los modos de operacion y los indicadores de produccion. La arquitectura tambien considera una base de datos para almacenar lotes, resultados de inspeccion, tiempos de ciclo, fallas y consumos.

La comunicacion IIoT permitira enviar informacion seleccionada a una plataforma de supervision remota. El acceso remoto debera estar protegido mediante autenticacion, segmentacion de red y permisos diferenciados para operacion, mantenimiento e ingenieria.

## 6.5. Filosofia de control

### 6.5.1. Objetivos del control

Los objetivos de la filosofia de control son:

- Mantener un flujo ordenado y continuo de componentes entre las estaciones.
- Ejecutar las operaciones repetitivas con posiciones y secuencias reproducibles.
- Mantener las variables termicas, de vacio, velocidad y sujecion dentro de los limites definidos por la receta.
- Evitar movimientos cuando no se cumplan las condiciones de seguridad o disponibilidad.
- Separar automaticamente los productos que no cumplan los criterios de calidad.
- Registrar los datos necesarios para la trazabilidad de cada modulo.
- Permitir una detencion controlada y una recuperacion segura despues de una falla.

### 6.5.2. Modos de operacion

La implementacion definitiva debera considerar los siguientes modos:

- **Parada o espera:** la linea permanece energizada, pero no inicia ciclos de produccion.
- **Manual o mantenimiento:** el operador autorizado puede accionar equipos individuales bajo permisos, limites de carrera y condiciones de seguridad.
- **Semiautomatico:** el operador autoriza cada ciclo o etapa, manteniendose activos los enclavamientos.
- **Automatico:** el PLC coordina la secuencia completa a partir de las senales de los sensores y de la receta seleccionada.
- **Emergencia o defecto:** se bloquean las funciones que puedan generar un riesgo y se mantiene solamente la operacion permitida por el analisis de riesgos.

El cambio de modo no debera provocar el arranque inesperado de motores, robots, calefactores o actuadores. Toda transicion debera dejar el equipo en un estado conocido.

### 6.5.3. Lazos de control propuestos

Los siguientes lazos se proponen para cumplir los requerimientos de la asignatura y deberan ser validados con los datos de la tecnologia finalmente seleccionada:

| Lazo | Variable controlada | Variable manipulada | Estrategia |
|---|---|---|---|
| Temperatura de laminacion | Temperatura de la camara o del conjunto | Potencia de los calefactores | Control PID con limites alto y bajo |
| Vacio de laminacion | Presion absoluta o nivel de vacio | Velocidad de la bomba o apertura de una valvula | Control PI con permiso de camara cerrada |
| Transporte e indexacion | Velocidad o posicion del producto | Frecuencia del variador o posicion del servomotor | Control de velocidad y posicion coordinado con sensores |
| Sujecion del manipulador | Presion de vacio o presion de sujecion | Valvula, eyector o regulador proporcional | Control PI y alarma por perdida de sujecion |

El lazo de temperatura sera el lazo analogico principal de la propuesta. El PLC comparara la temperatura medida con el setpoint de la receta y ajustara la potencia de calefaccion mediante un controlador PID. La salida debera limitarse para evitar sobretemperatura y debera bloquearse ante perdida de sensor, apertura de la camara o activacion de una proteccion.

El lazo de vacio regulara la condicion necesaria para la laminacion. La bomba o valvula se ajustara segun la diferencia entre el vacio medido y el setpoint. Si el vacio no alcanza el valor requerido dentro del tiempo permitido, el ciclo se detendra y el producto quedara identificado para inspeccion.

El control de transporte coordinara la velocidad de las cintas con las posiciones de toma y descarga. En las estaciones de manipulacion se utilizara indexacion: el transportador avanzara una distancia definida, confirmara que termino el movimiento y habilitara el siguiente paso solamente si la zona de destino esta disponible.

El control de sujecion verificara que el manipulador tenga suficiente vacio o presion antes de iniciar un traslado. Una perdida de sujecion durante el movimiento debera generar una parada segura, una alarma y la retencion del producto en el estado que determine el analisis de riesgos.

### 6.5.4. Secuencia y permisos de marcha

La secuencia automatica se habilitara solamente si se cumplen los siguientes permisos generales:

- Parada de emergencia liberada y circuito de seguridad rearmado.
- Guardas y puertas cerradas cuando corresponda.
- Equipos de campo disponibles y sin fallas activas.
- Robots, gantries y ejes referenciados.
- Presion neumatica y vacio dentro de las condiciones minimas.
- Estaciones termicas en condiciones de iniciar el ciclo.
- Cintas y zonas de transferencia libres o en la condicion definida por la receta.
- Comunicacion valida entre el PLC, los variadores, los equipos de campo y el sistema de supervision.

Cada movimiento de robot debera tener una orden, una confirmacion de ejecucion y una confirmacion de termino. Si la confirmacion no llega dentro del tiempo establecido, se generara una alarma de tiempo excedido y se impedira el siguiente paso.

### 6.5.5. Alarmas e interbloqueos

Las alarmas principales consideradas son perdida de sensor, sobretemperatura, vacio insuficiente, perdida de sujecion, sobrecorriente, sobrecarga de motor, atasco de material, posicion no alcanzada, falta de componente, perdida de comunicacion y falla del sistema de seguridad.

Los interbloqueos deberan impedir que:

- Una cinta avance si la zona siguiente esta ocupada o bloqueada.
- Un robot se mueva si no esta referenciado o si existe una persona en su zona protegida.
- Una ventosa transporte una pieza sin confirmacion de sujecion.
- Una estacion termica inicie un ciclo sin producto presente y sin cierre confirmado.
- Un producto rechazado ingrese al embalaje de productos aprobados.
- La linea reinicie automaticamente despues de una parada de emergencia.

Las funciones de parada de emergencia y seguridad de maquinas deberan implementarse mediante el sistema de seguridad correspondiente. No se debera depender exclusivamente de la logica normal del PLC para detener una condicion peligrosa.

## 6.6. Guia GEMMA

La guia GEMMA organiza los estados de funcionamiento, parada y defecto de la linea de ensamblaje. Los estados propuestos son los siguientes.

### Bloque A1: Parada en el estado inicial

**Condicion del sistema:** la fabrica se encuentra energizada y lista para recibir una orden de produccion, pero la linea no esta ejecutando ciclos.

**Acciones de control:**

- Mantener detenidas las cintas y los transportadores indexados.
- Deshabilitar los alimentadores de celdas y elementos auxiliares.
- Mantener los robots y gantries en posicion inicial o segura.
- Mantener las ventosas, calefactores y bombas de vacio deshabilitados.
- Mantener los cabezales de las estaciones termicas en posicion superior o segura.
- Mostrar en el SCADA la disponibilidad de los equipos y las alarmas pendientes.

**Transicion:** se pasa a F1 cuando el operador solicita produccion automatica y todos los permisos de marcha estan activos. Si se detecta una condicion peligrosa, se pasa a D1.

### Bloque A2: Parada solicitada al fin del ciclo

**Condicion del sistema:** el operador solicita detener la produccion mientras la linea se encuentra en F1.

**Acciones de control:**

- Detener la alimentacion de nuevos componentes.
- Impedir el inicio de nuevos ciclos de manipulacion.
- Permitir que la operacion activa termine solo si es segura.
- Completar o cancelar de manera controlada el movimiento del transportador indexado.
- Llevar los robots y gantries a una posicion segura.
- Finalizar el ciclo termico o llevarlo a un estado seguro de acuerdo con la receta.
- Desactivar calefactores, bombas, ventosas y accionamientos que ya no sean necesarios.

**Transicion:** una vez que no existan movimientos ni ciclos peligrosos activos, el sistema vuelve a A1.

### Bloque A6: Puesta en el estado inicial

**Condicion del sistema:** estado de recuperacion posterior a una parada de emergencia o a un defecto que requirio rearme.

**Acciones de control:**

- Verificar que la causa de la falla haya sido eliminada.
- Confirmar que no existan personas en las zonas de peligro.
- Revisar la posicion de los ejes y referenciar nuevamente los equipos cuando corresponda.
- Verificar que los cabezales termicos esten arriba y que los calefactores esten desenergizados.
- Confirmar que no exista perdida de vacio, presion anormal o atasco de material.
- Separar e identificar los productos que estaban en proceso durante la falla.
- Solicitar reconocimiento manual de las alarmas y rearme del circuito de seguridad.

**Transicion:** cuando las verificaciones sean satisfactorias, se retorna a A1. Si persiste la falla, el sistema permanece bloqueado y solicita mantenimiento.

### Bloque F1: Produccion normal

**Condicion del sistema:** la linea opera en modo automatico con todos los permisos activos.

**Acciones de control:**

- Alimentar los componentes segun la orden de produccion.
- Regular la velocidad de los transportadores y ejecutar los avances indexados.
- Detener cada rama cuando el sensor confirme que el material llego a la posicion de toma.
- Coordinar la secuencia de los gantries y del robot de seis ejes mediante comandos, confirmacion de ejecucion y senal de termino.
- Ejecutar el dispensado, posicionamiento, corte y liberacion de las tiras conductoras.
- Controlar la temperatura, el vacio, la velocidad y la sujecion mediante sus respectivos lazos.
- Registrar los datos de proceso, las alarmas, los tiempos de ciclo y el resultado de las inspecciones.
- Enviar los productos aprobados a embalaje y los rechazados a retrabajo o segregacion.

**Transicion:** una orden de parada lleva a A2; una condicion peligrosa lleva a D1; una falla no critica puede llevar a D3.

### Bloque D1: Parada de emergencia

**Condicion del sistema:** se presenta una situacion que puede provocar lesiones, dano al equipo, incendio, perdida de producto o una condicion insegura.

**Acciones de control:**

- Abrir el circuito de seguridad y detener los accionamientos peligrosos mediante la funcion de seguridad correspondiente.
- Desenergizar los calefactores y bloquear el inicio de ciclos termicos.
- Detener las cintas, transportadores, robots y actuadores que representen un riesgo.
- Mantener o liberar una carga del manipulador solo de acuerdo con el estado seguro definido en el analisis de riesgos.
- Bloquear nuevos comandos de produccion y alimentacion de materiales.
- Activar las alarmas visuales y sonoras y registrar el evento en el SCADA.

**Gatilladores posibles:** accionamiento del pulsador de emergencia, apertura de una guarda, sobretemperatura critica, perdida de sujecion con riesgo de caida, sobrecorriente severa, atasco peligroso, falla del variador o perdida de una condicion de seguridad.

**Transicion:** una vez controlado el peligro, el sistema pasa a A6. No se permite retornar directamente a F1.

### Bloque D3: Produccion a pesar de los defectos

**Condicion del sistema:** se detecta una falla no critica que no permite operar en las condiciones normales, pero que puede ser gestionada sin comprometer la seguridad.

**Acciones de control:**

- Informar la falla al operador y registrar el equipo afectado.
- Reducir la velocidad o limitar la operacion a las estaciones disponibles cuando el analisis de riesgos lo permita.
- Cambiar a modo semiautomatico o manual supervisado para completar una operacion autorizada.
- Bloquear las estaciones cuya medicion sea indispensable para la calidad o la seguridad.
- Identificar y separar los productos fabricados durante la condicion degradada.
- Programar la correccion y el mantenimiento antes de retornar a la produccion normal.

Una falla en un dispositivo de seguridad, en el control de temperatura, en la confirmacion de posicion de un robot o en la sujecion de una pieza no se considerara un defecto tolerable. En esos casos, la linea debera detenerse y pasar a D1 o A6 segun corresponda.

## 6.7. Transiciones principales de la guia GEMMA

| Estado de origen | Condicion | Estado de destino |
|---|---|---|
| A1 | Orden de marcha y permisos activos | F1 |
| F1 | Solicitud normal de detencion | A2 |
| A2 | Ciclo terminado y equipos seguros | A1 |
| F1 | Falla no critica autorizada | D3 |
| F1 o D3 | Riesgo para personas, equipo o proceso | D1 |
| D1 | Peligro eliminado y rearme autorizado | A6 |
| A6 | Verificaciones satisfactorias | A1 |
| D3 | Falla corregida y producto segregado | A6 o A1 |

La guia GEMMA debera implementarse en el programa del PLC y representarse en el SCADA mediante estados visibles, alarmas y permisos. En la simulacion OIP, estos estados se representan principalmente mediante la maquina de estados de Node-RED, las senales de los sensores, las ordenes a los actuadores y las confirmaciones de termino de cada movimiento.

## 6.8. Alcance para las siguientes etapas de ingenieria

La ingenieria conceptual define la secuencia general, la arquitectura de control, los lazos propuestos y los estados GEMMA. En la ingenieria basica se deberan desarrollar, como minimo, el diagrama ISA 5.1, los diagramas de lazos ISA 5.4, el listado de entradas y salidas, la matriz causa-efecto, la seleccion del PLC, la definicion de instrumentos y la especificacion de los equipos de seguridad.

Tambien se deberan validar experimentalmente los setpoints, los tiempos de ciclo, las condiciones de aceptacion de calidad, la capacidad de almacenamiento y la coordinacion entre las estaciones. La simulacion OIP servira como apoyo para verificar la secuencia discreta y la comunicacion entre sensores, controladores y actuadores, pero no reemplaza la validacion de seguridad, calidad ni desempeno que corresponda realizar con los equipos reales.

## Referencias

- Open Industry Project. `Simulation.tscn`, `node-red/control_config.json` y documentacion de las skills `oip`, `oip-proyecto` y `oip-nodered-comms`.
- Mondragon Assembly. [Solar Automation Solutions](https://www.mondragon-assembly.com/solar-automation-solutions/).
- Mondragon Assembly. [Turnkey lines for PV module manufacturing](https://www.mondragon-assembly.com/solar-automation-solutions/turnkey-lines-for-pv-module-manufacturing/).
- Duoc UC. `INFORMES/Descripción de portafolio.md`, requerimientos de la ingeniería conceptual de automatización.
