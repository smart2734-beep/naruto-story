extends Node2D
## 보스: 정비기 거름집게 (기획서 8장 1장 보스, Q5).
## 직선 집게 → 바닥 쓸기 → 직선 집게 → 물길 방출 을 반복한다. 모든 패턴은 예고 뒤에 온다.
##   직선 집게: 플레이어 쪽 직선(폭 32) 예고 0.9초 → 뻗기 → 1.3초 빈틈(피해 1.5배)
##   바닥 쓸기: 몸 둘레 반지름 96 예고 1.0초 → 쓸기
##   물길 방출: 3.2초 예고 → 방이 잠긴다. 수문 손잡이로 안전 지대를 확보하고 그 안에 있어야 안전 → 1.6초 배기(빈틈)
## 일반 회피(94px)만으로 모두 피할 수 있게 잡았다: 집게 반폭+몸 16+9 < 94, 근접(46)에서 쓸기 밖까지 96+9-46 < 94.

signal aim_started(enemy)
signal defeated(enemy)
signal release_started
signal flooded(secured: bool)

enum State { SLEEP, IDLE, CLAW_AIM, CLAW_STRIKE, CLAW_RECOVER, SWEEP_AIM, SWEEP_HIT, RELEASE_AIM, RELEASE_FLOOD, VENT, STOPPED }

const PATTERN := ["claw", "sweep", "claw", "release"]
const CLAW_AIM_TIME := 0.9
const CLAW_LEN := 260.0
const CLAW_WIDTH := 32.0
const CLAW_DMG := 22.0
const CLAW_RECOVER := 1.3
const SWEEP_AIM_TIME := 1.0
const SWEEP_R := 96.0
const SWEEP_DMG := 16.0
const RELEASE_AIM_TIME := 3.2
const FLOOD_TIME := 0.8
const FLOOD_DMG := 20.0
const FLOOD_WORKER_DMG := 30.0
const VENT_TIME := 1.6
const IDLE_TIME := 0.8
const MOVE_SPEED := 35.0
const MIN_X := 1290.0
const MAX_X := 1590.0

var alive := true
var max_hp := 320.0
var hp := 320.0
var state: State = State.SLEEP
var t := 0.0
var dir := Vector2.DOWN
var step := 0
var flash := 0.0
var anim := 0.0
var hit_done := false
var player  # player.gd
var dungeon  # dungeon.gd
var home := Vector2.ZERO
var _body: StaticBody2D


func _ready() -> void:
	home = position
	add_to_group("enemy")
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 20.0
	cs.shape = sh
	_body.add_child(cs)
	add_child(_body)


func wake() -> void:
	if state == State.SLEEP:
		state = State.IDLE
		t = 1.2


## 재도전: 체력과 패턴을 처음으로 되돌린다.
func reset_fight() -> void:
	if not alive:
		return
	hp = max_hp
	position = home
	step = 0
	state = State.SLEEP
	if dungeon:
		dungeon.flood = 0.0
		dungeon.secured = false


func reset_to_home() -> void:
	pass  # 일반 적 재배치에서는 건드리지 않는다. 보스 재도전은 reset_fight().


## 테스트·연출용: 다음 패턴을 바로 시작한다.
func force_pattern(name: String) -> void:
	step = PATTERN.find(name)
	_start_next()


func vulnerable() -> bool:
	return state == State.CLAW_RECOVER or state == State.VENT


func _player_ok() -> bool:
	return player != null and not player.dead and not player.falling


func _start_next() -> void:
	var p: String = PATTERN[step % PATTERN.size()]
	step += 1
	match p:
		"claw":
			dir = (player.global_position - global_position).normalized() if _player_ok() else Vector2.DOWN
			state = State.CLAW_AIM
			t = CLAW_AIM_TIME
		"sweep":
			state = State.SWEEP_AIM
			t = SWEEP_AIM_TIME
		"release":
			state = State.RELEASE_AIM
			t = RELEASE_AIM_TIME
			if dungeon:
				dungeon.secured = false
			release_started.emit()
	aim_started.emit(self)


func _in_claw(p: Vector2) -> bool:
	var d := p - global_position
	var along := d.dot(dir)
	return along > 0.0 and along < CLAW_LEN and absf(d.dot(dir.orthogonal())) < CLAW_WIDTH * 0.5 + 9.0


func _physics_process(delta: float) -> void:
	anim += delta
	flash = maxf(flash - delta, 0.0)
	if not alive:
		queue_redraw()
		return
	match state:
		State.SLEEP, State.STOPPED:
			pass
		State.IDLE:
			if _player_ok():
				position.x = move_toward(position.x, clampf(player.global_position.x, MIN_X, MAX_X), MOVE_SPEED * delta)
			t -= delta
			if t <= 0.0 and _player_ok():
				_start_next()
		State.CLAW_AIM:
			t -= delta
			if t <= 0.0:
				state = State.CLAW_STRIKE
				t = 0.18
				hit_done = false
		State.CLAW_STRIKE:
			t -= delta
			if not hit_done and _player_ok() and _in_claw(player.global_position):
				hit_done = player.take_damage(CLAW_DMG, global_position, self) or player.guard_t > 0.0
			if t <= 0.0:
				state = State.CLAW_RECOVER
				t = CLAW_RECOVER
		State.SWEEP_AIM:
			t -= delta
			if t <= 0.0:
				state = State.SWEEP_HIT
				t = 0.2
				hit_done = false
		State.SWEEP_HIT:
			t -= delta
			if not hit_done and _player_ok() and global_position.distance_to(player.global_position) < SWEEP_R + 9.0:
				hit_done = player.take_damage(SWEEP_DMG, global_position, self) or player.guard_t > 0.0
			if t <= 0.0:
				state = State.IDLE
				t = 0.6
		State.RELEASE_AIM:
			t -= delta
			if dungeon:
				dungeon.flood = clampf(1.0 - t / RELEASE_AIM_TIME, 0.0, 1.0) * 0.35
			if t <= 0.0:
				state = State.RELEASE_FLOOD
				t = FLOOD_TIME
				_flood_hit()
		State.RELEASE_FLOOD:
			t -= delta
			if dungeon:
				dungeon.flood = 1.0
			if t <= 0.0:
				state = State.VENT
				t = VENT_TIME
		State.VENT:
			t -= delta
			if dungeon:
				dungeon.flood = clampf(t / VENT_TIME, 0.0, 1.0)
			if t <= 0.0:
				state = State.IDLE
				t = IDLE_TIME
		State.CLAW_RECOVER:
			t -= delta
			if t <= 0.0:
				state = State.IDLE
				t = IDLE_TIME
	queue_redraw()


