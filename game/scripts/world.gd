extends Node2D
## 갈대둑 지도. 임시 도형 아트와 충돌 영역. 1타일 = 32px.
##
##   서쪽 열 (x 0~384)   : 이음터(아래) → 갈대둑 필드 → 수문(위)            — Q1
##   동쪽 늪 (y 316~1472): 다리 → 젖은 둑, 느슨한 줄, 진흙 발판, 둥지 섬      — Q2
##   동쪽 점검로 (y 16~284): 계단 → 하온 → 끊긴 틈 → 착지 발판 → 수문 손잡이 — Q3
##
## 충돌 레이어: 1 = 벽·물 (항상 막힘), 2 = 진흙·틈 (회피 중에는 넘을 수 있고, 그 위에서 멈추면 빠진다)

const W := 1088.0
const H := 1920.0
const COL_W := 384.0  ## 서쪽 열 너비
const FIELD_BOTTOM := 1480.0
const PLATFORM_BOTTOM := 216.0
const TOP_MARGIN := 240.0
## 지도 아래 렌더링 여백. 충돌 경계(H)는 그대로 두고 카메라만 더 내려갈 수 있게 한다.
## 시작 지점(y 1850)에서도 플레이어가 화면 세로 45~62% 안에 오도록 한다 (아트 명세 6장).
const BOTTOM_MARGIN := 260.0
const PIT_LAYER := 2

const HOUSES: Array[Rect2] = [Rect2(24, 1520, 96, 64), Rect2(264, 1520, 96, 64), Rect2(24, 1790, 80, 60), Rect2(290, 1800, 70, 56)]
const FENCES: Array[Rect2] = [Rect2(16, 1472, 134, 12), Rect2(234, 1472, 134, 12)]
const WATER: Array[Rect2] = [
	Rect2(16, 96, 80, 1376),            # 서쪽 강
	Rect2(300, 96, 68, 784), Rect2(300, 928, 68, 544),  # 동쪽 강 (y 880~928에 다리)
	Rect2(470, 980, 250, 120), Rect2(640, 600, 170, 110),  # 늪 웅덩이
	Rect2(840, 716, 232, 44),           # 둥지 섬 남쪽 물
	Rect2(480, 160, 592, 124),          # 점검로 아래 물
]
const REEDS: Array[Rect2] = [Rect2(126, 1200, 40, 30), Rect2(232, 980, 44, 30), Rect2(108, 840, 36, 36), Rect2(240, 600, 40, 28), Rect2(150, 420, 34, 26),
	Rect2(900, 1080, 50, 40), Rect2(420, 1300, 60, 36), Rect2(980, 880, 40, 60)]
const GATE := Rect2(96, 24, 192, 56)
const WELL_POS := Vector2(200, 1620)

const EAST_FOREST := Rect2(368, 1472, 704, 432)
const DIVIDER := Rect2(368, 16, 12, 268)  ## 수문 앞마당과 점검로 사이 돌벽
const WALKWAY_RAIL := Rect2(380, 16, 692, 24)
const BRIDGE := Rect2(300, 880, 68, 48)
const SAFE_BANK := Rect2(384, 330, 150, 110)
const ISLAND := Rect2(872, 316, 200, 400)
const NEST_POS := Vector2(985, 520)
const HANDLE_POS := Vector2(1030, 100)

## 퀘스트로 열고 닫는 벽: id → Rect2
const REMOVABLE := {
	"east_barrier": Rect2(352, 880, 16, 48),   # 다리 동쪽 통제선 (Q2 전)
	"channel_top": Rect2(840, 316, 32, 164),
	"channel_mid": Rect2(840, 480, 32, 40),    # 고정점 설치 → 밧줄 다리
	"channel_bot": Rect2(840, 520, 32, 196),
	"channel_wall_l": Rect2(380, 284, 20, 32),
	"steps_barrier": Rect2(400, 284, 60, 32),  # 점검로 계단 (Q3 전)
	"channel_wall_r": Rect2(460, 284, 612, 32),
}
## 빠질 수 있는 곳 (레이어 2)
const PITS := {
	"mud_w": Rect2(368, 760, 192, 40),
	"mud_e": Rect2(640, 760, 432, 40),
	"gap": Rect2(640, 40, 120, 120),
}

