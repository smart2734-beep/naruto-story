extends Node
## 검토용 재현 장면. 실제 게임 스크립트를 그대로 사용하며 진행 위치만 준비한다.
## 기본: Q3 완료 대화 안전성. --beetle: 돌진 접촉 피해. --practice: 연습 재시도 관찰.
var main_script
var m

func _ready() -> void:
	_run.call_deferred()

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _run() -> void:
	main_script = load("res://scripts/main.gd")
	m = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _wait(0.3)
	var args := OS.get_cmdline_user_args()
	var ok: bool
	if args.has("--beetle"):
		ok = await _beetle()
	elif args.has("--practice"):
		await _practice()
		ok = true  # UX 관찰. 기존 8초 규칙 자체를 실패로 처리하지 않는다.
	else:
		ok = await _dialogue()
	await _wait(0.8)
	print("REVIEW RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

func _dialogue() -> bool:
	m._complete_q2()
	m._enter_stage(main_script.Stage.Q3_HANDLE)
	m.player.position = Vector2(1010, 118)
	m.player.invuln = 0.0
	await _settle()
	var in_range: bool = m.current_interact == m.handle_spot
	print("HANDLE_IN_RANGE=", in_range)
	if not in_range:
		return false
	m._on_interact(m.current_interact)
	await get_tree().process_frame
	var hp_before: float = m.player.hp
	print("HANDLE_READING_START hp=", hp_before, " dialogue=", m.hud.dialogue_active(), " locked=", m.player.locked, " dodge_allowed=", m.player.try_dodge())
	await _wait(2.5)
	var safe: bool = m.hud.dialogue_active() and m.player.hp == hp_before and not m.player.dead
	print("HANDLE_READING_AFTER hp=", m.player.hp, " dialogue=", m.hud.dialogue_active(), " locked=", m.player.locked)
	var deaths := [0]
	m.player.died.connect(func(): deaths[0] += 1)
	m.player.hp = 20.0
	m.player.invuln = 0.0
	await _wait(3.0)
	print("HANDLE_LOW_HP_READING deaths=", deaths[0], " dialogue=", m.hud.dialogue_active(), " dead=", m.player.dead)
	return safe and deaths[0] == 0

func _beetle() -> bool:
	m._enter_stage(main_script.Stage.Q2_ROPES)
	m.player.position = Vector2(584, 1180)
	m.player.invuln = 0.0
	# 플레이어가 먼저 적을 처치하지 않도록 기본 공격 대기시간만 늘린다.
	m.player.attack_cd = 999.0
	await _settle()
	var bt = m.enemies[2]
	var stats := [INF, 0]
	var record := func():
		stats[0] = minf(stats[0], bt.position.distance_to(m.player.position))
		if bt.state == bt.State.CHARGE:
			stats[1] += 1
	get_tree().physics_frame.connect(record)
	await _wait(4.0)
	var damaged: bool = m.player.hp < 100.0
	var contacted: bool = stats[1] > 0 and stats[0] < 21.0
	print("BEETLE_BASELINE hp=", m.player.hp, " min_distance=", stats[0], " charge_frames=", stats[1], " player_layer=", m.player.collision_layer, " enemy_mask=", bt.collision_mask)
	# 진단용 대조 조건. 게임 본체 수정이 아니며 플레이어와의 물리 충돌만 제외한다.
	m.player.position = Vector2(584, 1180)
	m.player.hp = 100.0
	m.player.invuln = 0.0
	m.player.collision_layer = 4
	bt.reset_to_home()
	stats[0] = INF
	stats[1] = 0
	await _wait(4.0)
	print("BEETLE_CONTROL hp=", m.player.hp, " min_distance=", stats[0], " charge_frames=", stats[1], " player_layer=", m.player.collision_layer, " enemy_mask=", bt.collision_mask)
	get_tree().physics_frame.disconnect(record)
	return contacted and damaged

func _practice() -> void:
	m._complete_q2()
	m.hud.toasts.clear()
	m.world.reveal_hidden_near(main_script.World.SAFE_LANDING.get_center(), 200.0)
	m._enter_stage(main_script.Stage.Q3_GAP)
	m.player.shoe = true
	m.dotom.equip()
	m.player.position = Vector2(630, 100)
	m.player.gyeol = 100.0
	await _settle()
	m.hud.forced_move = Vector2.RIGHT
	m.player.move_input = Vector2.RIGHT
	m.player.try_dodge()
	await _wait(0.45)
	m.hud.forced_move = null
	await _wait(0.9)
	print("PRACTICE_RESET position=", m.player.position, " falling=", m.player.falling, " energy=", m.player.gyeol, " step_cd=", m.player.step_cd)
	# 기존 점검처럼 step_cd를 0으로 만들지 않고 올바른 착지점으로 재시도한다.
	m.player.position = Vector2(630, 60)
	m.hud.forced_move = Vector2.RIGHT
	m.player.move_input = Vector2.RIGHT
	m.player.try_dodge()
	await _wait(0.45)
	m.hud.forced_move = null
	print("IMMEDIATE_SAFE_RETRY falling=", m.player.falling, " position=", m.player.position, " step_cd=", m.player.step_cd)
