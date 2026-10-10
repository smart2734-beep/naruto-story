extends Node
## 검토용 Q5 재현. 기본: 물길 방출 때 실제 이동해 손잡이에 접근한다.
## --worker: 안전 발판 난간 통과 관찰. --choice: 선택 문구와 실제 영물 상태 비교.
var m
var main_script
var dungeon_script
var boss_script

func _ready() -> void:
	_run.call_deferred()

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	main_script = load("res://scripts/main.gd")
	dungeon_script = load("res://scripts/dungeon.gd")
	boss_script = load("res://scripts/enemy_boss_claw.gd")
	await _wait(0.3)
	var args := OS.get_cmdline_user_args()
	if args.has("--worker"):
		await _worker()
	elif args.has("--choice"):
		await _choice()
	else:
		await _release(args.has("--near"), args.has("--reaction"))
	get_tree().quit(0)  # 수치·안내 관찰이며 전체 클리어의 합격 판정이 아니다.

func _release(near: bool, reaction: bool) -> void:
	m.in_dungeon = true
	m._apply_camera_limits(main_script.DUNGEON_LIMITS)
	m._enter_stage(main_script.Stage.Q5_BOSS)
	m.boss.position = Vector2(1290, 270)
	m.player.respawn(dungeon_script.SLUICE + Vector2(0, 24) if near else Vector2(1290, 314))
	m.player.gear = "줄비"
	m.player.invuln = 0.0
	m.player.attack_cd = 999.0
	m.worker.reset_at(dungeon_script.WAIT_SPOT, m.worker.WState.WAIT)
	await get_tree().process_frame
	m.boss.force_pattern("release")
	var elapsed := 0.0
	var dodge_count := 0
	var activated_at := -1.0
	var flood_time := [-1.0]
	var started := Time.get_ticks_msec()
	m.boss.flooded.connect(func(_secured: bool): flood_time[0] = (Time.get_ticks_msec() - started) / 1000.0)
	if reaction:
		await _wait(0.6)
		elapsed += 0.6
	# 난간 아래로 돌아 들어가는 경로. 마지막 점은 손잡이 판정(44px) 안이다.
	var route: Array[Vector2] = [Vector2(1538, 586), Vector2(1592, 586), Vector2(1592, 515)]
	var waypoint := 0
	while elapsed < 6.0:
		if m.player.position.distance_to(m.sluice_spot.position) < 44.0:
			m.hud.forced_move = Vector2.ZERO
			m._on_interact(m.sluice_spot)
			if m.dungeon.secured and activated_at < 0.0:
				activated_at = elapsed
		elif waypoint < route.size():
			var target := route[waypoint]
			if m.player.position.distance_to(target) < 12.0:
				waypoint += 1
			else:
				var dir: Vector2 = (target - m.player.position).normalized()
				m.hud.forced_move = dir
				m.player.move_input = dir
				if m.player.position.distance_to(target) > 110.0 and m.player.try_dodge():
					dodge_count += 1
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if flood_time[0] >= 0.0 and elapsed > 4.5:
			break
	m.hud.forced_move = null
	print("RELEASE_ROUTE near=", near, " reaction=", reaction, " activated_at=", activated_at, " flood_at=", flood_time[0], " dodges=", dodge_count, " position=", m.player.position, " hp=", m.player.hp, " worker_hp=", m.worker.hp, " secured=", m.dungeon.secured)

func _worker() -> void:
	m.in_dungeon = true
	m._enter_stage(main_script.Stage.Q5_ESCORT)
	m.player.respawn(Vector2(1600, 510))
	m.worker.reset_at(Vector2(1480, 510), m.worker.WState.FOLLOW)
	var crossed := [false]
	var rail := Rect2(1554, 470, 6, 104)
	var sample := func():
		if rail.has_point(m.worker.position):
			crossed[0] = true
	get_tree().process_frame.connect(sample)
	await _wait(2.0)
	get_tree().process_frame.disconnect(sample)
	print("WORKER_RAIL crossed=", crossed[0], " position=", m.worker.position, " state=", m.worker.wstate)

func _choice() -> void:
	GameState.contract_spirit("도톰")
	GameState.contract_spirit("줄비")
	m.dotom.become_companion()
	m._enter_stage(main_script.Stage.Q5_GO)
	m._choose_spirit_and_descend()
	print("SPIRIT_OPTIONS=", m.hud.choice_options)
	m.hud.pick_choice(1)
	await _wait(1.0)
	print("SPIRIT_AFTER_CHOICE active=", GameState.active_spirit, " gear=", m.player.gear, " companion=", m.julbi.state == m.julbi.State.COMPANION)
