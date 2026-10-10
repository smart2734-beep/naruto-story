extends CharacterBody2D
## 덩굴딱정벌레: 돌진 후 빈틈. 다가옴 → 몸을 낮추고 돌진 방향 예고 → 직선 돌진(벽에 막히면 멈춤) → 덩굴이 엉켜 빈틈 → 복귀.

signal aim_started(enemy)
signal defeated(enemy)

enum State { IDLE, APPROACH, AIM, CHARGE, STUNNED, RETURN }

const NOTICE := 150.0
const CHARGE_RANGE := 110.0
const WALK_SPEED := 38.0
const AIM_TIME := 0.75
const CHARGE_SPEED := 360.0
const CHARGE_DIST := 190.0
const STUN_TIME := 1.5
const DAMAGE := 18.0
const HIT_RADIUS := 18.0
const LANE_WIDTH := 26.0
const LEASH := 260.0

var home := Vector2.ZERO
var state: State = State.IDLE
var t := 0.0
var cooldown := 0.8
var dir := Vector2.DOWN
var traveled := 0.0
var max_hp := 40.0
var hp := 40.0
var alive := true
var hit_player := false
var flash := 0.0
var anim := 0.0
var fade := 1.0
var player  # player.gd


func _ready() -> void:
	home = position
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 0
	collision_mask = 1 | 2
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	add_to_group("enemy")


func reset_to_home() -> void:
	if not alive:
		return
	position = home
	state = State.IDLE
	cooldown = 1.0


func _player_ok() -> bool:
	return player != null and not player.dead and not player.falling


func _physics_process(delta: float) -> void:
	if not alive:
		fade -= delta * 2.0
		queue_redraw()
		if fade <= 0.0:
			queue_free()
		return
	flash = maxf(flash - delta, 0.0)
	anim += delta
	var to_player := Vector2.ZERO
	var dist := INF
	if _player_ok():
		to_player = player.global_position - global_position
		dist = to_player.length()
	match state:
		State.IDLE:
			cooldown -= delta
			velocity = Vector2.ZERO
			if cooldown <= 0.0 and dist < NOTICE:
				state = State.APPROACH
		State.APPROACH:
			if dist > NOTICE * 1.4 or position.distance_to(home) > LEASH:
				state = State.RETURN
			elif dist < CHARGE_RANGE:
				dir = to_player.normalized()
				state = State.AIM
				t = AIM_TIME
				velocity = Vector2.ZERO
				aim_started.emit(self)
			else:
				velocity = to_player.normalized() * WALK_SPEED
				dir = to_player.normalized()
		State.AIM:
			velocity = Vector2.ZERO
			t -= delta
			if t <= 0.0:
				state = State.CHARGE
				traveled = 0.0
				hit_player = false
		State.CHARGE:
			velocity = dir * CHARGE_SPEED
			var before := position
			move_and_slide()
			traveled += position.distance_to(before)
			if not hit_player and _player_ok() and global_position.distance_to(player.global_position) < HIT_RADIUS:
				hit_player = player.take_damage(DAMAGE, global_position, self) or player.guard_t > 0.0
			# 다 달렸거나 벽에 막히면 덩굴이 엉킨다.
			if traveled >= CHARGE_DIST or position.distance_to(before) < CHARGE_SPEED * delta * 0.3:
				state = State.STUNNED
				t = STUN_TIME
			velocity = Vector2.ZERO
			queue_redraw()
			return
		State.STUNNED:
			velocity = Vector2.ZERO
			t -= delta
			if t <= 0.0:
				state = State.APPROACH if dist < NOTICE else State.RETURN
				cooldown = 0.6
		State.RETURN:
			var to_home := home - position
			if to_home.length() < 4.0:
				state = State.IDLE
				cooldown = 0.8
				velocity = Vector2.ZERO
			else:
				velocity = to_home.normalized() * WALK_SPEED * 1.5
				dir = to_home.normalized()
			if dist < NOTICE * 0.7:
				state = State.APPROACH
	move_and_slide()
	queue_redraw()


func take_hit(amount: float, _from: Vector2) -> void:
	if not alive:
		return
	if state == State.STUNNED:
		amount *= 1.5
	hp -= amount
	flash = 0.15
	var ft := preload("res://scripts/float_text.gd").new()
	ft.text = str(roundi(amount))
	ft.color = Color("ffe08a") if state == State.STUNNED else Color.WHITE
	ft.position = position + Vector2(0, -22)
	get_parent().add_child(ft)
	if hp <= 0.0:
		alive = false
		remove_from_group("enemy")
		collision_mask = 0
		defeated.emit(self)


func _draw() -> void:
	var a := fade
	if state == State.AIM and alive:
		var progress := 1.0 - t / AIM_TIME
		var perp := dir.orthogonal() * (LANE_WIDTH * 0.5)
		var end := dir * CHARGE_DIST
		draw_colored_polygon(PackedVector2Array([perp, end + perp, end - perp, -perp]), Color(0.9, 0.5, 0.1, 0.18))
		var fe := dir * CHARGE_DIST * progress
		draw_colored_polygon(PackedVector2Array([perp, fe + perp, fe - perp, -perp]), Color(1.0, 0.55, 0.1, 0.45))
		draw_polyline(PackedVector2Array([perp, end + perp, end - perp, -perp, perp]), Color(1.0, 0.6, 0.2, 0.9), 1.5)
		draw_string(GameState.world_font, Vector2(-10, -24), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 16, Color("ff9030"))

	draw_set_transform(Vector2(0, 7), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.3 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var shell := Color("3a6a3a")
	if flash > 0.0:
		shell = Color.WHITE
	shell.a = a
	var crouch := 0.85 if state == State.AIM else 1.0
	var side := dir.orthogonal()
	# 다리
	for i in 3:
		var leg := sin(anim * 12.0 + i) * 2.0 if velocity.length() > 1.0 else 0.0
		var base := dir * (4.0 - i * 4.0)
		draw_line(base + side * 7.0, base + side * (12.0 + leg), Color(0.2, 0.25, 0.15, a), 1.5)
		draw_line(base - side * 7.0, base - side * (12.0 - leg), Color(0.2, 0.25, 0.15, a), 1.5)
	draw_set_transform(Vector2.ZERO, dir.angle(), Vector2(1.0, crouch))
	draw_circle(Vector2(-2, 0), 10.0, shell)
	draw_line(Vector2(-11, 0), Vector2(7, 0), Color(0.15, 0.3, 0.15, a), 1.5)
	draw_circle(Vector2(9, 0), 5.0, Color(0.25, 0.35, 0.2, a))
	draw_line(Vector2(12, -2), Vector2(18, -6), Color(0.6, 0.75, 0.3, a), 2.0)
	draw_line(Vector2(12, 2), Vector2(18, 6), Color(0.6, 0.75, 0.3, a), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if state == State.STUNNED and alive:
		# 엉킨 덩굴 = 빈틈
		for i in 4:
			var ang := anim * 2.0 + i * PI / 2.0
			draw_arc(Vector2.ZERO, 13.0, ang, ang + 0.9, 6, Color("a8c060"), 2.0)
		var spin := anim * 6.0
		for i in 3:
			draw_circle(Vector2(0, -18) + Vector2(cos(spin + i * TAU / 3.0) * 8.0, sin(spin + i * TAU / 3.0) * 3.0), 1.6, Color("ffe08a"))

	if hp < max_hp and alive:
		draw_rect(Rect2(-12, -22, 24, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-12, -22, 24.0 * hp / max_hp, 3), Color("e05050"))
