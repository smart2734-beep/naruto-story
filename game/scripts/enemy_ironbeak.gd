extends Node2D
## 철부리새: 직선 급습. 노려보기(예고) → 급강하 → 휘청(빈틈) → 복귀.
## 예고는 색만이 아니라 방향선·차오르는 길이·느낌표로 함께 보여준다 (기획서 2장).

signal aim_started(bird)
signal defeated(bird)

enum State { IDLE, AIM, SWOOP, RECOVER, RETURN }

const DETECT := 170.0
const AIM_TIME := 0.9
const SWOOP_SPEED := 430.0
const SWOOP_DIST := 220.0
const RECOVER_TIME := 1.1
const DAMAGE := 15.0
const HIT_RADIUS := 16.0
const LANE_WIDTH := 22.0

var home := Vector2.ZERO
var state: State = State.IDLE
var t := 0.0
var cooldown := 1.0
var dir := Vector2.DOWN
var traveled := 0.0
var max_hp := 30.0
var hp := 30.0
var alive := true
var hit_player := false
var flash := 0.0
var bob := 0.0
var fade := 1.0
var player  # player.gd (동적 접근: dead, take_damage)


func _ready() -> void:
	home = position
	add_to_group("enemy")


func reset_to_home() -> void:
	if not alive:
		return
	position = home
	state = State.IDLE
	cooldown = 1.0
	bob = 0.0


func _physics_process(delta: float) -> void:
	if not alive:
		fade -= delta * 2.0
		queue_redraw()
		if fade <= 0.0:
			queue_free()
		return
	flash = maxf(flash - delta, 0.0)
	bob += delta
	match state:
		State.IDLE:
			cooldown -= delta
			position = home + Vector2(sin(bob * 1.3) * 6.0, 0.0)
			if cooldown <= 0.0 and player and not player.dead \
					and global_position.distance_to(player.global_position) < DETECT:
				dir = (player.global_position - global_position).normalized()
				state = State.AIM
				t = AIM_TIME
				aim_started.emit(self)
		State.AIM:
			t -= delta
			if t <= 0.0:
				state = State.SWOOP
				traveled = 0.0
				hit_player = false
		State.SWOOP:
			var step := SWOOP_SPEED * delta
			position += dir * step
			traveled += step
			if not hit_player and player and global_position.distance_to(player.global_position) < HIT_RADIUS:
				hit_player = player.take_damage(DAMAGE, global_position)
			if traveled >= SWOOP_DIST:
				state = State.RECOVER
				t = RECOVER_TIME
		State.RECOVER:
			t -= delta
			if t <= 0.0:
				state = State.RETURN
		State.RETURN:
			position = position.move_toward(home, 110.0 * delta)
			if position.distance_to(home) < 2.0:
				position = home
				state = State.IDLE
				cooldown = 1.2
				bob = 0.0
	queue_redraw()


func take_hit(amount: float, _from: Vector2) -> void:
	if not alive:
		return
	# 급강하 뒤 휘청일 때가 반격 기회.
	if state == State.RECOVER:
		amount *= 1.5
	hp -= amount
	flash = 0.15
	var ft := preload("res://scripts/float_text.gd").new()
	ft.text = str(roundi(amount))
	ft.color = Color("ffe08a") if state == State.RECOVER else Color.WHITE
	ft.position = position + Vector2(0, -22)
	get_parent().add_child(ft)
	if hp <= 0.0:
		alive = false
		remove_from_group("enemy")
		defeated.emit(self)


func _draw() -> void:
	var a := fade
	if state == State.AIM and alive:
		var progress := 1.0 - t / AIM_TIME
		var perp := dir.orthogonal() * (LANE_WIDTH * 0.5)
		var end := dir * SWOOP_DIST
		var lane := PackedVector2Array([perp, end + perp, end - perp, -perp])
		draw_colored_polygon(lane, Color(0.9, 0.15, 0.1, 0.18))
		var fill_end := dir * SWOOP_DIST * progress
		draw_colored_polygon(PackedVector2Array([perp, fill_end + perp, fill_end - perp, -perp]), Color(1.0, 0.25, 0.1, 0.45))
		draw_polyline(PackedVector2Array([perp, end + perp, end - perp, -perp, perp]), Color(1.0, 0.35, 0.2, 0.9), 1.5)
		# 방향 화살촉
		for i in range(1, 4):
			var c := dir * (SWOOP_DIST * i / 4.0)
			draw_polyline(PackedVector2Array([c - dir * 6.0 + perp * 0.6, c, c - dir * 6.0 - perp * 0.6]), Color(1, 0.9, 0.8, 0.8), 1.5)
		var f := GameState.world_font
		draw_string(f, Vector2(-10, -30), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 16, Color("ff5030"))

	var lift := -6.0 + sin(bob * 6.0) * 1.5
	if state == State.SWOOP:
		lift = -2.0
	elif state == State.RECOVER:
		lift = 0.0
	# 그림자
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.3 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var body := Color("6c7a89")
	if flash > 0.0:
		body = Color.WHITE
	body.a = a
	var o := Vector2(0, lift)
	var flap := sin(bob * 14.0) * 4.0 if state != State.RECOVER else 0.0
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([o + side * 5.0, o + side * 15.0 + Vector2(0, flap), o - dir * 4.0]), Color(0.35, 0.42, 0.5, a))
	draw_colored_polygon(PackedVector2Array([o - side * 5.0, o - side * 15.0 + Vector2(0, flap), o - dir * 4.0]), Color(0.35, 0.42, 0.5, a))
	draw_circle(o, 8.0, body)
	# 쇠부리
	draw_colored_polygon(PackedVector2Array([o + dir * 15.0, o + dir * 6.0 + side * 3.5, o + dir * 6.0 - side * 3.5]), Color(0.25, 0.25, 0.3, a))
	draw_circle(o + dir * 3.0 + side * 3.0, 1.5, Color(1, 0.9, 0.3, a))

	if state == State.RECOVER and alive:
		var spin := bob * 6.0
		for i in 3:
			var p := o + Vector2(0, -14) + Vector2(cos(spin + i * TAU / 3.0) * 8.0, sin(spin + i * TAU / 3.0) * 3.0)
			draw_circle(p, 1.6, Color("ffe08a"))

	if hp < max_hp and alive:
		draw_rect(Rect2(-12, -24, 24, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-12, -24, 24.0 * hp / max_hp, 3), Color("e05050"))