## 물이 차는 순간: 확보된 안전 지대 안이면 무사하다. 정비공은 확보하지 못하면 다친다.
func _flood_hit() -> void:
	var secured: bool = dungeon != null and dungeon.secured
	if _player_ok() and not (secured and dungeon.in_safe_zone(player.global_position)):
		player.take_damage(FLOOD_DMG, global_position, null)
	flooded.emit(secured)


func take_hit(amount: float, _from: Vector2) -> void:
	if not alive or state == State.SLEEP:
		return
	if vulnerable():
		amount *= 1.5
	hp -= amount
	flash = 0.12
	var ft := preload("res://scripts/float_text.gd").new()
	ft.text = str(roundi(amount))
	ft.color = Color("ffe08a") if vulnerable() else Color.WHITE
	ft.position = position + Vector2(0, -36)
	get_parent().add_child(ft)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		state = State.STOPPED
		remove_from_group("enemy")
		if dungeon:
			dungeon.flood = 0.0
			dungeon.boss_stopped = true
		defeated.emit(self)


func _draw() -> void:
	# 예고
	if alive and state == State.CLAW_AIM:
		var k := 1.0 - t / CLAW_AIM_TIME
		var perp := dir.orthogonal() * CLAW_WIDTH * 0.5
		var end := dir * CLAW_LEN
		draw_colored_polygon(PackedVector2Array([perp, end + perp, end - perp, -perp]), Color(0.85, 0.32, 0.29, 0.18))
		var fe := dir * CLAW_LEN * k
		draw_colored_polygon(PackedVector2Array([perp, fe + perp, fe - perp, -perp]), Color(1.0, 0.47, 0.37, 0.45))
		draw_polyline(PackedVector2Array([perp, end + perp, end - perp, -perp, perp]), Color(1.0, 0.47, 0.37, 0.9), 1.5)
	elif alive and state == State.SWEEP_AIM:
		var k2 := 1.0 - t / SWEEP_AIM_TIME
		draw_circle(Vector2.ZERO, SWEEP_R, Color(0.85, 0.32, 0.29, 0.14))
		draw_arc(Vector2.ZERO, SWEEP_R, 0, TAU, 48, Color(1.0, 0.47, 0.37, 0.9), 2.0)
		draw_arc(Vector2.ZERO, SWEEP_R * k2, 0, TAU, 48, Color(1.0, 0.47, 0.37, 0.6), 4.0)
	elif alive and state == State.RELEASE_AIM:
		var blink := 0.5 + 0.5 * sin(anim * 10.0)
		draw_string(GameState.world_font, Vector2(-60, -54), "물길 방출!", HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(0.6, 0.9, 1.0, 0.6 + 0.4 * blink))

	# 몸체: 녹슨 정비기와 두 집게
	var body := Color("8a6a4a") if state != State.STOPPED else Color("5a4a3a")
	if flash > 0.0:
		body = Color.WHITE
	elif vulnerable():
		body = Color("b05a3a")
	draw_set_transform(Vector2(0, 16), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-22, -18, 44, 34), body)
	draw_rect(Rect2(-22, -18, 44, 34), Color("3a2a1a"), false, 2.0)
	draw_circle(Vector2(0, -2), 7.0, Color("f2d28b") if state not in [State.STOPPED, State.SLEEP] else Color("4a4a4a"))
	var reach := 0.0
	if state == State.CLAW_STRIKE:
		reach = CLAW_LEN * (1.0 - t / 0.18)
	elif state == State.CLAW_RECOVER:
		reach = CLAW_LEN * 0.85
	var side := dir.orthogonal()
	for s in [-1.0, 1.0]:
		var base: Vector2 = side * 18.0 * s + Vector2(0, 6)
		var tip: Vector2 = base + dir * (16.0 + reach)
		draw_line(base, tip, Color("5a5f66"), 5.0)
		draw_line(tip, tip + dir.rotated(0.6 * float(s)) * 10.0, Color("3a3f46"), 4.0)
	# 덧씌운 계약 고리
	draw_arc(Vector2(0, 12), 6.0, 0, TAU, 12, Color("c8c8d0"), 2.0)
	if state == State.VENT:
		for i in 4:
			var y := -24.0 - fposmod(anim * 30.0 + i * 8.0, 30.0)
			draw_circle(Vector2(-10 + i * 7, y), 3.0, Color(0.85, 0.85, 0.85, 0.5))
	if state == State.STOPPED:
		return
	if state != State.SLEEP:
		draw_rect(Rect2(-30, -34, 60, 5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-30, -34, 60.0 * hp / max_hp, 5), Color("d9514b"))
