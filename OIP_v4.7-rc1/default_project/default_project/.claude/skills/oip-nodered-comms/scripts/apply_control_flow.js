#!/usr/bin/env node
/*
 * apply_control_flow.js
 * ---------------------
 * Aplica (o actualiza) la logica de control de una linea OIP al flujo Node-RED:
 *   - anade los tags de entrada/salida al server tree del opc-ua-server
 *   - regenera oip-sim-func a partir del tree (nunca queda desfasado)
 *   - crea/actualiza el bucle de control (oip-sim-inject-loop) y la funcion
 *     de control (oip-sim-func-control: sensores -> cintas/spawners/robot)
 *   - cablea oip-sim-io (read) -> oip-sim-func-control -> oip-sim-write-io
 *
 * Es idempotente: correrlo de nuevo no duplica nodos ni variables. Ademas
 * retira del tree las variables generadas por este script que ya no estan en
 * el config (ej. tags renombrados Robot1_* -> Gantry1_*).
 *
 * Uso:
 *   node scripts/apply_control_flow.js                        # linea demo (default)
 *   node scripts/apply_control_flow.js --config node-red/control_config.json
 *   node scripts/apply_control_flow.js --flow node-red/flows.json
 *
 * Despues: corre scripts/sync_deployed_flow.ps1 y reinicia Node-RED.
 */
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
function arg(name, def) {
  const i = args.indexOf('--' + name);
  return i !== -1 && args[i + 1] ? args[i + 1] : def;
}

const FLOW_PATH = path.resolve(arg('flow', 'node-red/flows.json'));
const CONFIG_PATH = arg('config', null);

// Config por defecto: linea demo (3 cintas + spawner S1 + pausa por Sensor1).
// Robot: null = el flujo NO controla el robot (solo cintas + spawners).
const DEFAULT_CONFIG = {
  inputs: [
    { name: 'Sensor1', nodeId: 'ns=2;s=Sensor1', type: 'Boolean' }
  ],
  pauseSensor: 'Sensor1', // sensor de pausa: detiene la linea holdMs ms
  holdMs: 2000,
  belts: {
    speed: 0.5,
    items: [
      { name: 'BeltConveyor_Speed', path: 'ns=2;s=BeltConveyor_Speed', type: 'Float' },
      { name: 'BeltConveyor2_Speed', path: 'ns=2;s=BeltConveyor2_Speed', type: 'Float' },
      { name: 'BeltConveyor3_Speed', path: 'ns=2;s=BeltConveyor3_Speed', type: 'Float' }
    ]
  },
  spawners: [
    {
      name: 'S1',
      rate: 60,
      autoEnable: { name: 'S1_AUTO_ENABLE', path: 'ns=2;s=S1_AUTO_ENABLE', type: 'Boolean' },
      rateTag: { name: 'S1_RATE', path: 'ns=2;s=S1_RATE', type: 'Float' }
    }
  ],
  robot: null,
  indexingBelts: []
};

const cfg = CONFIG_PATH
  ? JSON.parse(fs.readFileSync(path.resolve(CONFIG_PATH), 'utf8'))
  : DEFAULT_CONFIG;

// Normaliza spawners: acepta `spawners` (array) y `spawner` (legacy, singular).
const spawners = cfg.spawners || (cfg.spawner ? [cfg.spawner] : []);

// Normaliza grupos de cintas. El formato antiguo con `belts.items` sigue siendo
// valido y se trata como un unico grupo.
const beltGroups = (cfg.belts.groups || [{
  name: 'all',
  speed: cfg.belts.speed,
  items: cfg.belts.items || []
}]).map((group, index) => ({
  name: group.name || ('group' + index),
  speed: Number(group.speed !== undefined ? group.speed : cfg.belts.speed),
  items: group.items || []
}));

// Una alimentacion asocia sensor, grupo de cintas y spawners. La asociacion
// permite que una rama continue funcionando mientras la otra esta ocupada.
const feedCfg = (cfg.feeds || []).map(feed => ({
  name: feed.name,
  sensor: feed.sensor,
  beltGroup: feed.beltGroup,
  spawners: (feed.spawners || [])
    .map(name => spawners.findIndex(s => s.name === name))
    .filter(index => index >= 0)
}));

// Normaliza robots: acepta `robots` (array) y `robot` (legacy, singular).
// Cada robot: {name?, command, execute, done, vacuum, sequence|wps, ...}.
const robotList = cfg.robots || (cfg.robot ? [cfg.robot] : []);
const directSixAxisIndex = robotList.findIndex(r =>
  (r.name || '') === '6axisRobot' && (r.robotSensor || cfg.robotSensor) === '6axisSensor1');

// Maquina1 (opcional): secuencia Z -> release -> cut que corre en paralelo al
// ultimo robot tras el pulso del indexing belt. Debe terminar antes de que el
// ultimo robot suelte (vacuum OFF). Config: {z, release, cut, zMoves[], moveMs, pulseMs}.
const maquina = cfg.maquina || null;
const hasMaquina = !!maquina;

// Maquinas termicas (MaquinaTermica, protocolo de estacion + modelo PID):
// cada una genera los tags de estacion que la parte registra en OIPComms y
// que deben existir en el tree del server o el simulador aborta.
// Config: [{name, prefix?, setpoint?, mv?, pv?, cycleTime?}].
const machines = (cfg.machines || []).map(m => ({
  name: m.name,
  prefix: m.prefix || m.name,
  setpoint: m.setpoint || (m.prefix || m.name) + '_SETPOINT',
  mv: m.mv || (m.prefix || m.name) + '_MV',
  pv: m.pv || (m.prefix || m.name) + '_PV',
  cycleTime: m.cycleTime || (m.prefix || m.name) + '_CYCLE_TIME'
}));
const hasMachines = machines.length > 0;

// Horno (MaquinaTermica): handshake de estacion disparado por cada paso del
// indexing belt. Fire-and-forget paralelo, un ciclo por paso.
const horno = cfg.horno || null;
const hasHorno = !!horno;

// ---------- helpers ----------
function loadFlow(p) {
  if (!fs.existsSync(p)) throw new Error('Flujo no encontrado: ' + p);
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}
function find(flow, id) {
  return flow.find(n => n.id === id);
}
function fail(id) {
  throw new Error('Nodo "' + id + '" no encontrado en ' + FLOW_PATH +
    ' (¿es el template node-red/flows.json?)');
}

// ---------- 1) Server tree ----------
const flow = loadFlow(FLOW_PATH);
const server = find(flow, 'oip-sim-server'); if (!server) fail('oip-sim-server');
const tree = JSON.parse(server.tree);
const vars = tree.folders[0].variables;

