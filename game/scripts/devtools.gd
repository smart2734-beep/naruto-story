extends Node
## 개발용: 자동 점검(--autotest)과 장면 캡처(--shot=경로 --scenario=이름).
## 실제 입력 대신 순간이동·직접 호출로 진행하되, 판정(피격·낙하·보상)은 게임 코드 그대로 쓴다.
##
## 캡처 장면: start, dialogue, aim, reward, q2_ropes, q2_calm, q2_follow, q3_marked, q3_shoe, q3_patrol, q3_done

const Main := preload("res://scripts/main.gd")
const Dotom := preload("res://scripts/spirit_dotom.gd")
const Ironbeak := preload("res://scripts/enemy_ironbeak.gd")
const Beetle := preload("res://scripts/enemy_beetle.gd")
const Patrol := preload("res://scripts/enemy_patrol.gd")
const World := preload("res://scripts/world.gd")
const Julbi := preload("res://scripts/spirit_julbi.gd")

var m  # main.gd
var fails: Array[String] = []


func start(main_node, args: PackedStringArray) -> void:
	m = main_node
	if args.has("--autotest"):
		_autotest()
	else:
		_screenshot(m._arg_value(args, "--shot=", ""), m._arg_value(args, "--scenario=", "start"))


# ── 공통 도우미 ───────────────────────────────────────────

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## 순간이동 뒤 _process가 한 번 이상 돌도록 기다린다.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _teleport(p: Vector2) -> void:
	m.player.position = p
	m.player.velocity = Vector2.ZERO
	m._last_player_pos = p
	m.camera.reset_smoothing()


func _interact(n) -> void:
	await _settle()
	m._on_interact(n)
	m.hud.skip_dialogue()


