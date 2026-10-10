extends Node2D
## 물레방아 아래 짧은 던전 (Q5). 바깥 지도 오른쪽(x 1200~1680)에 따로 둔다.
##   1방(아래): 일반 적  →  2방: 물레 손잡이 두 개를 맞춰 배수, 고립된 정비공
##   3방(위): 거름집게. 오른쪽 아래 높은 발판이 안전 지대, 그 위 수문 손잡이로 물길 방출을 막는다.

const X0 := 1200.0
const X1 := 1680.0
const Y0 := 0.0
const Y1 := 1500.0
const DOOR_X := Rect2(1410, 0, 60, 0)  ## 방 사이 문 (x 범위만 사용)
const WALL_12 := 1092.0  ## 1방·2방 사이 벽 중심 y
const WALL_23 := 632.0   ## 2방·3방 사이 벽 중심 y
const POOL := Rect2(1216, 780, 448, 180)
const HANDLE_L := Vector2(1292, 1020)
const HANDLE_R := Vector2(1588, 1020)
const PLAQUE := Vector2(1440, 1000)
const SAFE_ZONE := Rect2(1560, 470, 104, 154)
const SLUICE := Vector2(1592, 488)
const WAIT_SPOT := Vector2(1628, 578)
const BOSS_HOME := Vector2(1440, 240)
const START := Vector2(1440, 1430)
const ROOM2_START := Vector2(1440, 1060)
const ROOM3_START := Vector2(1440, 600)
const ARROWS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
## 두 물레 손잡이가 서로 마주 볼 때(왼쪽 →, 오른쪽 ←) 물이 빠진다.
const TARGET_L := 1
const TARGET_R := 3

var t := 0.0
var handle_l := 0
var handle_r := 1
var drained := false
var drain_k := 1.0  ## 물 높이 1 → 0
var flood := 0.0  ## 보스 물길 방출 수위 0~1
var secured := false  ## 수문 손잡이로 안전 지대 확보
var boss_stopped := false
var _pool_body: StaticBody2D


func _ready() -> void:
	var walls: Array[Rect2] = [
		Rect2(X0, Y0, 16, Y1), Rect2(X1 - 16, Y0, 16, Y1), Rect2(X0, Y0, X1 - X0, 16), Rect2(X0, Y1 - 16, X1 - X0, 16),
		Rect2(X0 + 16, WALL_12 - 8, 1410 - X0 - 16, 16), Rect2(1470, WALL_12 - 8, X1 - 16 - 1470, 16),
		Rect2(X0 + 16, WALL_23 - 8, 1410 - X0 - 16, 16), Rect2(1470, WALL_23 - 8, X1 - 16 - 1470, 16),
		# 안전 지대 발판의 왼쪽·위 난간 (입구는 아래쪽 왼편)
		Rect2(SAFE_ZONE.position.x - 6, SAFE_ZONE.position.y, 6, SAFE_ZONE.size.y - 50),
	]
	for r in walls:
		_add_box(r)
	_pool_body = _add_box(POOL)