// Lista de variables a garantizar: entradas + cintas + spawners + robot + indexing belts.
const desired = [];
for (const inp of cfg.inputs) {
  desired.push({ name: inp.name, nodeId: inp.nodeId, type: inp.type || 'Boolean' });
}
for (const group of beltGroups) {
  for (const b of group.items) {
    desired.push({ name: b.name, nodeId: b.path, type: b.type || 'Float' });
  }
}
for (const s of spawners) {
  // Tags de estacion (protocolo Maquina: <PREFIX>_CMD/EXEC/DONE/RUNNING/READY/COUNT).
  // El spawner (CeldaSpawner/PlacerSpawner) los registra en OIPComms, asi que
  // deben existir en el tree del server o el simulador aborta (BadNodeIdUnknown).
  const PREFIX = s.name;
  desired.push(
    { name: PREFIX + '_CMD', nodeId: 'ns=2;s=' + PREFIX + '_CMD', type: 'Int32' },
    { name: PREFIX + '_EXEC', nodeId: 'ns=2;s=' + PREFIX + '_EXEC', type: 'Boolean' },
    { name: PREFIX + '_DONE', nodeId: 'ns=2;s=' + PREFIX + '_DONE', type: 'Boolean' },
    { name: PREFIX + '_RUNNING', nodeId: 'ns=2;s=' + PREFIX + '_RUNNING', type: 'Boolean' },
    { name: PREFIX + '_READY', nodeId: 'ns=2;s=' + PREFIX + '_READY', type: 'Boolean' },
    { name: PREFIX + '_COUNT', nodeId: 'ns=2;s=' + PREFIX + '_COUNT', type: 'Int32' }
  );
  desired.push({ name: s.autoEnable.name, nodeId: s.autoEnable.path, type: 'Boolean' });
  desired.push({ name: s.rateTag.name, nodeId: s.rateTag.path, type: 'Float' });
}
if (cfg.robot && !Array.isArray(cfg.robots)) {
  desired.push(
    { name: cfg.robot.command.name, nodeId: cfg.robot.command.path, type: cfg.robot.command.type || 'Int16' },
    { name: cfg.robot.execute.name, nodeId: cfg.robot.execute.path, type: 'Boolean' },
    { name: cfg.robot.done.name, nodeId: cfg.robot.done.path, type: 'Boolean' },
    { name: cfg.robot.vacuum.name, nodeId: cfg.robot.vacuum.path, type: 'Boolean' }
  );
}
for (const r of robotList) {
  desired.push(
    { name: r.command.name, nodeId: r.command.path, type: r.command.type || 'Int16' },
    { name: r.execute.name, nodeId: r.execute.path, type: 'Boolean' },
    { name: r.done.name, nodeId: r.done.path, type: 'Boolean' },
    { name: r.vacuum.name, nodeId: r.vacuum.path, type: 'Boolean' }
  );
}
for (const ib of cfg.indexingBelts || []) {
  desired.push(
    { name: ib.step.name, nodeId: ib.step.path, type: ib.step.type || 'Boolean' }
  );
  if (ib.running) {
    desired.push(
      { name: ib.running.name, nodeId: ib.running.path, type: ib.running.type || 'Boolean' }
    );
  }
}
if (cfg.maquina) {
  // Maquina1: tags de Z/release/cut (+ speed opcional) -> deben existir en el
  // tree porque la parte los registra en OIPComms (regla de oro).
  desired.push(
    { name: cfg.maquina.z.name, nodeId: cfg.maquina.z.path, type: cfg.maquina.z.type || 'Float' },
    { name: cfg.maquina.release.name, nodeId: cfg.maquina.release.path, type: cfg.maquina.release.type || 'Boolean' },
    { name: cfg.maquina.cut.name, nodeId: cfg.maquina.cut.path, type: cfg.maquina.cut.type || 'Boolean' }
  );
  if (cfg.maquina.speed) {
    desired.push({ name: cfg.maquina.speed.name, nodeId: cfg.maquina.speed.path, type: cfg.maquina.speed.type || 'Float' });
  }
}
for (const m of machines) {
  // Estaciones MaquinaTermica (ej. Horno): handshake de estacion + PID analogico.
  desired.push(
    { name: m.prefix + '_CMD', nodeId: 'ns=2;s=' + m.prefix + '_CMD', type: 'Int32' },
    { name: m.prefix + '_EXEC', nodeId: 'ns=2;s=' + m.prefix + '_EXEC', type: 'Boolean' },
    { name: m.prefix + '_DONE', nodeId: 'ns=2;s=' + m.prefix + '_DONE', type: 'Boolean' },
    { name: m.prefix + '_RUNNING', nodeId: 'ns=2;s=' + m.prefix + '_RUNNING', type: 'Boolean' },
    { name: m.prefix + '_READY', nodeId: 'ns=2;s=' + m.prefix + '_READY', type: 'Boolean' },
    { name: m.prefix + '_FAULT', nodeId: 'ns=2;s=' + m.prefix + '_FAULT', type: 'Boolean' },
    { name: m.prefix + '_IN_POS', nodeId: 'ns=2;s=' + m.prefix + '_IN_POS', type: 'Boolean' },
    { name: m.setpoint, nodeId: 'ns=2;s=' + m.setpoint, type: 'Float' },
    { name: m.mv, nodeId: 'ns=2;s=' + m.mv, type: 'Float' },
    { name: m.pv, nodeId: 'ns=2;s=' + m.pv, type: 'Float' },
    { name: m.cycleTime, nodeId: 'ns=2;s=' + m.cycleTime, type: 'Float' }
  );
}
if (hasHorno) {
  // Tags del horno: handshake de estacion (CMD/EXEC/DONE/RUNNING) + PID (MV/SETPOINT).
  // Pueden solapar con machines[] (el dedup de desiredNames evita duplicados).
  desired.push(
    { name: horno.command.name, nodeId: horno.command.path, type: horno.command.type || 'Int32' },
    { name: horno.execute.name, nodeId: horno.execute.path, type: 'Boolean' },
    { name: horno.done.name, nodeId: horno.done.path, type: 'Boolean' },
    { name: horno.running.name, nodeId: horno.running.path, type: 'Boolean' },
    { name: horno.mv.name, nodeId: horno.mv.path, type: 'Float' },
    { name: horno.setpoint.name, nodeId: horno.setpoint.path, type: 'Float' }
  );
}

let added = 0;
for (const d of desired) {
  if (!vars.some(v => v.name === d.name)) {
    vars.push({
      name: d.name, type: d.type, value: 0, access: 'readwrite',
      description: d.name + ' (OIP, generado por apply_control_flow.js)',
      displayName: '', nodeId: d.nodeId, namespaceId: 2
    });
    added++;
  }
}

// Prune: retira variables generadas por este script que ya no estan en `desired`
// (conserva las anadidas a mano por el usuario).
const desiredNames = new Set(desired.map(d => d.name));
const removeNames = new Set(cfg.removeTags || []);
const kept = [];
for (const v of vars) {
  if (removeNames.has(v.name)) {
    continue;
  }
  if (!desiredNames.has(v.name) &&
      typeof v.description === 'string' &&
      v.description.includes('(OIP, generado por apply_control_flow.js)')) {
    continue;
  }
  kept.push(v);
}
const pruned = vars.length - kept.length;
vars.length = 0;
vars.push(...kept);

server.tree = JSON.stringify(tree);

// ---------- 2) oip-sim-func (regenerado desde el tree) ----------
const func = find(flow, 'oip-sim-func'); if (!func) fail('oip-sim-func');
const funcLines = vars.map(v => '  { "name": "' + v.name + '", "path": "' + v.nodeId + '" },');
func.func = 'msg.payload = [\n' + funcLines.join('\n') + '\n];\nreturn msg;';

// ---------- 3) Wiring de lectura -> control ----------
const io = find(flow, 'oip-sim-io'); if (!io) fail('oip-sim-io');
io.wires = [['oip-sim-debug', 'oip-sim-func-control']];

// ---------- 4) Nodos de control ----------
const beltGroupCfg = beltGroups.map(group => ({
  name: group.name,
  speed: group.speed,
  items: group.items.map(b => ({ name: b.name, path: b.path }))
}));
const spawnerCfg = spawners.map(s => ({
  autoEnable: { name: s.autoEnable.name, path: s.autoEnable.path },
  rate: { name: s.rateTag.name, path: s.rateTag.path },
  ready: { name: s.name + '_READY', path: 'ns=2;s=' + s.name + '_READY' }
}));
const feedRuntimeCfg = feedCfg.map(feed => ({
  name: feed.name,
  sensor: feed.sensor,
  beltGroup: feed.beltGroup,
  spawners: feed.spawners
}));

// Config de robots (plural). Se normaliza para soportar `cfg.robot` (singular, legacy).
const robotSources = robotList.length
  ? robotList
  : (cfg.robot && !Array.isArray(cfg.robots) ? [cfg.robot] : []);
const robotCfgs = robotSources.map(r => ({
  name: r.name || ('Robot' + (robotSources.indexOf(r) + 1)),
  command: { name: r.command.name, path: r.command.path, type: r.command.type || 'Int16' },
  execute: { name: r.execute.name, path: r.execute.path },
  done: { name: r.done.name, path: r.done.path },
  vacuum: { name: r.vacuum.name, path: r.vacuum.path },
  robotSensor: r.robotSensor || null,
  waitForIndexing: !!r.waitForIndexing,
  cycleNext: r.cycleNext || null,
  cycleChild: robotSources.some(source => source.cycleNext === r.name),
  // oneShot: 1 ciclo completo por deteccion (disparo por flanco real con
  // re-arme al ver el sensor LOW). Sin oneShot se mantiene el latch de nivel.
  oneShot: !!r.oneShot,
  gridCmds: Array.isArray(r.gridCmds) && r.gridCmds.length ? r.gridCmds.map(Number) : null
}));

// Secuencia del robot/gantry: si hay `sequence` (paso a paso con vacuum por
// paso) se usa tal cual; si solo hay `wps` (legacy) se convierte a sequence.
function legacySequence(wps) {
  const seq = [{ cmd: 0 }]; // home
  wps.forEach((c, i) => {
    seq.push({ cmd: c, vacuum: i === 0 });
  });
  if (seq.length >= 2) seq[seq.length - 1].vacuum = false; // vacuum OFF al soltar
  seq.push({ cmd: wps[0] }); // vuelta al primer waypoint
  return seq;
}

