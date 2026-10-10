extends Node2D
## 첫 시제품 진행 관리 (기획서 9장):
##   Q1 「물보다 먼저 도착해야」 — 이음터 → 갈대둑, 부품 전달
##   Q2 「젖은 둑의 작은 발」   — 느슨한 줄 조사, 고정점 설치, 도톰 계약
##   Q3 「마지막 한 걸음」      — 도톰 동행 탐지 → 신발 변신 → 틈 건너기 → 압력 해제
## 실행 인자 (Godot 실행 시 `--` 뒤에 붙임):
##   --autotest           전체 흐름을 자동 점검하고 종료 (성공 0 / 실패 1)
##   --shot=경로.png       장면을 캡처하고 종료.  --scenario=이름 과 함께 사용 (devtools.gd 참고)

const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const Ironbeak := preload("res://scripts/enemy_ironbeak.gd")
const Beetle := preload("res://scripts/enemy_beetle.gd")
const Patrol := preload("res://scripts/enemy_patrol.gd")
const Dotom := preload("res://scripts/spirit_dotom.gd")
const Interactable := preload("res://scripts/interactable.gd")
const Hud := preload("res://scripts/hud.gd")
const FloatText := preload("res://scripts/float_text.gd")
const DevTools := preload("res://scripts/devtools.gd")

enum Stage {
	TALK_DANU, GET_CRATE, GO_ENTRANCE, CROSS, BACKFLOW, TALK_MAEDEUP,
	Q2_GO_BANK, Q2_ROPES, Q2_GET_ROPE, Q2_ANCHOR, Q2_CALM, Q2_FOLLOW, Q2_CONTRACT,
	Q3_TALK_HAON, Q3_FIND, Q3_TRANSFORM, Q3_GAP, Q3_HANDLE, Q3_DONE,
}

const VILLAGE_START := Vector2(192, 1850)
const ENTRANCE := Vector2(192, 1420)
const EAST_BANK := Vector2(420, 905)
const NORTH_BANK := Vector2(600, 720)
const GAP_START := Vector2(600, 100)
const GAP_FAR := Vector2(850, 100)
const ROPE_POS: Array[Vector2] = [Vector2(560, 1180), Vector2(590, 560)]
const ANCHOR_SPOT := Vector2(812, 500)
const MAEDEUP_ANCHOR := Vector2(790, 450)
const MAP_SIZE := Vector2(World.W, World.H)
const Q1_TITLE := "Q1. 물보다 먼저 도착해야"
const Q2_TITLE := "Q2. 젖은 둑의 작은 발"
const Q3_TITLE := "Q3. 마지막 한 걸음"
const XP := {"ironbeak": 15, "beetle": 20, "patrol": 30}
## 상단 HUD에 가리지 않도록 플레이어를 화면 중앙보다 조금 아래에 둔다.
const CAMERA_LOOK_AHEAD := Vector2(0, -36)
## 영물 변신 (기획서 6장 규칙 5): 전투 중 2초 준비·피격 시 취소·성공 후 10초 대기.
## 전투 밖은 즉시 전환하고, 조작을 막지 않는 짧은 연출(TRANSFORM_FX초)만 보여준다.
const TRANSFORM_COMBAT := 2.0
const TRANSFORM_FX := 0.8
const TRANSFORM_COMBAT_CD := 10.0
const COMBAT_RADIUS := 220.0

var world
var player
var camera: Camera2D
var hud
var danu
var crate
var haon
var maedeup
var dotom
var ropes: Array = []
var anchor_spot
var handle_spot
var enemies: Array = []

var stage: Stage = Stage.TALK_DANU
var current_interact = null
var shake := 0.0
var moved_distance := 0.0
var spirit_switch_cd := 0.0
var _pending_shoe := false
var _transform_in_combat := false
var _last_player_pos := Vector2.ZERO
var _once: Dictionary = {}