var t := 0.0
var backflow := 0.0  ## 0 = 정상 흐름, 1 = 역류
var goal = null  ## 위치 목표 표시 (Vector2 또는 null)
var anchor_built := false
var gap_fixed := false
var leaf_marks: Array[Vector2] = []

## 약한 발판. 오래 서 있으면(delay초) 무너진다. hidden 발판은 도톰이 동행일 때만 구분된다.
var weak_planks: Array = [
	{"id": "board", "rect": Rect2(560, 760, 80, 40), "delay": 0.7, "hidden": false, "revealed": true, "timer": 0.0, "broken": false},
	{"id": "land_mid", "rect": Rect2(760, 80, 60, 40), "delay": 0.12, "hidden": true, "revealed": false, "timer": 0.0, "broken": false},
	{"id": "land_bot", "rect": Rect2(760, 120, 60, 40), "delay": 0.12, "hidden": true, "revealed": false, "timer": 0.0, "broken": false},
]
const SAFE_LANDING := Rect2(760, 40, 60, 40)

var _removable_bodies: Dictionary = {}
var _pit_bodies: Dictionary = {}
var _pit_enabled: Dictionary = {}
var _grass: PackedVector2Array = []
var _marsh: PackedVector2Array = []
var _pebbles: PackedVector2Array = []


func _ready() -> void:
	var blockers: Array[Rect2] = [
		Rect2(0, 0, 16, H), Rect2(W - 16, 0, 16, H), Rect2(0, 0, W, 16), Rect2(0, H - 16, W, 16),
		GATE, EAST_FOREST, DIVIDER, WALKWAY_RAIL,
	]
	blockers.append_array(HOUSES)
	blockers.append_array(FENCES)
	blockers.append_array(WATER)
	blockers.append_array(REEDS)
	for r in blockers:
		_add_box(r, 1)
	_add_circle(WELL_POS, 14.0)
	for id in REMOVABLE:
		_removable_bodies[id] = _add_box(REMOVABLE[id], 1)
	for id in PITS:
		_pit_bodies[id] = _add_box(PITS[id], PIT_LAYER)
		_pit_enabled[id] = true

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 420:
		_grass.append(Vector2(rng.randf_range(96, 300), rng.randf_range(PLATFORM_BOTTOM, FIELD_BOTTOM)))
	for i in 700:
		_marsh.append(Vector2(rng.randf_range(384, W - 16), rng.randf_range(316, FIELD_BOTTOM)))
	for i in 160:
		_pebbles.append(Vector2(rng.randf_range(16, COL_W - 16), rng.randf_range(FIELD_BOTTOM + 12, H - 16)))


