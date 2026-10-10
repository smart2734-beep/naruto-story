extends Node
## Q4의 허용된 조기 강화 경로를 실제 게임 로직으로 재현한다.
## 기본: 제작 직후 마을 작업대에서 +1. --normal: 마지막 안내 단계에서 +1.
## 순간이동·대사 넘기기는 준비용이며, 재료 추가나 보상·강화 강제 설정은 하지 않는다.
var m
var dev

func _ready() -> void:
	_run.call_deferred()

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	m.hud._input(event)

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	dev = load("res://scripts/devtools.gd").new()
	add_child(dev)
	dev.m = m
	await _wait(0.3)
	await dev._fast_forward_to_q2()
	await dev._to_q4()
	# 준비용 순간이동이 실제 귀환 이동 시간을 생략하므로, 진행 중인 2초 변신을 먼저 마친다.
	await dev._wait_until(func(): return m.player.transform_t <= 0.0, 3.0)
	var main_script = load("res://scripts/main.gd")
	if m.stage != main_script.Stage.Q4_CRAFT:
		print("REVIEW RESULT: FAIL (Q4 preparation)")
		get_tree().quit(2)
		return
	dev._teleport(m.bench_village.position + Vector2(0, 26))
	await dev._interact(m.bench_village)
	_key(KEY_1)  # 제작 목록의 실제 입력 처리
	m.hud.skip_dialogue()
	var early := not OS.get_cmdline_user_args().has("--normal")
	if early:
		await dev._interact(m.bench_village)
		_key(KEY_1)  # 제작 뒤에는 강화가 첫 행
		m.hud.close_craft()
	print("AFTER_CRAFT early=", early, " weapon=", GameState.weapon_label(), " ore=", GameState.count("하천광"), " currency=", GameState.currency)
	dev._teleport(main_script.RING_POS + Vector2(0, -24))
	await dev._interact(m.ring_spot)
	print("AFTER_RING stage=", main_script.Stage.keys()[m.stage], " available=", GameState.available_spirits(), " transform=", m.player.transform_t, " combat=", m._in_combat(), " dead=", m.player.dead, " falling=", m.player.falling)
	m._on_portrait_long()
	print("AFTER_SWAP stage=", main_script.Stage.keys()[m.stage], " active=", GameState.active_spirit, " julbi=", m.julbi.state)
	dev._teleport(main_script.RING_POS + Vector2(0, -30))
	for i in 2:
		var found: bool = await dev._wait_until(func(): return m.hooks[i].interactable, 4.0)
		if not found:
			print("REVIEW RESULT: FAIL (hook preparation)")
			get_tree().quit(2)
			return
		dev._teleport(m.hooks[i].position + Vector2(0, -22))
		await dev._interact(m.hooks[i])
		dev._teleport(main_script.RING_POS + Vector2(0, -30))
	dev._teleport(main_script.RING_POS + Vector2(0, -24))
	await dev._interact(m.ring_spot)
	m._on_portrait()
	await dev._settle()
	dev._teleport(m.dummy.position + Vector2(-130, 0))
	await dev._dodge_toward(Vector2.RIGHT)
	await _wait(0.3)
	print("AFTER_WAVE stage=", main_script.Stage.keys()[m.stage], " weapon=", GameState.weapon_label())
	if m.stage == main_script.Stage.Q4_UPGRADE:
		dev._teleport(m.dogyeom.position + Vector2(0, 26))
		await dev._interact(m.dogyeom)
		dev._teleport(main_script.BENCH_MILL + Vector2(0, -26))
		await dev._interact(m.bench_mill)
		print("FINAL_BENCH rows=", m.hud.craft_rows, " ore=", GameState.count("하천광"), " currency=", GameState.currency, " resupply=", GameState.flags.get("q4_resupply", 0))
		_key(KEY_1)
		m.hud.skip_dialogue()
	var ok: bool = m.stage == main_script.Stage.Q4_DONE and GameState.weapon_plus == 1 and GameState.claimed_rewards.has("Q4") and m.world.hatch_open
	print("FINAL stage=", main_script.Stage.keys()[m.stage], " weapon=", GameState.weapon_label(), " reward=", GameState.claimed_rewards.has("Q4"), " hatch=", m.world.hatch_open)
	print("REVIEW RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