func _ready() -> void:
	world = World.new()
	add_child(world)

	danu = _make_npc("단우", Vector2(190, 1720), Color("4a5a3a"), Color("c8a060"), Color("2a2a2a"))
	crate = _make_npc("부품 상자", Vector2(300, 1700), Color.WHITE, Color.WHITE, Color.WHITE)
	crate.kind = "crate"
	crate.action_label = "받기"
	haon = _make_npc("수문지기 하온", Vector2(192, 150), Color("5a4a6a"), Color("9ab0c0"), Color("c8c8c8"))
	maedeup = _make_npc("매듭", Vector2(250, 250), Color("3a5a6a"), Color("e09050"), Color("4a2a1a"))
	_set_present(maedeup, false)
	for p in ROPE_POS:
		var r = _make_npc("느슨한 줄", p, Color.WHITE, Color.WHITE, Color.WHITE)
		r.kind = "rope"
		r.action_label = "조사"
		ropes.append(r)
	anchor_spot = _make_npc("고정점", ANCHOR_SPOT, Color.WHITE, Color.WHITE, Color.WHITE)
	anchor_spot.kind = "spot"
	anchor_spot.action_label = "설치"
	anchor_spot.interactable = false
	handle_spot = _make_npc("압력 손잡이", World.HANDLE_POS + Vector2(-8, 18), Color.WHITE, Color.WHITE, Color.WHITE)
	handle_spot.kind = "spot"
	handle_spot.action_label = "돌리기"
	handle_spot.interactable = false

	dotom = Dotom.new()
	dotom.position = World.NEST_POS
	add_child(dotom)
	dotom.startled.connect(_on_dotom_startled)
	dotom.trusted.connect(_on_dotom_trusted)
	dotom.arrived.connect(_on_dotom_arrived)
	dotom.marked.connect(_on_dotom_marked)

	for home in [Vector2(200, 1080), Vector2(170, 720)]:
		_add_enemy(Ironbeak.new(), home, "ironbeak")
	for home in [Vector2(700, 1200), Vector2(540, 640)]:
		_add_enemy(Beetle.new(), home, "beetle")
	var patrol = Patrol.new()
	patrol.min_x = 850.0
	patrol.max_x = 1000.0
	_add_enemy(patrol, Vector2(900, 100), "patrol")

	player = Player.new()
	player.position = VILLAGE_START
	player.world = world
	add_child(player)
	player.died.connect(_on_player_died)
	player.fell.connect(_on_player_fell)
	player.dodged.connect(_on_player_dodged)
	player.extra_step_used.connect(_on_extra_step)
	player.guard_success.connect(_on_guard_success)
	player.transform_done.connect(_on_transform_done)
	player.transform_cancelled.connect(_on_transform_cancelled)
	_last_player_pos = player.position
	for e in enemies:
		e.player = player
	dotom.player = player

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = -int(World.TOP_MARGIN)
	camera.limit_right = int(MAP_SIZE.x)
	camera.limit_bottom = int(MAP_SIZE.y + World.BOTTOM_MARGIN)
	camera.offset = CAMERA_LOOK_AHEAD
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	player.add_child(camera)
	_fit_camera()
	get_viewport().size_changed.connect(_fit_camera)

	hud = Hud.new()
	add_child(hud)
	hud.player = player
	hud.interact_pressed.connect(func(): _on_interact(current_interact))
	hud.portrait_pressed.connect(_on_portrait)

	_enter_stage(Stage.TALK_DANU)
	hud.show_hint("왼쪽 아래를 누른 채 끌어서 이동하세요")

	var args := OS.get_cmdline_user_args()
	if args.has("--autotest") or _arg_value(args, "--shot=", "") != "":
		var dev = DevTools.new()
		add_child(dev)
		dev.start(self, args)


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


func _add_enemy(e, home: Vector2, kind: String) -> void:
	e.position = home
	e.set_meta("kind", kind)
	add_child(e)
	e.aim_started.connect(_on_enemy_aim)
	e.defeated.connect(_on_enemy_defeated)
	enemies.append(e)