func _add_box(r: Rect2, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.get_center()
	body.add_child(cs)
	add_child(body)
	return body


func _add_circle(p: Vector2, radius: float) -> void:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = radius
	cs.shape = sh
	cs.position = p
	body.add_child(cs)
	add_child(body)


# ── 퀘스트용 API ──────────────────────────────────────────

func set_blocker(id: String, enabled: bool) -> void:
	var body: StaticBody2D = _removable_bodies[id]
	body.get_child(0).set_deferred("disabled", not enabled)


func blocker_enabled(id: String) -> bool:
	var body: StaticBody2D = _removable_bodies[id]
	return not body.get_child(0).disabled


func set_pit(id: String, enabled: bool) -> void:
	_pit_enabled[id] = enabled
	var body: StaticBody2D = _pit_bodies[id]
	body.get_child(0).set_deferred("disabled", not enabled)


func is_pit(p: Vector2) -> bool:
	for id in PITS:
		if _pit_enabled[id] and (PITS[id] as Rect2).has_point(p):
			return true
	return false


func build_anchor() -> void:
	anchor_built = true
	set_blocker("channel_mid", false)


func fix_gap() -> void:
	gap_fixed = true
	set_pit("gap", false)
	for wp in weak_planks:
		if wp["hidden"]:
			wp["broken"] = false
			wp["delay"] = INF


## 플레이어가 서 있는 약한 발판의 타이머를 진행한다. 무너지면 true.
func update_weak(p: Vector2, delta: float, airborne: bool) -> bool:
	var collapsed := false
	for wp in weak_planks:
		var r: Rect2 = wp["rect"]
		if not airborne and not wp["broken"] and r.has_point(p):
			wp["timer"] += delta
			if wp["timer"] >= wp["delay"]:
				wp["broken"] = true
				collapsed = true
		else:
			wp["timer"] = maxf(wp["timer"] - delta, 0.0)
	return collapsed


func reset_weak() -> void:
	for wp in weak_planks:
		wp["broken"] = false
		wp["timer"] = 0.0


## 도톰의 동행 탐지: 근처의 숨은 약한 발판을 드러낸다. 새로 드러낸 것이 있으면 true.
func reveal_hidden_near(p: Vector2, radius: float) -> bool:
	var found := false
	for wp in weak_planks:
		if wp["hidden"] and not wp["revealed"] and (wp["rect"] as Rect2).get_center().distance_to(p) < radius:
			wp["revealed"] = true
			found = true
	if found and not leaf_marks.has(SAFE_LANDING.get_center()):
		leaf_marks.append(SAFE_LANDING.get_center())
	return found


# ── 그리기 ───────────────────────────────────────────────

func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _water_color() -> Color:
	return Color("3f7fa8").lerp(Color("6b6a4a"), backflow)


func _draw() -> void:
	var water_col := _water_color()
	# 수문 위 저수지 (카메라가 상단 HUD 아래까지 내려 보이도록 지도 밖에 그린다)
	draw_rect(Rect2(-64, -TOP_MARGIN, W + 128, TOP_MARGIN + 16), water_col)
	for i in 60:
		var rx := fposmod(i * 71.0 + t * 8.0, W + 64.0) - 32.0
		var ry := -TOP_MARGIN + fposmod(i * 37.0, TOP_MARGIN)
		draw_line(Vector2(rx, ry), Vector2(rx + 14, ry), Color(1, 1, 1, 0.2), 1.0)
	draw_rect(Rect2(-64, 8, W + 128, 8), Color("6e6c62"))

	_draw_west(water_col)
	_draw_east(water_col)

	if goal != null:
		var g: Vector2 = goal
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		draw_arc(g, 16.0 + pulse * 4.0, 0, TAU, 28, Color(1.0, 0.85, 0.3, 0.9), 2.0)
		draw_arc(g, 8.0, 0, TAU, 20, Color(1.0, 0.85, 0.3, 0.5), 2.0)


func _draw_water(r: Rect2, col: Color, flow: float) -> void:
	draw_rect(r, col)
	var n := int(r.size.x * r.size.y / 4200.0) + 3
	for i in n:
		var y := fposmod(i * 53.0 + t * 26.0 * flow, r.size.y)
		var x := r.position.x + fposmod(i * 29.0, maxf(r.size.x - 16.0, 1.0)) + 4.0
		draw_line(Vector2(x, r.position.y + y), Vector2(x + 10, r.position.y + y), Color(1, 1, 1, 0.25), 1.0)
	draw_rect(r, Color("2c5670").lerp(Color("4a4a30"), backflow), false, 2.0)


func _draw_reeds(r: Rect2) -> void:
	draw_rect(r, Color("4e6a33"))
	var n := int(r.size.x / 6.0)
	for i in n + 1:
		var x := r.position.x + 3 + i * (r.size.x - 6) / maxf(n, 1)
		var sway := sin(t * 2.0 + i) * 2.0
		draw_line(Vector2(x, r.end.y), Vector2(x + sway, r.position.y - 6), Color("a8b060"), 2.0)


func _draw_west(water_col: Color) -> void:
	# 필드 바닥
	draw_rect(Rect2(0, 16, COL_W, FIELD_BOTTOM - 16), Color("6f8f4e"))
	draw_rect(Rect2(150, PLATFORM_BOTTOM, 84, FIELD_BOTTOM - PLATFORM_BOTTOM), Color("8a7a55"))
	for p in _grass:
		draw_rect(Rect2(p, Vector2(2, 3)), Color("5c7a3e"))
	# 수문 앞 돌바닥
	draw_rect(Rect2(16, 16, COL_W - 32, PLATFORM_BOTTOM - 16), Color("8d8b80"))
	for y in range(24, int(PLATFORM_BOTTOM), 24):
		draw_line(Vector2(16, y), Vector2(COL_W - 16, y), Color("7a786e"), 1.0)

	var flow := lerpf(1.0, -2.2, backflow)
	for i in 3:
		_draw_water(WATER[i], water_col, flow)
	# 동쪽 강 다리
	draw_rect(BRIDGE, Color("8a6a40"))
	for x in range(int(BRIDGE.position.x), int(BRIDGE.end.x), 10):
		draw_line(Vector2(x, BRIDGE.position.y), Vector2(x, BRIDGE.end.y), Color("5a4020"), 1.0)
	if blocker_enabled("east_barrier"):
		var b: Rect2 = REMOVABLE["east_barrier"]
		draw_rect(Rect2(b.position.x + 4, b.position.y - 4, 6, b.size.y + 8), Color("5a3a20"))
		for i in 3:
			draw_line(Vector2(b.position.x, b.position.y + 8 + i * 14), Vector2(b.end.x, b.position.y + 14 + i * 14), Color("d04030"), 3.0)

	# 수문
	draw_rect(Rect2(GATE.position.x, 16, GATE.size.x, 8), water_col)
	draw_rect(GATE, Color("6a4e34"))
	for i in 5:
		var x := GATE.position.x + 8 + i * 44.0
		draw_rect(Rect2(x, GATE.position.y, 8, GATE.size.y), Color("4a3422"))
	draw_rect(Rect2(GATE.position.x, GATE.position.y + 22, GATE.size.x, 8), Color("5a5f66"))
	var wheel := Vector2(GATE.get_center().x, GATE.end.y + 4)
	draw_arc(wheel, 10.0, 0, TAU, 20, Color("3a3f46"), 3.0)
	var spin := t * (0.5 + backflow * 6.0)
	for i in 4:
		draw_line(wheel, wheel + Vector2.RIGHT.rotated(spin + i * PI / 2.0) * 10.0, Color("3a3f46"), 2.0)
	if backflow > 0.0:
		for i in 8:
			var sx := GATE.position.x + 12 + i * 24.0
			var sy := GATE.end.y + fposmod(t * 60.0 + i * 13.0, 40.0)
			draw_circle(Vector2(sx, sy), 2.0 + backflow, Color(0.7, 0.68, 0.5, 0.6 * backflow))

	for i in 5:
		_draw_reeds(REEDS[i])

	# 마을
	draw_rect(Rect2(0, FIELD_BOTTOM, COL_W, H - FIELD_BOTTOM), Color("c8b088"))
	for p in _pebbles:
		draw_rect(Rect2(p, Vector2(2, 2)), Color("ae966e"))
	draw_rect(Rect2(150, FIELD_BOTTOM, 84, H - FIELD_BOTTOM), Color("bba27a"))
	for r in HOUSES:
		draw_rect(r, Color("a07850"))
		draw_rect(Rect2(r.position.x - 4, r.position.y - 10, r.size.x + 8, r.size.y * 0.55), Color("7a4a3a"))
		draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 7, r.end.y - 18, 14, 18), Color("4a3020"))
		draw_rect(Rect2(r.position.x + 8, r.end.y - 22, 10, 8), Color("e8d8a0"))
	for r in FENCES:
		draw_rect(r, Color("8a6a40"))
		for x in range(int(r.position.x), int(r.end.x), 12):
			draw_rect(Rect2(x, r.position.y - 4, 4, r.size.y + 4), Color("6a4a28"))
	_draw_south_margin()
	draw_rect(Rect2(140, 1460, 10, 28), Color("5a3a20"))
	draw_rect(Rect2(234, 1460, 10, 28), Color("5a3a20"))
	draw_rect(Rect2(136, 1456, 112, 6), Color("7fd6c2"))
	draw_circle(WELL_POS, 14.0, Color("7a7a78"))
	draw_circle(WELL_POS, 9.0, Color("2f4f68"))