// Concatena las secuencias de todos los robots en un solo flujo lineal de `rstep`.
// Cada entrada lleva `{robotIdx, cmd, vacuum?, indexingPulse?}`. Una transicion
// declarada con `cycleNext` pasa por WAIT_ROBOT antes de continuar la unidad;
// solo el ultimo robot del ciclo vuelve a 'RUN'.
const robotSeq = [];
for (let ri = 0; ri < robotSources.length; ri++) {
  const r = robotSources[ri];
  let seq = [];
  if (Array.isArray(r.sequence)) seq = r.sequence;
  else if (Array.isArray(r.wps)) seq = legacySequence(r.wps);
  for (let i = 0; i < seq.length; i++) {
    robotSeq.push(Object.assign({ robotIdx: ri }, seq[i]));
  }
}
const hasRobot = robotSeq.length > 0;
const indexingBelts = cfg.indexingBelts || [];
const hasIndexingBelts = indexingBelts.length > 0;
const batch = cfg.batch || null;
const batchSize = batch ? Math.max(1, Math.floor(Number(batch.size || 0))) : 0;
const batchGapSteps = batch ? Math.max(0, Math.floor(Number(batch.indexingGapSteps || 0))) : 0;
const hasBatchGap = hasIndexingBelts && batchSize > 0 && batchGapSteps > 0;

function robotSensorName(ri) {
  return robotSources[ri].robotSensor || cfg.robotSensor || null;
}

// The robot sequences share one rstep counter, but robots triggered by
// different sensors must start at their own sequence offset and finish there.
const robotStartSteps = [];
let robotStepOffset = 0;
for (let ri = 0; ri < robotSources.length; ri++) {
  robotStartSteps[ri] = robotStepOffset;
  const seq = Array.isArray(robotSources[ri].sequence)
    ? robotSources[ri].sequence
    : (Array.isArray(robotSources[ri].wps) ? legacySequence(robotSources[ri].wps) : []);
  for (const entry of seq) {
    robotStepOffset += 1 + (entry.vacuum !== undefined
      ? 2
      : (entry.indexingPulse && hasIndexingBelts ? 1 : 0));
  }
}

// Construye los cases del switch(rstep) del robot/gantry (si robotList).
// Cada paso de la secuencia genera:
//   - un case para el movimiento (robotMove(ROB_IDX, cmd)),
//   - opcional: un case para escribir vacuum + dwell (VAC_DWELL_MS),
//   - opcional: un case para disparar el pulso del indexing belt.
function buildRobotCases(seq) {
  const cases = [];
  let step = 0;
  const N = seq.length;
  for (let i = 0; i < N; i++) {
    const entry = seq[i];
    const ri = entry.robotIdx;
    const nextEntry = seq[i + 1];
    const nextRi = nextEntry && nextEntry.robotIdx !== ri ? nextEntry.robotIdx : -1;
    const explicitCycle = nextRi >= 0 && robotSources[ri].cycleNext === robotSources[nextRi].name;
    const continuesWithNextRobot = nextEntry && nextEntry.robotIdx !== ri &&
      (robotSensorName(nextEntry.robotIdx) === robotSensorName(ri) || explicitCycle);
    const cycleTransition = continuesWithNextRobot && nextRi >= 0;
    const isLast = i === N - 1 || (!continuesWithNextRobot && nextEntry && nextEntry.robotIdx !== ri);
    const hasSub = entry.vacuum !== undefined || (entry.indexingPulse && hasIndexingBelts);
    const isGridStep = !!entry.gridNext;
    const moveCall = isGridStep
      ? 'robotMoveGrid(' + ri + ')'
      : 'robotMove(' + ri + ', ' + entry.cmd + ')';
    const moveLabel = isGridStep
      ? 'cmd grid[' + ((robotCfgs[ri] && robotCfgs[ri].gridCmds) || []).join(',') + ']'
      : 'cmd ' + entry.cmd;
    const sMove = step++;
    const nextFirst = step;

    if (isLast && !hasSub) {
      cases.push(
        '            case ' + sMove + ': // R' + ri + ' mover a ' + moveLabel + ' (fin)\n' +
        '                if (' + moveCall + ') finishRobotSequence();\n' +
        '                break;'
      );
    } else {
      cases.push(
        '            case ' + sMove + ': // R' + ri + ' mover a ' + moveLabel + '\n' +
        '                if (' + moveCall + ') rstep = ' + nextFirst + ';\n' +
        '                break;'
      );
    }

    if (entry.vacuum !== undefined) {
      const sVac = step++;
      // Si hay maquina1: arranca cuando el ultimo robot TOMA el placer (su
      // vacuum pasa a true) y no suelta (vacuum OFF) hasta que maquina1 termino.
      // Un paso puede optar por salir de la compuerta con `gate: false`.
      const lastRi = robotSources.length - 1;
      const gateLast = entry.robotIdx === lastRi && entry.vacuum === false && hasMaquina && entry.gate !== false;
      const head = '            case ' + sVac + ': // R' + ri + ' vacuum ' + entry.vacuum +
        (gateLast ? ' (espera maquina1)' : '') + '\n';
      let body = '';
      if (gateLast) body += '                if (mqDone) {\n';
      body +=
        '                    w(ROB[' + ri + '].vacuum.name, ROB[' + ri + '].vacuum.path, ' + entry.vacuum + ');\n';
       body +=
        '                    c.set(\'vacDwellUntil\', now + VAC_DWELL_MS);\n' +
        '                    rstep = ' + step + ';\n';
      if (gateLast) body += '                }\n';
      body += '                break;';
      cases.push(head + body);
      const sDwell = step++;
      const finish = cycleTransition
        ? 'waitForRobot(' + nextRi + ');'
        : (isLast ? 'finishRobotSequence();' : 'rstep = ' + step + ';');
      if (entry.indexingPulse && hasIndexingBelts) {
        cases.push(
          '            case ' + sDwell + ': // esperar vacuum + pulso indexing\n' +
          '                if (now >= c.get(\'vacDwellUntil\')) {\n' +
          '                    c.set(\'stepPulseUntil\', now + STEP_PULSE_MS);\n' +
          (hasBatchGap ? '                    countBatchUnit();\n' : '') +
          (hasMaquina ? '                    startMaquina();\n' : '') +
          (hasHorno ? '                    hornoFire();\n' : '') +
          '                    ' + finish + '\n' +
          '                }\n' +
          '                break;'
        );
      } else {
      const finishNoBrace = cycleTransition
        ? 'waitForRobot(' + nextRi + ');'
        : (isLast ? 'finishRobotSequence();' : 'rstep = ' + step + ';');
      cases.push(
          '            case ' + sDwell + ': // esperar vacuum\n' +
          '                if (now >= c.get(\'vacDwellUntil\')) ' + finishNoBrace + '\n' +
          '                break;'
      );
      }
    } else if (entry.indexingPulse && hasIndexingBelts) {
      const sPulse = step++;
      const finish = cycleTransition
        ? 'waitForRobot(' + nextRi + ');'
        : (isLast ? 'finishRobotSequence();' : 'rstep = ' + step + ';');
      cases.push(
        '            case ' + sPulse + ': // pulso indexing\n' +
        '                c.set(\'stepPulseUntil\', now + STEP_PULSE_MS);\n' +
        (hasHorno ? '                hornoFire();\n' : '') +
        '                ' + finish + '\n' +
        '                break;'
      );
    }
  }
  return cases;
}
const robotCases = buildRobotCases(robotSeq);
const hasPause = !!cfg.pauseSensor;
const pauseVar = hasPause ? JSON.stringify(cfg.pauseSensor) : 'null';

