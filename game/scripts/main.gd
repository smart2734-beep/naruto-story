extends Node2D
## 첫 시제품 진행 관리: 이음터 → 갈대둑, Q1 「물보다 먼저 도착해야」.
## 실행 인자 (Godot 실행 시 `--` 뒤에 붙임):
##   --autotest           Q1 전체 흐름을 자동 점검하고 종료 (성공 0 / 실패 1)
##   --shot=경로.png       장면을 캡처하고 종료.  --scenario=start|dialogue|aim|reward 와 함께 사용

const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const Ironbeak := preload("res://scripts/enemy_ironbeak.gd")
const Interactable := preload("res://scripts/interactable.gd")
const Hud := preload("res://scripts/hud.gd")
const FloatText := preload("res://scripts/float_text.gd")

enum Stage { TALK_DANU, GET_CRATE, GO_ENTRANCE, CROSS, BACKFLOW, TALK_MAEDEUP, Q1_DONE }

const VILLAGE_START := Vector2(192, 1850)
const ENTRANCE := Vector2(192, 1420)
const MAP_SIZE := Vector2(384, 1920)
const Q1_TITLE := "Q1. 물보다 먼저 도착해야"
const BIRD_XP := 15
## 상단 HUD에 가리지 않도록 플레이어를 화면 중앙보다 조금 아래에 둔다.
const CAMERA_LOOK_AHEAD := Vector2(0, -36)

var world
var player
var camera: Camera2D
var hud
var danu
var crate
var haon
var maedeup
var birds: Array = []

var stage: Stage = Stage.TALK_DANU
var respawn_point := VILLAGE_START
var current_interact = null
var shake := 0.0
var moved_distance := 0.0
var _last_player_pos := Vector2.ZERO
var _first_aim_seen := false
var _first_dodge_praised := false