func _draw_east(water_col: Color) -> void:
	# 늪 바닥
	draw_rect(Rect2(368, 316, W - 384, FIELD_BOTTOM - 316), Color("5e7a48"))
	for p in _marsh:
		draw_rect(Rect2(p, Vector2(3, 2)), Color("4e6a3c"))
	draw_rect(SAFE_BANK, Color("8f9a5a"))
	draw_rect(SAFE_BANK, Color("6f7a40"), false, 2.0)
	draw_rect(ISLAND, Color("6a8a50"))
	# 동쪽 숲 (막힌 곳)
	draw_rect(EAST_FOREST, Color("2f4a2a"))
	for i in 40:
		var c := Vector2(EAST_FOREST.position.x + fposmod(i * 67.0, EAST_FOREST.size.x), EAST_FOREST.position.y + fposmod(i * 41.0, EAST_FOREST.size.y))
		draw_circle(c, 18.0, Color("3a5a32"))

	var flow := lerpf(0.6, -1.5, backflow)
	for i in range(3, WATER.size()):
		_draw_water(WATER[i], water_col, flow)
	# 둥지 섬 물길
	for id in ["channel_top", "channel_bot", "channel_wall_l", "channel_wall_r"]:
		_draw_water(REMOVABLE[id], water_col, flow)
	var mid: Rect2 = REMOVABLE["channel_mid"]
	if anchor_built:
		draw_rect(mid, water_col)
		draw_rect(Rect2(mid.position.x - 6, mid.position.y + 6, mid.size.x + 12, mid.size.y - 12), Color("8a6a40"))
		for x in range(int(mid.position.x - 6), int(mid.end.x + 6), 8):
			draw_line(Vector2(x, mid.position.y + 6), Vector2(x, mid.end.y - 6), Color("5a4020"), 1.0)
		draw_line(Vector2(mid.position.x - 8, mid.position.y + 4), Vector2(mid.end.x + 8, mid.position.y + 4), Color("d8c090"), 2.0)
		draw_line(Vector2(mid.position.x - 8, mid.end.y - 4), Vector2(mid.end.x + 8, mid.end.y - 4), Color("d8c090"), 2.0)
	else:
		_draw_water(mid, water_col, flow)
	# 고정점 기둥
	draw_rect(Rect2(mid.position.x - 18, mid.position.y + 8, 8, 24), Color("5a3a20"))

	# 점검로 계단
	var steps: Rect2 = REMOVABLE["steps_barrier"]
	if blocker_enabled("steps_barrier"):
		_draw_water(steps, water_col, flow)
	else:
		draw_rect(steps, Color("8d8b80"))
		for y in range(int(steps.position.y), int(steps.end.y), 8):
			draw_line(Vector2(steps.position.x, y), Vector2(steps.end.x, y), Color("6e6c62"), 2.0)

	# 진흙과 젖은 나무 발판
	for id in ["mud_w", "mud_e"]:
		var r: Rect2 = PITS[id]
		draw_rect(r, Color("4a3a28"))
		for i in int(r.size.x / 24.0):
			var bx := r.position.x + 8 + i * 24.0
			var by := r.position.y + 10 + fposmod(i * 13.0 + t * 3.0, r.size.y - 16)
			draw_circle(Vector2(bx, by), 2.0, Color("6a5a40"))
	_draw_planks()

	# 점검로
	draw_rect(Rect2(380, 40, 100, 244), Color("8d8b80"))
	draw_rect(Rect2(480, 40, 160, 120), Color("8d8b80"))
	draw_rect(Rect2(820, 40, W - 16 - 820, 120), Color("8d8b80"))
	for x in range(380, int(W - 16), 32):
		draw_line(Vector2(x, 40), Vector2(x, 160), Color("7a786e"), 1.0)
	draw_rect(DIVIDER, Color("6e6c62"))
	draw_rect(WALKWAY_RAIL, Color("5a5f66"))
	for x in range(380, int(W - 16), 24):
		draw_rect(Rect2(x, 22, 4, 18), Color("3a3f46"))
	# 끊긴 틈
	var gap: Rect2 = PITS["gap"]
	if gap_fixed:
		draw_rect(gap, Color("8a6a40"))
		for x in range(int(gap.position.x), int(gap.end.x), 10):
			draw_line(Vector2(x, gap.position.y), Vector2(x, gap.end.y), Color("5a4020"), 1.0)
	else:
		draw_rect(gap, Color("1e3a50").lerp(Color("3a3a24"), backflow))
		for i in 6:
			var y := gap.position.y + 10 + fposmod(i * 23.0 + t * 40.0, gap.size.y - 20)
			draw_line(Vector2(gap.position.x + 10, y), Vector2(gap.end.x - 10, y), Color(1, 1, 1, 0.12), 1.0)
		draw_line(gap.position, Vector2(gap.position.x, gap.end.y), Color("5a5040"), 3.0)
		draw_line(Vector2(gap.end.x, gap.position.y), gap.end, Color("5a5040"), 3.0)
	draw_rect(SAFE_LANDING, Color("8a6a40"))
	_draw_plank_lines(SAFE_LANDING)

	# 압력 손잡이
	draw_circle(HANDLE_POS + Vector2(0, -6), 14.0, Color("5a5f66"))
	var hs := t * (0.3 + backflow * 4.0)
	draw_arc(HANDLE_POS + Vector2(0, -6), 11.0, 0, TAU, 20, Color("c8a050"), 3.0)
	for i in 3:
		draw_line(HANDLE_POS + Vector2(0, -6), HANDLE_POS + Vector2(0, -6) + Vector2.RIGHT.rotated(hs + i * TAU / 3.0) * 11.0, Color("c8a050"), 2.0)

	for i in range(5, REEDS.size()):
		_draw_reeds(REEDS[i])

	for p in leaf_marks:
		var b := sin(t * 3.0) * 1.5
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10 + b), p + Vector2(7, -2 + b), p + Vector2(0, 6 + b), p + Vector2(-7, -2 + b)]), Color("8fdc5a"))
		draw_line(p + Vector2(0, -8 + b), p + Vector2(0, 5 + b), Color("4a8a2a"), 1.5)