// El Function node conserva context entre ejecuciones de Godot. Estas salidas
// se invalidan cuando los spawners anuncian que una nueva simulacion esta lista.
const controlOutputPaths = [];
const beltNames = [];
for (const group of beltGroups) {
  for (const item of group.items) {
    controlOutputPaths.push(item.path);
    beltNames.push(item.name);
  }
}
for (const s of spawners) {
  controlOutputPaths.push(s.autoEnable.path, s.rateTag.path);
}
for (const r of robotCfgs) {
  controlOutputPaths.push(r.command.path, r.execute.path, r.vacuum.path);
}
for (const ib of indexingBelts) {
  controlOutputPaths.push(ib.step.path);
}
if (hasMaquina) {
  controlOutputPaths.push(maquina.z.path, maquina.release.path, maquina.cut.path);
  if (maquina.y) controlOutputPaths.push(maquina.y.path);
  if (maquina.speed) controlOutputPaths.push(maquina.speed.path);
}
if (hasHorno) {
  controlOutputPaths.push(horno.command.path, horno.execute.path, horno.mv.path, horno.setpoint.path);
}
const uniqueControlOutputPaths = [...new Set(controlOutputPaths)];

// Genera el JS de control como UN solo nodo autocontenido (oip-sim-func-control):
// decodifica msg.payload en v, ejecuta feeds + maquina de estados y devuelve las escrituras.
// El estado de la maquina de estados vive en el contexto del propio nodo.
const L = [];
L.push('// Control de linea OIP (generado por apply_control_flow.js)');
L.push('// Entrada: msg.payload = [{name,path,value,status}] (lectura OPC UA, cada 50ms)');
L.push('// Salida:  msg.payload = [{name,path,value}]        (escritura OPC UA)');
L.push('const v = {};');
L.push('for (let i = 0; i < msg.payload.length; i++) {');
L.push('    v[msg.payload[i].name] = msg.payload[i].value;');
L.push('}');
L.push('const writes = [];');
L.push('const now = Date.now();');
L.push('const c = context;');
L.push('function w(name, path, value) {');
L.push("    const key = 'out:' + path;");
L.push("    const last = c.get(key);");
L.push("    const lastAt = c.get(key + ':ts') || 0;");
L.push('    if (last === value && now - lastAt <= REASSERT_MS) return;');
L.push('    writes.push({ name: name, path: path, value: value });');
L.push('    c.set(key, value);');
L.push("    c.set(key + ':ts', now);");
L.push('}');
if (hasPause) {
  L.push('const sensorPause = !!v[' + pauseVar + '];');
}
if (hasRobot) {
  for (let ri = 0; ri < robotCfgs.length; ri++) {
    const sen = robotCfgs[ri].robotSensor || cfg.robotSensor;
    if (sen) {
      L.push('const robotSensor' + ri + ' = !!v[' + JSON.stringify(sen) + '];');
    }
  }
  L.push('const robotDone = [' + robotCfgs.map((rc, ri) => '!!v[' + JSON.stringify(rc.done.name) + ']').join(', ') + '];');
}
if (hasHorno) {
  L.push('const hornoDone = !!v[' + JSON.stringify(horno.done.name) + '];');
  L.push('const hornoRunning = !!v[' + JSON.stringify(horno.running.name) + '];');
}
L.push('');
L.push('const SPEED = ' + Number(cfg.belts.speed) + ';');
if (hasPause) {
  L.push('const HOLD_MS = ' + Number(cfg.holdMs) + ';');
}
L.push('const REASSERT_MS = 5000;');
if (hasRobot || hasHorno) L.push('const EXEC_PULSE_MS = 400;');
if (hasRobot) L.push('const VAC_DWELL_MS = 300;');
if (hasIndexingBelts) L.push('const STEP_PULSE_MS = 200;');
if (hasBatchGap) {
  L.push('const BATCH_SIZE = ' + batchSize + ';');
  L.push('const BATCH_GAP_STEPS = ' + batchGapSteps + ';');
}
if (hasMaquina) L.push('const MQ_MOVE_MS = ' + Number(maquina.moveMs || 400) + ';');
if (hasMaquina) L.push('const MQ_PULSE_MS = ' + Number(maquina.pulseMs || 200) + ';');
L.push('');
L.push('const READY_TAGS = ' + JSON.stringify(spawnerCfg.map(s => s.ready.name)) + ';');
L.push('const simulatorReady = READY_TAGS.length === 0 || READY_TAGS.every(name => !!v[name]);');
L.push("const simulatorWasReady = c.get('simulatorReady');");
L.push('const simulatorRestart = simulatorReady && simulatorWasReady === false;');
L.push("c.set('simulatorReady', simulatorReady);");
L.push('function resetControlState() {');
L.push("    c.set('state', 'RUN');");
L.push("    c.set('rstep', 0);");
L.push("    c.set('activeRobot', -1);");
L.push("    c.set('nextRobot', 0);");
L.push("    c.set('waitingRobot', -1);");
L.push("    c.set('waitingRobot6ax', -1);");
L.push("    c.set('vacDwellUntil', 0);");
L.push("    c.set('stepPulseUntil', 0);");
L.push("    c.set('lastPause', false);");
L.push("    c.set('mqStarted', false);");
L.push("    c.set('mqFinished', false);");
L.push("    c.set('mqStep', 0);");
L.push("    c.set('mqTarget', null);");
L.push("    c.set('mqDwellUntil', 0);");
L.push("    c.set('batchUnitCount', 0);");
L.push("    c.set('batchGapPending', false);");
L.push("    c.set('batchGapRemaining', 0);");
L.push("    c.set('batchGapNextAt', 0);");
L.push("    c.set('hornoArmed', false);");
L.push("    c.set('hornoExecHigh', false);");
L.push("    c.set('hornoExecLowSince', 0);");
L.push("    c.set('hornoMvSent', 0);");
L.push("    c.set('hornoSpSent', 0);");
L.push("    c.set('execHigh', []);");
L.push("    c.set('execLowSince', []);");
L.push("    c.set('execHighSince', []);");
for (let ri = 0; ri < robotCfgs.length; ri++) {
  L.push("    c.set('robotPending" + ri + "', false);");
  if (robotCfgs[ri].oneShot) L.push("    c.set('r" + ri + "Armed', true);");
  if (robotCfgs[ri].gridCmds) L.push("    c.set('gridIdx" + ri + "', 0);");
}
for (const name of beltNames) {
  L.push("    c.set('belt:" + name + "', null);");
  L.push("    c.set('beltTs:" + name + "', 0);");
}
for (let i = 0; i < spawners.length; i++) {
  L.push("    c.set('spawn" + i + "On', null);");
  L.push("    c.set('spawn" + i + "Rate', null);");
  L.push("    c.set('spawn" + i + "Ts', 0);");
}
for (const outputPath of uniqueControlOutputPaths) {
  L.push("    c.set('out:" + outputPath + "', null);");
  L.push("    c.set('out:" + outputPath + ":ts', 0);");
}
L.push('}');
L.push('if (!simulatorReady) {');
L.push('    resetControlState();');
L.push('    return null;');
L.push('}');
L.push('if (simulatorRestart) resetControlState();');
L.push('');
L.push("let state = c.get('state') || 'RUN';");
if (hasRobot) {
  L.push("let rstep = c.get('rstep') || 0;");
  L.push("let activeRobot = c.get('activeRobot');");
  L.push("if (activeRobot === undefined || activeRobot === null) activeRobot = -1;");
  L.push("let nextRobot = c.get('nextRobot');");
  L.push("if (typeof nextRobot !== 'number' || nextRobot < 0 || nextRobot >= " + robotCfgs.length + ") nextRobot = 0;");
  L.push('const ROBOT_START_STEPS = ' + JSON.stringify(robotStartSteps) + ';');
  // Arrays de handshake por robot (inicializan perezosamente).
  L.push("let execHigh = c.get('execHigh') || [];");
  L.push("let execLowSince = c.get('execLowSince') || [];");
  L.push("let execHighSince = c.get('execHighSince') || [];");
  L.push('const ROB_COUNT = ' + robotCfgs.length + ';');
  L.push('for (let i = 0; i < ROB_COUNT; i++) {');
  L.push('    if (execHigh[i] === undefined) execHigh[i] = false;');
  L.push('    if (execLowSince[i] === undefined) execLowSince[i] = 0;');
  L.push('    if (execHighSince[i] === undefined) execHighSince[i] = 0;');
  L.push('}');
}
if (hasMaquina) {
  L.push("const mqDone = !c.get('mqStarted') || c.get('mqFinished');");
}
L.push('');
if (hasPause) {
  L.push("const sPauseEdge = sensorPause && !c.get('lastPause');");
}
if (hasRobot) {
  for (let ri = 0; ri < robotCfgs.length; ri++) {
    const sen = robotCfgs[ri].robotSensor || cfg.robotSensor;
    if (sen) {
      if (robotCfgs[ri].oneShot) {
        // oneShot: un ciclo completo por deteccion. Disparo solo con el haz
        // bloqueado Y armado; se desarma al disparar y se rearma en cuanto el
        // sensor se lee LOW (en reposo o durante la propia secuencia, cuando
        // el lote recogido libera el haz). Un haz bloqueado de forma continua
        // produce exactamente UN ciclo.
        L.push("let sRobotEdge" + ri + " = false;");
        L.push("if (activeRobot === " + ri + ") {");
        L.push("    if (!robotSensor" + ri + ") c.set('r" + ri + "Armed', true);");
        L.push("} else if (!robotSensor" + ri + ") {");
        L.push("    c.set('r" + ri + "Armed', true);");
        L.push("} else {");
        L.push("    sRobotEdge" + ri + " = c.get('r" + ri + "Armed') !== false;");
        L.push("}");
      } else {
        // A level signal represents product availability. A pending request is
        // created whenever the robot is idle, so a permanently occupied sensor
        // can feed successive cycles without relying on a falling edge.
        L.push("if (activeRobot !== " + ri + ") c.set('robotPending" + ri + "', robotSensor" + ri + ');');
        L.push("const sRobotEdge" + ri + " = !!c.get('robotPending" + ri + "');");
      }
    }
  }
  L.push('const ROBOT_PENDING = [' + robotCfgs.map((rc, ri) =>
    (rc.robotSensor || cfg.robotSensor) ? 'sRobotEdge' + ri : 'false').join(', ') + '];');
  L.push('function robotTurnAllows(ri) {');
  L.push("    let start = c.get('nextRobot');");
  L.push('    if (typeof start !== \'number\' || start < 0 || start >= ROB_COUNT) start = 0;');
  L.push('    for (let offset = 0; offset < ROB_COUNT; offset++) {');
  L.push('        const candidate = (start + offset) % ROB_COUNT;');
  L.push('        if (ROBOT_PENDING[candidate]) return candidate === ri;');
  L.push('    }');
  L.push('    return false;');
  L.push('}');
}
if (hasPause) {
  L.push("c.set('lastPause', sensorPause);");
}
L.push('');
L.push('const BELT_GROUPS = ' + JSON.stringify(beltGroupCfg) + ';');
L.push('// Write-on-change por grupo de alimentacion; cada rama puede detenerse');
L.push('// sin afectar a las demas y se re-asserta cada REASSERT_MS.');
L.push('function beltGroup(name, speed) {');
L.push('    for (let gi = 0; gi < BELT_GROUPS.length; gi++) {');
L.push('        const group = BELT_GROUPS[gi];');
L.push('        if (group.name !== name) continue;');
L.push('        for (let i = 0; i < group.items.length; i++) {');
L.push('            const b = group.items[i];');
L.push("            if (c.get('belt:' + b.name) !== speed || now - (c.get('beltTs:' + b.name) || 0) > REASSERT_MS) {");
L.push('                w(b.name, b.path, speed);');
L.push("                c.set('belt:' + b.name, speed);");
L.push("                c.set('beltTs:' + b.name, now);");
L.push('            }');
L.push('        }');
L.push('        return;');
L.push('    }');
L.push('}');
L.push('function belts(speed) {');
L.push('    for (let gi = 0; gi < BELT_GROUPS.length; gi++) {');
L.push('        beltGroup(BELT_GROUPS[gi].name, speed);');
L.push('    }');
L.push('}');
L.push('');
L.push('const SPAWNERS = ' + JSON.stringify(spawnerCfg.map((s, i) => ({
  autoEnable: s.autoEnable,
  rate: s.rate,
  rateValue: Number(spawners[i].rate)
}))) + ';');
L.push('function spawner(index, on) {');
L.push('    if (index < 0 || index >= SPAWNERS.length) return;');
L.push('    const s = SPAWNERS[index];');
L.push("    const key = 'spawn' + index;");
L.push("    const lastOn = c.get(key + 'On');");
L.push("    const lastRate = c.get(key + 'Rate');");
L.push("    const stale = now - (c.get(key + 'Ts') || 0) > REASSERT_MS;");
L.push('    let wrote = false;');
L.push('    if (lastOn !== on || stale) {');
L.push('        w(s.autoEnable.name, s.autoEnable.path, on);');
L.push("        c.set(key + 'On', on);");
L.push('        wrote = true;');
L.push('    }');
L.push('    if (lastRate !== s.rateValue || stale) {');
L.push('        w(s.rate.name, s.rate.path, s.rateValue);');
L.push("        c.set(key + 'Rate', s.rateValue);");
L.push('        wrote = true;');
L.push('    }');
L.push("    if (wrote) c.set(key + 'Ts', now);");
L.push('}');
L.push('function spawners(on) {');
L.push('    for (let i = 0; i < SPAWNERS.length; i++) spawner(i, on);');
L.push('}');
L.push('');
L.push('const FEEDS = ' + JSON.stringify(feedRuntimeCfg) + ';');
L.push('// Sensor alto significa producto disponible en el punto de toma.');
L.push('// La rama ocupada se para; las demas conservan su velocidad.');
L.push('function feedControl() {');
L.push('    if (!FEEDS.length) {');
L.push('        belts(SPEED);');
L.push('        spawners(true);');
L.push('        return;');
L.push('    }');
L.push('    for (let i = 0; i < FEEDS.length; i++) {');
L.push('        const feed = FEEDS[i];');
  L.push('        const occupied = v[feed.sensor] === undefined ? true : !!v[feed.sensor];');
