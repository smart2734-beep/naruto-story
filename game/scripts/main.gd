extends Node2D
## 첫 시제품 진행 관리 (기획서 9장):
##   Q1 「물보다 먼저 도착해야」 — 이음터 → 갈대둑, 부품 전달
##   Q2 「젖은 둑의 작은 발」   — 느슨한 줄 조사, 고정점 설치, 도톰 계약
##   Q3 「마지막 한 걸음」      — 도톰 동행 탐지 → 신발 변신 → 틈 건너기 → 압력 해제
##   Q4 「방앗간의 헐거운 이음」 — 도안 제출·물길 장도 제작 → 줄비 임시 동행·연결쇠 → 손잡이 수선·계약 → 검 변신 → +1 강화
## 실행 인자 (Godot 실행 시 `--` 뒤에 붙임):
##   --autotest           전체 흐름을 자동 점검하고 종료 (성공 0 / 실패 1)
##   --shot=경로.png       장면을 캡처하고 종료.  --scenario=이름 과 함께 사용 (devtools.gd 참고)

const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const Ironbeak := preload("res://scripts/enemy_ironbeak.gd")
const Beetle := preload("res://scripts/enemy_beetle.gd")
const Patrol := preload("res://scripts/enemy_patrol.gd")
const Dotom := preload("res://scripts/spirit_dotom.gd")
const Julbi := preload("res://scripts/spirit_julbi.gd")
const Dummy := preload("res://scripts/enemy_dummy.gd")
const FxWave := preload("res://scripts/fx_wave.gd")
const Dungeon := preload("res://scripts/dungeon.gd")
const Boss := preload("res://scripts/enemy_boss_claw.gd")
const Worker := preload("res://scripts/npc_worker.gd")
const Interactable := preload("res://scripts/interactable.gd")
const Hud := preload("res://scripts/hud.gd")
const FloatText := preload("res://scripts/float_text.gd")
const DevTools := preload("res://scripts/devtools.gd")

enum Stage {
	TALK_DANU, GET_CRATE, GO_ENTRANCE, CROSS, BACKFLOW, TALK_MAEDEUP,
	Q2_GO_BANK, Q2_ROPES, Q2_GET_ROPE, Q2_ANCHOR, Q2_CALM, Q2_FOLLOW, Q2_CONTRACT,
	Q3_TALK_HAON, Q3_FIND, Q3_TRANSFORM, Q3_GAP, Q3_HANDLE,
	Q3_DONE,  # = Q4 시작: 도겸에게 고리 보여주기
	Q4_CRAFT, Q4_GO_MILL, Q4_SWAP, Q4_UNHOOK, Q4_REPAIR, Q4_BLADE, Q4_UPGRADE,
	Q4_DONE,  # = Q5 시작: 단우에게 알리기
	Q5_GO, Q5_ROOM1, Q5_DRAIN, Q5_RESCUE, Q5_ESCORT, Q5_BOSS, Q5_CORE, Q5_END,
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
const Q4_TITLE := "Q4. 방앗간의 헐거운 이음"
const DOGYEOM_VILLAGE := Vector2(300, 1622)
const DOGYEOM_MILL := Vector2(880, 1236)
const BENCH_VILLAGE := Vector2(352, 1652)
const BENCH_MILL := Vector2(836, 1262)
const RING_POS := Vector2(955, 1290)
const HOOK_POS: Array[Vector2] = [Vector2(885, 1290), Vector2(1025, 1290)]
const JULBI_HOME := Vector2(1000, 1240)
const DUMMY_POS := Vector2(910, 1196)
const Q5_TITLE := "Q5. 물을 돌려놓는 손"
const XP := {"ironbeak": 15, "beetle": 20, "patrol": 30, "dummy": 0, "boss": 120}
const OVERWORLD_LIMITS := Rect2(0, -World.TOP_MARGIN, World.W, World.H + World.BOTTOM_MARGIN + World.TOP_MARGIN)
const DUNGEON_LIMITS := Rect2(Dungeon.X0, -120, Dungeon.X1 - Dungeon.X0, Dungeon.Y1 + 200)
## 상단 HUD에 가리지 않도록 플레이어를 화면 중앙보다 조금 아래에 둔다.
const CAMERA_LOOK_AHEAD := Vector2(0, -36)
## 영물 변신 (기획서 6장 규칙 5): 전투 중 2초 준비·피격 시 취소·성공 후 10초 대기.
## 전투 밖은 즉시 전환하고, 조작을 막지 않는 짧은 연출(TRANSFORM_FX초)만 보여준다.
const TRANSFORM_COMBAT := 2.0
const TRANSFORM_FX := 0.8
const TRANSFORM_COMBAT_CD := 10.0
const COMBAT_RADIUS := 220.0
## 대화·작업대·암전 중에는 적과 위험 판정을 멈춘다. 다시 움직일 때 플레이어에게 잠깐 무적을 준다.
const RESUME_GRACE := 0.8
const PREVIEW_CAMERA_SHIFT := 80.0

var world
var player
var camera: Camera2D
var hud
var danu
var crate
var haon
var maedeup
var dotom
var julbi
var spirit_nodes: Dictionary = {}
var ropes: Array = []
var anchor_spot
var handle_spot
var dogyeom
var bench_village
var bench_mill
var ring_spot
var hooks: Array = []
var dummy
var enemies: Array = []
# Q5: 물레방아 아래 던전
var dungeon
var boss
var worker
var hatch_spot
var plaque_spot
var handle_l_spot
var handle_r_spot
var sluice_spot
var core_spot
var in_dungeon := false
var _drain_time := 0.0

var stage: Stage = Stage.TALK_DANU
var current_interact = null
var shake := 0.0
var moved_distance := 0.0
## 전투 변신 뒤 전환 대기시간은 영물마다 따로 센다 (기획서 6장 규칙 5: "해당 영물에").
var _switch_cd: Dictionary = {}
var spirit_switch_cd: float:
	get:
		return float(_switch_cd.get(GameState.active_spirit, 0.0))
	set(v):
		_switch_cd[GameState.active_spirit] = v
var _pending_gear := ""  ## 변신이 끝나면 적용할 장비 상태 ("" = 동행으로)
var _pending_spirit := ""  ## 변신을 시작한 영물. 결과와 대기시간은 이 영물에만 적용한다.
var _hook_marking := false
var _paused := false
var pan_offset := Vector2.ZERO  ## 착지 지점을 보여주는 짧은 카메라 이동
var preview_offset := Vector2.ZERO  ## 착지 미리보기가 화면 안에 들어오도록 카메라를 밀어 주는 값
var _transform_in_combat := false
var _last_player_pos := Vector2.ZERO
var _once: Dictionary = {}


func _ready() -> void:
	world = World.new()
	add_child(world)
	dungeon = Dungeon.new()
	add_child(dungeon)