func _ready() -> void:
	world = World.new()
	add_child(world)

	danu = _make_npc("단우", Vector2(190, 1720), Color("4a5a3a"), Color("c8a060"), Color("2a2a2a"))
	crate = _make_npc("부품 상자", Vector2(300, 1700), Color.WHITE, Color.WHITE, Color.WHITE)
	crate.kind = "crate"
	crate.action_label = "받기"
	haon = _make_npc("수문지기 하온", Vector2(192, 150), Color("5a4a6a"), Color("9ab0c0"), Color("c8c8c8"))
	maedeup = _make_npc("매듭", Vector2(250, 250), Color("3a5a6a"), Color("e09050"), Color("4a2a1a"))
	maedeup.visible = false
	maedeup.interactable = false

	for home in [Vector2(200, 1080), Vector2(170, 720)]:
		var b = Ironbeak.new()
		b.position = home
		add_child(b)
		b.aim_started.connect(_on_bird_aim)
		b.defeated.connect(_on_bird_defeated)
		birds.append(b)

	player = Player.new()
	player.position = VILLAGE_START
	add_child(player)
	player.died.connect(_on_player_died)
	player.dodged.connect(_on_player_dodged)
	_last_player_pos = player.position
	for b in birds:
		b.player = player

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = -int(World.TOP_MARGIN)
	camera.offset = CAMERA_LOOK_AHEAD
	camera.limit_right = int(MAP_SIZE.x)
	camera.limit_bottom = int(MAP_SIZE.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	player.add_child(camera)
	_fit_camera()
	get_viewport().size_changed.connect(_fit_camera)

	hud = Hud.new()
	add_child(hud)
	hud.player = player
	hud.interact_pressed.connect(func(): _on_interact(current_interact))

	_enter_stage(Stage.TALK_DANU)
	hud.show_hint("왼쪽 아래를 누른 채 끌어서 이동하세요")

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autotest":
			_run_autotest()
		elif a.begins_with("--shot="):
			_run_screenshot(a.substr(7), _arg_value(args, "--scenario=", "start"))


func _arg_value(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


## 가로 약 10타일(320px)이 보이도록 확대 배율을 맞춘다.
func _fit_camera() -> void:
	var w := get_viewport().get_visible_rect().size.x
	var z := w / 320.0
	camera.zoom = Vector2(z, z)


func _make_npc(npc_name: String, pos: Vector2, body: Color, accent: Color, hair: Color):
	var n = Interactable.new()
	n.display_name = npc_name
	n.position = pos
	n.body_color = body
	n.accent = accent
	n.hair = hair
	add_child(n)
	return n


# ── 진행 단계 ─────────────────────────────────────────────

func _enter_stage(s: Stage) -> void:
	stage = s
	for n in [danu, crate, haon, maedeup]:
		n.marked = false
	world.goal = null
	match s:
		Stage.TALK_DANU:
			danu.marked = true
			hud.set_objective(Q1_TITLE, "교관 단우와 대화하기", danu.position)
		Stage.GET_CRATE:
			crate.marked = true
			hud.set_objective(Q1_TITLE, "표시된 부품 상자 받기", crate.position)
		Stage.GO_ENTRANCE:
			world.goal = ENTRANCE
			hud.set_objective(Q1_TITLE, "마을 북문을 지나 갈대둑 입구로", ENTRANCE)
			hud.show_hint("노란 화살표와 고리가 다음 목적지예요", 3.5)
		Stage.CROSS:
			haon.marked = true
			respawn_point = ENTRANCE
			hud.set_objective(Q1_TITLE, "철부리새를 피해 수문지기 하온에게 전달", haon.position)
			hud.show_hint("가까운 적은 자동으로 공격해요. 싸우지 않고 돌아가도 괜찮아요", 4.0)
		Stage.BACKFLOW:
			hud.set_objective(Q1_TITLE, "…수문에서 이상한 소리가 난다", null)
		Stage.TALK_MAEDEUP:
			maedeup.marked = true
			hud.set_objective(Q1_TITLE, "달려온 매듭과 대화하기", maedeup.position)
		Stage.Q1_DONE:
			hud.set_objective("Q2. 젖은 둑의 작은 발", "다음 빌드에서 이어집니다 (도톰 계약)", null)


func _process(delta: float) -> void:
	player.locked = hud.dialogue_active()
	moved_distance += player.position.distance_to(_last_player_pos)
	_last_player_pos = player.position

	if stage == Stage.TALK_DANU and moved_distance > 40.0 and hud.hint_text.begins_with("왼쪽 아래"):
		hud.show_hint("단우에게 다가가 [대화] 버튼을 누르세요")
	if stage == Stage.GO_ENTRANCE and player.position.y < ENTRANCE.y + 16.0:
		_enter_stage(Stage.CROSS)

	# 가장 가까운 상호작용 대상
	current_interact = null
	var best := 44.0
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.visible and n.interactable:
			var d: float = player.position.distance_to(n.position)
			if d < best:
				best = d
				current_interact = n
	hud.interact_label = current_interact.action_label if current_interact != null and not player.dead else ""

	if stage == Stage.TALK_MAEDEUP:
		hud.target_world = maedeup.position

	if shake > 0.0:
		shake = maxf(shake - delta, 0.0)
		camera.offset = CAMERA_LOOK_AHEAD + Vector2(randf_range(-3, 3), randf_range(-3, 3)) * shake * 2.0
	else:
		camera.offset = CAMERA_LOOK_AHEAD


func _on_interact(n) -> void:
	if n == null or hud.dialogue_active() or player.dead:
		return
	if n == danu:
		if stage == Stage.TALK_DANU:
			hud.clear_hint()
			hud.start_dialogue([
				["단우", "왔구나. 오늘 네 첫 임무는 배달이야."],
				["단우", "갈대둑 수문지기 하온 어르신께 교체용 부품을 전해 드려. 상자는 저기 표시해 뒀어."],
				["단우", "길에 철부리새가 있어. 덤비기 전에 꼭 일직선으로 노려보니까, 그 선이 보이면 옆으로 피해."],
				["단우", "빠르게 가라는 뜻이 아니야. 도착해야 한다는 뜻이지."],
			], func(): _enter_stage(Stage.GET_CRATE))
		elif stage == Stage.GET_CRATE:
			hud.start_dialogue([["단우", "상자는 오른쪽에 표시해 둔 거야."]])
		elif stage < Stage.BACKFLOW:
			hud.start_dialogue([["단우", "서두를 필요 없어. 다치지 말고 도착만 해."]])
		else:
			hud.start_dialogue([["단우", "수문이 역류했다고? …매듭을 도와줘. 네 손이 필요할 거야."]])
	elif n == crate:
		if stage == Stage.GET_CRATE:
			crate.visible = false
			crate.interactable = false
			player.carrying = true
			hud.toast("교체용 부품 상자를 받았다")
			_enter_stage(Stage.GO_ENTRANCE)
	elif n == haon:
		if stage == Stage.CROSS or stage == Stage.GO_ENTRANCE:
			hud.start_dialogue([
				["하온", "오, 조합에서 온 견습생이구먼. 부품 상자, 잘 받았네."],
				["하온", "철부리새 사이를 지나왔다니 제법이야. 자, 이건 수고비일세. 단우가 맡겨 둔 장도도 함께."],
			], _deliver_q1)
		elif stage < Stage.CROSS:
			hud.start_dialogue([["하온", "부품은 아직인가? 단우에게 먼저 가 보게."]])
		else:
			hud.start_dialogue([["하온", "수문이 저렇게 거꾸로 도는 건 처음 보네… 매듭을 도와주게."]])
	elif n == maedeup:
		if stage == Stage.TALK_MAEDEUP:
			hud.start_dialogue([
				["매듭", "하온 어르신! 둑 아래 줄이 전부 느슨해졌어요."],
				["매듭", "넌 단우 선배네 견습생이지? 마침 잘 왔어. 젖은 발판 쪽에 손이 하나 더 필요해."],
				["매듭", "작은 영물 둥지가 물에 잠기기 직전이야. 잡으려는 게 아니라, 돌아갈 곳을 만들어 주는 거야. 같이 가 줄래?"],
			], func():
				hud.toast(Q1_TITLE + " 완료")
				_enter_stage(Stage.Q1_DONE))
		else:
			hud.start_dialogue([["매듭", "준비되면 젖은 둑으로 가자. (다음 빌드에서 이어집니다)"]])


func _deliver_q1() -> void:
	player.carrying = false
	hud.clear_hint()
	if GameState.claim_reward("Q1"):
		var gained := GameState.xp_to_level(2)
		GameState.add_currency(20)
		GameState.learn_skill("사선베기")
		GameState.weapon = "기본 장도"
		GameState.changed.emit()
		hud.toast("부품 전달 완료!")
		if gained > 0:
			hud.toast("레벨 업! Lv.%d" % GameState.level)
		hud.toast("재화 +20 · 장비: 기본 장도")
		hud.toast("기술 습득: 사선베기")
	_enter_stage(Stage.BACKFLOW)
	_play_backflow()


func _play_backflow() -> void:
	await get_tree().create_timer(1.6).timeout
	shake = 1.0
	var tw := create_tween()
	tw.tween_property(world, "backflow", 1.0, 1.2)
	await get_tree().create_timer(0.8).timeout
	hud.start_dialogue([["하온", "…잠깐, 이 소리는? 수문이 거꾸로 돌고 있어!"]], func():
		maedeup.visible = true
		maedeup.interactable = true
		maedeup.position = Vector2(250, 330)
		maedeup.walk_target = player.position + Vector2(40, 30)
		hud.show_hint("사선베기: 오른쪽 아래 버튼. 비스듬히 돌진하며 베어요 (결력 15)", 5.0)
		_enter_stage(Stage.TALK_MAEDEUP))


# ── 전투 이벤트 ───────────────────────────────────────────

func _on_bird_aim(_bird) -> void:
	if not _first_aim_seen:
		_first_aim_seen = true
		hud.show_hint("빨간 선이 차오르면 [회피]! 선 밖으로 비켜서세요", 4.0)


func _on_player_dodged() -> void:
	if _first_aim_seen and not _first_dodge_praised:
		for b in birds:
			if is_instance_valid(b) and b.alive and b.state == Ironbeak.State.AIM:
				_first_dodge_praised = true
				hud.show_hint("좋아요! 급강하 뒤 휘청일 때가 반격 기회예요", 3.0)
				break


func _on_bird_defeated(bird) -> void:
	var gained := GameState.add_xp(BIRD_XP)
	var ft = FloatText.new()
	ft.text = "+%d 경험" % BIRD_XP
	ft.color = Color("9be7ff")
	ft.position = bird.position + Vector2(0, -34)
	add_child(ft)
	if gained > 0:
		hud.toast("레벨 업! Lv.%d" % GameState.level)


func _on_player_died() -> void:
	hud.show_fade("쓰러졌다…\n갈대둑 입구에서 다시 시작합니다.\n부품은 그대로예요.")
	await get_tree().create_timer(1.6).timeout
	player.respawn(respawn_point)
	camera.reset_smoothing()
	for b in birds:
		if is_instance_valid(b):
			b.reset_to_home()
	hud.hide_fade()


# ── 자동 점검 / 스크린샷 ──────────────────────────────────

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## 순간이동 뒤 _process가 한 번 이상 돌도록 기다린다.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _teleport(p: Vector2) -> void:
	player.position = p
	_last_player_pos = p
	camera.reset_smoothing()


func _bird_wait_aim(bird, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if bird.state == Ironbeak.State.AIM:
			return true
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
	return false


func _run_autotest() -> void:
	var fails: Array[String] = []
	var check := func(ok: bool, what: String):
		print(("  [OK]   " if ok else "  [FAIL] ") + what)
		if not ok:
			fails.append(what)
	print("=== AUTOTEST Q1 ===")
	await _wait(0.3)

	check.call(stage == Stage.TALK_DANU, "시작 단계는 단우와 대화")
	_teleport(danu.position + Vector2(0, 24))
	await _settle()
	check.call(current_interact == danu, "단우 근처에서 상호작용 대상이 단우")
	_on_interact(current_interact)
	check.call(player.locked or hud.dialogue_active(), "대화 중 조작 잠금")
	hud.skip_dialogue()
	check.call(stage == Stage.GET_CRATE, "대화 후 상자 받기 단계")

	_teleport(crate.position + Vector2(-24, 0))
	await _settle()
	_on_interact(current_interact)
	check.call(player.carrying and stage == Stage.GO_ENTRANCE, "상자 받은 뒤 입구 이동 단계")

	_teleport(ENTRANCE + Vector2(0, -20))
	await _settle()
	check.call(stage == Stage.CROSS and respawn_point == ENTRANCE, "입구 도착 → 필드 진입, 재시작 지점 갱신")

	# 1) 가만히 서 있으면 급강하에 맞는다
	var b1 = birds[0]
	_teleport(b1.home + Vector2(0, 120))
	var aimed: bool = await _bird_wait_aim(b1, 3.0)
	check.call(aimed, "철부리새가 근처 플레이어를 노려봄(예고)")
	check.call(_first_aim_seen and hud.hint_text.begins_with("빨간 선"), "첫 예고 때 회피 안내 표시")
	await _wait(1.3)
	check.call(player.hp < player.max_hp, "예고를 무시하면 피해를 입음 (체력 %d)" % roundi(player.hp))

	# 2) 예고 중 옆으로 회피하면 맞지 않는다
	b1.hp = b1.max_hp
	player.respawn(b1.home + Vector2(0, 120))
	b1.reset_to_home()
	aimed = await _bird_wait_aim(b1, 3.0)
	await _wait(0.5)
	player.move_input = b1.dir.orthogonal()
	player.try_dodge()
	await _wait(0.2)
	player.move_input = Vector2.ZERO
	await _wait(1.0)
	check.call(player.hp == player.max_hp, "예고 중 옆으로 회피하면 피해 없음")

	# 3) 처치 시 경험치
	var xp_before: int = GameState.xp
	b1.take_hit(100.0, player.position)
	check.call(not b1.alive and GameState.xp == xp_before + BIRD_XP, "철부리새 처치 시 경험치 +%d" % BIRD_XP)

	# 4) 쓰러지면 입구에서 재시작, 부품 유지
	_teleport(ENTRANCE + Vector2(0, -200))
	player.hp = 1.0
	player.invuln = 0.0
	player.take_damage(5.0, player.position + Vector2(0, 10))
	check.call(player.dead and hud.fade > 0.0, "체력 0 → 쓰러짐 화면")
	await _wait(2.0)
	check.call(not player.dead and player.position.distance_to(ENTRANCE) < 2.0 and player.carrying and player.hp == player.max_hp, "입구에서 재시작, 부품 유지, 체력 회복")

	# 5) 전달과 보상
	_teleport(haon.position + Vector2(0, 30))
	await _settle()
	check.call(current_interact == haon, "하온 근처에서 상호작용 대상이 하온")
	_on_interact(current_interact)
	hud.skip_dialogue()
	check.call(GameState.level == 2 and GameState.currency == 20 and GameState.has_skill("사선베기") and GameState.weapon == "기본 장도", "보상: Lv.2, 재화 20, 사선베기, 기본 장도")
	check.call(not player.carrying and stage == Stage.BACKFLOW, "전달 후 수문 이벤트 단계")

	await _wait(3.0)
	hud.skip_dialogue()
	check.call(world.backflow > 0.5, "수문 역류 연출")
	check.call(maedeup.visible and stage == Stage.TALK_MAEDEUP, "매듭 등장, Q2 요청 대기")
	await _wait(2.0)
	_teleport(maedeup.position + Vector2(0, 20))
	await _settle()
	_on_interact(current_interact)
	hud.skip_dialogue()
	check.call(stage == Stage.Q1_DONE, "매듭 대화 후 Q1 완료")

	# 6) 보상 중복 없음
	_teleport(haon.position + Vector2(0, 30))
	await _settle()
	_on_interact(haon)
	hud.skip_dialogue()
	_deliver_q1()
	check.call(GameState.currency == 20, "Q1 보상은 한 번만 지급")

	# 7) 사선베기
	player.gyeol = 100.0
	var used: bool = player.try_skill()
	check.call(used and absf(player.gyeol - 85.0) < 0.01, "사선베기 사용 시 결력 15 소모")
	check.call(not player.try_skill(), "재사용 대기 중에는 다시 쓸 수 없음")

	print("=== RESULT: %s (%d fail) ===" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)


func _run_screenshot(path: String, scenario: String) -> void:
	await _wait(0.4)
	match scenario:
		"dialogue":
			_teleport(danu.position + Vector2(0, 24))
			await _wait(0.2)
			_on_interact(danu)
			await _wait(2.5)
		"aim":
			hud.skip_dialogue()
			_enter_stage(Stage.CROSS)
			player.carrying = true
			hud.clear_hint()
			_teleport(birds[0].home + Vector2(-30, 110))
			await _bird_wait_aim(birds[0], 3.0)
			await _wait(0.45)
		"reward":
			_enter_stage(Stage.CROSS)
			player.carrying = true
			_teleport(haon.position + Vector2(0, 30))
			await _wait(0.2)
			_on_interact(haon)
			hud.skip_dialogue()
			await _wait(0.6)
		_:
			await _wait(0.6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
	get_tree().quit()