L.push('        let speed = SPEED;');
L.push('        for (let gi = 0; gi < BELT_GROUPS.length; gi++) {');
L.push('            if (BELT_GROUPS[gi].name === feed.beltGroup) {');
L.push('                speed = BELT_GROUPS[gi].speed;');
L.push('                break;');
L.push('            }');
L.push('        }');
L.push("        beltGroup(feed.beltGroup, occupied ? 0 : speed);");
L.push('        for (let si = 0; si < feed.spawners.length; si++) {');
L.push('            spawner(feed.spawners[si], !occupied);');
L.push('        }');
L.push('    }');
L.push('}');
L.push('');
if (hasRobot) {
  // Elegir robotDone por indice leyendo variables robotDone0, robotDone1, ...
  L.push('const ROB = ' + JSON.stringify(robotCfgs.map(rc => ({
    name: rc.name,
    command: rc.command,
    execute: rc.execute,
    done: rc.done,
    vacuum: rc.vacuum,
    gridCmds: rc.gridCmds
  }))) + ';');
  L.push('// Handshake robusto por robot: execute LOW durante EXEC_PULSE_MS (el gantry sondea a 30ms');
  L.push('// y SIEMPRE vera el LOW), despues HIGH; pasado otro EXEC_PULSE_MS se da el paso');
  L.push('// por completado cuando done==true. No puede quedarse colgado.');
  L.push('function robotMove(ri, cmd) {');
  L.push('    const R = ROB[ri];');
  L.push('    w(R.command.name, R.command.path, cmd);');
  L.push('    let doneRi = robotDone[ri];');
  L.push('    if (!execHigh[ri]) {');
  L.push('        if (!execLowSince[ri]) execLowSince[ri] = now;');
  L.push('        if (now - execLowSince[ri] < EXEC_PULSE_MS) {');
  L.push('            w(R.execute.name, R.execute.path, false);');
  L.push('            return false;');
  L.push('        }');
  L.push('        execLowSince[ri] = 0;');
  L.push('        execHigh[ri] = true;');
  L.push('        execHighSince[ri] = now;');
  L.push('        return false;');
  L.push('    }');
  L.push('    w(R.execute.name, R.execute.path, true);');
  L.push('    if (now - execHighSince[ri] < EXEC_PULSE_MS) return false;');
  L.push('    if (doneRi) {');
  L.push('        execHigh[ri] = false;');
  L.push('        execLowSince[ri] = 0;');
  L.push('        execHighSince[ri] = 0;');
  L.push('        return true;');
  L.push('    }');
  L.push('    return false;');
  L.push('}');
  L.push('');
  L.push('// Igual que robotMove pero el cmd se resuelve en runtime: recorre');
  L.push('// R.gridCmds en ciclo (contador persistente gridIdx<ri> en context).');
  L.push('// El indice solo avanza cuando done confirma la llegada, asi un ciclo');
  L.push('// abortado no pierde la posicion de la grilla.');
  L.push('function robotMoveGrid(ri) {');
  L.push('    const R = ROB[ri];');
  L.push('    const cmds = R.gridCmds || [0];');
  L.push("    let gi = c.get('gridIdx' + ri);");
  L.push('    if (gi === undefined || gi === null) gi = 0;');
  L.push('    w(R.command.name, R.command.path, cmds[gi % cmds.length]);');
  L.push('    if (!execHigh[ri]) {');
  L.push('        if (!execLowSince[ri]) execLowSince[ri] = now;');
  L.push('        if (now - execLowSince[ri] < EXEC_PULSE_MS) {');
  L.push('            w(R.execute.name, R.execute.path, false);');
  L.push('            return false;');
  L.push('        }');
  L.push('        execLowSince[ri] = 0;');
  L.push('        execHigh[ri] = true;');
  L.push('        execHighSince[ri] = now;');
  L.push('        return false;');
  L.push('    }');
  L.push('    w(R.execute.name, R.execute.path, true);');
  L.push('    if (now - execHighSince[ri] < EXEC_PULSE_MS) return false;');
  L.push('    if (robotDone[ri]) {');
  L.push("        c.set('gridIdx' + ri, gi + 1);");
  L.push('        execHigh[ri] = false;');
  L.push('        execLowSince[ri] = 0;');
  L.push('        execHighSince[ri] = 0;');
  L.push('        return true;');
  L.push('    }');
  L.push('    return false;');
  L.push('}');
  L.push('');
}
if (hasIndexingBelts) {
  L.push('const INDEXING_BELTS = ' + JSON.stringify(indexingBelts.map(ib => ({
    step: { name: ib.step.name, path: ib.step.path },
    running: ib.running ? { name: ib.running.name, path: ib.running.path } : null
  }))) + ';');
  L.push('function indexingBeltsPulse(active) {');
  L.push('    for (let i = 0; i < INDEXING_BELTS.length; i++) {');
  L.push('        const ib = INDEXING_BELTS[i];');
  L.push("        const last = c.get('ibStep:' + ib.step.name);");
  L.push('        if (last !== active || now - (c.get(\'ibStepTs:\' + ib.step.name) || 0) > REASSERT_MS) {');
  L.push('            w(ib.step.name, ib.step.path, active);');
  L.push("            c.set('ibStep:' + ib.step.name, active);");
  L.push("            c.set('ibStepTs:' + ib.step.name, now);");
  L.push('        }');
  L.push('    }');
  L.push('}');
  L.push('function indexingIdle() {');
  L.push('    for (let i = 0; i < INDEXING_BELTS.length; i++) {');
  L.push('        const ib = INDEXING_BELTS[i];');
  L.push('        if (ib.running && v[ib.running.name]) return false;');
  L.push('    }');
  L.push('    return true;');
  L.push('}');
  L.push('');
}
if (hasRobot) {
  L.push('function waitForRobot(ri) {');
  L.push('    activeRobot = -1;');
  L.push('    rstep = ROBOT_START_STEPS[ri];');
  L.push("    c.set('waitingRobot', ri);");
  L.push("    c.set('vacDwellUntil', 0);");
  L.push("    state = 'WAIT_ROBOT';");
  L.push('}');
  L.push('function finishRobotSequence() {');
  // oneShot robots (6axisRobot) are independent: do not rotate nextRobot so
  // gantry turn-taking is not disrupted.
  L.push('    if (activeRobot >= 0 && !ROB[activeRobot].oneShot) nextRobot = (activeRobot + 1) % ROB_COUNT;');
  if (hasBatchGap) {
    L.push("    activeRobot = -1;");
    L.push("    const _saved6ax = c.get('waitingRobot6ax');");
    L.push("    if (typeof _saved6ax === 'number' && _saved6ax >= 0) {");
    L.push("        c.set('waitingRobot6ax', -1);");
    L.push("        c.set('waitingRobot', _saved6ax);");
    L.push("        rstep = ROBOT_START_STEPS[_saved6ax];");
    L.push("        c.set('vacDwellUntil', 0);");
    L.push("        state = 'WAIT_ROBOT';");
    L.push("    } else if (c.get('batchGapPending')) {");
    L.push("        c.set('batchGapPending', false);");
    L.push("        c.set('batchGapRemaining', BATCH_GAP_STEPS);");
    L.push("        c.set('batchGapNextAt', 0);");
    L.push("        c.set('stepPulseUntil', now + STEP_PULSE_MS);");
    L.push("        state = 'BATCH_GAP';");
    L.push('    } else {');
    L.push("        state = 'RUN';");
    L.push('    }');
  } else {
    L.push("    activeRobot = -1;");
    L.push("    const _saved6ax2 = c.get('waitingRobot6ax');");
    L.push("    if (typeof _saved6ax2 === 'number' && _saved6ax2 >= 0) {");
    L.push("        c.set('waitingRobot6ax', -1);");
    L.push("        c.set('waitingRobot', _saved6ax2);");
    L.push("        rstep = ROBOT_START_STEPS[_saved6ax2];");
    L.push("        c.set('vacDwellUntil', 0);");
    L.push("        state = 'WAIT_ROBOT';");
    L.push('    } else {');
    L.push("        state = 'RUN';");
    L.push('    }');
  }
  L.push('}');
  if (hasBatchGap) {
    L.push('function countBatchUnit() {');
    L.push("    const count = (c.get('batchUnitCount') || 0) + 1;");
    L.push('    if (count >= BATCH_SIZE) {');
    L.push("        c.set('batchUnitCount', 0);");
    L.push("        c.set('batchGapPending', true);");
    L.push('    } else {');
    L.push("        c.set('batchUnitCount', count);");
    L.push('    }');
    L.push('}');
  }
  L.push('');
}
if (hasMaquina) {
  L.push('const MQ = ' + JSON.stringify({
    z: { name: maquina.z.name, path: maquina.z.path },
    y: maquina.y ? { name: maquina.y.name, path: maquina.y.path } : null,
    speed: maquina.speed ? { name: maquina.speed.name, path: maquina.speed.path } : null,
    release: { name: maquina.release.name, path: maquina.release.path },
    cut: { name: maquina.cut.name, path: maquina.cut.path },
    zMoves: maquina.zMoves || []
  }) + ';');
  L.push('const MAQUINA_Y = ' + Number(maquina.yValue || 0) + ';');
  L.push('const MAQUINA_SPEED = ' + Number(maquina.speedValue || 1) + ';');
  L.push('// Maquina1: secuencia tras el pulso del indexing belt, en paralelo al ultimo robot.');
  L.push('// zMoves[0..n] -> release (pulso) -> cut (pulso). Corre mientras el ultimo robot');
  L.push('// transporta el placer y garantiza terminar ANTES del vacuum OFF (mqDone).');
  L.push('function startMaquina() {');
  L.push("    if (c.get('mqStarted')) return;");
  L.push("    c.set('mqStarted', true);");
  L.push("    c.set('mqFinished', false);");
  L.push("    c.set('mqStep', 0);");
  L.push("    c.set('mqTarget', null);");
  L.push("    c.set('mqDwellUntil', 0);");
  L.push("    if (MQ.y) w(MQ.y.name, MQ.y.path, MAQUINA_Y);");
  L.push("    if (MQ.speed) w(MQ.speed.name, MQ.speed.path, MAQUINA_SPEED);");
  L.push('}');
  L.push('function maquinaRun() {');
  L.push("    if (!c.get('mqStarted') || c.get('mqFinished')) return;");
  L.push("    let s = c.get('mqStep') || 0;");
  L.push("    const d = c.get('mqDwellUntil') || 0;");
  L.push('    const ZL = MQ.zMoves.length;');
  L.push('    if (s < ZL) {');
  L.push('        const target = MQ.zMoves[s];');
  L.push("        if (c.get('mqTarget') !== target) {");
  L.push('            w(MQ.z.name, MQ.z.path, target);');
  L.push("            c.set('mqTarget', target);");
  L.push("            c.set('mqDwellUntil', now + MQ_MOVE_MS);");
  L.push('        } else if (now >= d) {');
  L.push("            c.set('mqStep', s + 1);");
  L.push("            c.set('mqTarget', null);");
  L.push('        }');
  L.push('    } else if (s === ZL) {');
  L.push('        if (now >= d) {');
  L.push('            w(MQ.release.name, MQ.release.path, true);');
  L.push("            c.set('mqDwellUntil', now + MQ_PULSE_MS);");
  L.push("            c.set('mqStep', s + 1);");
  L.push('        }');
  L.push('    } else if (s === ZL + 1) {');
  L.push('        if (now >= d) {');
  L.push('            w(MQ.release.name, MQ.release.path, false);');
  L.push('            w(MQ.cut.name, MQ.cut.path, true);');
  L.push("            c.set('mqDwellUntil', now + MQ_PULSE_MS);");
  L.push("            c.set('mqStep', s + 1);");
  L.push('        }');
  L.push('    } else if (s === ZL + 2) {');
  L.push('        if (now >= d) {');
  L.push('            w(MQ.cut.name, MQ.cut.path, false);');
  L.push("            c.set('mqFinished', true);");
  L.push('        }');
  L.push('    }');
  L.push('}');
  L.push('');
}
if (hasHorno) {
  L.push('const HORNO = ' + JSON.stringify({
    command: horno.command,
    execute: horno.execute,
    mv: horno.mv,
    setpoint: horno.setpoint
  }) + ';');
  L.push('const HORNO_MV = ' + Number(horno.mvValue || 100) + ';');
  L.push('const HORNO_SETPOINT = ' + Number(horno.setpointValue || 150) + ';');
  L.push('// Horno: ciclo termico disparado por cada paso del indexing belt (fire-and-forget).');
  L.push('// hornoFire() se llama en el caso del pulso; hornoRun() cada tick (todos los estados).');
  L.push('// Un ciclo por paso: hornoArmed bloquea re-disparo hasta que H1_DONE se active.');
  L.push('function hornoFire() {');
  L.push("    if (c.get('hornoArmed')) return;");
  L.push("    c.set('hornoArmed', true);");
  L.push("    c.set('hornoExecLowSince', now);");
  L.push("    c.set('hornoExecHigh', false);");
  L.push('}');
  L.push('function hornoRun() {');
  L.push("    if (!c.get('hornoArmed')) {");
  L.push("        if (c.get('hornoMvSent') !== 0) {");
  L.push('            w(HORNO.mv.name, HORNO.mv.path, 0);');
  L.push("            c.set('hornoMvSent', 0);");
  L.push('        }');
  L.push('        return;');
  L.push('    }');
  L.push('    w(HORNO.command.name, HORNO.command.path, 1);');
  L.push("    if (!c.get('hornoExecHigh')) {");
  L.push("        const lo = c.get('hornoExecLowSince') || 0;");
  L.push("        if (now - lo < EXEC_PULSE_MS) {");
  L.push('            w(HORNO.execute.name, HORNO.execute.path, false);');
  L.push('            return;');
  L.push('        }');
  L.push("        c.set('hornoExecHigh', true);");
  L.push('        w(HORNO.execute.name, HORNO.execute.path, true);');
  L.push('        return;');
  L.push('    }');
  L.push('    w(HORNO.execute.name, HORNO.execute.path, true);');
  L.push("    if (c.get('hornoMvSent') !== HORNO_MV) {");
  L.push('        w(HORNO.mv.name, HORNO.mv.path, HORNO_MV);');
  L.push("        c.set('hornoMvSent', HORNO_MV);");
  L.push('    }');
  L.push("    if (c.get('hornoSpSent') !== HORNO_SETPOINT) {");
  L.push('        w(HORNO.setpoint.name, HORNO.setpoint.path, HORNO_SETPOINT);');
  L.push("        c.set('hornoSpSent', HORNO_SETPOINT);");
  L.push('    }');
  L.push("    if (hornoDone) {");
  L.push("        c.set('hornoArmed', false);");
  L.push('        w(HORNO.mv.name, HORNO.mv.path, 0);');
  L.push("        c.set('hornoMvSent', 0);");
  L.push('    }');
  L.push('}');
  L.push('');
}
if (directSixAxisIndex >= 0) {
  L.push('// 6-axis: sensor directo, independiente de los gantries. Se lanza cuando');
  L.push('// activeRobot no es el propio robot (state puede ser cualquier valor).');
  L.push("// Si estaba en WAIT_ROBOT (gantry encadenado), preserva waitingRobot.");
  L.push("if (" + (robotCfgs[directSixAxisIndex].cycleChild ? 'false' : 'true') +
    " && sRobotEdge" + directSixAxisIndex + " && activeRobot !== " + directSixAxisIndex + ") {");
  L.push("    const _savedWR = c.get('waitingRobot');");
  L.push("    if (typeof _savedWR === 'number' && _savedWR >= 0) c.set('waitingRobot6ax', _savedWR);");
  L.push("    state = 'ROBOT';");
  L.push("    activeRobot = " + directSixAxisIndex + ";");
  L.push("    rstep = ROBOT_START_STEPS[" + directSixAxisIndex + "]; ");
  if (robotCfgs[directSixAxisIndex].oneShot) {
    L.push("    c.set('r" + directSixAxisIndex + "Armed', false);");
  } else {
    L.push("    c.set('robotPending" + directSixAxisIndex + "', false);");
  }
  L.push('    for (let i = 0; i < ROB_COUNT; i++) {');
  L.push('        execHigh[i] = false; execLowSince[i] = 0; execHighSince[i] = 0;');
  L.push('    }');
  L.push("    c.set('vacDwellUntil', 0);");
  if (hasIndexingBelts) {
    L.push("    c.set('stepPulseUntil', 0);");
    L.push('    indexingBeltsPulse(false);');
  }
  L.push('    feedControl();');
  L.push('    w(ROB[' + directSixAxisIndex + '].vacuum.name, ROB[' + directSixAxisIndex + '].vacuum.path, false);');
  L.push('}');
  L.push('');
}
L.push('switch (state) {');
L.push("    case 'RUN':");
// Estructura del if/else del case RUN segun tenga pausa y/o robot:
//   hasPause + hasRobot: if (sPauseEdge) {} else if (sRobotEdge) {} else {}
//   hasPause + !hasRobot: if (sPauseEdge) {} else {}
//   !hasPause + hasRobot: if (sRobotEdge) {} else {}
//   !hasPause + !hasRobot: {} (sin if)
const hasIf = hasPause || hasRobot;
if (hasIf) {
  if (hasPause) {
    L.push('        if (sPauseEdge) {');
    L.push('            // Parar YA en el mismo tick del flanco');
    L.push("            state = 'HOLD';");
    L.push("            c.set('holdUntil', now + HOLD_MS);");
    L.push('            belts(0);');
    L.push('            spawners(false);');
    if (hasIndexingBelts) L.push('            indexingBeltsPulse(false);');
    if (hasRobot) {
      // Per-robot sensors: no old sRobotEdge wrapper, each robot has its own edge
    }
  } else if (hasRobot) {
    // Per-robot sensors: each robot checks its own sensor edge
  }
  if (hasRobot) {
    // Only non-oneShot robots (gantries) participate in the RUN if-else chain.
    // oneShot robots (6axisRobot) are handled by the direct-launch block above.
    let runChainIdx = 0;
    for (let ri = 0; ri < robotCfgs.length; ri++) {
      if (robotCfgs[ri].oneShot) continue;
      const sen = robotCfgs[ri].robotSensor || cfg.robotSensor;
      if (sen) {
        const trigger = (robotCfgs[ri].cycleChild ? 'false' : 'true') +
          ' && sRobotEdge' + ri + ' && robotTurnAllows(' + ri + ')' +
          (robotCfgs[ri].waitForIndexing && hasIndexingBelts ? ' && indexingIdle()' : '');
        if (runChainIdx === 0 && !hasPause) {
          L.push('        if (' + trigger + ') {');
        } else {
          L.push('        } else if (' + trigger + ') {');
        }
        runChainIdx++;
        L.push("            state = 'ROBOT';");
        L.push('            activeRobot = ' + ri + ';');
        L.push('            rstep = ROBOT_START_STEPS[' + ri + '];');
        L.push("            c.set('robotPending" + ri + "', false);");
        L.push('            for (let i = 0; i < ROB_COUNT; i++) {');
        L.push('                execHigh[i] = false; execLowSince[i] = 0; execHighSince[i] = 0;');
        L.push('            }');
        L.push("            c.set('vacDwellUntil', 0);");
        if (hasIndexingBelts) {
          L.push("            c.set('stepPulseUntil', 0);");
          L.push('            indexingBeltsPulse(false);');
        }
        if (hasMaquina) {
          L.push("            c.set('mqStarted', false);");
          L.push("            c.set('mqFinished', false);");
          L.push("            c.set('mqStep', 0);");
          L.push("            c.set('mqTarget', null);");
          L.push("            c.set('mqDwellUntil', 0);");
        }
        L.push('            feedControl();');
        L.push('            w(ROB[' + ri + '].vacuum.name, ROB[' + ri + '].vacuum.path, false);');
      }
    }
    L.push('        } else {');
  } else {
    L.push('        } else {');
  }
  L.push('            feedControl();');
  if (hasIndexingBelts) L.push('            indexingBeltsPulse(false);');
  L.push('        }');
} else {
  L.push('        feedControl();');
  if (hasIndexingBelts) L.push('        indexingBeltsPulse(false);');
}
L.push('        break;');
L.push('');
if (hasPause) {
  L.push("    case 'HOLD':");
  L.push('        belts(0);');
  L.push('        spawners(false);');
  if (hasIndexingBelts) {
    L.push('        indexingBeltsPulse(false);');
  }
  L.push("        if (now >= c.get('holdUntil')) { state = 'RUN'; }");
  L.push('        break;');
  L.push('');
}
if (hasRobot) {
  L.push("    case 'ROBOT':");
  L.push('        feedControl();');
  if (hasIndexingBelts) {
    L.push("        if (now < (c.get('stepPulseUntil') || 0)) {");
    L.push('            indexingBeltsPulse(true);');
    L.push('        } else {');
    L.push('            indexingBeltsPulse(false);');
    L.push('        }');
  }
  L.push('        switch (rstep) {');
  for (const s of robotCases) L.push(s);
  L.push('        }');
  if (hasMaquina) {
    L.push('        maquinaRun();');
  }
  L.push('        break;');
}
if (hasRobot) {
  L.push('');
  L.push("    case 'WAIT_ROBOT':");
  L.push('        feedControl();');
  if (hasIndexingBelts) {
    L.push("        if (now < (c.get('stepPulseUntil') || 0)) {");
    L.push('            indexingBeltsPulse(true);');
    L.push('        } else {');
    L.push('            indexingBeltsPulse(false);');
    L.push('        }');
  }
  L.push("        const waitingRobot = c.get('waitingRobot');");
  L.push('        if (waitingRobot >= 0 && waitingRobot < ROB_COUNT && ROBOT_PENDING[waitingRobot]' +
    (hasIndexingBelts ? ' && indexingIdle()' : '') + ') {');
  L.push('            activeRobot = waitingRobot;');
  L.push("            c.set('robotPending' + waitingRobot, false);");
  L.push("            c.set('waitingRobot', -1);");
  L.push('            for (let i = 0; i < ROB_COUNT; i++) {');
  L.push('                execHigh[i] = false; execLowSince[i] = 0; execHighSince[i] = 0;');
  L.push('            }');
  L.push("            c.set('vacDwellUntil', 0);");
  L.push("            state = 'ROBOT';");
  L.push('        }');
  if (hasMaquina) {
    L.push('        maquinaRun();');
  }
  L.push('        break;');
}
if (hasBatchGap) {
  L.push('');
  L.push("    case 'BATCH_GAP':");
  L.push('        feedControl();');
  L.push("        if (now < (c.get('stepPulseUntil') || 0)) {");
  L.push('            indexingBeltsPulse(true);');
  L.push('        } else {');
  L.push('            indexingBeltsPulse(false);');
  L.push("            const nextAt = c.get('batchGapNextAt') || 0;");
  L.push("            if (!nextAt) {");
  L.push("                c.set('batchGapNextAt', now + STEP_PULSE_MS);");
  L.push('            } else if (now >= nextAt) {');
  L.push("                const remaining = (c.get('batchGapRemaining') || 0) - 1;");
  L.push("                c.set('batchGapRemaining', remaining);");
  L.push('                if (remaining <= 0) {');
  L.push("                    c.set('batchGapNextAt', 0);");
  L.push("                    state = 'RUN';");
  L.push('                } else {');
  L.push("                    c.set('batchGapNextAt', 0);");
  L.push("                    c.set('stepPulseUntil', now + STEP_PULSE_MS);");
  L.push('                }');
  L.push('            }');
  L.push('        }');
  if (hasMaquina) {
    L.push('        maquinaRun();');
  }
  L.push('        break;');
}
L.push('}');
if (hasHorno) {
  L.push('hornoRun();');
}
L.push('');
L.push("c.set('state', state);");
if (hasRobot) {
  L.push("c.set('rstep', rstep);");
  L.push("c.set('activeRobot', activeRobot);");
  L.push("c.set('nextRobot', nextRobot);");
  L.push("c.set('execHigh', execHigh);");
  L.push("c.set('execLowSince', execLowSince);");
  L.push("c.set('execHighSince', execHighSince);");
}
if (hasBatchGap) {
  L.push("c.set('batchUnitCount', c.get('batchUnitCount') || 0);");
  L.push("c.set('batchGapPending', c.get('batchGapPending') || false);");
  L.push("c.set('batchGapRemaining', c.get('batchGapRemaining') || 0);");
  L.push("c.set('batchGapNextAt', c.get('batchGapNextAt') || 0);");
}
L.push('');
L.push('if (writes.length === 0) return null;');
L.push('msg.payload = writes;');
L.push('return msg;');
const CONTROL_JS = L.join('\n');