	danu = _make_npc("단우", Vector2(190, 1720), Color("4a5a3a"), Color("c8a060"), Color("2a2a2a"), preload("res://assets/characters/danu-frames.tres"))
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

	# Q4: 마을 작업장과 방앗간
	dogyeom = _make_npc("장인 도겸", DOGYEOM_VILLAGE, Color("5a5048"), Color("c8a050"), Color("3a3030"))
	bench_village = _make_npc("작업대", BENCH_VILLAGE, Color.WHITE, Color.WHITE, Color.WHITE)
	bench_village.kind = "bench"
	bench_village.action_label = "작업"
	bench_mill = _make_npc("공구대", BENCH_MILL, Color.WHITE, Color.WHITE, Color.WHITE)
	bench_mill.kind = "bench"
	bench_mill.action_label = "작업"
	_set_present(bench_mill, false)
	ring_spot = _make_npc("걸린 고리", RING_POS, Color.WHITE, Color.WHITE, Color.WHITE)
	ring_spot.kind = "spot"
	ring_spot.action_label = "조사"
	ring_spot.interactable = false
	for p in HOOK_POS:
		var h = _make_npc("연결쇠", p, Color.WHITE, Color.WHITE, Color.WHITE)
		h.kind = "hook"
		h.action_label = "풀기"
		h.interactable = false
		hooks.append(h)

	dotom = Dotom.new()
	dotom.position = World.NEST_POS
	add_child(dotom)
	dotom.startled.connect(_on_dotom_startled)
	dotom.trusted.connect(_on_dotom_trusted)
	dotom.arrived.connect(_on_dotom_arrived)
	dotom.marked.connect(_on_dotom_marked)
	julbi = Julbi.new()
	julbi.position = JULBI_HOME
	add_child(julbi)
	julbi.marked.connect(_on_julbi_marked)
	spirit_nodes = {"도톰": dotom, "줄비": julbi}

	for home in [Vector2(200, 1080), Vector2(170, 720)]:
		_add_enemy(Ironbeak.new(), home, "ironbeak")
	for home in [Vector2(700, 1200), Vector2(540, 640)]:
		_add_enemy(Beetle.new(), home, "beetle")
	var patrol = Patrol.new()
	patrol.min_x = 850.0
	patrol.max_x = 1000.0
	_add_enemy(patrol, Vector2(900, 100), "patrol")
	dummy = Dummy.new()
	_add_enemy(dummy, DUMMY_POS, "dummy")
	# Q5 던전: 1방의 일반 적과 3방의 보스
	for home in [Vector2(1340, 1220), Vector2(1545, 1265)]:
		_add_enemy(Beetle.new(), home, "beetle")
	boss = Boss.new()
	boss.dungeon = dungeon
	_add_enemy(boss, Dungeon.BOSS_HOME, "boss")
	boss.release_started.connect(_on_boss_release)
	boss.flooded.connect(_on_boss_flooded)

	# Q5 상호작용
	hatch_spot = _make_spot("방앗간 아래", World.HATCH.get_center() + Vector2(0, -26), "내려가기")
	plaque_spot = _make_spot("안내판", Dungeon.PLAQUE + Vector2(0, 22), "읽기")
	plaque_spot.interactable = true
	handle_l_spot = _make_spot("왼쪽 물레 손잡이", Dungeon.HANDLE_L + Vector2(0, 26), "돌리기")
	handle_r_spot = _make_spot("오른쪽 물레 손잡이", Dungeon.HANDLE_R + Vector2(0, 26), "돌리기")
	sluice_spot = _make_spot("수문 손잡이", Dungeon.SLUICE + Vector2(0, 20), "내리기")
	core_spot = _make_spot("멈춘 정비기", Dungeon.BOSS_HOME, "회수")
	worker = Worker.new()
	worker.display_name = "정비공 보리"
	worker.position = Vector2(1440, 700)
	worker.body_color = Color("4a5a6a")
	worker.accent = Color("d2ad62")
	worker.hair = Color("5a3a20")
	worker.dungeon = dungeon
	worker.wait_spot = Dungeon.WAIT_SPOT
	add_child(worker)
	worker.interactable = false
	worker.reached_wait_spot.connect(_on_worker_waiting)
	worker.downed.connect(_on_worker_downed)

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
	player.wave_fired.connect(_on_wave_fired)
	player.trait_triggered.connect(_on_trait_triggered)
	_last_player_pos = player.position
	for e in enemies:
		e.player = player
	dotom.player = player
	julbi.player = player
	worker.player = player