func _set_present(n, present: bool) -> void:
	n.visible = present
	n.interactable = present


func _first(id: String) -> bool:
	if _once.has(id):
		return false
	_once[id] = true
	return true


# ── 진행 단계 ─────────────────────────────────────────────

func _enter_stage(s: Stage) -> void:
	stage = s
	for n in [danu, crate, haon, maedeup, anchor_spot, handle_spot]:
		n.marked = false
	for r in ropes:
		r.marked = false
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
			hud.set_objective(Q1_TITLE, "철부리새를 피해 수문지기 하온에게 전달", haon.position)
			hud.show_hint("가까운 적은 자동으로 공격해요. 싸우지 않고 돌아가도 괜찮아요", 4.0)
		Stage.BACKFLOW:
			hud.set_objective(Q1_TITLE, "…수문에서 이상한 소리가 난다", null)
		Stage.TALK_MAEDEUP:
			maedeup.marked = true
			hud.set_objective(Q1_TITLE, "달려온 매듭과 대화하기", maedeup.position)

		Stage.Q2_GO_BANK:
			world.goal = EAST_BANK
			hud.set_objective(Q2_TITLE, "동쪽 다리를 건너 젖은 둑으로", EAST_BANK)
		Stage.Q2_ROPES:
			_update_rope_objective()
		Stage.Q2_GET_ROPE:
			maedeup.marked = true
			hud.set_objective(Q2_TITLE, "고정점 옆의 매듭에게 가기", maedeup.position)
		Stage.Q2_ANCHOR:
			anchor_spot.interactable = true
			anchor_spot.marked = true
			hud.set_objective(Q2_TITLE, "지급된 밧줄로 고정점 설치", ANCHOR_SPOT)
		Stage.Q2_CALM:
			dotom.calm_enabled = true
			hud.set_objective(Q2_TITLE, "도톰에게 다가가기 — 가까이선 멈춰서 기다리기", dotom.position)
		Stage.Q2_FOLLOW:
			hud.set_objective(Q2_TITLE, "쫓지 말고, 도톰을 따라 안전한 둑으로", dotom.position)
		Stage.Q2_CONTRACT:
			hud.set_objective(Q2_TITLE, "안전한 둑에서 계약 대화", null)

		Stage.Q3_TALK_HAON:
			haon.marked = true
			hud.set_objective(Q3_TITLE, "북쪽 점검로의 하온에게", haon.position)
		Stage.Q3_FIND:
			world.goal = GAP_START
			hud.set_objective(Q3_TITLE, "도톰과 함께 끊긴 틈 앞으로 (동행 상태)", GAP_START)
		Stage.Q3_TRANSFORM:
			hud.set_objective(Q3_TITLE, "초상화를 눌러 도톰을 신발로", null)
			hud.show_hint("왼쪽의 도톰 초상화를 누르면 신발로 변해요")
		Stage.Q3_GAP:
			hud.set_objective(Q3_TITLE, "틈 가장자리에서 잎 표시 쪽으로 회피", World.SAFE_LANDING.get_center())
			hud.show_hint("틈 끝에 붙어서 잎 쪽으로 [회피]! 신발이 한 걸음 더 내딛어요")
		Stage.Q3_HANDLE:
			handle_spot.interactable = true
			handle_spot.marked = true
			hud.set_objective(Q3_TITLE, "순찰기를 피해 압력 손잡이 돌리기", World.HANDLE_POS)
			hud.show_hint("순찰기는 바라보는 방향으로만 쏴요. 뒤나 옆으로 돌아가세요", 4.5)
		Stage.Q3_DONE:
			hud.set_objective("Q4. 방앗간의 헐거운 이음", "다음 빌드에서 이어집니다 (도겸의 작업장)", null)


