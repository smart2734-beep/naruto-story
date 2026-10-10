extends Node2D
## 이음터(아래) → 갈대둑 필드 → 수문(위). 임시 도형 아트와 충돌 영역.
## 1타일 = 32px. 화면에는 가로 약 10타일이 보이도록 카메라를 맞춘다.

const W := 384.0
const H := 1920.0
const FIELD_BOTTOM := 1480.0
const PLATFORM_BOTTOM := 216.0
const TOP_MARGIN := 240.0

const HOUSES: Array[Rect2] = [Rect2(24, 1520, 96, 64), Rect2(264, 1520, 96, 64), Rect2(24, 1790, 80, 60), Rect2(290, 1800, 70, 56)]
const FENCES: Array[Rect2] = [Rect2(16, 1472, 134, 12), Rect2(234, 1472, 134, 12)]
const WATER: Array[Rect2] = [Rect2(16, 96, 80, 1376), Rect2(300, 96, 68, 1376)]
const REEDS: Array[Rect2] = [Rect2(126, 1200, 40, 30), Rect2(232, 980, 44, 30), Rect2(108, 840, 36, 36), Rect2(240, 600, 40, 28), Rect2(150, 420, 34, 26)]
const GATE := Rect2(96, 24, 192, 56)
const WELL_POS := Vector2(200, 1620)

var t := 0.0
var backflow := 0.0  ## 0 = 정상 흐름, 1 = 역류
var goal = null  ## 위치 목표 표시 (Vector2 또는 null)
var _grass: PackedVector2Array = []
var _pebbles: PackedVector2Array = []


func _ready() -> void:
	var blockers: Array[Rect2] = [
		Rect2(0, 0, 16, H), Rect2(W - 16, 0, 16, H), Rect2(0, 0, W, 16), Rect2(0, H - 16, W, 16),
		GATE,
	]
	blockers.append_array(HOUSES)
	blockers.append_array(FENCES)
	blockers.append_array(WATER)
	blockers.append_array(REEDS)
	for r in blockers:
		_add_box(r)
	_add_circle(WELL_POS, 14.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 420:
		_grass.append(Vector2(rng.randf_range(96, 300), rng.randf_range(PLATFORM_BOTTOM, FIELD_BOTTOM)))
	for i in 160:
		_pebbles.append(Vector2(rng.randf_range(16, W - 16), rng.randf_range(FIELD_BOTTOM + 12, H - 16)))


func _add_box(r: Rect2) -> void:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.get_center()
	body.add_child(cs)
	add_child(body)


func _add_circle(p: Vector2, radius: float) -> void:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = radius
	cs.shape = sh
	cs.position = p
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	# 수문 위 저수지 (카메라가 상단 HUD 아래까지 내려 보이도록 지도 밖에 그린다)
	var reservoir := Color("3f7fa8").lerp(Color("6b6a4a"), backflow)
	draw_rect(Rect2(-64, -TOP_MARGIN, W + 128, TOP_MARGIN + 16), reservoir)
	for i in 30:
		var rx := fposmod(i * 71.0 + t * 8.0, W + 64.0) - 32.0
		var ry := -TOP_MARGIN + fposmod(i * 37.0, TOP_MARGIN)
		draw_line(Vector2(rx, ry), Vector2(rx + 14, ry), Color(1, 1, 1, 0.2), 1.0)
	draw_rect(Rect2(-64, 8, W + 128, 8), Color("6e6c62"))
	# 필드 바닥
	draw_rect(Rect2(0, 16, W, FIELD_BOTTOM - 16), Color("6f8f4e"))
	draw_rect(Rect2(150, PLATFORM_BOTTOM, 84, FIELD_BOTTOM - PLATFORM_BOTTOM), Color("8a7a55"))
	for p in _grass:
		draw_rect(Rect2(p, Vector2(2, 3)), Color("5c7a3e"))
	# 수문 앞 돌바닥
	draw_rect(Rect2(16, 16, W - 32, PLATFORM_BOTTOM - 16), Color("8d8b80"))
	for y in range(24, int(PLATFORM_BOTTOM), 24):
		draw_line(Vector2(16, y), Vector2(W - 16, y), Color("7a786e"), 1.0)

	# 물길
	var clean := Color("3f7fa8")
	var muddy := Color("6b6a4a")
	var water_col := clean.lerp(muddy, backflow)
	var flow := lerpf(1.0, -2.2, backflow)
	for r in WATER:
		draw_rect(r, water_col)
		for i in 26:
			var y := fposmod(i * 53.0 + t * 26.0 * flow, r.size.y)
			var x := r.position.x + fposmod(i * 29.0, r.size.x - 16.0) + 4.0
			draw_line(Vector2(x, r.position.y + y), Vector2(x + 10, r.position.y + y), Color(1, 1, 1, 0.25), 1.0)
		draw_rect(r, Color("2c5670").lerp(Color("4a4a30"), backflow), false, 2.0)

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

	# 갈대
	for r in REEDS:
		draw_rect(r, Color("4e6a33"))
		for i in 7:
			var x := r.position.x + 3 + i * (r.size.x - 6) / 6.0
			var sway := sin(t * 2.0 + i) * 2.0
			draw_line(Vector2(x, r.end.y), Vector2(x + sway, r.position.y - 6), Color("a8b060"), 2.0)

	# 마을 바닥
	draw_rect(Rect2(0, FIELD_BOTTOM, W, H - FIELD_BOTTOM), Color("c8b088"))
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
	# 마을 문기둥
	draw_rect(Rect2(140, 1460, 10, 28), Color("5a3a20"))
	draw_rect(Rect2(234, 1460, 10, 28), Color("5a3a20"))
	draw_rect(Rect2(136, 1456, 112, 6), Color("7fd6c2"))
	# 우물
	draw_circle(WELL_POS, 14.0, Color("7a7a78"))
	draw_circle(WELL_POS, 9.0, Color("2f4f68"))

	if goal != null:
		var g: Vector2 = goal
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		draw_arc(g, 16.0 + pulse * 4.0, 0, TAU, 28, Color(1.0, 0.85, 0.3, 0.9), 2.0)
		draw_arc(g, 8.0, 0, TAU, 20, Color(1.0, 0.85, 0.3, 0.5), 2.0)