	camera = Camera2D.new()
	_apply_camera_limits(OVERWORLD_LIMITS)
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
	hud.portrait_long_pressed.connect(_on_portrait_long)
	hud.craft_picked.connect(_on_craft)

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


func _apply_camera_limits(r: Rect2) -> void:
	camera.limit_left = int(r.position.x)
	camera.limit_top = int(r.position.y)
	camera.limit_right = int(r.end.x)
	camera.limit_bottom = int(r.end.y)


func _make_spot(label_name: String, pos: Vector2, action: String):
	var n = _make_npc(label_name, pos, Color.WHITE, Color.WHITE, Color.WHITE)
	n.kind = "spot"
	n.action_label = action
	n.interactable = false
	return n


func _make_npc(npc_name: String, pos: Vector2, body: Color, accent: Color, hair: Color, frames: SpriteFrames = null):
	var n = Interactable.new()
	n.frames = frames
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
	for n in [danu, crate, haon, maedeup, anchor_spot, handle_spot, dogyeom, bench_village, bench_mill, ring_spot,
			hatch_spot, plaque_spot, handle_l_spot, handle_r_spot, sluice_spot, core_spot, worker]:
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
			hud.show_hint("아래쪽 도톰 초상화를 누르면 신발로 변해요")
		Stage.Q3_GAP:
			hud.set_objective(Q3_TITLE, "틈 가장자리에서 잎 표시 쪽으로 회피", World.SAFE_LANDING.get_center())
			hud.show_hint("틈 끝에 붙어서 잎 쪽으로 [회피]! 신발이 한 걸음 더 내딛어요")
		Stage.Q3_HANDLE:
			handle_spot.interactable = true
			handle_spot.marked = true
			hud.set_objective(Q3_TITLE, "순찰기를 피해 압력 손잡이 돌리기", World.HANDLE_POS)
			hud.show_hint("순찰기는 바라보는 방향으로만 쏴요. 뒤나 옆으로 돌아가세요", 4.5)
		Stage.Q3_DONE:
			dogyeom.marked = true
			hud.set_objective(Q4_TITLE, "마을 작업장의 도겸에게 고리 보여주기", dogyeom.position)
		Stage.Q4_CRAFT:
			bench_village.marked = true
			hud.set_objective(Q4_TITLE, "작업대에서 물길 장도 제작", bench_village.position)
		Stage.Q4_GO_MILL:
			ring_spot.interactable = true
			ring_spot.marked = true
			hud.set_objective(Q4_TITLE, "갈대둑 방앗간 앞방의 걸린 고리 조사", RING_POS)
		Stage.Q4_SWAP:
			hud.set_objective(Q4_TITLE, "도톰을 쉬게 하고 줄비와 함께하기", null)
			hud.show_hint("영물 초상화를 길게 누르면 활성 영물을 바꿔요 (PC: T)")
		Stage.Q4_UNHOOK:
			hud.set_objective(Q4_TITLE, "줄비가 표시한 연결쇠 풀기 (%d/2)" % _hooks_done(), RING_POS)
		Stage.Q4_REPAIR:
			ring_spot.interactable = true
			ring_spot.marked = true
			ring_spot.display_name = "앞방 손잡이"
			ring_spot.action_label = "수선"
			hud.set_objective(Q4_TITLE, "도겸과 안전한 손잡이 수선 (무료)", RING_POS)
		Stage.Q4_BLADE:
			hud.set_objective(Q4_TITLE, "줄비를 검으로 — 회피 직후 허수아비 공격", DUMMY_POS)
			hud.show_hint("초상화를 눌러 줄비를 검으로. 회피한 뒤 2초 안에 공격하면 파동이 나가요")
		Stage.Q4_UPGRADE:
			bench_mill.marked = true
			hud.set_objective(Q4_TITLE, "공구대에서 장도 +1 강화", BENCH_MILL)
		Stage.Q4_DONE:
			danu.marked = true
			hud.set_objective(Q5_TITLE, "단우에게 방앗간 아래 일을 알리기", danu.position)
		Stage.Q5_GO:
			hatch_spot.interactable = true
			hatch_spot.marked = true
			hud.set_objective(Q5_TITLE, "방앗간 아래 덮개로 내려가기", hatch_spot.position)
		Stage.Q5_ROOM1:
			hud.set_objective(Q5_TITLE, "첫 방을 지나 물레방으로", Vector2(1440, Dungeon.WALL_12))
		Stage.Q5_DRAIN:
			for h in [handle_l_spot, handle_r_spot]:
				h.interactable = true
				h.marked = true
			hud.set_objective(Q5_TITLE, "물레 손잡이 두 개를 맞춰 물 빼기", Dungeon.PLAQUE)
		Stage.Q5_RESCUE:
			worker.interactable = true
			worker.marked = true
			hud.set_objective(Q5_TITLE, "고립된 정비공에게", worker.position)
		Stage.Q5_ESCORT:
			worker.interactable = false
			hud.set_objective(Q5_TITLE, "정비공을 위쪽 방 오른쪽 높은 발판까지 안내", Dungeon.WAIT_SPOT)
		Stage.Q5_BOSS:
			sluice_spot.interactable = true
			hud.set_objective(Q5_TITLE, "거름집게 멈추기 — 물길 방출 땐 수문 손잡이", null)
		Stage.Q5_CORE:
			core_spot.position = boss.position + Vector2(0, 30)
			core_spot.interactable = true
			core_spot.marked = true
			sluice_spot.interactable = false
			hud.set_objective(Q5_TITLE, "멈춘 정비기에서 계약 고리 회수", core_spot.position)
		Stage.Q5_END:
			hud.set_objective("여행 준비", "시제품 끝 — 첫 임무: 사다리령의 운송 기록 확인", null)


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
	for k in _switch_cd:
		_switch_cd[k] = maxf(float(_switch_cd[k]) - delta, 0.0)
	hud.spirit_cd = spirit_switch_cd / TRANSFORM_COMBAT_CD

