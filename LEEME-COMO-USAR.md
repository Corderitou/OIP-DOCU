# OIP v4.7 — Guía de uso para nuevo usuario

Proyecto de simulación industrial (línea de ensamblaje demo) sobre un **fork custom de Godot 4.7**.
Este paquete incluye TODO lo necesario: editor, proyecto, modelos, documentación y el flujo Node-RED de control.

---

## 1. Estructura del paquete

```
aa\
├── LEEME-COMO-USAR.md              ← esta guía
└── OIP_v4.7-rc1\
    ├── OIP_v4.7-rc1.exe            ← el EDITOR (fork custom de Godot, NO usar un Godot oficial)
    └── default_project\
        └── default_project\        ← el proyecto
            ├── project.godot       ← archivo del proyecto (abrir este)
            ├── Simulation.tscn     ← escena demo de la línea
            ├── src\  parts\  addons\  assets\
            ├── docs\               ← documentación técnica (22 documentos)
            ├── node-red\           ← servidor OPC UA + flujo de control desplegado
            ├── oip_data\           ← config de comms (grupo PLCSIM)
            └── AGENTS.md           ← guía de desarrollo (reglas internas del proyecto)
```

**IMPORTANTE**: NO cambiar la estructura de carpetas. El editor se llama desde el proyecto
mediante la ruta relativa `..\..\OIP_v4.7-rc1.exe`; si mueves carpetas, se rompe.

---

## 2. Requisitos

- Windows 10/11 x64.
- **Node.js LTS** (solo necesario para Node-RED, sección 4): https://nodejs.org
- Sin instalación adicional: el editor es portable, el paquete incluye todo lo demás.

---

## 3. Primer arranque (simulación offline, sin comms)

1. Ejecuta `OIP_v4.7-rc1\OIP_v4.7-rc1.exe`.
2. En el Project Manager pulsa **Import** y selecciona
   `OIP_v4.7-rc1\default_project\default_project\project.godot` (o ábrelo de la lista).
3. **El primer import tarda VARIOS MINUTOS y parece colgado: es normal, espera.**
   (Las siguientes aperturas son rápidas porque se reutiliza la caché `.godot/`.)
4. Abre la escena `Simulation.tscn` y pulsa **F5** (o el botón Play) para correr la demo.
5. La escena puede auto-iniciar la simulación al abrir/lanzar; usa los controles del
   editor para parar/reiniciar si hace falta.

---

## 4. Node-RED (control de la línea por OPC UA)

La línea demo está gobernada por un flujo Node-RED que actúa como **servidor OPC UA**
(`opc.tcp://localhost:4840`). El simulador lee/escribe sus tags ahí (grupo `PLCSIM`,
config en `oip_data/tag_groups.cfg`).

1. Abre una terminal en `OIP_v4.7-rc1\default_project\default_project\node-red\`.
2. Instala dependencias (solo la primera vez):
   ```
   npm install
   ```
3. Arranca el servidor:
   ```
   npm start
   ```
4. Abre la UI en http://localhost:1880 — el flujo ya viene cargado (`flows.json`).
5. **Arranca Node-RED ANTES de iniciar la simulación en el editor**, si no, el simulador
   no encontrará el servidor OPC UA y los tags no responderán.

El ciclo demo: sensores de cinta disparan los pedales de la línea; el Horno y la
Máquina1 se controlan desde el flujo; el robot 6 ejes recoge lotes de 6 unidades.

---

## 5. Documentación incluida

| Documento | Contenido |
|---|---|
| `README.md` (raíz del proyecto) | Introducción al framework OIP, protocolos soportados, primeros pasos |
| `docs/index.md` | Índice de TODA la documentación técnica |
| `docs/tutorial-getting-started.md` | Tutorial inicial de uso |
| `docs/tutorial-communication-setup.md` | Cómo configurar comunicaciones |
| `docs/howto-opc-ua-configuration.md` | Configuración OPC UA |
| `docs/howto-node-red-export.md` | Export/trabajo con Node-RED |
| `docs/howto-six-axis-robot-grid.md` | Robot 6 ejes y grilla de waypoints |
| `docs/howto-import-models.md` | Importar modelos 3D (usar .glb, NO .fbx/.blend) |
| `docs/reference-parts-catalog.md` | Catálogo de partes disponibles |
| `docs/reference-shortcuts.md` | Atajos de teclado del editor |
| `docs/plcsim-io-map.md` | Mapa de E/S del PLC simulado |
| `AGENTS.md` | Reglas de desarrollo (crear partes, comms, validación headless) |
| `.claude/skills/` | Skills con contexto profundo: `oip`, `oip-nodered-comms`, `oip-proyecto` |

Para explorar todo: empieza por `docs/index.md`.

---

## 6. Advertencias importantes

- **NO borres la carpeta `.godot/`**: la reimportación desde cero tarda muchísimo.
- **Cierra el editor correctamente** (File → Quit). Si el proceso `OIP_v4.7-rc1.exe`
  queda zombie, bloquea el DLL de comms y los siguientes arranques fallan con
  `Can't open GDExtension dynamic library`. Solución: matar el proceso en el
  Administrador de tareas y reabrir.
- **NO ejecutes `trim.py`**: borra modelos .glb que la escena necesita.
- Comms: si ves errores `Failed to write tag` seguidos de un stop de simulación,
  dale play nuevamente.
- La licencia del framework es MIT (ver `LICENSE`).

---

## 7. Verificación rápida de que todo funciona

1. `npm start` en `node-red/` → UI accesible en http://localhost:1880.
2. Abrir el proyecto en el editor → abrir `Simulation.tscn` → F5.
3. En la UI de Node-RED deberías ver los tags del grupo `PLCSIM` moverse
   (sensores, cintas, robot) cuando la simulación corre.

¿Problemas? Revisa `docs/tutorial-communication-setup.md` y `AGENTS.md`.