func _update_rope_objective() -> void:
	var n := 0
	for r in ropes:
		if r.checked:
			n += 1
		else:
			r.marked = true
	var target = null
	for r in ropes:
		if not r.checked:
			target = r.position
			break
	hud.set_objective(Q2_TITLE, "느슨한 줄 조사 (%d/2)" % n, target)


func _process(delta: float) -> void:
	player.locked = hud.dialogue_active()
	moved_distance += player.position.distance_to(_last_player_pos)
	_last_player_pos = player.position
	spirit_switch_cd = maxf(spirit_switch_cd - delta, 0.0)
	hud.spirit_cd = spirit_switch_cd / TRANSFORM_COMBAT_CD

	if not player.falling and not player.dead and world.update_weak(player.position, delta, player.airborne()):
		player.start_fall()

	match stage:
		Stage.TALK_DANU:
			if moved_distance > 40.0 and hud.hint_text.begins_with("왼쪽 아래"):
				hud.show_hint("단우에게 다가가 [대화] 버튼을 누르세요")
		Stage.GO_ENTRANCE:
			if player.position.y < ENTRANCE.y + 16.0:
				_enter_stage(Stage.CROSS)
		Stage.TALK_MAEDEUP:
			hud.target_world = maedeup.position
		Stage.Q2_GO_BANK:
			if player.position.distance_to(EAST_BANK) < 40.0:
				_enter_stage(Stage.Q2_ROPES)
				hud.show_hint("젖은 나무 발판 위에 오래 서 있으면 무너져요", 4.0)
		Stage.Q2_CALM, Stage.Q2_FOLLOW:
			hud.target_world = dotom.position
		Stage.Q3_FIND:
			_check_detection()
		Stage.Q3_GAP:
			if player.position.x > World.SAFE_LANDING.end.x and player.position.y < 170.0 and not player.falling:
				_enter_stage(Stage.Q3_HANDLE)

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

	if shake > 0.0:
		shake = maxf(shake - delta, 0.0)
		camera.offset = CAMERA_LOOK_AHEAD + Vector2(randf_range(-3, 3), randf_range(-3, 3)) * shake * 2.0
	else:
		camera.offset = CAMERA_LOOK_AHEAD


## Q3: 동행 도톰이 끊긴 틈 근처에 오면 안전한 착지 발판을 찾아 잎 표시를 남긴다.
func _check_detection() -> void:
	if player.position.distance_to(GAP_START) > 150.0:
		return
	if dotom.state == Dotom.State.EQUIPPED:
		if _first("hint_need_companion"):
			hud.show_hint("도톰을 동행 상태로 두어야 숨은 발판을 찾아요. 초상화를 눌러 되돌리세요", 4.0)
		return
	if dotom.state == Dotom.State.COMPANION and world.reveal_hidden_near(World.SAFE_LANDING.get_center(), 200.0):
		GameState.set_flag("q3_detect")
		dotom.run_mark(Vector2(World.PITS["gap"].position.x - 8, World.SAFE_LANDING.get_center().y))
		hud.show_hint("도톰이 건너편 발판을 살펴요…", 2.0)


# ── 상호작용 ─────────────────────────────────────────────

func _on_interact(n) -> void:
	if n == null or hud.dialogue_active() or player.dead or player.falling:
		return
	if n == danu:
		_talk_danu()
	elif n == crate:
		if stage == Stage.GET_CRATE:
			_set_present(crate, false)
			player.carrying = true
			hud.toast("교체용 부품 상자를 받았다")
			_enter_stage(Stage.GO_ENTRANCE)
	elif n == haon:
		_talk_haon()
	elif n == maedeup:
		_talk_maedeup()
	elif ropes.has(n):
		_inspect_rope(n)
	elif n == anchor_spot:
		if stage == Stage.Q2_ANCHOR:
			_install_anchor()
	elif n == handle_spot:
		if stage == Stage.Q3_HANDLE:
			_turn_handle()


