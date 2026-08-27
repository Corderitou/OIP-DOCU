extends SceneTree

var _t := 0.0
var _break_at := -1.0
var _n_poll_empty := 0
var _writes := false
var _reads := false
var _once := false
var _only := "all"
var _hz := 60
var _frame := 0

const TAGS := [
	"ns=2;s=BeltConveyor_Speed", "ns=2;s=BeltConveyor_Running",
	"ns=2;s=BeltConveyor2_Speed", "ns=2;s=BeltConveyor2_Running",
	"ns=2;s=BeltConveyor3_Speed", "ns=2;s=BeltConveyor3_Running",
	"ns=2;s=S1_DONE", "ns=2;s=S1_RUNNING", "ns=2;s=S1_READY",
	"ns=2;s=Vastago_Extend",
	"ns=2;s=Robot1_Command", "ns=2;s=Robot1_Execute", "ns=2;s=Robot1_Done",
	"ns=2;s=Maquina1_Cut", "ns=2;s=Maquina1_Release", "ns=2;s=Maquina1_Z",
	"ns=2;s=Maquina1_Y", "ns=2;s=Maquina1_Speed",
]

const BOOL_TAGS := [
	"ns=2;s=BeltConveyor_Running", "ns=2;s=BeltConveyor2_Running", "ns=2;s=BeltConveyor3_Running",
	"ns=2;s=S1_DONE", "ns=2;s=S1_RUNNING", "ns=2;s=S1_READY",
	"ns=2;s=Vastago_Extend",
	"ns=2;s=Robot1_Execute", "ns=2;s=Robot1_Done",
	"ns=2;s=Maquina1_Cut", "ns=2;s=Maquina1_Release",
]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "writes":
			_writes = true
		elif a == "reads":
			_reads = true
		elif a == "once":
			_once = true
		elif a.begins_with("only="):
			_only = a.get_slice("=", 1)
		elif a.begins_with("hz="):
			_hz = int(a.get_slice("=", 1))
	call_deferred("_run")


func _on_polled(g: String) -> void:
	if g.is_empty():
		_n_poll_empty += 1
		if _break_at < 0.0:
			_break_at = _t
			print("P t=%.2f FIRST EMPTY POLL" % _t)
		return
	print("P t=%.1f POLL '%s'" % [_t, g])


func _on_group_init(g: String) -> void:
	print("P t=%.1f INIT '%s'" % [_t, g])


func _on_err() -> void:
	print("P t=%.2f SIG comms_error" % _t)


func _process(_delta: float) -> bool:
	if _writes or _reads:
		_frame += 1
		if _once and _frame > 1:
			return false
		if _frame % int(60.0 / _hz) != 0:
			return false
		if _only == "celda":
			if _writes:
				OIPComms.write_bit("PLCSIM", "ns=2;s=S1_READY", true)
				OIPComms.write_bit("PLCSIM", "ns=2;s=S1_RUNNING", true)
				OIPComms.write_bit("PLCSIM", "ns=2;s=S1_DONE", true)
			if _reads:
				OIPComms.read_bit("PLCSIM", "ns=2;s=S1_READY")
				OIPComms.read_bit("PLCSIM", "ns=2;s=S1_RUNNING")
				OIPComms.read_bit("PLCSIM", "ns=2;s=S1_DONE")
		elif _only == "one":
			if _writes:
				OIPComms.write_bit("PLCSIM", "ns=2;s=S1_RUNNING", true)
			if _reads:
				OIPComms.read_bit("PLCSIM", "ns=2;s=S1_RUNNING")
		else:
			if _writes:
				for t in BOOL_TAGS:
					OIPComms.write_bit("PLCSIM", t, true)
			if _reads:
				for t in BOOL_TAGS:
					OIPComms.read_bit("PLCSIM", t)
	return false


func _run() -> void:
	print("=== REPRO12C tags=%d only=%s hz=%d writes=%s reads=%s ===" % [TAGS.size(), _only, _hz, str(_writes), str(_reads)])
	var comms: Object = Engine.get_singleton("OIPComms")
	comms.tag_group_polled.connect(_on_polled)
	comms.tag_group_initialized.connect(_on_group_init)
	comms.comms_error.connect(_on_err)
	comms.set_enable_comms(true)
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	if _only == "celda":
		comms.register_tag("PLCSIM", "ns=2;s=S1_READY", 1)
		comms.register_tag("PLCSIM", "ns=2;s=S1_RUNNING", 1)
		comms.register_tag("PLCSIM", "ns=2;s=S1_DONE", 1)
	elif _only == "one":
		comms.register_tag("PLCSIM", "ns=2;s=S1_RUNNING", 1)
	else:
		for t in TAGS:
			var ok: bool = comms.register_tag("PLCSIM", t, 1)
			if not ok:
				print("REGF fail: ", t)
	comms.set_sim_running(true)
	for i in range(150):
		await create_timer(0.1).timeout
		_t += 0.1
		if _break_at > 0.0 and _t > _break_at + 2.0:
			break
	print("=== REPRO12C END only=%s hz=%d | break_at=%.2f empty_polls=%d ===" % [_only, _hz, _break_at, _n_poll_empty])
	quit(0)