const tabId = (find(flow, 'oip-sim-tab') || {}).id || 'oip-sim-tab';

function upsert(node) {
  const idx = flow.findIndex(n => n.id === node.id);
  if (idx !== -1) flow[idx] = node;
  else flow.push(node);
}

upsert({
  id: 'oip-sim-inject-loop', type: 'inject', z: tabId,
  name: 'Bucle de control (50 ms)', props: [{ p: 'payload' }],
  repeat: '0.05', crontab: '', once: true, onceDelay: 0.1, topic: '',
  payload: '', payloadType: 'date', x: 160, y: 300,
  wires: [['oip-sim-func']]
});

upsert({
  id: 'oip-sim-func-control', type: 'function', z: tabId,
  name: 'Control: sensores, cintas, spawners y robot',
  func: CONTROL_JS, outputs: 1, timeout: 0, noerr: 0,
  initialize: '', finalize: '', libs: [], x: 600, y: 300,
  wires: [['oip-sim-write-io']]
});

// oip-sim-write-io: si no existe, crearlo (write OPC UA).
if (!find(flow, 'oip-sim-write-io')) {
  upsert({
    id: 'oip-sim-write-io', type: 'opcua-server-io', z: tabId,
    name: 'Escribir al OPC UA', serverRef: 'Node-RED OPC UA Server',
    mode: 'write', identifierType: 'nodeId', tagPath: '', tagNodeId: '',
    methodName: '', intervalMs: '', inputs: 1, outputs: 1, x: 600, y: 180,
    wires: [[]]
  });
}