func _talk_danu() -> void:
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
	elif stage < Stage.Q2_CONTRACT:
		hud.start_dialogue([["단우", "수문이 역류했다고? …매듭을 도와줘. 네 손이 필요할 거야."]])
	else:
		hud.start_dialogue([["단우", "영물과 계약했다고? 잘했어. 약속은 지키는 쪽이 먼저 지치지 않게 하는 거야."]])


func _talk_haon() -> void:
	if stage == Stage.CROSS or stage == Stage.GO_ENTRANCE:
		hud.start_dialogue([
			["하온", "오, 조합에서 온 견습생이구먼. 부품 상자, 잘 받았네."],
			["하온", "철부리새 사이를 지나왔다니 제법이야. 자, 이건 수고비일세. 단우가 맡겨 둔 장도도 함께."],
		], _deliver_q1)
	elif stage < Stage.CROSS:
		hud.start_dialogue([["하온", "부품은 아직인가? 단우에게 먼저 가 보게."]])
	elif stage == Stage.Q3_TALK_HAON:
		hud.start_dialogue([
			["하온", "왔구먼. 역류가 멈추질 않네. 점검로 끝의 압력 손잡이를 돌려야 하는데…"],
			["하온", "물살에 점검로 한가운데가 끊겼어. 사람 걸음으론 못 건너는 폭이야."],
			["하온", "그 작은 녀석이 뭔가 아는 눈치구먼. 함께 가 보게."],
		], func(): _enter_stage(Stage.Q3_FIND))
	elif stage >= Stage.Q3_FIND and stage < Stage.Q3_DONE:
		hud.start_dialogue([["하온", "건너편 손잡이일세. 무리하지 말게. 떨어져도 여기서 다시 시작하면 돼."]])
	elif stage == Stage.Q3_DONE:
		hud.start_dialogue([["하온", "그 고리는 도겸에게 보여 보게. 마을 작업장의 장인일세."]])
	else:
		hud.start_dialogue([["하온", "수문이 저렇게 거꾸로 도는 건 처음 보네… 매듭을 도와주게."]])


func _talk_maedeup() -> void:
	match stage:
		Stage.TALK_MAEDEUP:
			hud.start_dialogue([
				["매듭", "하온 어르신! 둑 아래 줄이 전부 느슨해졌어요."],
				["매듭", "넌 단우 선배네 견습생이지? 마침 잘 왔어. 젖은 발판 쪽에 손이 하나 더 필요해."],
				["매듭", "작은 영물 둥지가 물에 잠기기 직전이야. 잡으려는 게 아니라, 돌아갈 곳을 만들어 주는 거야. 같이 가 줄래?"],
			], _start_q2)
		Stage.Q2_GET_ROPE:
			hud.start_dialogue([
				["매듭", "둘 다 봤구나. 이 둑은 원래 작은 영물들이 오가는 길이었어."],
				["매듭", "이 밧줄로 섬까지 고정점을 하나 더 걸자. 둥지를 옮길 길이 생길 거야."],
			], func():
				GameState.add_item("밧줄")
				hud.toast("밧줄을 받았다")
				_enter_stage(Stage.Q2_ANCHOR))
		Stage.Q2_ANCHOR:
			hud.start_dialogue([["매듭", "물길 앞 말뚝에 밧줄을 걸면 돼."]])
		Stage.Q2_CALM:
			hud.start_dialogue([["매듭", "잡으려 하지 마. 돌아갈 곳부터 만들어줘. 가까이선 멈춰서 기다려 주고."]])
		_:
			if stage >= Stage.Q3_TALK_HAON:
				hud.start_dialogue([["매듭", "도톰이랑 잘 지내. 무리하게 데려가면 안 돼."]])
			else:
				hud.start_dialogue([["매듭", "젖은 둑은 다리 건너편이야."]])


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
		_set_present(maedeup, true)
		maedeup.position = Vector2(250, 330)
		maedeup.walk_target = player.position + Vector2(40, 30)
		hud.show_hint("사선베기: 오른쪽 아래 버튼. 비스듬히 돌진하며 베어요 (결력 15)", 5.0)
		_enter_stage(Stage.TALK_MAEDEUP))


