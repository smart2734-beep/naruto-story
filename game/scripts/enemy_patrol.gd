extends Node2D
## 녹슨 순찰기: 방향성 직선 공격. 정해진 구간을 왕복하며 바라보는 방향으로만 쏜다.
## 앞쪽 일직선에 플레이어가 있으면 멈춰서 예고 → 충격파 발사 → 과열(빈틈). 뒤나 옆에서 다가가면 안전하다.

signal aim_started(enemy)
signal defeated(enemy)

enum State { PATROL, AIM, FIRE, OVERHEAT }

const SPEED := 40.0
const SIGHT := 210.0
const SIGHT_HALF_WIDTH := 22.0
const AIM_TIME := 0.8
const FIRE_TIME := 0.25
const OVERHEAT_TIME := 1.3
const DAMAGE := 20.0
const LANE_WIDTH := 26.0

var min_x := 0.0
var max_x := 0.0
var facing := 1.0  ## +1 오른쪽, -1 왼쪽
var state: State = State.PATROL
var t := 0.0
var turn_wait := 0.0
var max_hp := 60.0
var hp := 60.0
var alive := true
var flash := 0.0
var anim := 0.0
var fade := 1.0
var hit_done := false
var home := Vector2.ZERO
var player  # player.gd


func _ready() -> void:
	home = position
	add_to_group("enemy")


func reset_to_home() -> void:
	if not alive:
		return
	position = home
	state = State.PATROL
	facing = 1.0


func _dir() -> Vector2:
	return Vector2(facing, 0)


func _in_lane(p: Vector2, length: float) -> bool:
	var d := p - global_position
	return d.x * facing > 0.0 and absf(d.x) < length and absf(d.y) < SIGHT_HALF_WIDTH


func _physics_process(delta: float) -> void:
	if not alive:
		fade -= delta * 2.0
		queue_redraw()
		if fade <= 0.0:
			queue_free()
		return
	flash = maxf(flash - delta, 0.0)
	anim += delta
	var p_ok: bool = player != null and not player.dead and not player.falling
	match state:
		State.PATROL:
			if turn_wait > 0.0:
				turn_wait -= delta
			else:
				position.x += facing * SPEED * delta
				if (facing > 0.0 and position.x >= max_x) or (facing < 0.0 and position.x <= min_x):
					position.x = clampf(position.x, min_x, max_x)
					facing = -facing
					turn_wait = 0.6
			if p_ok and _in_lane(player.global_position, SIGHT):
				state = State.AIM
				t = AIM_TIME
				aim_started.emit(self)
		State.AIM:
			t -= delta
			if t <= 0.0:
				state = State.FIRE
				t = FIRE_TIME
				hit_done = false
		State.FIRE:
			t -= delta
			if not hit_done and p_ok and _in_lane(player.global_position, SIGHT):
				hit_done = player.take_damage(DAMAGE, global_position, self) or player.guard_t > 0.0
			if t <= 0.0:
				state = State.OVERHEAT
				t = OVERHEAT_TIME
		State.OVERHEAT:
			t -= delta
			if t <= 0.0:
				state = State.PATROL
	queue_redraw()


func take_hit(amount: float, from: Vector2) -> void:
	if not alive:
		return
	if state == State.OVERHEAT:
		amount *= 1.5
	hp -= amount
	flash = 0.15
	var ft := preload("res://scripts/float_text.gd").new()
	ft.text = str(roundi(amount))
	ft.color = Color("ffe08a") if state == State.OVERHEAT else Color.WHITE
	ft.position = position + Vector2(0, -24)
	get_parent().add_child(ft)
	# 뒤에서 맞으면 돌아본다.
	if state == State.PATROL and (from.x - global_position.x) * facing < 0.0:
		facing = -facing
	if hp <= 0.0:
		alive = false
		remove_from_group("enemy")
		defeated.emit(self)


func _draw() -> void:
	var a := fade
	var d := _dir()
	var perp := Vector2(0, LANE_WIDTH * 0.5)
	if alive and state == State.AIM:
		var progress := 1.0 - t / AIM_TIME
		var end := d * SIGHT
		draw_colored_polygon(PackedVector2Array([perp, end + perp, end - perp, -perp]), Color(0.9, 0.15, 0.1, 0.16))
		var fe := d * SIGHT * progress
		draw_colored_polygon(PackedVector2Array([perp, fe + perp, fe - perp, -perp]), Color(1.0, 0.25, 0.1, 0.42))
		draw_polyline(PackedVector2Array([perp, end + perp, end - perp, -perp, perp]), Color(1.0, 0.35, 0.2, 0.9), 1.5)
		draw_string(GameState.world_font, Vector2(-10, -26), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 16, Color("ff5030"))
	elif alive and state == State.FIRE:
		var end := d * SIGHT
		draw_colored_polygon(PackedVector2Array([perp * 0.6, end + perp * 0.6, end - perp * 0.6, -perp * 0.6]), Color(1.0, 0.9, 0.5, 0.85))
	elif alive and state == State.PATROL:
		# 시야 방향을 옅게 표시 — 앞쪽만 위험하다는 것을 읽을 수 있게
		draw_colored_polygon(PackedVector2Array([d * 14.0 + perp * 0.6, d * 60.0 + perp, d * 60.0 - perp, d * 14.0 - perp * 0.6]), Color(1.0, 0.9, 0.4, 0.12))

	draw_set_transform(Vector2(0, 9), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.3 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var body := Color("8a6a4a")
	if flash > 0.0:
		body = Color.WHITE
	elif state == State.OVERHEAT:
		body = Color("b05a3a")
	body.a = a
	draw_rect(Rect2(-11, -10, 22, 18), body)
	draw_rect(Rect2(-11, -10, 22, 18), Color(0.3, 0.22, 0.15, a), false, 1.5)
	for i in 3:
		draw_circle(Vector2(-6 + i * 6, 9), 2.5, Color(0.25, 0.25, 0.28, a))
	# 방향 렌즈
	draw_circle(Vector2(facing * 9.0, -2), 4.0, Color(1.0, 0.8, 0.3, a) if state != State.OVERHEAT else Color(0.4, 0.3, 0.2, a))
	draw_rect(Rect2(-3, -16, 6, 6), Color(0.4, 0.35, 0.3, a))
	if state == State.OVERHEAT and alive:
		for i in 3:
			var y := -18.0 - fposmod(anim * 20.0 + i * 6.0, 16.0)
			draw_circle(Vector2(-4 + i * 4, y), 2.0, Color(0.8, 0.8, 0.8, 0.5))

	if hp < max_hp and alive:
		draw_rect(Rect2(-12, -26, 24, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-12, -26, 24.0 * hp / max_hp, 3), Color("e05050"))