func _add_box(r: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.get_center()
	body.add_child(cs)
	add_child(body)
	return body


func turn_handle(right: bool) -> bool:
	if drained:
		return false
	if right:
		handle_r = (handle_r + 1) % 4
	else:
		handle_l = (handle_l + 1) % 4
	if handle_l == TARGET_L and handle_r == TARGET_R:
		drained = true
		_pool_body.get_child(0).set_deferred("disabled", true)
	return drained


func room_of(p: Vector2) -> int:
	if p.y > WALL_12:
		return 1
	if p.y > WALL_23:
		return 2
	return 3


func checkpoint_for(p: Vector2) -> Vector2:
	match room_of(p):
		1:
			return START
		2:
			return ROOM2_START
	return ROOM3_START


func in_safe_zone(p: Vector2) -> bool:
	return SAFE_ZONE.has_point(p)


func _process(delta: float) -> void:
	t += delta
	if drained and drain_k > 0.0:
		drain_k = maxf(drain_k - delta / 1.5, 0.0)
	queue_redraw()


func _draw() -> void:
	# 바깥 어둠
	draw_rect(Rect2(X0 - 60, Y0 - 200, X1 - X0 + 260, Y1 - Y0 + 400), Color("14202b"))  # 바깥 지도(x ≤ 1088)를 덮지 않게
	# 바닥: 젖은 석재
	draw_rect(Rect2(X0, Y0, X1 - X0, Y1 - Y0), Color("4a5048"))
	for y in range(int(Y0) + 16, int(Y1), 32):
		draw_line(Vector2(X0, y), Vector2(X1, y), Color("3e443e"), 1.0)
		var off := 16 if (y / 32) % 2 == 0 else 0
		for x in range(int(X0) + off, int(X1), 32):
			draw_line(Vector2(x, y), Vector2(x, y + 32), Color("3e443e"), 1.0)
	# 벽
	var wall := Color("2a2e2a")
	draw_rect(Rect2(X0, Y0, 16, Y1), wall)
	draw_rect(Rect2(X1 - 16, Y0, 16, Y1), wall)
	draw_rect(Rect2(X0, Y0, X1 - X0, 16), wall)
	draw_rect(Rect2(X0, Y1 - 16, X1 - X0, 16), wall)
	for wy in [WALL_12, WALL_23]:
		draw_rect(Rect2(X0, wy - 8, 1410 - X0, 16), wall)
		draw_rect(Rect2(1470, wy - 8, X1 - 1470, 16), wall)
		# 문틀과 황동 램프
		draw_rect(Rect2(1404, wy - 12, 6, 24), Color("75513a"))
		draw_rect(Rect2(1470, wy - 12, 6, 24), Color("75513a"))
		draw_circle(Vector2(1398, wy - 14), 3.0, Color("f2d28b"))
		draw_circle(Vector2(1398, wy - 14), 9.0, Color(0.95, 0.82, 0.55, 0.15))
	# 입구 계단
	for i in 4:
		draw_rect(Rect2(1410, Y1 - 16 - 10 - i * 8, 60, 6), Color("6e6c62"))

	# 2방: 물웅덩이, 물레 손잡이, 안내판
	if drain_k > 0.0:
		var water := Color(0.25, 0.4, 0.45, 0.85 * drain_k + 0.1)
		draw_rect(POOL, water)
		for i in 14:
			var y := POOL.position.y + fposmod(i * 41.0 + t * 12.0, POOL.size.y)
			var x := POOL.position.x + fposmod(i * 67.0, POOL.size.x - 20.0)
			draw_line(Vector2(x, y), Vector2(x + 14, y), Color(1, 1, 1, 0.2 * drain_k), 1.0)
	else:
		draw_rect(POOL, Color("3a3e36"))
		draw_rect(POOL, Color("2e322c"), false, 2.0)
	_draw_handle(HANDLE_L, handle_l, handle_l == TARGET_L)
	_draw_handle(HANDLE_R, handle_r, handle_r == TARGET_R)
	draw_rect(Rect2(PLAQUE + Vector2(-20, -14), Vector2(40, 20)), Color("75513a"))
	draw_line(PLAQUE + Vector2(-14, -4), PLAQUE + Vector2(-4, -4), Color("f2d28b"), 2.0)
	draw_line(PLAQUE + Vector2(-7, -8), PLAQUE + Vector2(-4, -4), Color("f2d28b"), 2.0)
	draw_line(PLAQUE + Vector2(14, -4), PLAQUE + Vector2(4, -4), Color("f2d28b"), 2.0)
	draw_line(PLAQUE + Vector2(7, -8), PLAQUE + Vector2(4, -4), Color("f2d28b"), 2.0)

	# 3방: 안전 지대 발판과 수문 손잡이
	draw_rect(SAFE_ZONE, Color("777d78"))
	draw_rect(SAFE_ZONE, Color("a2a58f"), false, 2.0)
	for i in 4:
		draw_rect(Rect2(SAFE_ZONE.position.x + 6, SAFE_ZONE.end.y - 10 - i * 7, 40, 4), Color("8a8e86"))
	draw_circle(SLUICE + Vector2(0, -8), 11.0, Color("5a5f66"))
	draw_arc(SLUICE + Vector2(0, -8), 9.0, 0, TAU, 16, Color("d2ad62"), 3.0)
	draw_line(SLUICE + Vector2(0, -8), SLUICE + Vector2(0, -8) + Vector2.RIGHT.rotated(t * (4.0 if secured else 0.3)) * 9.0, Color("d2ad62"), 2.0)

	# 물길 방출: 안전 지대(확보했을 때) 밖이 잠긴다
	if flood > 0.0:
		var fl := Color(0.35, 0.55, 0.6, 0.55 * flood)
		var arena := Rect2(X0 + 16, Y0 + 16, X1 - X0 - 32, WALL_23 - 8 - 16)
		if secured:
			draw_rect(Rect2(arena.position, Vector2(SAFE_ZONE.position.x - arena.position.x, arena.size.y)), fl)
			draw_rect(Rect2(SAFE_ZONE.position.x, arena.position.y, SAFE_ZONE.size.x, SAFE_ZONE.position.y - arena.position.y), fl)
			draw_rect(SAFE_ZONE.grow(3), Color(0.6, 0.95, 1.0, 0.8), false, 3.0)
		else:
			draw_rect(arena, fl)
		for i in 20:
			var x := arena.position.x + fposmod(i * 53.0 + t * 40.0, arena.size.x)
			var y := arena.position.y + fposmod(i * 37.0, arena.size.y)
			draw_line(Vector2(x, y), Vector2(x + 12, y), Color(1, 1, 1, 0.25 * flood), 1.0)


func _draw_handle(p: Vector2, dir_i: int, ok: bool) -> void:
	draw_circle(p, 14.0, Color("5a4028"))
	draw_arc(p, 14.0, 0, TAU, 20, Color("9be7a0") if ok else Color("75513a"), 2.0)
	var d := ARROWS[dir_i]
	draw_line(p, p + d * 12.0, Color("f2d28b"), 3.0)
	draw_line(p + d * 12.0, p + d * 6.0 + d.orthogonal() * 4.0, Color("f2d28b"), 3.0)
	draw_line(p + d * 12.0, p + d * 6.0 - d.orthogonal() * 4.0, Color("f2d28b"), 3.0)