# ── Q2 ───────────────────────────────────────────────────

func _start_q2() -> void:
	hud.toast(Q1_TITLE + " 완료")
	world.set_blocker("east_barrier", false)
	maedeup.walk_target = null
	maedeup.position = EAST_BANK + Vector2(30, -40)
	_enter_stage(Stage.Q2_GO_BANK)


func _inspect_rope(r) -> void:
	if stage != Stage.Q2_ROPES or r.checked:
		return
	r.checked = true
	r.marked = false
	var line := "줄이 물에 불어 느슨해졌다. 둑 아래로 무언가 무겁게 지나간 자국이 있다."
	if r == ropes[1]:
		line = "작은 발자국이 둥지 쪽으로 이어진다. 물이 더 차오르면 이 줄로는 버티지 못한다."
	hud.start_dialogue([["조사", line]], func():
		if ropes.all(func(x): return x.checked):
			maedeup.position = MAEDEUP_ANCHOR
			_enter_stage(Stage.Q2_GET_ROPE)
		else:
			_update_rope_objective())


func _install_anchor() -> void:
	GameState.add_item("밧줄", -1)
	anchor_spot.interactable = false
	world.build_anchor()
	hud.toast("고정점 설치 — 섬으로 밧줄 다리가 놓였다")
	hud.start_dialogue([
		["매듭", "좋아, 단단해. 저기 둥지 옆에 있는 게 도톰이야."],
		["매듭", "잡으려 하지 마. 돌아갈 곳부터 만들어줘."],
		["매듭", "겁이 많아서 뛰어오면 숨어. 가까이 가면 멈춰서 기다려 줘."],
	], func(): _enter_stage(Stage.Q2_CALM))


func _on_dotom_startled() -> void:
	hud.show_hint("놀라서 숨었어요. 가까이선 멈춰서 기다려 주세요", 3.5)


func _on_dotom_trusted() -> void:
	if stage != Stage.Q2_CALM:
		return
	hud.clear_hint()
	hud.start_dialogue([
		["도톰", "(킁킁… 발끝 냄새를 맡더니, 둥지를 등에 지고 앞장선다)"],
		["매듭", "길을 알려 주려는 거야. 쫓지 말고 따라가."],
	], func():
		var path: Array[Vector2] = [Vector2(960, 500), Vector2(880, 500), Vector2(820, 500), Vector2(700, 470), Vector2(560, 420), Vector2(470, 390)]
		dotom.start_lead(path)
		maedeup.position = World.SAFE_BANK.get_center() + Vector2(40, -20)
		_enter_stage(Stage.Q2_FOLLOW))


func _on_dotom_arrived() -> void:
	if stage != Stage.Q2_FOLLOW:
		return
	_enter_stage(Stage.Q2_CONTRACT)
	hud.start_dialogue([
		["매듭", "여기면 물이 차도 괜찮아. 돌아갈 길도 네가 같이 확인했고."],
		["매듭", "계약은 붙잡는 게 아니야. 서로 지킬 약속을 정하는 거지."],
		["도톰", "(둥지를 내려놓고, 네 신발 끝에 작은 앞발을 올린다)"],
		["매듭", "돌아갈 곳을 함께 지켜 주면, 도톰도 네 길을 지켜 줄 거래. 계약 성립이야."],
	], _complete_q2)


