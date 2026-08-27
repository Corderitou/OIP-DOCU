extends SceneTree

var _t := 0.0
var _broken := false
var _break_at := -1.0
var _n_poll_empty := 0
var _n_tags := 1
var _writes := false
var _reads := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("tags="):
			_n_tags = int(a.get_slice("=", 1))
		elif a == "writes":
			_writes = true
		elif a == "reads":
			_reads = true
	call_deferred("_run")


func _on_polled(g: String) -> void:
	if g.is_empty():
		_n_poll_empty += 1
		if _break_at < 0.0:
			_break_at = _t
			print("P t=%.2f FIRST EMPTY POLL (marks break)" % _t)
		return
	print("P t=%.1f POLL '%s'" % [_t, g])


func _on_group_init(g: String) -> void:
	print("P t=%.1f INIT '%s'" % [_t, g])


func _on_err() -> void:
	_broken = true
	print("P t=%.2f SIG comms_error" % _t)


func _process(_delta: float) -> bool:
	if not _writes and not _reads:
		return false
	for i in _n_tags:
		var tag := "ns=2;s=Tag%03d" % i
		if _writes:
			OIPComms.write_bit("PLCSIM", tag, true)
		if _reads:
			OIPComms.read_float32("PLCSIM", tag)
	return false


func _run() -> void:
	print("=== REPRO11 tags=%d writes=%s reads=%s ===" % [_n_tags, str(_writes), str(_reads)])
	var comms: Object = Engine.get_singleton("OIPComms")
	comms.tag_group_polled.connect(_on_polled)
	comms.tag_group_initialized.connect(_on_group_init)
	comms.comms_error.connect(_on_err)
	comms.set_enable_comms(true)
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	for i in _n_tags:
		var ok: bool = comms.register_tag("PLCSIM", "ns=2;s=Tag%03d" % i, 1)
		if not ok:
			print("REGF fail for Tag%03d" % i)
	comms.set_sim_running(true)
	for i in range(120):
		await create_timer(0.1).timeout
		_t += 0.1
		if _break_at > 0.0 and _t > _break_at + 2.0:
			break
	print("=== REPRO11 END tags=%d writes=%s reads=%s | break_at=%.2f empty_polls=%d err=%s ===" % [_n_tags, str(_writes), str(_reads), _break_at, _n_poll_empty, str(_broken)])
	quit(0)
