extends Node2D
## 영물 줄비. 얇은 비늘이 접힌 긴 몸과 두 앞발. 장난을 좋아하지만 남의 도구를 망가뜨리는 건 싫어한다 (기획서 6장).
## 계약 전: 방앗간 앞에서 고리 쪽을 기웃거린다.
## 동행: 걸린 연결쇠를 찾아 방향을 표시하고, 전투에서는 4초마다 가까운 적에게 작은 균형 손상.
## 장비: 검의 겹날(이 노드는 숨김). 효과는 player.gd의 blade.

signal marked

enum State { WILD, COMPANION, MARKING, EQUIPPED, RESTING }

const CHIP_INTERVAL := 4.0
const CHIP_RANGE := 110.0
const CHIP_DMG := 3.0

var state: State = State.WILD
var player  # player.gd
var home := Vector2.ZERO
var mark_target := Vector2.ZERO
var t := 0.0
var anim := 0.0
var alert_t := 0.0
var chip_t := CHIP_INTERVAL
var dart_t := 0.0
var dart_to := Vector2.ZERO
var face := Vector2.LEFT


func _ready() -> void:
	home = position


func _move_to(target: Vector2, speed: float, delta: float) -> bool:
	var d := target - position
	if d.length() > 0.5:
		face = d.normalized()
	position = position.move_toward(target, speed * delta)
	return position.distance_to(target) < 1.0


func _process(delta: float) -> void:
	anim += delta
	alert_t = maxf(alert_t - delta, 0.0)
	dart_t = maxf(dart_t - delta, 0.0)
	match state:
		State.WILD:
			position = home + Vector2(sin(anim * 1.5) * 10.0, 0)
			face = Vector2(cos(anim * 1.5), 0).normalized() if absf(cos(anim * 1.5)) > 0.1 else face
		State.COMPANION:
			var target: Vector2 = player.position - player.facing * 22.0 + Vector2(-14, 6)
			if position.distance_to(target) > 260.0:
				position = target
			var sp := maxf(player.velocity.length() * 1.15, 50.0)
			if dart_t > 0.0:
				_move_to(dart_to, 260.0, delta)
			elif position.distance_to(target) > 6.0:
				_move_to(target, sp, delta)
			_combat_chip(delta)
		State.MARKING:
			if _move_to(mark_target, 150.0, delta):
				t -= delta
				if t <= 0.0:
					state = State.COMPANION
					marked.emit()
		_:
			pass
	visible = state != State.EQUIPPED and state != State.RESTING
	queue_redraw()


## 동행 전투 보조: 가까운 적에게 짧게 달려들어 균형을 흔든다.
func _combat_chip(delta: float) -> void:
	chip_t -= delta
	if chip_t > 0.0:
		return
	chip_t = CHIP_INTERVAL
	var best = null
	var best_d := CHIP_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		var d := position.distance_to(e.position)
		if e.alive and d < best_d:
			best = e
			best_d = d
	if best != null:
		dart_to = best.position
		dart_t = 0.3
		alert_t = 0.4
		best.take_hit(CHIP_DMG, position)


func become_companion() -> void:
	if state == State.EQUIPPED or state == State.RESTING or state == State.WILD:
		position = player.position + Vector2(-14, 6) if player else position
	state = State.COMPANION
	chip_t = CHIP_INTERVAL


func equip() -> void:
	state = State.EQUIPPED


func rest() -> void:
	state = State.RESTING


func run_mark(target: Vector2) -> void:
	mark_target = target
	t = 0.7
	alert_t = 0.8
	state = State.MARKING


func alert() -> void:
	alert_t = 0.8


func _draw() -> void:
	draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.6, 0.4))
	draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var dir := Vector2(1, 0) if face.x >= 0.0 else Vector2(-1, 0)
	# 긴 몸: 접힌 비늘 마디
	for i in 6:
		var p := -dir * (i * 3.6) + Vector2(0, sin(anim * 8.0 + i * 0.9) * 1.6 - 2.0)
		draw_circle(p, 4.2 - i * 0.35, Color("7aa8b0"))
		draw_arc(p, 4.2 - i * 0.35, -PI * 0.9, -PI * 0.1, 6, Color("5fc5c9"), 1.0)
	var head := dir * 5.0 + Vector2(0, -3)
	draw_circle(head, 4.5, Color("8ab8c0"))
	draw_circle(head + dir * 2.0 + Vector2(0, -1), 1.2, Color("102028"))
	# 두 앞발
	draw_line(dir * 2.0 + Vector2(0, 1), dir * 3.0 + Vector2(0, 5), Color("4a7880"), 1.5)
	draw_line(dir * 4.5 + Vector2(0, 1), dir * 5.5 + Vector2(0, 5), Color("4a7880"), 1.5)
	if alert_t > 0.0:
		draw_string(GameState.world_font, Vector2(-10, -14), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color("5fc5c9"))
	if state == State.WILD:
		var f := GameState.world_font
		draw_string_outline(f, Vector2(-30, -14), "줄비", HORIZONTAL_ALIGNMENT_CENTER, 60, 7, 3, Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(-30, -14), "줄비", HORIZONTAL_ALIGNMENT_CENTER, 60, 7, Color("c0e8f0"))