func _complete_q2() -> void:
	dotom.nest_pos = World.SAFE_BANK.get_center() + Vector2(-30, 10)
	dotom.nest_at_home = true
	dotom.become_companion()
	hud.spirit_form = "동행"
	if GameState.claim_reward("Q2"):
		GameState.contract_spirit("도톰")
		var gained := GameState.xp_to_level(3)
		GameState.add_item("수초섬유", 3)
		hud.toast(Q2_TITLE + " 완료")
		hud.toast("영물 계약: 도톰 (활성 1칸)")
		if gained > 0:
			hud.toast("레벨 업! Lv.%d" % GameState.level)
		hud.toast("수초섬유 +3")
	hud.show_hint("도톰은 동행할 때 숨은 발판을 찾아줘요. 북쪽 점검로로 가 봐요", 4.5)
	dotom.alert()
	world.set_blocker("steps_barrier", false)
	haon.position = Vector2(430, 120)
	_enter_stage(Stage.Q3_TALK_HAON)


# ── Q3 ───────────────────────────────────────────────────

func _on_dotom_marked() -> void:
	if stage == Stage.Q3_FIND:
		hud.toast("도톰이 안전한 발판에 잎을 남겼다")
		_enter_stage(Stage.Q3_TRANSFORM)


func _on_portrait() -> void:
	if not GameState.spirits.has("도톰") or player.transform_t > 0.0 or spirit_switch_cd > 0.0:
		return
	if hud.dialogue_active() or player.dead or player.falling:
		return
	if dotom.state == Dotom.State.MARKING:
		return
	_pending_shoe = not player.shoe
	_transform_in_combat = _in_combat()
	if _transform_in_combat:
		hud.toast("변신 준비 2초 — 맞으면 끊겨요")
		player.start_transform(TRANSFORM_COMBAT)
	else:
		player.transform_fx = TRANSFORM_FX
		_on_transform_done()


func _in_combat() -> bool:
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.position.distance_to(player.position) < COMBAT_RADIUS:
			return true
	return false


## 한 영물은 동행 또는 장비 중 한 상태만 가진다 (기획서 6장 규칙 3).
## 신발이면 dotom 노드가 숨고 동행 탐지·경고가 멈추며, 동행이면 player.shoe가 꺼져 추가 한 걸음·이동속도 보너스가 없다.
func _on_transform_done() -> void:
	if _transform_in_combat:
		spirit_switch_cd = TRANSFORM_COMBAT_CD
		_transform_in_combat = false
	if _pending_shoe:
		dotom.equip()
		player.shoe = true
		hud.spirit_form = "신발"
		if _first("first_shoe"):
			hud.toast("도톰이 신발 무늬가 되었다 — 회피 끝에 한 걸음 더")
		if stage == Stage.Q3_TRANSFORM:
			_enter_stage(Stage.Q3_GAP)
	else:
		player.shoe = false
		dotom.become_companion()
		hud.spirit_form = "동행"


func _on_transform_cancelled() -> void:
	hud.toast("변신이 끊겼다")


func _on_extra_step() -> void:
	GameState.set_flag("q3_step")
	var ft = FloatText.new()
	ft.text = "한 걸음 더!"
	ft.color = Color("b0ff70")
	ft.position = player.position + Vector2(0, -26)
	add_child(ft)


func _turn_handle() -> void:
	handle_spot.interactable = false
	if GameState.claim_reward("Q3"):
		var gained := GameState.xp_to_level(4)
		GameState.learn_skill("되받기")
		GameState.add_item("하천광", 2)
		GameState.add_item("물길 장도 도안")
		hud.toast(Q3_TITLE + " 완료 — 압력 해제")
		if gained > 0:
			hud.toast("레벨 업! Lv.%d" % GameState.level)
		hud.toast("기술 습득: 되받기")
		hud.toast("하천광 +2 · 물길 장도 도안")
	var tw := create_tween()
	tw.tween_property(world, "backflow", 0.0, 1.5)
	world.fix_gap()
	shake = 0.6
	hud.start_dialogue([
		["하온", "(멀리서) 물소리가 돌아왔어! 네가 한 걸음 더 간 덕에, 아래 마을이 숨을 쉬겠구나."],
		["조사", "압력이 빠지자 손잡이 축에 낯선 쇠고리가 드러났다. 정상 부품 위에 누군가 덧씌운 고리다."],
		["하온", "이건 우리 수문 부품이 아니야… 도겸에게 보여 보게. 마을 작업장의 장인일세."],
	], func():
		hud.show_hint("되받기: 맞기 직전에 누르면 막고 반격해요 (결력 12)", 5.0)
		_enter_stage(Stage.Q3_DONE))