	_update_pause()
	if not _paused and not player.falling and not player.dead and world.update_weak(player.position, delta, player.airborne()):
		player.start_fall()
	_update_landing_preview()

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
		Stage.Q4_UNHOOK:
			_check_hooks()
		Stage.Q5_ROOM1:
			if player.position.y < Dungeon.WALL_12:
				_enter_stage(Stage.Q5_DRAIN)
				hud.show_hint("안내판을 읽어 보세요. 두 손잡이의 화살표가 핵심이에요", 4.0)
		Stage.Q5_DRAIN:
			_drain_time += delta
			if _drain_time > 25.0 and not dungeon.drained:
				_drain_time = 0.0
				hud.show_hint("예: 왼쪽 손잡이는 오른쪽(→)을, 오른쪽 손잡이는 왼쪽(←)을 가리키게", 5.0)
		Stage.Q5_ESCORT:
			hud.target_world = Dungeon.WAIT_SPOT if dungeon.room_of(player.position) == 3 else Vector2(1440, Dungeon.WALL_23)
		Stage.Q5_BOSS:
			_guide_release()

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
		camera.offset = CAMERA_LOOK_AHEAD + pan_offset + preview_offset + Vector2(randf_range(-3, 3), randf_range(-3, 3)) * shake * 2.0
	else:
		camera.offset = CAMERA_LOOK_AHEAD + pan_offset + preview_offset
	hud.spirit_status = player.gear_status() if player.gear != "" else _companion_status()


## 필수 대화·작업대·암전 동안 적의 공격과 발판 붕괴를 멈춘다 (Codex Q3 검토 P1).
## 퀘스트는 적을 처치하지 않고 우회해도 완료되므로, 대사를 읽는 동안 맞아서는 안 된다.
func _update_pause() -> void:
	var pause: bool = hud.busy()
	if pause == _paused:
		return
	_paused = pause
	worker.paused = pause
	for e in enemies:
		if is_instance_valid(e):
			e.set_physics_process(not pause)
	if not pause:
		player.invuln = maxf(player.invuln, RESUME_GRACE)


func _companion_status() -> String:
	match GameState.active_spirit:
		"도톰":
			return "숨은 발판 탐지"
		"줄비":
			return "연결쇠 탐지" if stage >= Stage.Q4_GO_MILL and stage <= Stage.Q4_UNHOOK else "가까운 적 보조 공격"
	return ""


## Q3 착지 미리보기: 틈 앞에서 지금 회피하면 어디에 닿는지 보여준다 (신발 한 걸음 포함).
func _update_landing_preview() -> void:
	world.preview = null
	var want := Vector2.ZERO
	if stage == Stage.Q3_TRANSFORM or stage == Stage.Q3_GAP:
		var gap: Rect2 = World.PITS["gap"]
		var p: Vector2 = player.position
		var near := p.x >= gap.position.x - 110.0 and p.x <= World.SAFE_LANDING.end.x and p.y <= gap.end.y
		if near:
			# 착지 원과 잎이 화면 안에 들어오도록 카메라를 틈 건너편 쪽으로 민다 (Codex Q4 검토 P2).
			# 회피 중에도 같은 값을 유지해 화면이 튀지 않게 한다.
			want = Vector2(PREVIEW_CAMERA_SHIFT, 0.0)
		if near and p.x <= gap.position.x and not player.airborne() and not player.falling:
			var dir: Vector2 = player.move_input.normalized() if player.move_input.length() > 0.2 else player.facing
			var land: Vector2 = p + dir * player.dodge_reach()
			world.preview = land
			world.preview_ok = not world.is_pit(land) and not world.is_unsafe_plank(land) and land.y > 40.0 and land.y < 160.0
	_apply_preview_offset(want)

func _apply_preview_offset(want: Vector2) -> void:
	preview_offset = preview_offset.lerp(want, clampf(get_process_delta_time() * 6.0, 0.0, 1.0))


func _pan_to(target: Vector2) -> void:
	var tw := create_tween()
	tw.tween_property(self, "pan_offset", target - player.position, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.8)
	tw.tween_property(self, "pan_offset", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_SINE)


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
	elif n == dogyeom:
		_talk_dogyeom()
	elif n == bench_village or n == bench_mill:
		_open_bench(n)
	elif n == ring_spot:
		if stage == Stage.Q4_GO_MILL:
			_inspect_ring()
		elif stage == Stage.Q4_REPAIR:
			_repair_handle()
	elif hooks.has(n):
		_unhook(n)
	elif n == hatch_spot:
		if stage == Stage.Q5_GO:
			_choose_spirit_and_descend()
	elif n == plaque_spot:
		hud.start_dialogue([["안내판", "두 화살표가 서로를 향하게 돌리세요. 왼쪽 →, 오른쪽 ←."]])
	elif n == handle_l_spot or n == handle_r_spot:
		_turn_wheel(n == handle_r_spot)
	elif n == worker:
		if stage == Stage.Q5_RESCUE:
			_rescue_worker()
	elif n == sluice_spot:
		_pull_sluice()
	elif n == core_spot:
		if stage == Stage.Q5_CORE:
			_recover_ring()


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
	elif stage == Stage.Q4_DONE:
		hud.start_dialogue([
			["단우", "도겸한테 들었어. 방앗간 아래 정비기는 물을 고르는 기계야. 고리가 씌워졌다면 스스로 멈추지 않을 거야."],
			["단우", "아침에 정비공 보리가 내려갔다가 아직 안 돌아왔어."],
			["단우", "오늘 네 임무는 기계를 이기는 게 아니야. 모두를 데리고 돌아오는 거야."],
		], func(): _enter_stage(Stage.Q5_GO))
	elif stage >= Stage.Q5_GO and stage < Stage.Q5_END:
		hud.start_dialogue([["단우", "방앗간 아래 덮개야. 보리를 먼저 찾아."]])
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
	if GameState.claim_reward("Q2"):
		GameState.contract_spirit("도톰")
		var gained := GameState.xp_to_level(3)
		GameState.add_item("수초섬유", 3)
		hud.toast(Q2_TITLE + " 완료")
		hud.toast("영물 계약: 도톰 (활성 1칸)")
		if gained > 0:
			hud.toast("레벨 업! Lv.%d" % GameState.level)
		hud.toast("수초섬유 +3")
	_refresh_spirit_hud()
	hud.show_hint("도톰은 동행할 때 숨은 발판을 찾아줘요. 북쪽 점검로로 가 봐요", 4.5)
	dotom.alert()
	world.set_blocker("steps_barrier", false)
	haon.position = Vector2(430, 120)
	_enter_stage(Stage.Q3_TALK_HAON)


# ── Q3 ───────────────────────────────────────────────────

func _on_dotom_marked() -> void:
	if stage == Stage.Q3_FIND:
		hud.toast("도톰이 안전한 발판에 잎을 남겼다")
		_pan_to(World.SAFE_LANDING.get_center())
		_enter_stage(Stage.Q3_TRANSFORM)


# ── 영물 공통: 활성 1칸, 동행 ↔ 장비 ─────────────────────

func active_node():
	return spirit_nodes.get(GameState.active_spirit)


func _gear_name(id: String) -> String:
	return "신발" if id == "도톰" else "검"


func _refresh_spirit_hud() -> void:
	var id := GameState.active_spirit
	hud.spirit_name = id
	hud.spirit_form = _gear_name(id) if id != "" and player.gear == id else ("동행" if id != "" else "")
	hud.spirit_can_swap = GameState.available_spirits().size() >= 2


## 초상화 누르기: 활성 영물의 동행 ↔ 장비 전환.
func _on_portrait() -> void:
	var id := GameState.active_spirit
	var node = active_node()
	if node == null or player.transform_t > 0.0:
		return
	if spirit_switch_cd > 0.0:
		hud.toast("%s 전환 대기 %d초" % [id, ceili(spirit_switch_cd)])
		return
	if hud.dialogue_active() or player.dead or player.falling:
		return
	if not GameState.spirits.has(id):
		hud.toast("%s와는 아직 계약 전이라 변신할 수 없어요" % id)
		return
	if (node == dotom and dotom.state == Dotom.State.MARKING) or (node == julbi and julbi.state == Julbi.State.MARKING):
		return
	_pending_gear = "" if player.gear == id else id
	_pending_spirit = id
	_transform_in_combat = _in_combat()
	if _transform_in_combat:
		hud.toast("변신 준비 2초 — 맞으면 끊겨요")
		player.start_transform(TRANSFORM_COMBAT)
	else:
		player.transform_fx = TRANSFORM_FX
		_on_transform_done()


func _in_combat() -> bool:
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.get_meta("kind") != "dummy" and e.position.distance_to(player.position) < COMBAT_RADIUS:
			return true
	return false


## 한 영물은 동행 또는 장비 중 한 상태만 가진다 (기획서 6장 규칙 3).
## 장비면 영물 노드가 숨어 동행 탐지·보조가 멈추고, 동행이면 player.gear가 비어 신발·검 효과가 없다.
func _on_transform_done() -> void:
	var id := _pending_spirit
	if id != GameState.active_spirit:
		return  # 준비 중에 활성 영물이 바뀌었다 → 무효
	if _transform_in_combat:
		_switch_cd[id] = TRANSFORM_COMBAT_CD
		_transform_in_combat = false
	var node = active_node()
	if _pending_gear != "":
		node.equip()
		player.gear = id
		if id == "도톰" and _first("first_shoe"):
			hud.toast("도톰이 신발 무늬가 되었다 — 회피 끝에 한 걸음 더")
		elif id == "줄비" and _first("first_blade"):
			hud.toast("줄비가 겹날이 되었다 — 회피 직후 공격에 파동")
		if stage == Stage.Q3_TRANSFORM and id == "도톰":
			_enter_stage(Stage.Q3_GAP)
	else:
		player.gear = ""
		node.become_companion()
	_refresh_spirit_hud()


## 초상화 길게 누르기: 활성 영물 교체. 쉬는 영물은 숙소로 가고 전투 보너스가 없다. 전투 중에는 불가.
func _on_portrait_long() -> void:
	var avail := GameState.available_spirits()
	if avail.size() < 2 or player.transform_t > 0.0 or hud.dialogue_active():
		return
	if _in_combat():
		hud.toast("전투 중에는 영물을 바꿀 수 없어요")
		return
	var cur := GameState.active_spirit
	set_active_spirit(avail[(avail.find(cur) + 1) % avail.size()])


func set_active_spirit(id: String) -> void:
	var old := GameState.active_spirit
	if old == id:
		return
	if player.transform_t > 0.0:
		player.transform_t = 0.0  # 교체하면 진행 중인 변신 준비는 취소
		_transform_in_combat = false
	if old != "":
		if player.gear == old:
			player.gear = ""
		spirit_nodes[old].rest()
	GameState.active_spirit = id
	spirit_nodes[id].become_companion()
	_refresh_spirit_hud()
	hud.toast("%s와 함께 · %s는 숙소에서 쉼" % [id, old])
	if stage == Stage.Q4_SWAP and id == "줄비":
		hud.clear_hint()
		_enter_stage(Stage.Q4_UNHOOK)


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


# ── Q4 ───────────────────────────────────────────────────

func _talk_dogyeom() -> void:
	match stage:
		Stage.Q3_DONE:
			hud.start_dialogue([
				["도겸", "수문에서 나온 고리라고? …보여 줘 봐."],
				["도겸", "공방 납품 규격이 아니야. 누군가 정상 부품 위에 덧씌웠군."],
				["도겸", "잘 만든 도구는 힘을 더하지. 나쁜 고리는 누구의 힘인지부터 빼앗고."],
				["도겸", "하온이 준 물길 장도 도안 있지? 작업장에 등록하면 조합 지원금이 나와. 그걸로 네 장도부터 제대로 만들어."],
			], _grant_q4_support)
		Stage.Q4_CRAFT, Stage.Q4_UPGRADE:
			if _q4_resupply():
				return
			hud.start_dialogue([["도겸", "작업대에서 하면 돼. 재료가 모자라면 나한테 말하고."]])
		Stage.Q4_GO_MILL, Stage.Q4_SWAP, Stage.Q4_UNHOOK:
			hud.start_dialogue([["도겸", "방앗간 앞방 고리부터 봐 줘. 줄비가 그 근처에 살아."]])
		Stage.Q4_REPAIR, Stage.Q4_BLADE:
			hud.start_dialogue([["도겸", "줄비랑 손발 맞춰 봐. 허수아비는 마음껏 쳐도 돼."]])
		Stage.Q4_DONE:
			hud.start_dialogue([["도겸", "방앗간 아래는 정비기 구역이야. 단우랑 같이 가."]])
		_:
			hud.start_dialogue([["도겸", "작업장은 정리 중이야. 고칠 게 생기면 가져와."]])


## 도안 제출: 지원금 50 + 하천광 2, 물길 장도 제작법 등록. 한 번만 지급한다.
func _grant_q4_support() -> void:
	if GameState.claim_reward("Q4_support"):
		GameState.add_item("물길 장도 도안", -1)
		GameState.known_recipes.append("물길 장도")
		GameState.add_currency(50)
		GameState.add_item("하천광", 2)
		hud.toast("도안 등록: 물길 장도")
		hud.toast("제작 지원금 +50 · 하천광 +2")
	_enter_stage(Stage.Q4_CRAFT)


## 퀘스트 재료를 다른 제작에 써 버렸을 때, 지금 단계에 필요한 만큼만 다시 받는다 (기획서 Q4 실패 조건).
func _q4_resupply() -> bool:
	var cost: Dictionary = {}
	if stage == Stage.Q4_CRAFT and GameState.weapon != "물길 장도":
		cost = GameState.RECIPES["물길 장도"]
	elif stage == Stage.Q4_UPGRADE and GameState.weapon_plus < 1:
		cost = GameState.next_upgrade_cost()
	if cost.is_empty() or GameState.can_pay(cost):
		return false
	var given: Array[String] = []
	for k in cost:
		var missing: int = int(cost[k]) - GameState.count(k)
		if missing > 0:
			if k == "재화":
				GameState.add_currency(missing)
			else:
				GameState.add_item(k, missing)
			given.append("%s %d" % [k, missing])
	GameState.set_flag("q4_resupply", int(GameState.flags.get("q4_resupply", 0)) + 1)
	hud.start_dialogue([["도겸", "재료를 다른 데 썼구나. 괜찮아, 이번 일에 필요한 만큼은 조합에서 내줄게. (%s)" % ", ".join(given)]])
	return true


func _open_bench(n) -> void:
	var rows := _craft_rows()
	if rows.is_empty():
		hud.toast("지금 만들거나 강화할 수 있는 것이 없어요")
		return
	hud.open_craft("작업대 — 이음터 작업장" if n == bench_village else "방앗간 공구대", rows)


func _cost_row(id: String, title: String, desc: String, cost: Dictionary, button: String) -> Dictionary:
	var lines: Array = []
	for k in cost:
		lines.append([k, GameState.count(k), int(cost[k])])
	return {"id": id, "title": title, "desc": desc, "cost": lines, "button": button, "can": GameState.can_pay(cost)}


func _craft_rows() -> Array:
	var rows: Array = []
	if GameState.known_recipes.has("물길 장도") and GameState.weapon != "물길 장도":
		rows.append(_cost_row("craft:물길 장도", "물길 장도 제작", "기본 성능 ×1.35 · 회피 직후 공격 시 결력 3 회복", GameState.RECIPES["물길 장도"], "제작"))
	if GameState.weapon != "연습용 목도" and GameState.weapon_plus < GameState.MAX_PLUS:
		rows.append(_cost_row("upgrade", "%s → +%d 강화" % [GameState.weapon, GameState.weapon_plus + 1], "성능 +8% · 실패·파괴 없는 확정 강화", GameState.next_upgrade_cost(), "강화"))
	return rows


func _on_craft(id: String) -> void:
	if id.begins_with("craft:"):
		var w := id.substr(6)
		if not GameState.craft_weapon(w):
			return
		hud.toast("%s 제작 완료!" % w)
		if stage == Stage.Q4_CRAFT:
			hud.close_craft()
			hud.start_dialogue([
				["도겸", "손에 맞지? 회피하고 바로 베면 숨이 조금 돌아올 거야."],
				["도겸", "이제 방앗간 앞방에 걸린 고리를 봐 줘. 거기 사는 줄비가 요즘 예민해."],
			], func(): _enter_stage(Stage.Q4_GO_MILL))
			return
	elif id == "upgrade":
		if not GameState.upgrade_weapon():
			return
		hud.toast("%s 강화 성공!" % GameState.weapon_label())
		if stage == Stage.Q4_UPGRADE and GameState.weapon == "물길 장도" and GameState.weapon_plus >= 1:
			hud.close_craft()
			_complete_q4()
			return
	var rows := _craft_rows()
	if rows.is_empty():
		hud.close_craft()
	else:
		hud.craft_rows = rows


func _inspect_ring() -> void:
	ring_spot.interactable = false
	hud.start_dialogue([
		["조사", "앞방 문틀의 연결쇠마다 낯선 고리가 물려 있다. 억지로 당기면 문틀째 뜯겨 나갈 것 같다."],
		["줄비", "(문틀 위에서 비늘을 접었다 펴며, 고리를 하나씩 꼬리로 가리킨다)"],
		["줄비", "(그러다 네 곁의 도톰을 보고 머뭇거린다. 지금은 한 영물만 함께할 수 있다)"],
	], func():
		if not GameState.temp_spirits.has("줄비") and not GameState.spirits.has("줄비"):
			GameState.temp_spirits.append("줄비")
		_refresh_spirit_hud()
		_enter_stage(Stage.Q4_SWAP))


func _hooks_done() -> int:
	var n := 0
	for h in hooks:
		if h.checked:
			n += 1
	return n


## 줄비 동행 탐지: 방앗간 앞에서 아직 찾지 못한 연결쇠를 하나씩 표시한다. 검 상태면 찾지 않는다.
func _check_hooks() -> void:
	if _hook_marking or GameState.active_spirit != "줄비" or julbi.state != Julbi.State.COMPANION:
		return
	if player.position.distance_to(RING_POS) > 170.0:
		return
	for h in hooks:
		if not h.interactable and not h.checked:
			_hook_marking = true
			julbi.run_mark(h.position + Vector2(0, -14))
			return


func _on_julbi_marked() -> void:
	if not _hook_marking:
		return
	_hook_marking = false
	for h in hooks:
		if not h.interactable and not h.checked:
			h.interactable = true
			h.marked = true
			hud.toast("줄비가 연결쇠를 찾았다 — 화살표 방향으로 풀기")
			return


func _unhook(h) -> void:
	if stage != Stage.Q4_UNHOOK or h.checked:
		return
	h.checked = true
	h.marked = false
	h.interactable = false
	hud.toast("연결쇠를 풀었다 (%d/2)" % _hooks_done())
	if _hooks_done() >= hooks.size():
		dogyeom.position = DOGYEOM_MILL
		_set_present(bench_mill, true)
		hud.start_dialogue([["도겸", "(뒤따라와서) 연결쇠가 다 풀렸네. 이제 제대로 된 손잡이를 달자. 이번 수선은 조합 일이니 값은 안 받아."]],
			func(): _enter_stage(Stage.Q4_REPAIR))
	else:
		_enter_stage(Stage.Q4_UNHOOK)


## 안전한 손잡이 수선(무료) → 줄비 계약.
func _repair_handle() -> void:
	ring_spot.interactable = false
	hud.start_dialogue([
		["조사", "(도겸이 고리를 떼어 내고 새 손잡이를 맞춘다. 줄비가 손잡이 끝을 꼬리로 감아 본다)"],
		["도겸", "봐, 마음에 들어 하네. 남의 도구를 망가뜨리지 않는 손이란 걸 알아본 거야."],
		["줄비", "(겹친 비늘을 펼쳐 네 장도 날 위에 살짝 올려 놓는다 — 계약의 표시다)"],
	], func():
		if GameState.claim_reward("Q4_contract"):
			GameState.contract_spirit("줄비")
			hud.toast("영물 계약: 줄비")
		_refresh_spirit_hud()
		_enter_stage(Stage.Q4_BLADE))


func _on_wave_fired(origin: Vector2, dir: Vector2) -> void:
	var fx = FxWave.new()
	fx.position = origin
	fx.dir = dir
	fx.length = player.WAVE_LEN
	fx.width = player.WAVE_WIDTH
	add_child(fx)
	if stage == Stage.Q4_BLADE:
		hud.toast("줄비 파동! 회피 직후 첫 공격")
		hud.clear_hint()
		_enter_q4_upgrade()


func _on_trait_triggered() -> void:
	var ft = FloatText.new()
	ft.text = "결력 +3"
	ft.color = Color("5fc5c9")
	ft.position = player.position + Vector2(0, -30)
	add_child(ft)


## 강화 단계 진입: 물길 장도를 이미 +1 이상 강화했다면 그 달성을 인정하고 바로 완료한다 (Codex Q4 검토 P1).
## 저장 기능이 생겨 강화된 장비로 이 단계에 들어오는 경우도 같은 판정을 쓴다.
func _q4_upgrade_done() -> bool:
	return GameState.weapon == "물길 장도" and GameState.weapon_plus >= 1


func _enter_q4_upgrade() -> void:
	if _q4_upgrade_done():
		hud.toast("이미 %s — 강화 목표 달성" % GameState.weapon_label())
		_complete_q4()
	else:
		_enter_stage(Stage.Q4_UPGRADE)


func _complete_q4() -> void:
	if stage == Stage.Q4_DONE:
		return
	# 진행 상태는 대사를 기다리지 않고 바로 확정한다.
	world.hatch_open = true
	_enter_stage(Stage.Q4_DONE)
	if GameState.claim_reward("Q4"):
		var gained := GameState.xp_to_level(5)
		GameState.add_item("하천광", 3)
		hud.toast(Q4_TITLE + " 완료")
		if gained > 0:
			hud.toast("레벨 업! Lv.%d" % GameState.level)
		hud.toast("다음 강화 재료: 하천광 +3")
	hud.start_dialogue([
		["도겸", "확정 강화는 실패가 없어. 대신 재료가 정직하게 들지."],
		["도겸", "활성 칸은 아직 하나야. 상황에 맞게 도톰이든 줄비든 골라서 데려가."],
		["줄비", "(갑자기 물레방아 쪽으로 몸을 늘이더니, 고리에서 이어진 긴 연결선을 따라 바닥 덮개를 두드린다)"],
		["도겸", "방앗간 아래로 이어진다고? …단우에게 알리자. 거긴 정비기가 있는 곳이야."],
	], func():
		hud.show_hint("초상화를 길게 누르면 도톰과 줄비를 바꿔 데려갈 수 있어요", 5.0))


# ── Q5: 물레방아 아래 ─────────────────────────────────────

## 내려가기 전에 함께 갈 영물을 고른다 (기획서 Q5 ‘활성 영물 선택 안내’). 안에서도 전투 밖이면 바꿀 수 있다.
func _choose_spirit_and_descend() -> void:
	var avail := GameState.available_spirits()
	if avail.size() < 2:
		_enter_dungeon()
		return
	hud.start_choice("누구와 함께 내려갈까?", [
		["도톰과 함께", "동행: 숨은 발판 탐지 / 신발: 회피 뒤 한 걸음"],
		["줄비와 함께", "동행: 가까운 적 보조 공격 / 검: 회피 뒤 첫 공격에 파동"],
	], func(i: int):
		var id := "도톰" if i == 0 else "줄비"
		set_active_spirit(id)
		# 선택은 함께 갈 영물만 정한다. 동행으로 들어가고, 장비 변신은 초상화로 따로 한다.
		if player.gear != "":
			player.gear = ""
			spirit_nodes[id].become_companion()
		_refresh_spirit_hud()
		_enter_dungeon(), "동행으로 들어가요 · 초상화로 동행·장비 전환")


func _enter_dungeon() -> void:
	hud.show_fade("방앗간 아래로 내려간다…")
	await get_tree().create_timer(0.7).timeout
	in_dungeon = true
	player.respawn(Dungeon.START, false)
	_apply_camera_limits(DUNGEON_LIMITS)
	camera.reset_smoothing()
	var node = active_node()
	if node != null and node.visible:
		node.position = Dungeon.START + Vector2(14, 6)
	hud.hide_fade()
	_enter_stage(Stage.Q5_ROOM1)
	hud.show_hint("활성 영물은 전투 밖에서 초상화를 길게 눌러 바꿀 수 있어요", 4.0)


func _turn_wheel(right: bool) -> void:
	if stage != Stage.Q5_DRAIN:
		return
	var done: bool = dungeon.turn_handle(right)
	if _first("hint_wheel_turn") and not done:
		hud.show_hint("손잡이는 누를 때마다 90도 돌아가요. 왼쪽 →, 오른쪽 ←가 되면 물이 빠져요", 4.5)
	var arrows := ["↑", "→", "↓", "←"]
	hud.toast("%s 손잡이: %s" % ["오른쪽" if right else "왼쪽", arrows[dungeon.handle_r if right else dungeon.handle_l]])
	if done:
		for h in [handle_l_spot, handle_r_spot]:
			h.interactable = false
			h.marked = false
		shake = 0.5
		hud.clear_hint()
		hud.start_dialogue([["정비공 보리", "(웅덩이 너머에서) 물이 빠진다! 여기예요, 여기!"]], func(): _enter_stage(Stage.Q5_RESCUE))


func _rescue_worker() -> void:
	hud.start_dialogue([
		["정비공 보리", "살았다… 정비기를 멈추러 왔다가 물이 차서 갇혔어요."],
		["정비공 보리", "저 정비기, 원래 물을 고르는 기계예요. 집게에 낯선 고리가 씌워진 뒤로 물을 거꾸로 뿜어요."],
		["정비공 보리", "위쪽 방 오른쪽에 높은 발판이 있어요. 거기라면 물이 차도 버틸 수 있어요. 데려가 주세요."],
	], func():
		worker.wstate = Worker.WState.FOLLOW
		_enter_stage(Stage.Q5_ESCORT))


func _on_worker_waiting() -> void:
	if stage != Stage.Q5_ESCORT:
		return
	_enter_stage(Stage.Q5_BOSS)
	hud.start_dialogue([
		["정비공 보리", "여기서 기다릴게요. 물길을 뿜기 전에 저 수문 손잡이를 내려 주세요!"],
		["정비공 보리", "집게를 뻗거나 김을 뿜고 나면 한동안 멈춰요. 그때가 기회예요."],
	], func():
		boss.wake()
		hud.show_hint("물길 방출 예고가 뜨면 오른쪽 발판의 수문 손잡이를 내리고, 발판 안에 있으세요", 5.0))


func _on_boss_release() -> void:
	sluice_spot.marked = true
	_guide_release()


## 물길 방출 예고 동안: 남은 초와 함께 “수문 내리기 → 발판 안에서 대기”를 단계별로 안내하고,
## 목표 화살표를 수문(확보 전) → 안전 발판(확보 후)으로 바꾼다 (Codex Q5 검토).
func _guide_release() -> void:
	if boss.state != Boss.State.RELEASE_AIM:
		if hud.hint_text.begins_with("물길 방출") or hud.hint_text.begins_with("수문 확보"):
			hud.clear_hint()
			hud.target_world = null
		return
	var left := ceili(boss.t)
	if not dungeon.secured:
		hud.target_world = Dungeon.SLUICE
		hud.show_hint("물길 방출 %d초 — ① 수문 내리기 → ② 발판 안에서 대기" % left)
	elif dungeon.in_safe_zone(player.position):
		hud.target_world = null
		hud.show_hint("수문 확보! 발판 안에서 대기 (%d초)" % left)
	else:
		hud.target_world = Dungeon.SAFE_ZONE.get_center()
		hud.show_hint("수문 확보! ② 발판 안으로 들어가세요 (%d초)" % left)


func _pull_sluice() -> void:
	if stage != Stage.Q5_BOSS:
		return
	if boss.state == Boss.State.RELEASE_AIM and not dungeon.secured:
		dungeon.secured = true
		sluice_spot.marked = false
		hud.toast("수문을 내렸다 — 높은 발판이 안전 지대가 됐다")
	elif not dungeon.secured:
		hud.toast("물길을 뿜으려 할 때 내려야 해요")


func _on_boss_flooded(secured: bool) -> void:
	sluice_spot.marked = false
	if secured:
		hud.toast("정비공 무사!")
	else:
		worker.hurt(Boss.FLOOD_WORKER_DMG)
		if worker.wstate != Worker.WState.DOWN:
			hud.toast("정비공이 물에 휩쓸렸다! (체력 %d)" % roundi(worker.hp))


func _on_worker_downed() -> void:
	hud.show_fade("정비공이 쓰러졌다…\n이 방 입구에서 다시 도전합니다.")
	await get_tree().create_timer(1.6).timeout
	player.respawn(Dungeon.ROOM3_START)
	player.hp = player.max_hp
	camera.reset_smoothing()
	_reset_boss_room()
	hud.hide_fade()


## 보스 재도전: 보스 체력·패턴, 물, 정비공을 대기 위치로 되돌린다 (기획서 Q5 실패 조건).
func _reset_boss_room() -> void:
	boss.reset_fight()
	worker.reset_at(Dungeon.WAIT_SPOT, Worker.WState.WAIT)
	sluice_spot.marked = false
	await get_tree().create_timer(1.0).timeout
	if stage == Stage.Q5_BOSS:
		boss.wake()


func _on_boss_stopped() -> void:
	shake = 0.8
	hud.start_dialogue([["정비공 보리", "멈췄다…! 집게 안쪽을 보세요. 그 고리예요."]], func(): _enter_stage(Stage.Q5_CORE))


## 고리 회수와 이야기 선택. 선택 전에는 결과를 확정하지 않는다.
func _recover_ring() -> void:
	core_spot.interactable = false
	hud.start_dialogue([
		["조사", "정비기의 집게 안쪽에 덧씌운 계약 고리가 물려 있다. 수문에서 나온 것과 같은 모양이다."],
		["정비공 보리", "이걸 누가 맡아야 할까요? 조합이 조사해 줄 수도 있고… 우리 마을이 같이 지킬 수도 있고요."],
	], func():
		hud.start_choice("회수한 계약 고리를 어디에 맡길까?", [
			["길잇기 조합에 맡긴다", "조합이 기록하고 조사한다 · 다음 장에서 매듭이 증언"],
			["주민 대표와 공동 보관한다", "이음터 주민이 함께 지킨다 · 다음 장에서 하온이 증언"],
		], _complete_q5))


func _complete_q5(choice: int) -> void:
	var keeper := "조합" if choice == 0 else "주민"
	if GameState.claim_reward("Q5"):
		GameState.set_flag("q5_ring_keeper", keeper)
		GameState.xp_to_level(6)
		var gained := GameState.add_xp(150)
		GameState.add_currency(60)
		GameState.add_item("조율 부품")
		GameState.add_item("혈계·도구 수련권")
		hud.toast(Q5_TITLE + " 완료")
		hud.toast("Lv.%d · 재화 +60" % GameState.level + (" · 레벨 업!" if gained > 0 else ""))
		hud.toast("확정 조율 부품 · 혈계·도구 수련권")
	_finish_prototype()


## 마을로 돌아와 사다리령 납품 인장과 첫 여행 임무를 보여주고 끝낸다 (기획서 Q5 연결).
func _finish_prototype() -> void:
	var keeper := str(GameState.flags.get("q5_ring_keeper", "조합"))
	hud.show_fade("보리와 함께 마을로 돌아왔다.")
	await get_tree().create_timer(1.0).timeout
	in_dungeon = false
	_apply_camera_limits(OVERWORLD_LIMITS)
	player.respawn(danu.position + Vector2(0, 40), false)
	camera.reset_smoothing()
	worker.visible = false
	worker.interactable = false
	var node = active_node()
	if node != null and node.visible:
		node.position = player.position + Vector2(14, 6)
	hud.hide_fade()
	_enter_stage(Stage.Q5_END)
	var keep_line := "조합 금고에 고리를 맡겼어. 매듭이 기록을 맡기로 했고." if keeper == "조합" else "주민 대표들이 고리를 같이 지키기로 했어. 하온 어르신이 열쇠 하나를 맡았지."
	hud.start_dialogue([
		["단우", "다들 무사히 돌아왔구나. 그거면 됐어."],
		["단우", keep_line],
		["단우", "그런데 고리 안쪽에 납품 인장이 찍혀 있었어. 사다리령 운송조합의 인장이야."],
		["단우", "첫 여행 임무야. 사다리령에 가서 이 고리가 어디서 왔는지 운송 기록을 확인해 와. 준비되면 말해."],
	], func():
		hud.show_end([
			"시제품 끝 — 여행 준비 완료",
			"첫 여행 임무: 사다리령의 운송 기록 확인",
			"계약 고리 보관: %s" % ("길잇기 조합" if keeper == "조합" else "주민 공동 보관"),
			"사다리령 여행은 다음 버전에서 이어집니다.",
			"Lv.%d · %s · 영물: %s" % [GameState.level, GameState.weapon_label(), ", ".join(GameState.spirits)],
			"플레이해 주셔서 감사합니다",
		]))


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
	if e == boss:
		_on_boss_stopped()


## 쓰러지거나 빠졌을 때 돌아갈 가장 가까운 안전 지점.
func checkpoint_for(p: Vector2) -> Vector2:
	if in_dungeon:
		return dungeon.checkpoint_for(p)
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
	var boss_room: bool = in_dungeon and stage == Stage.Q5_BOSS and dungeon.room_of(player.position) == 3
	hud.show_fade("쓰러졌다…\n%s\n얻은 것은 그대로예요." % ("이 방 입구에서 다시 도전합니다." if boss_room else "가까운 안전한 곳에서 다시 시작합니다."))
	await get_tree().create_timer(1.6).timeout
	player.respawn(at)
	camera.reset_smoothing()
	_reset_enemies()
	if boss_room:
		_reset_boss_room()
	hud.hide_fade()


func _on_player_fell() -> void:
	var at := checkpoint_for(player.position)
	# 틈 연습 구간(건너기 전)에서는 결력을 바로 채운다 (기획서 Q3 실패 조건).
	var practice := at == GAP_START
	hud.toast("발판이 무너졌다 — 다시 해 봐요" if practice else "빠졌다 — 가까운 둑에서 다시")
	await get_tree().create_timer(0.6).timeout
	world.reset_weak()
	player.respawn(at, practice)
	if practice:
		# 연습 구간: 결력과 함께 한 걸음 대기도 초기화해 바로 다시 해 볼 수 있게 한다 (Codex Q3 검토 P2).
		player.step_cd = 0.0
		if _first("hint_practice_reset"):
			hud.show_hint("연습 구간이라 결력과 한 걸음 대기를 다시 채웠어요. 초록 원이 잎 위에 오면 회피!", 4.5)
	camera.reset_smoothing()
	var node = active_node()
	if node != null and node.visible:
		node.position = at + Vector2(14, 6)