func _draw_plank_lines(r: Rect2) -> void:
	for x in range(int(r.position.x), int(r.end.x), 10):
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("5a4020"), 1.0)


func _draw_planks() -> void:
	for wp in weak_planks:
		var r: Rect2 = wp["rect"]
		if wp["broken"]:
			draw_rect(r, Color("1e3a50") if wp["hidden"] else Color("4a3a28"))
			continue
		var shake_x := sin(t * 60.0) * 1.5 if wp["timer"] > 0.0 else 0.0
		var rr := Rect2(r.position + Vector2(shake_x, 0), r.size)
		draw_rect(rr, Color("8a6a40") if wp["hidden"] else Color("6a5030"))
		_draw_plank_lines(rr)
		if wp["revealed"] or gap_fixed:
			if wp["hidden"] and not gap_fixed:
				# 도톰이 알려준 위험 발판
				draw_line(rr.position + Vector2(10, 8), rr.end - Vector2(10, 8), Color("e05040"), 3.0)
				draw_line(Vector2(rr.end.x - 10, rr.position.y + 8), Vector2(rr.position.x + 10, rr.end.y - 8), Color("e05040"), 3.0)
			elif not wp["hidden"]:
				for i in 3:
					draw_line(rr.position + Vector2(10 + i * 22, 6), rr.position + Vector2(18 + i * 22, rr.size.y - 6), Color("2a1a10"), 1.5)