func _wait_state(e, st: int, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if is_instance_valid(e) and e.state == st:
			return true
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
	return false


func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await get_tree().process_frame
		left -= get_process_delta_time()
	return false


func _check(ok: bool, what: String) -> void:
	_section_total += 1
	if ok:
		_section_ok += 1
	print(("  [OK]   " if ok else "  [FAIL] ") + what)
	if not ok:
		fails.append(what)


func _enemy(kind: String, index := 0):
	var n := 0
	for e in m.enemies:
		if is_instance_valid(e) and e.get_meta("kind") == kind:
			if n == index:
				return e
			n += 1
	return null


func _dodge_toward(dir: Vector2) -> void:
	m.hud.forced_move = dir
	m.player.move_input = dir
	m.player.try_dodge()
	await _wait(0.45)
	m.hud.forced_move = null


# ── 자동 점검 ─────────────────────────────────────────────

func _autotest() -> void:
	await _wait(0.3)
	var only_q1 := OS.get_cmdline_user_args().has("--q1")
	await _section("Q1", _test_q1)
	if not only_q1:
		await _section("Q2", _test_q2)
		await _section("Q3", _test_q3)
		await _section("영물 규칙", _test_spirit_rules)
		await _section("Q4", _test_q4)
		await _section("HUD", _test_hud)
		await _section("Codex 재현", _test_codex_review)
	for line in _summary:
		print(line)
	print("=== RESULT: %s (%d fail) ===" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)


var _summary: Array[String] = []
var _section_ok := 0
var _section_total := 0


func _section(title: String, body: Callable) -> void:
	print("=== %s ===" % title)
	_section_ok = 0
	_section_total = 0
	await body.call()
	_summary.append("  %s: %d/%d" % [title, _section_ok, _section_total])


## Q1: 최초 구현(112e6c7)의 22개 항목을 같은 순서·의미로 유지한다.
func _test_q1() -> void:
	var p = m.player
	_check(m.stage == Main.Stage.TALK_DANU, "시작 단계는 단우와 대화")
	_teleport(m.danu.position + Vector2(0, 24))
	await _settle()
	_check(m.current_interact == m.danu, "단우 근처에서 상호작용 대상이 단우")
	m._on_interact(m.current_interact)
	await _settle()
	_check(p.locked and m.hud.dialogue_active(), "대화 중 조작 잠금")
	m.hud.skip_dialogue()
	_check(m.stage == Main.Stage.GET_CRATE, "대화 후 상자 받기 단계")

	_teleport(m.crate.position + Vector2(-24, 0))
	await _interact(m.crate)
	_check(p.carrying and m.stage == Main.Stage.GO_ENTRANCE, "상자 받은 뒤 입구 이동 단계")

	_teleport(Main.ENTRANCE + Vector2(0, -20))
	await _settle()
	_check(m.stage == Main.Stage.CROSS and m.checkpoint_for(Main.ENTRANCE + Vector2(0, -300)) == Main.ENTRANCE, "입구 도착 → 필드 진입, 재시작 지점 갱신")

	var b1 = _enemy("ironbeak")
	_teleport(b1.home + Vector2(0, 120))
	_check(await _wait_state(b1, Ironbeak.State.AIM, 3.0), "철부리새가 근처 플레이어를 노려봄(예고)")
	_check(m.hud.hint_text.begins_with("빨간 선"), "첫 예고 때 회피 안내 표시")
	await _wait(1.3)
	_check(p.hp < p.max_hp, "예고를 무시하면 피해를 입음 (체력 %d)" % roundi(p.hp))

	b1.hp = b1.max_hp
	p.respawn(b1.home + Vector2(0, 120))
	p.hp = p.max_hp
	b1.reset_to_home()
	await _wait_state(b1, Ironbeak.State.AIM, 3.0)
	await _wait(0.5)
	await _dodge_toward(b1.dir.orthogonal())
	await _wait(0.8)
	_check(p.hp == p.max_hp, "예고 중 옆으로 회피하면 피해 없음")

	var xp_before: int = GameState.xp
	b1.take_hit(100.0, p.position)
	_check(not b1.alive and GameState.xp == xp_before + 15, "철부리새 처치 시 경험치 +15")

	_teleport(Main.ENTRANCE + Vector2(0, -200))
	p.hp = 1.0
	p.invuln = 0.0
	p.take_damage(5.0, p.position + Vector2(0, 10))
	_check(p.dead and m.hud.fade > 0.0, "체력 0 → 쓰러짐 화면")
	await _wait(2.0)
	_check(not p.dead and p.position.distance_to(Main.ENTRANCE) < 2.0 and p.carrying and p.hp == p.max_hp, "입구에서 재시작, 부품 유지, 체력 회복")

	_teleport(m.haon.position + Vector2(0, 30))
	await _settle()
	_check(m.current_interact == m.haon, "하온 근처에서 상호작용 대상이 하온")
	m._on_interact(m.haon)
	m.hud.skip_dialogue()
	_check(GameState.level == 2 and GameState.currency == 20 and GameState.has_skill("사선베기") and GameState.weapon == "기본 장도", "보상: Lv.2, 재화 20, 사선베기, 기본 장도")
	_check(not p.carrying and m.stage == Main.Stage.BACKFLOW, "전달 후 수문 이벤트 단계")
	await _wait(3.0)
	m.hud.skip_dialogue()
	_check(m.world.backflow > 0.5, "수문 역류 연출")
	_check(m.maedeup.visible and m.stage == Main.Stage.TALK_MAEDEUP, "매듭 등장, Q2 요청 대기")
	_barrier_before_q2 = m.world.blocker_enabled("east_barrier")
	await _wait(2.0)
	_teleport(m.maedeup.position + Vector2(0, 20))
	await _interact(m.maedeup)
	_check(m.stage == Main.Stage.Q2_GO_BANK, "매듭 대화 후 Q1 완료 (Q2 시작)")

	_teleport(m.haon.position + Vector2(0, 30))
	await _interact(m.haon)
	_check(GameState.currency == 20 and not GameState.claim_reward("Q1"), "Q1 보상은 한 번만 지급")

	await _settle()
	p.gyeol = 100.0
	p.skill_cd = 0.0
	_check(p.try_skill() and absf(p.gyeol - 85.0) < 0.01, "사선베기 사용 시 결력 15 소모")
	_check(not p.try_skill(), "재사용 대기 중에는 다시 쓸 수 없음")


var _barrier_before_q2 := false


func _test_q2() -> void:
	var p = m.player
	var w = m.world
	await _settle()
	_check(_barrier_before_q2 and not w.blocker_enabled("east_barrier"), "Q2 전에는 동쪽 다리가 막혀 있고, Q2 시작 시 열림")
	# 실제로 걸어서 다리를 건넌다
	_teleport(Vector2(270, 904))
	m.hud.forced_move = Vector2.RIGHT
	var crossed: bool = await _wait_until(func(): return m.stage == Main.Stage.Q2_ROPES, 3.0)
	m.hud.forced_move = null
	_check(crossed, "걸어서 다리를 건너 젖은 둑 도착")

	_teleport(m.ropes[0].position + Vector2(-26, 0))
	await _interact(m.ropes[0])
	_check(m.ropes[0].checked and m.stage == Main.Stage.Q2_ROPES, "느슨한 줄 1 조사 (1/2)")

	# 젖은 발판에 오래 서 있으면 무너진다
	_teleport(Vector2(600, 780))
	await _wait(1.0)
	_check(p.falling, "젖은 나무 발판에 멈춰 있으면 붕괴")
	await _wait(0.8)
	_check(not p.falling and p.position == Main.EAST_BANK, "가까운 둑(동쪽 둑)에서 재시작")
	# 멈추지 않고 건너면 무너지지 않는다
	_teleport(Vector2(600, 815))
	m.hud.forced_move = Vector2.UP
	await _wait(0.6)
	m.hud.forced_move = null
	_check(not p.falling and p.position.y < 760.0, "젖은 발판을 멈추지 않고 건너면 안전")

	# 진흙은 걸어서 못 들어가고, 회피로는 넘을 수 있다
	_teleport(Vector2(450, 820))
	m.hud.forced_move = Vector2.UP
	await _wait(0.5)
	m.hud.forced_move = null
	_check(p.position.y > 795.0 and not p.falling, "진흙 띠는 걸어서 들어갈 수 없음")

	# 덩굴딱정벌레: 돌진 → 빈틈
	var bt = _enemy("beetle", 1)
	p.respawn(bt.home + Vector2(0, -100))
	p.hp = p.max_hp
	_check(await _wait_state(bt, Beetle.State.AIM, 5.0), "덩굴딱정벌레가 돌진을 예고")
	_check(await _wait_state(bt, Beetle.State.STUNNED, 3.0), "돌진 뒤 덩굴이 엉킨 빈틈")
	var hp_before: float = bt.hp
	bt.take_hit(10.0, p.position)
	_check(absf((hp_before - bt.hp) - 15.0) < 0.01, "빈틈에 공격하면 피해 1.5배")
	bt.take_hit(999.0, p.position)
	await _wait(0.1)

	_teleport(m.ropes[1].position + Vector2(-26, 0))
	await _interact(m.ropes[1])
	_check(m.stage == Main.Stage.Q2_GET_ROPE, "줄 2개 조사 → 매듭에게 밧줄 받기")
	_teleport(m.maedeup.position + Vector2(0, 20))
	await _interact(m.maedeup)
	_check(m.stage == Main.Stage.Q2_ANCHOR and GameState.items.get("밧줄", 0) == 1, "밧줄 받음 → 고정점 설치 단계")
	_teleport(Main.ANCHOR_SPOT + Vector2(-20, 0))
	await _interact(m.anchor_spot)
	await _settle()
	_check(w.anchor_built and not w.blocker_enabled("channel_mid") and m.stage == Main.Stage.Q2_CALM, "고정점 설치 → 섬으로 밧줄 다리")

	# 도톰: 뛰어서 다가가면 숨는다
	var d = m.dotom
	_teleport(d.position + Vector2(-90, 0))
	m.hud.forced_move = Vector2.RIGHT
	var startled: bool = await _wait_until(func(): return d.state == Dotom.State.HIDE, 2.0)
	m.hud.forced_move = null
	_check(startled, "도톰에게 뛰어가면 놀라서 숨음")
	await _wait(3.0)
	_check(d.state == Dotom.State.NEST, "잠시 뒤 다시 둥지로 돌아옴 (영구 실패 없음)")
	# 가까이에서 멈춰 기다리면 다가온다
	_teleport(d.position + Vector2(-100, 0))
	var trusted: bool = await _wait_until(func(): return m.hud.dialogue_active(), 5.0)
	_check(trusted, "멈춰서 기다리면 도톰이 먼저 다가옴")
	m.hud.skip_dialogue()
	_check(m.stage == Main.Stage.Q2_FOLLOW and d.has_nest, "도톰이 둥지를 지고 앞장섬")
	# 따라간다 (도톰 뒤를 걷는다)
	var arrived: bool = await _wait_until(func():
		if d.state == Dotom.State.LEAD:
			_teleport(d.position + (d.face * -40.0 if d.face != Vector2.ZERO else Vector2(40, 0)))
		return m.stage == Main.Stage.Q2_CONTRACT, 25.0)
	_check(arrived, "도톰을 따라 안전한 둑 도착")
	m.hud.skip_dialogue()
	_check(GameState.spirits.has("도톰") and GameState.level == 3 and GameState.items.get("수초섬유", 0) == 3, "Q2 보상: 도톰 계약, Lv.3, 수초섬유 3")
	_check(d.state == Dotom.State.COMPANION and m.hud.spirit_form == "동행", "도톰 동행 시작, 초상화 표시")
	_check(m.stage == Main.Stage.Q3_TALK_HAON, "Q3 개방: 하온에게")


func _test_q3() -> void:
	var p = m.player
	var w = m.world
	var d = m.dotom
	await _settle()
	_check(not w.blocker_enabled("steps_barrier"), "점검로 계단 열림")
	_teleport(m.haon.position + Vector2(0, 26))
	await _interact(m.haon)
	_check(m.stage == Main.Stage.Q3_FIND, "하온 대화 → 동행 도톰과 틈 앞으로")

	# 배타성: 신발 상태에서는 동행 탐지가 일어나지 않는다
	m._on_portrait()
	_check(p.shoe and p.transform_t == 0.0 and p.transform_fx > 0.0, "전투 밖 변신은 즉시 적용, 조작을 막지 않는 연출만")
	_teleport(Main.GAP_START)
	await _wait(1.0)
	_check(w.leaf_marks.is_empty() and m.stage == Main.Stage.Q3_FIND and m.hud.hint_text.begins_with("도톰을 동행"), "신발 상태에서는 동행 탐지 없음 (안내 표시)")
	m._on_portrait()
	_check(not p.shoe and d.state == Dotom.State.COMPANION and m.spirit_switch_cd == 0.0, "전투 밖에서는 대기시간 없이 다시 동행으로")
	# 동행 탐지
	d.position = Main.GAP_START + Vector2(-20, 10)
	var marked: bool = await _wait_until(func(): return m.stage == Main.Stage.Q3_TRANSFORM, 4.0)
	_check(marked and GameState.flag("q3_detect") and w.leaf_marks.size() == 1, "도톰 동행 탐지 → 안전 발판에 잎 표시")

	# 신발 없이 회피하면 틈에 빠진다 (연습 구간: 결력 회복)
	_teleport(Vector2(630, 60))
	p.gyeol = 40.0
	await _dodge_toward(Vector2.RIGHT)
	_check(p.falling, "일반 회피로는 틈을 못 건넘")
	await _wait(0.8)
	_check(p.position == Main.GAP_START and p.gyeol == p.max_gyeol, "출발 발판 복귀, 연습 구간이라 결력 즉시 회복")

	# 신발로 변신
	m._on_portrait()
	await _settle()
	_check(p.shoe and d.state == Dotom.State.EQUIPPED and not d.visible and m.hud.spirit_form == "신발", "도톰이 신발로 변신 (동행 효과 없음)")
	_check(m.stage == Main.Stage.Q3_GAP, "틈 건너기 단계")

	# 잘못된 발판(가운데)로 건너면 무너진다
	_teleport(Vector2(630, 100))
	await _dodge_toward(Vector2.RIGHT)
	await _wait(0.2)
	_check(p.falling, "잎 표시가 없는 발판에 착지하면 붕괴")
	await _wait(0.8)
	_check(p.step_cd == 0.0 and p.gyeol == p.max_gyeol, "연습 실패 복귀 시 결력과 한 걸음 대기를 함께 초기화")
	# 잎 표시 발판으로 건너기
	_teleport(Vector2(630, 60))
	p.gyeol = 100.0
	await _dodge_toward(Vector2.RIGHT)
	await _wait(0.3)
	_check(not p.falling and p.position.x > 760.0, "신발의 추가 한 걸음으로 틈 건넘 (x=%d)" % roundi(p.position.x))
	_check(GameState.flag("q3_step") and absf(p.gyeol - 90.0) < 1.0, "추가 한 걸음: 결력 10 소모, 사용 기록")
	_teleport(Vector2(835, 60))
	await _settle()
	_check(m.stage == Main.Stage.Q3_HANDLE, "건너편 도착 → 손잡이 단계")

	# 순찰기: 앞에 있으면 맞고, 뒤에 있으면 안전
	var pt = _enemy("patrol")
	pt.position = Vector2(900, 100)
	pt.facing = -1.0
	pt.state = Patrol.State.PATROL
	pt.turn_wait = 5.0
	p.respawn(Vector2(840, 100))
	p.hp = p.max_hp
	p.invuln = 0.0
	_check(await _wait_state(pt, Patrol.State.AIM, 2.0), "순찰기가 앞쪽 일직선의 플레이어를 예고")
	await _wait(1.2)
	_check(p.hp < p.max_hp, "예고를 무시하면 직선 공격에 맞음")
	pt.state = Patrol.State.PATROL
	pt.facing = -1.0
	pt.turn_wait = 5.0
	p.hp = p.max_hp
	p.invuln = 0.0
	_teleport(Vector2(960, 100))
	await _wait(1.5)
	_check(pt.state == Patrol.State.PATROL and p.hp == p.max_hp, "순찰기 뒤쪽은 안전")


	# 되받기는 Q3 보상 전이라 아직 없음
	_check(not p.try_guard(), "되받기는 아직 배우지 않음")

	_teleport(World.HANDLE_POS + Vector2(-20, 20))
	await _interact(m.handle_spot)
	_check(GameState.level == 4 and GameState.has_skill("되받기") and GameState.items.get("하천광", 0) == 2 and GameState.items.has("물길 장도 도안"), "Q3 보상: Lv.4, 되받기, 하천광 2, 물길 장도 도안")
	_check(w.gap_fixed and not w.is_pit(Vector2(700, 100)), "압력 해제 → 끊긴 점검로 복구")
	_check(m.stage == Main.Stage.Q3_DONE, "Q4 예고 단계")
	await _wait(1.8)
	_check(w.backflow < 0.1, "역류 멈춤")

	# 되받기: 막고 반격
	pt.state = Patrol.State.PATROL
	var pt_hp: float = pt.hp
	p.respawn(pt.position + Vector2(-30, 0))
	p.hp = p.max_hp
	p.gyeol = 100.0
	_check(p.try_guard(), "되받기 사용 (결력 12)")
	p.invuln = 0.0
	p.take_damage(20.0, pt.position, pt)
	_check(p.hp == p.max_hp and pt.hp < pt_hp, "되받기 중 맞으면 피해 없이 반격")


# ── 캡처 ─────────────────────────────────────────────────

func _screenshot(path: String, scenario: String) -> void:
	await _wait(0.4)
	if not scenario in ["start", "dialogue", "aim", "reward", "info"]:
		await _fast_forward_to_q2()
	match scenario:
		"dialogue":
			_teleport(m.danu.position + Vector2(0, 24))
			await _wait(0.2)
			m._on_interact(m.danu)
			await _wait(2.5)
		"aim":
			m.hud.skip_dialogue()
			m._enter_stage(Main.Stage.CROSS)
			m.player.carrying = true
			m.hud.clear_hint()
			var b = _enemy("ironbeak")
			_teleport(b.home + Vector2(-30, 110))
			await _wait_state(b, Ironbeak.State.AIM, 3.0)
			await _wait(0.45)
		"reward":
			m._enter_stage(Main.Stage.CROSS)
			m.player.carrying = true
			_teleport(m.haon.position + Vector2(0, 30))
			await _wait(0.2)
			m._on_interact(m.haon)
			m.hud.skip_dialogue()
			await _wait(0.6)
		"q2_ropes":
			var bt = _enemy("beetle", 0)
			_teleport(m.ropes[0].position + Vector2(-20, -40))
			await _wait_state(bt, Beetle.State.AIM, 5.0)
			await _wait(0.35)
		"q2_calm":
			await _to_calm()
			_teleport(m.dotom.position + Vector2(-110, 10))
			await _wait(0.8)
		"q2_follow":
			await _to_calm()
			_teleport(m.dotom.position + Vector2(-100, 0))
			await _wait_until(func(): return m.hud.dialogue_active(), 5.0)
			m.hud.skip_dialogue()
			await _wait(2.5)
			_teleport(m.dotom.position + Vector2(50, 20))
			await _wait(0.4)
		"q3_marked", "q3_shoe", "q3_patrol", "q3_done", "q3_preview":
			await _to_q3()
			_teleport(Main.GAP_START)
			m.dotom.position = Main.GAP_START + Vector2(-20, 10)
			await _wait_until(func(): return m.stage == Main.Stage.Q3_TRANSFORM, 4.0)
			await _wait(0.3)
			if scenario != "q3_marked":
				m._on_portrait()
				await _wait(1.0)
				m.hud.clear_hint()
				_teleport(Vector2(630, 60))
				await _wait(0.3)
			if scenario == "q3_preview":
				m.hud.forced_move = Vector2.RIGHT
				await _wait(0.2)
			elif scenario == "q3_shoe":
				m.hud.forced_move = Vector2.RIGHT
				m.player.move_input = Vector2.RIGHT
				m.player.try_dodge()
				await _wait(0.27)
			elif scenario == "q3_patrol":
				var pt = _enemy("patrol")
				pt.position = Vector2(960, 100)
				pt.facing = -1.0
				pt.turn_wait = 5.0
				_teleport(Vector2(850, 90))
				await _wait_state(pt, Patrol.State.AIM, 3.0)
				await _wait(0.4)
			elif scenario == "q3_done":
				_teleport(Vector2(850, 90))
				await _settle()
				_teleport(World.HANDLE_POS + Vector2(-20, 20))
				await _settle()
				m._on_interact(m.handle_spot)
				m.hud.skip_dialogue()
				await _wait(2.0)
		"info":
			m.hud.info_open = true
			m.hud.info_time = 99.0
			await _wait(0.3)
		"q4_craft":
			await _to_q4()
			_teleport(m.bench_village.position + Vector2(0, 26))
			await _settle()
			m._on_interact(m.bench_village)
			await _wait(0.3)
		"q4_hooks":
			await _to_q4()
			m._on_craft("craft:물길 장도")
			m.hud.skip_dialogue()
			_teleport(Main.RING_POS + Vector2(0, -24))
			await _interact(m.ring_spot)
			m.set_active_spirit("줄비")
			m.hud.toasts.clear()
			_teleport(Main.RING_POS + Vector2(-20, -40))
			await _wait_until(func(): return m.hooks[0].interactable, 4.0)
			await _wait(0.2)
		"q4_wave", "q4_done":
			await _to_q4()
			m._on_craft("craft:물길 장도")
			m.hud.skip_dialogue()
			_teleport(Main.RING_POS + Vector2(0, -24))
			await _interact(m.ring_spot)
			m.set_active_spirit("줄비")
			_teleport(Main.RING_POS + Vector2(0, -30))
			for i in 2:
				await _wait_until(func(): return m.hooks[i].interactable, 4.0)
				_teleport(m.hooks[i].position + Vector2(0, -22))
				await _interact(m.hooks[i])
			_teleport(Main.RING_POS + Vector2(0, -24))
			await _interact(m.ring_spot)
			m._on_portrait()
			m.hud.toasts.clear()
			m.hud.clear_hint()
			if scenario == "q4_wave":
				m.player.gyeol = 100.0
				_teleport(m.dummy.position + Vector2(-130, 0))
				m.hud.forced_move = Vector2.RIGHT
				m.player.move_input = Vector2.RIGHT
				m.player.try_dodge()
				await _wait(0.33)
				m.hud.forced_move = null
			else:
				m._enter_stage(Main.Stage.Q4_UPGRADE)
				GameState.add_item("하천광", 2)
				_teleport(Main.BENCH_MILL + Vector2(0, -26))
				await _settle()
				m._on_interact(m.bench_mill)
				m._on_craft("upgrade")
				m.hud.skip_dialogue()
				m.hud.toasts.clear()
				m.hud.clear_hint()
				_teleport(World.HATCH.get_center() + Vector2(0, -40))
				await _wait(0.4)
		_:
			await _wait(0.6)
	await RenderingServer.frame_post_draw
	var vp := get_viewport().get_visible_rect().size
	var sp: Vector2 = get_viewport().get_canvas_transform() * m.player.global_position
	print("viewport %dx%d, player screen %.0f%% x / %.0f%% y" % [vp.x, vp.y, sp.x / vp.x * 100.0, sp.y / vp.y * 100.0])
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
	get_tree().quit()


func _fast_forward_to_q2() -> void:
	m.hud.clear_hint()
	m._enter_stage(Main.Stage.CROSS)
	m.player.carrying = true
	m._deliver_q1()
	m.hud.toasts.clear()
	await _wait(2.6)
	m.hud.skip_dialogue()
	m._start_q2()
	_teleport(Main.EAST_BANK)
	await _settle()
	m.hud.clear_hint()


func _to_calm() -> void:
	for r in m.ropes:
		_teleport(r.position + Vector2(-26, 0))
		await _interact(r)
	_teleport(m.maedeup.position + Vector2(0, 20))
	await _interact(m.maedeup)
	_teleport(Main.ANCHOR_SPOT + Vector2(-20, 0))
	await _interact(m.anchor_spot)
	m.hud.toasts.clear()
	for e in m.enemies:
		if e.get_meta("kind") == "beetle":
			e.take_hit(999.0, Vector2.ZERO)


func _to_q3() -> void:
	await _to_calm()
	_teleport(m.dotom.position + Vector2(-100, 0))
	await _wait_until(func(): return m.hud.dialogue_active(), 5.0)
	m.hud.skip_dialogue()
	await _wait_until(func():
		if m.dotom.state == Dotom.State.LEAD:
			_teleport(m.dotom.position + Vector2(40, 0))
		return m.stage == Main.Stage.Q2_CONTRACT, 25.0)
	m.hud.skip_dialogue()
	m.hud.toasts.clear()
	_teleport(m.haon.position + Vector2(0, 26))
	await _interact(m.haon)
	m.hud.clear_hint()
	m.hud.toasts.clear()


## CLAUDE.md: 동행/장비 효과의 배타성·변신 취소·전환 대기시간을 직접 검증한다.
func _test_spirit_rules() -> void:
	var p = m.player
	var d = m.dotom
	m.hud.skip_dialogue()
	# 남은 적을 정리하고 전투 밖에서 동행 상태로 맞춘다
	for e in m.enemies:
		if is_instance_valid(e) and e.alive:
			e.take_hit(9999.0, Vector2.ZERO)
	await _wait(0.6)
	m.spirit_switch_cd = 0.0
	p.transform_t = 0.0
	p.respawn(Vector2(450, 120))
	if p.shoe:
		m._on_portrait()
	await _settle()

	# 효과 배타성: 이동속도와 노드 표시
	_teleport(Vector2(500, 100))
	m.hud.forced_move = Vector2.RIGHT
	await _wait(0.2)
	var v_companion: float = p.velocity.length()
	m.hud.forced_move = null
	_check(absf(v_companion - p.SPEED) < 0.5 and d.visible and not p.shoe, "동행: 신발 이동 보너스 없음 (%.0f), 도톰이 곁에 보임" % v_companion)
	m._on_portrait()
	_teleport(Vector2(500, 100))
	m.hud.forced_move = Vector2.RIGHT
	await _wait(0.2)
	var v_shoe: float = p.velocity.length()
	m.hud.forced_move = null
	_check(absf(v_shoe - p.SPEED * p.SHOE_SPEED_MULT) < 0.5 and not d.visible and d.state == Dotom.State.EQUIPPED, "신발: 이동속도 +5%% (%.0f), 동행 도톰은 사라짐" % v_shoe)
	m._on_portrait()
	await _settle()

	# 전투 중 변신: 준비 2초, 이동 불가, 피격·회피로 취소, 성공 후 10초 대기
	var dummy = Patrol.new()
	dummy.min_x = 800.0
	dummy.max_x = 800.0
	m._add_enemy(dummy, Vector2(800, 100), "patrol")
	dummy.player = p
	dummy.facing = 1.0
	dummy.turn_wait = 999.0
	_teleport(Vector2(700, 100))
	p.invuln = 0.0
	await _settle()
	m.spirit_switch_cd = 0.0
	m._on_portrait()
	_check(absf(p.transform_t - Main.TRANSFORM_COMBAT) < 0.05 and not p.shoe, "전투 중 변신은 2초 준비, 준비 중에는 아직 동행")
	m.hud.forced_move = Vector2.LEFT
	await _wait(0.3)
	m.hud.forced_move = null
	_check(p.position.distance_to(Vector2(700, 100)) < 1.0, "준비 중에는 이동할 수 없음")
	p.invuln = 0.0
	p.take_damage(1.0, dummy.position, dummy)
	_check(p.transform_t == 0.0 and not p.shoe and d.state == Dotom.State.COMPANION, "준비 중 맞으면 취소, 상태 유지")
	_check(m.spirit_switch_cd == 0.0, "취소된 변신에는 전환 대기시간 없음")
	await _wait(0.8)
	m._on_portrait()
	await _wait(0.2)
	m.hud.forced_move = Vector2.LEFT
	p.move_input = Vector2.LEFT
	p.try_dodge()
	m.hud.forced_move = null
	_check(p.transform_t == 0.0 and not p.shoe, "준비 중 회피하면 취소")
	await _wait(0.8)
	_teleport(Vector2(700, 100))
	await _settle()
	m._on_portrait()
	await _wait(Main.TRANSFORM_COMBAT + 0.2)
	_check(p.shoe and d.state == Dotom.State.EQUIPPED, "2초 준비를 마치면 신발로 전환")
	_check(m.spirit_switch_cd > Main.TRANSFORM_COMBAT_CD - 0.5, "전투 변신 성공 후 10초 전환 대기 (%.1f초 남음)" % m.spirit_switch_cd)
	m._on_portrait()
	await _settle()
	_check(p.shoe and p.transform_t == 0.0, "대기시간 중에는 다시 바꿀 수 없음")
	m.spirit_switch_cd = 0.05
	await _wait(0.2)
	_teleport(Vector2(450, 120))
	await _settle()
	m._on_portrait()
	_check(not p.shoe and d.state == Dotom.State.COMPANION, "대기시간이 끝나면 다시 전환 가능")

func _test_q4() -> void:
	var p = m.player
	var d = m.dotom
	var j = m.julbi
	m.hud.skip_dialogue()
	_check(m.stage == Main.Stage.Q3_DONE and m.dogyeom.marked, "Q3 완료 → 도겸에게 고리 보여주기")
	var cur_before: int = GameState.currency
	var ore_before: int = GameState.count("하천광")
	_teleport(m.dogyeom.position + Vector2(0, 26))
	await _interact(m.dogyeom)
	_check(m.stage == Main.Stage.Q4_CRAFT and GameState.known_recipes.has("물길 장도") and not GameState.items.has("물길 장도 도안"), "도안 제출 → 물길 장도 제작법 등록")
	_check(GameState.currency == cur_before + 50 and GameState.count("하천광") == ore_before + 2, "제작 지원금 50, 하천광 2")
	m._grant_q4_support()
	_check(GameState.currency == cur_before + 50, "도안 지원금은 한 번만 지급")

	# 작업대: 다른 허용 제작(기본 장도 강화)에 재료를 먼저 써 본다
	_teleport(m.bench_village.position + Vector2(0, 26))
	await _interact(m.bench_village)
	_check(m.hud.craft_open() and m.hud.craft_rows.size() == 2, "작업대 한 화면: 제작 1 + 강화 1")
	m._on_craft("upgrade")
	_check(GameState.weapon == "기본 장도" and GameState.weapon_plus == 1, "다른 허용 제작: 기본 장도 +1")
	m._on_craft("craft:물길 장도")
	_check(GameState.weapon == "물길 장도" and GameState.weapon_plus == 0 and absf(GameState.weapon_multiplier() - 1.35) < 0.001, "물길 장도 제작 (성능 ×1.35, 특성 보유)")
	_check(not m.hud.craft_open() and m.hud.dialogue_active(), "제작 뒤 작업대를 닫고 도겸 대사")
	m.hud.skip_dialogue()
	_check(m.stage == Main.Stage.Q4_GO_MILL, "방앗간 앞방 조사 단계")

	_teleport(Main.RING_POS + Vector2(0, -24))
	await _interact(m.ring_spot)
	_check(m.stage == Main.Stage.Q4_SWAP and GameState.temp_spirits.has("줄비") and m.hud.spirit_can_swap, "걸린 고리 조사 → 줄비 임시 동행 가능")
	_check(not m._in_combat(), "허수아비는 전투 판정에서 제외")

	# 전투 중에는 교체 불가
	var foe = Patrol.new()
	foe.min_x = 960.0
	foe.max_x = 960.0
	m._add_enemy(foe, Main.RING_POS + Vector2(0, -120), "patrol")
	foe.player = p
	foe.facing = 1.0
	foe.turn_wait = 999.0
	await _settle()
	m._on_portrait_long()
	_check(GameState.active_spirit == "도톰", "전투 중에는 활성 영물 교체 불가")
	foe.take_hit(9999.0, Vector2.ZERO)
	await _wait(0.6)
	m._switch_cd["도톰"] = 5.0
	m._on_portrait_long()
	await _settle()
	_check(m.spirit_switch_cd == 0.0 and float(m._switch_cd["도톰"]) > 4.0, "전환 대기시간은 영물마다 따로 (도톰 대기 중에도 줄비는 0)")
	m._switch_cd["도톰"] = 0.0
	_check(GameState.active_spirit == "줄비" and d.state == Dotom.State.RESTING and not d.visible and j.visible and j.state in [Julbi.State.COMPANION, Julbi.State.MARKING], "길게 눌러 교체: 줄비 동행, 도톰은 휴식")
	_check(m.stage == Main.Stage.Q4_UNHOOK, "연결쇠 풀기 단계")
	m._on_portrait()
	_check(p.gear == "", "계약 전 임시 동행은 변신할 수 없음")

	# 줄비 동행 탐지 → 연결쇠 풀기
	_teleport(Main.RING_POS + Vector2(0, -30))
	for i in 2:
		var found: bool = await _wait_until(func(): return m.hooks[i].interactable, 4.0)
		_check(found, "줄비가 연결쇠 %d을 찾아 표시" % (i + 1))
		_teleport(m.hooks[i].position + Vector2(0, -22))
		await _interact(m.hooks[i])
		_teleport(Main.RING_POS + Vector2(0, -30))
	_check(m.stage == Main.Stage.Q4_REPAIR and m.bench_mill.visible and m.dogyeom.position == Main.DOGYEOM_MILL, "연결쇠 2개 → 도겸 도착, 손잡이 수선 단계")
	_teleport(Main.RING_POS + Vector2(0, -24))
	await _interact(m.ring_spot)
	_check(GameState.spirits.has("줄비") and not GameState.temp_spirits.has("줄비") and m.stage == Main.Stage.Q4_BLADE, "무료 손잡이 수선 → 줄비 계약")

	# 줄비 검: 배타성과 파동
	m._on_portrait()
	await _settle()
	_check(p.gear == "줄비" and p.blade and not p.shoe and not j.visible and m.hud.spirit_form == "검", "줄비 검 변신 (동행 효과 없음)")
	_check(absf(p.damage_multiplier() - 1.35 * 1.04) < 0.001, "검: 기본 공격 +4%")
	var dmy = m.dummy
	var dmg_before: float = dmy.total_damage
	p.gyeol = 100.0
	p.wave_cd = 0.0
	p.trait_cd = 0.0
	p.attack_cd = 0.0
	_teleport(dmy.position + Vector2(-130, 0))
	await _dodge_toward(Vector2.RIGHT)
	await _wait(0.3)
	_check(m.stage == Main.Stage.Q4_UPGRADE and p.wave_cd > 0.0, "회피 직후 첫 공격 → 줄비 파동")
	_check(p.trait_cd > 0.0 and absf(p.gyeol - (100.0 - 15.0 + 3.0)) < 2.5, "파동 결력 15, 물길 장도 특성 결력 +3")
	_check(dmy.total_damage - dmg_before >= p.WAVE_DMG * 1.35, "파동이 정면의 허수아비에 피해")

	# 강화 재료 부족 → 도겸에게 퀘스트 재료 재지급 → +1
	_teleport(Main.BENCH_MILL + Vector2(0, -26))
	await _interact(m.bench_mill)
	var row: Dictionary = m.hud.craft_rows[0] if m.hud.craft_open() else {}
	_check(not row.is_empty() and row["id"] == "upgrade" and not row["can"], "공구대: 하천광이 모자라 강화 불가 표시")
	m.hud.close_craft()
	_teleport(m.dogyeom.position + Vector2(0, 26))
	await _interact(m.dogyeom)
	_check(GameState.count("하천광") >= 2 and int(GameState.flags.get("q4_resupply", 0)) == 1, "도겸이 이번 단계에 필요한 재료만 재지급")
	_teleport(Main.BENCH_MILL + Vector2(0, -26))
	await _interact(m.bench_mill)
	m._on_craft("upgrade")
	m.hud.skip_dialogue()
	_check(GameState.weapon_label() == "물길 장도 +1" and absf(GameState.weapon_multiplier() - 1.35 * 1.08) < 0.001, "물길 장도 +1 확정 강화")
	_check(m.stage == Main.Stage.Q4_DONE and GameState.level == 5 and GameState.count("하천광") == 3 and m.world.hatch_open, "Q4 보상: Lv.5, 다음 강화 재료, Q5 입구 열림")
	var cur_after: int = GameState.currency
	m._complete_q4()
	m.hud.skip_dialogue()
	_check(GameState.count("하천광") == 3 and GameState.currency == cur_after, "Q4 보상은 한 번만 지급")

	# 다시 도톰으로: 검 효과가 남지 않는다
	m._on_portrait_long()
	await _settle()
	_check(GameState.active_spirit == "도톰" and p.gear == "" and j.state == Julbi.State.RESTING and d.visible, "도톰으로 교체하면 줄비 검 효과 해제")


func _test_hud() -> void:
	var h = m.hud
	_check(h._quest_rect().end.y <= 180.0, "상시 정보(상태+목표)가 상단 180px 이내 (%.0f)" % h._quest_rect().end.y)
	# 터치 영역: 최소 48dp(약 96px) 지름, 서로 겹치지 않음
	var buttons := {"dodge": [h._dodge_c(), 82.0], "skill": [h._skill_c(), 64.0], "guard": [h._guard_c(), 60.0], "portrait": [h._portrait_c(), 58.0], "interact": [h._interact_c(), 66.0]}
	var min_ok := true
	for k in buttons:
		if float(buttons[k][1]) * 2.0 < 96.0:
			min_ok = false
	_check(min_ok, "버튼 입력 지름 96px 이상")
	var overlap := ""
	var keys := buttons.keys()
	for a in keys.size():
		for b in range(a + 1, keys.size()):
			var ka = keys[a]
			var kb = keys[b]
			if (buttons[ka][0] as Vector2).distance_to(buttons[kb][0]) < float(buttons[ka][1]) + float(buttons[kb][1]):
				overlap += "%s-%s " % [ka, kb]
	_check(overlap == "", "버튼 입력 영역끼리 겹치지 않음 %s" % overlap)

	# 목표 줄을 누르면 펼치고, 다시 누르면 접힌다
	var tap := InputEventScreenTouch.new()
	tap.index = 5
	tap.position = h._quest_rect().get_center()
	tap.pressed = true
	h._input(tap)
	_check(h.info_open, "목표 줄을 누르면 정보 펼침")
	h._input(tap)
	_check(not h.info_open, "다시 누르면 접힘")

	# 초상화: 짧게 = 전환, 길게 = 교체
	var taps := [0, 0]
	var c1 := func(): taps[0] += 1
	var c2 := func(): taps[1] += 1
	h.portrait_pressed.connect(c1)
	h.portrait_long_pressed.connect(c2)
	var down := InputEventScreenTouch.new()
	down.index = 6
	down.position = h._portrait_c()
	down.pressed = true
	var up := InputEventScreenTouch.new()
	up.index = 6
	up.position = h._portrait_c()
	up.pressed = false
	h._input(down)
	h._input(up)
	_check(taps[0] == 1 and taps[1] == 0, "초상화 짧게 누르기 → 동행/장비 전환 신호")
	h._input(down)
	await _wait(0.6)
	h._input(up)
	_check(taps[0] == 1 and taps[1] == 1, "초상화 길게 누르기 → 영물 교체 신호 (짧게 누르기 신호 없음)")
	h.portrait_pressed.disconnect(c1)
	h.portrait_long_pressed.disconnect(c2)
	m._on_portrait()  # 위 짧게 누르기로 바뀐 상태를 되돌린다
	m.spirit_switch_cd = 0.0

	# 대사 창 높이는 글 길이에 맞춘다
	var font := GameState.ui_font
	var w: float = h._size().x - 96
	var short_h := font.get_multiline_string_size("응.", HORIZONTAL_ALIGNMENT_LEFT, w, 28).y
	var long_h := font.get_multiline_string_size("아주 긴 대사가 여러 줄로 이어질 때는 창이 그만큼 높아져야 하고, 짧은 대사는 작은 창으로 보여서 몸과 목적지를 덜 가린다.", HORIZONTAL_ALIGNMENT_LEFT, w, 28).y
	_check(long_h > short_h * 1.8, "긴 대사는 여러 줄 (짧은 %.0f / 긴 %.0f)" % [short_h, long_h])

func _to_q4() -> void:
	await _to_q3()
	_teleport(Main.GAP_START)
	m.dotom.position = Main.GAP_START + Vector2(-20, 10)
	await _wait_until(func(): return m.stage == Main.Stage.Q3_TRANSFORM, 4.0)
	m._on_portrait()
	_teleport(Vector2(850, 90))
	await _settle()
	_teleport(World.HANDLE_POS + Vector2(-20, 20))
	await _interact(m.handle_spot)
	m._on_portrait()
	_teleport(m.dogyeom.position + Vector2(0, 26))
	await _interact(m.dogyeom)
	m.hud.toasts.clear()
	m.hud.clear_hint()

## docs/reviews/q3-review-2026-10-11.md 의 재현 조건을 본 점검에도 남긴다.
func _test_codex_review() -> void:
	var p = m.player
	# P1: 필수 대화 중에는 적이 공격하지 않는다 (대사를 즉시 넘기지 않고 읽는 동안)
	var foe = Patrol.new()
	foe.min_x = 520.0
	foe.max_x = 520.0
	m._add_enemy(foe, Vector2(520, 100), "patrol")
	foe.player = p
	foe.facing = -1.0
	foe.turn_wait = 999.0
	m.hud.skip_dialogue()
	p.respawn(Vector2(460, 100))
	p.hp = p.max_hp
	p.invuln = 0.0
	await _settle()
	m.hud.start_dialogue([["시험", "대사를 읽는 동안 순찰기가 정면에 있다."]])
	await _settle()
	var frozen_state: int = foe.state
	var frozen_t: float = foe.t
	await _wait(2.5)
	_check(p.hp == p.max_hp and not p.dead and foe.state == frozen_state and foe.t == frozen_t, "대사를 읽는 2.5초 동안 피해 없음, 적 정지")
	m.hud.skip_dialogue()
	await _settle()
	_check(p.invuln > 0.0, "대화가 끝나면 잠깐 무적으로 재개")
	foe.take_hit(9999.0, Vector2.ZERO)

	# P1: 덩굴딱정벌레 돌진이 플레이어 몸에 막히지 않고 피해를 준다
	_check(p.collision_layer == p.PLAYER_LAYER and (p.collision_layer & 3) == 0, "플레이어는 벽·틈과 다른 충돌 레이어")
	var bt = Beetle.new()
	m._add_enemy(bt, Vector2(470, 220), "beetle")
	bt.player = p
	p.respawn(Vector2(430, 120))
	p.hp = p.max_hp
	p.invuln = 0.0
	p.attack_cd = 999.0
	_check(await _wait_state(bt, Beetle.State.CHARGE, 5.0), "딱정벌레가 돌진")
	await _wait(0.6)
	_check(p.hp == p.max_hp - bt.DAMAGE, "예고를 무시하면 돌진 피해 %d (체력 %d)" % [bt.DAMAGE, roundi(p.hp)])
	p.attack_cd = 0.0
	bt.take_hit(9999.0, Vector2.ZERO)

	# 디자인: 착지 미리보기 (Q3 단계에서 틈 앞)
	var keep_stage = m.stage
	m._enter_stage(Main.Stage.Q3_GAP)
	m.world.gap_fixed = false
	m.world.set_pit("gap", true)
	p.respawn(Vector2(630, 60))
	p.gear = "도톰"
	p.step_cd = 0.0
	p.gyeol = 100.0
	m.hud.forced_move = Vector2.RIGHT
	await _wait(0.05)
	var ok_preview: bool = m.world.preview != null and m.world.preview_ok
	p.step_cd = 5.0
	await _settle()
	var short_preview: bool = m.world.preview != null and not m.world.preview_ok
	m.hud.forced_move = null
	_check(ok_preview and short_preview, "착지 미리보기: 한 걸음 가능하면 초록, 대기 중이면 빨강")
	_check(p.gear_status() == "한 걸음 5초", "초상화 아래 상태 문구 (%s)" % p.gear_status())
	m.world.fix_gap()
	p.gear = ""
	m._enter_stage(keep_stage)

	# Q4 P1 (q4-review): 물길 장도를 미리 +1 해 두었으면 파동 체험 뒤 바로 완료가 인정된다.
	var keep_weapon: String = GameState.weapon
	var keep_plus: int = GameState.weapon_plus
	var ore: int = GameState.count("하천광")
	GameState.weapon = "물길 장도"
	GameState.weapon_plus = 1
	m._enter_stage(Main.Stage.Q4_BLADE)
	m._on_wave_fired(p.position, Vector2.RIGHT)
	m.hud.skip_dialogue()
	_check(m.stage == Main.Stage.Q4_DONE and m.world.hatch_open and GameState.count("하천광") == ore, "미리 +1 강화한 물길 장도는 Q4 강화 목표로 인정 (보상 중복 없음)")
	GameState.weapon = keep_weapon
	GameState.weapon_plus = keep_plus
	m._enter_stage(keep_stage)