# ── 전투·사고 ─────────────────────────────────────────────

func _on_enemy_aim(e) -> void:
	var kind: String = e.get_meta("kind")
	if kind == "ironbeak" and _first("hint_aim"):
		hud.show_hint("빨간 선이 차오르면 [회피]! 선 밖으로 비켜서세요", 4.0)
	elif kind == "beetle" and _first("hint_beetle"):
		hud.show_hint("덩굴딱정벌레는 돌진한 뒤 덩굴이 엉켜요. 그때가 기회!", 4.0)
	# 도톰 동행: 적의 돌진 경로를 한 번 알린다 (기획서 6장)
	if kind == "beetle" and dotom.state == Dotom.State.COMPANION:
		dotom.alert()


func _on_player_dodged() -> void:
	if _once.has("hint_aim") and not _once.has("praise_dodge"):
		for e in enemies:
			if is_instance_valid(e) and e.alive and e.get_meta("kind") == "ironbeak" and e.state == Ironbeak.State.AIM:
				_once["praise_dodge"] = true
				hud.show_hint("좋아요! 급강하 뒤 휘청일 때가 반격 기회예요", 3.0)
				break


func _on_guard_success() -> void:
	var ft = FloatText.new()
	ft.text = "되받기!"
	ft.color = Color("c8b8ff")
	ft.position = player.position + Vector2(0, -26)
	add_child(ft)


func _on_enemy_defeated(e) -> void:
	var amount: int = XP[e.get_meta("kind")]
	var gained := GameState.add_xp(amount)
	var ft = FloatText.new()
	ft.text = "+%d 경험" % amount
	ft.color = Color("9be7ff")
	ft.position = e.position + Vector2(0, -34)
	add_child(ft)
	if gained > 0:
		hud.toast("레벨 업! Lv.%d" % GameState.level)


## 쓰러지거나 빠졌을 때 돌아갈 가장 가까운 안전 지점.
func checkpoint_for(p: Vector2) -> Vector2:
	if p.x > 380.0 and p.y < 284.0:
		return GAP_FAR if p.x > World.SAFE_LANDING.end.x else GAP_START
	if p.x > 368.0 and p.y < 760.0:
		return NORTH_BANK
	if p.x > 368.0:
		return EAST_BANK
	return ENTRANCE if stage >= Stage.CROSS else VILLAGE_START


func _reset_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.reset_to_home()


func _on_player_died() -> void:
	var at := checkpoint_for(player.position)
	hud.show_fade("쓰러졌다…\n가까운 안전한 곳에서 다시 시작합니다.\n얻은 것은 그대로예요.")
	await get_tree().create_timer(1.6).timeout
	player.respawn(at)
	camera.reset_smoothing()
	_reset_enemies()
	hud.hide_fade()


func _on_player_fell() -> void:
	var at := checkpoint_for(player.position)
	# 틈 연습 구간(건너기 전)에서는 결력을 바로 채운다 (기획서 Q3 실패 조건).
	var practice := at == GAP_START
	hud.toast("발판이 무너졌다 — 다시 해 봐요" if practice else "빠졌다 — 가까운 둑에서 다시")
	await get_tree().create_timer(0.6).timeout
	world.reset_weak()
	player.respawn(at, practice)
	camera.reset_smoothing()
	if dotom.state == Dotom.State.COMPANION:
		dotom.position = at + Vector2(14, 6)