## 지도 남쪽 밖: 이동할 수 없는 마을 담장과 교육원 뒤뜰. 카메라 여백용 장식.
func _draw_south_margin() -> void:
	var top := H - 16.0
	draw_rect(Rect2(-64, top, COL_W + 64, BOTTOM_MARGIN + 16), Color("a8946e"))
	draw_rect(Rect2(COL_W - 16, top, W - COL_W + 80, BOTTOM_MARGIN + 16), Color("2f4a2a"))
	for i in 18:
		var c := Vector2(COL_W + fposmod(i * 83.0, W - COL_W), top + 30 + fposmod(i * 47.0, BOTTOM_MARGIN - 40))
		draw_circle(c, 18.0, Color("3a5a32"))
	# 담장
	draw_rect(Rect2(0, top, COL_W, 16), Color("7a786e"))
	for x in range(0, int(COL_W), 24):
		draw_line(Vector2(x, top), Vector2(x, H), Color("5e5c54"), 1.0)
	draw_line(Vector2(0, top + 8), Vector2(COL_W, top + 8), Color("5e5c54"), 1.0)
	# 교육원 뒤뜰 지붕과 화단
	draw_rect(Rect2(40, H + 40, 120, 70), Color("6a4a3a"))
	draw_rect(Rect2(40, H + 40, 120, 12), Color("7a5a48"))
	draw_rect(Rect2(230, H + 60, 110, 60), Color("6a4a3a"))
	draw_rect(Rect2(230, H + 60, 110, 12), Color("7a5a48"))
	for i in 6:
		draw_circle(Vector2(30 + i * 60, H + 160), 12.0, Color("5e7a48"))
		draw_circle(Vector2(30 + i * 60, H + 156), 4.0, Color("d2ad62"))