// ---------- 5) Guardar ----------
fs.writeFileSync(FLOW_PATH, JSON.stringify(flow, null, 4) + '\n', 'utf8');
console.log('OK: ' + FLOW_PATH);
console.log('  - variables en tree: ' + vars.length + ' (añadidas: ' + added + ', retiradas: ' + pruned + ')');
console.log('  - oip-sim-func: ' + vars.length + ' tags');
console.log('  - oip-sim-inject-loop: repeat 0.05s');
console.log('  - oip-sim-func-control: ' +
  (hasPause ? 'sensor [' + cfg.pauseSensor + ' pausa de ' + cfg.holdMs + ' ms], ' : 'sin sensor de pausa, ') +
  'velocidad ' + cfg.belts.speed + ' m/s, ' + spawners.length + ' spawner(s)' +
  (hasRobot ? ', ' + robotCfgs.length + ' robot(s): ' + robotCfgs.map(r => r.name).join(' + ') + ' (' + robotSeq.length + ' pasos totales)' : ', robot: no controlado') +
  (hasIndexingBelts ? ', indexing belts: ' + indexingBelts.length : '') +
  (hasMaquina ? ', maquina1: ' + (maquina.zMoves || []).length + ' mov Z + release/cut (fin antes del vacuum OFF del ultimo robot)' : '') +
  (hasMachines ? ', maquinas termicas: ' + machines.map(m => m.name).join(' + ') : '') +
  (hasHorno ? ', horno: ' + horno.command.name + ' (fire-and-forget por paso)' : ''));
console.log('Siguiente paso: powershell -File .claude/skills/oip-nodered-comms/scripts/sync_deployed_flow.ps1');
