extends Node2D
## 영물 도톰. 이끼색 털과 여섯 개의 작은 발. 겁이 많지만 길 기억력이 좋다 (기획서 6장).
## 계약 전: 둥지 곁. 뛰어서 다가오면 놀라 숨고, 가까이에서 멈춰 기다리면 먼저 다가온다.
## 계약 후: 동행(따라다니며 숨은 발판 표시) 또는 장비(신발, 이 노드는 숨김).

signal startled
signal trusted
signal arrived
signal marked

enum State { NEST, HIDE, APPROACH, WAIT, LEAD, COMPANION, MARKING, EQUIPPED, RESTING }

const STARTLE_DIST := 70.0
const STARTLE_SPEED := 30.0
const CALM_DIST := 130.0
const CALM_TIME := 1.2
const HIDE_TIME := 2.5
const LEAD_SPEED := 55.0
const LEAD_WAIT_DIST := 110.0

var state: State = State.NEST
var player  # player.gd
var nest_pos := Vector2.ZERO
var hide_pos := Vector2.ZERO
var calm_enabled := false
var has_nest := false
var nest_at_home := true
var lead_path: Array[Vector2] = []
var mark_target := Vector2.ZERO
var t := 0.0
var still_t := 0.0
var anim := 0.0
var alert_t := 0.0
var face := Vector2.LEFT


func _ready() -> void:
	nest_pos = position
	hide_pos = position + Vector2(50, -40)


func _player_speed() -> float:
	return player.velocity.length() if player else 0.0


func _move_to(target: Vector2, speed: float, delta: float) -> bool:
	var d := target - position
	if d.length() > 0.5:
		face = d.normalized()
	position = position.move_toward(target, speed * delta)
	return position.distance_to(target) < 1.0


func _process(delta: float) -> void:
	anim += delta
	alert_t = maxf(alert_t - delta, 0.0)
	var dist: float = position.distance_to(player.position) if player else INF
	match state:
		State.NEST:
			_move_to(nest_pos + Vector2(-18, 0), 30.0, delta)
			if calm_enabled and player:
				if dist < STARTLE_DIST and _player_speed() > STARTLE_SPEED:
					_startle()
				elif dist < CALM_DIST and _player_speed() < 5.0:
					still_t += delta
					if still_t >= CALM_TIME:
						state = State.APPROACH
				else:
					still_t = 0.0
		State.HIDE:
			_move_to(hide_pos, 160.0, delta)
			t -= delta
			if t <= 0.0:
				state = State.NEST
				still_t = 0.0
		State.APPROACH:
			if dist < 50.0 and _player_speed() > STARTLE_SPEED:
				_startle()
			elif dist > 28.0:
				_move_to(player.position, 40.0, delta)
			else:
				state = State.WAIT
				trusted.emit()
		State.WAIT:
			if player:
				face = (player.position - position).normalized()
		State.LEAD:
			if lead_path.is_empty():
				state = State.WAIT
				arrived.emit()
			elif dist > LEAD_WAIT_DIST:
				face = (player.position - position).normalized()  # 돌아보며 기다린다
			elif _move_to(lead_path[0], LEAD_SPEED, delta):
				lead_path.pop_front()
		State.COMPANION:
			var target: Vector2 = player.position - player.facing * 22.0 + Vector2(14, 6)
			if position.distance_to(target) > 260.0:
				position = target
			var sp := maxf(player.velocity.length() * 1.15, 50.0)
			if position.distance_to(target) > 6.0:
				_move_to(target, sp, delta)
		State.MARKING:
			if _move_to(mark_target, 150.0, delta):
				t -= delta
				if t <= 0.0:
					state = State.COMPANION
					marked.emit()
		State.EQUIPPED, State.RESTING:
			pass
	visible = state != State.EQUIPPED and state != State.RESTING
	queue_redraw()


func _startle() -> void:
	state = State.HIDE
	t = HIDE_TIME
	still_t = 0.0
	alert_t = 0.6
	startled.emit()


func start_lead(path: Array[Vector2]) -> void:
	lead_path = path.duplicate()
	has_nest = true
	nest_at_home = false
	state = State.LEAD


func become_companion() -> void:
	has_nest = false
	calm_enabled = false
	if (state == State.EQUIPPED or state == State.RESTING) and player:
		position = player.position + Vector2(14, 6)
	state = State.COMPANION


## 활성 칸에서 빠져 숙소에서 쉰다 (전투 보너스 없음).
func rest() -> void:
	state = State.RESTING


func equip() -> void:
	state = State.EQUIPPED


func run_mark(target: Vector2) -> void:
	mark_target = target
	t = 0.8
	alert_t = 0.8
	state = State.MARKING


func alert() -> void:
	alert_t = 0.8


func _draw() -> void:
	var f := GameState.world_font
	if nest_at_home:
		var np := nest_pos - position
		draw_set_transform(np + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, 12.0, Color("7a5a30"))
		draw_circle(Vector2.ZERO, 7.0, Color("5a4020"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(np + Vector2(-12, 2), np + Vector2(12, 6), Color("9a7a48"), 1.5)
	if state == State.HIDE:
		# 갈대 사이로 귀만 보인다
		draw_circle(Vector2(-4, -2), 3.0, Color("6a8a40"))
		draw_circle(Vector2(4, -2), 3.0, Color("6a8a40"))
		if alert_t > 0.0:
			draw_string(f, Vector2(-10, -12), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color("ffcc33"))
		return
	var hop := absf(sin(anim * 10.0)) * 2.0 if state in [State.LEAD, State.APPROACH, State.MARKING, State.COMPANION] else 0.0
	draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 여섯 발
	for i in 3:
		var x := -5.0 + i * 5.0
		var step := sin(anim * 14.0 + i * 2.0) * 1.2 if hop > 0.0 else 0.0
		draw_circle(Vector2(x, 5 + step), 1.6, Color("4a6030"))
		draw_circle(Vector2(x + 1.5, 6 - step), 1.6, Color("4a6030"))
	var o := Vector2(0, -hop)
	draw_circle(o, 7.5, Color("6a8a40"))
	draw_circle(o + Vector2(0, 2), 5.0, Color("8aa858"))
	# 귀와 눈
	draw_circle(o + Vector2(-5, -6), 2.5, Color("5a7a34"))
	draw_circle(o + Vector2(5, -6), 2.5, Color("5a7a34"))
	var eye := face * 2.5
	draw_circle(o + Vector2(-2.5, -1) + eye, 1.4, Color("1a1a10"))
	draw_circle(o + Vector2(2.5, -1) + eye, 1.4, Color("1a1a10"))
	if has_nest:
		draw_set_transform(o + Vector2(0, -9), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 7.0, Color("8a6a3a"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(o + Vector2(-7, -10), o + Vector2(7, -8), Color("5a4020"), 1.0)
	if alert_t > 0.0:
		draw_string(f, Vector2(-10, -14 - hop), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color("ffcc33"))
	if state == State.NEST or state == State.WAIT or state == State.APPROACH:
		draw_string_outline(f, Vector2(-30, -16), "도톰", HORIZONTAL_ALIGNMENT_CENTER, 60, 7, 3, Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(-30, -16), "도톰", HORIZONTAL_ALIGNMENT_CENTER, 60, 7, Color("d8f0b0"))
