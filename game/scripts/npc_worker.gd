extends "res://scripts/interactable.gd"
## Q5의 고립된 정비공. 구조하면 플레이어를 따라오고, 안전 지대에 데려가면 그 자리에서 기다린다.
## 체력이 0이 되면 실패 — 현재 방의 체크포인트에서 다시 (기획서 Q5 실패 조건).

signal reached_wait_spot
signal downed

enum WState { STRANDED, FOLLOW, WAIT, DOWN }

const SPEED := 108.0
const KEEP := 34.0

var wstate: WState = WState.STRANDED
var max_hp := 60.0
var hp := 60.0
var dungeon  # dungeon.gd
var player  # player.gd
var wait_spot := Vector2.ZERO
var paused := false
var hurt_t := 0.0
var _entry_i := 0


func _process(delta: float) -> void:
	t += delta
	hurt_t = maxf(hurt_t - delta, 0.0)
	if not paused and wstate == WState.FOLLOW and player:
		var target := _path_target()
		# 플레이어가 안전 지대에 들어가면 정비공은 발판 입구를 거쳐 대기 자리로 간다.
		if wait_spot != Vector2.ZERO and dungeon.room_of(position) == 3 and dungeon.in_safe_zone(player.position):
			target = _entry_target()
		if target != player.position or position.distance_to(target) > KEEP:
			position = position.move_toward(target, SPEED * delta)
		if wait_spot != Vector2.ZERO and position.distance_to(wait_spot) < 46.0:
			wstate = WState.WAIT
			position = wait_spot
			reached_wait_spot.emit()
	queue_redraw()


## 다른 방에 있으면 먼저 문 가운데로 간다 (벽을 뚫고 가지 않게).
func _path_target() -> Vector2:
	for wy in [dungeon.WALL_12, dungeon.WALL_23]:
		if (position.y - wy) * (player.position.y - wy) < 0.0:
			var my_side := 1.0 if position.y > wy else -1.0
			var near_door := Vector2(1440.0, wy + my_side * 16.0)
			if absf(position.x - 1440.0) > 4.0:
				return near_door
			return Vector2(1440.0, wy - my_side * 16.0)
	return player.position

## 발판 밖이면 왼쪽 아래 입구 경유점을 차례로 지나고, 발판 안(또는 난간이 없는 위쪽)이면 대기 자리로 간다.
func _entry_target() -> Vector2:
	var zone: Rect2 = dungeon.SAFE_ZONE
	if dungeon.in_safe_zone(position) or position.x >= zone.position.x:
		return wait_spot
	var wp: Vector2 = dungeon.SAFE_ENTRY[_entry_i]
	if position.distance_to(wp) < 4.0 and _entry_i < dungeon.SAFE_ENTRY.size() - 1:
		_entry_i += 1
	return dungeon.SAFE_ENTRY[_entry_i]

func hurt(amount: float) -> void:
	if wstate == WState.DOWN:
		return
	hp = maxf(hp - amount, 0.0)
	hurt_t = 0.4
	if hp <= 0.0:
		wstate = WState.DOWN
		downed.emit()


func reset_at(p: Vector2, st: WState) -> void:
	_entry_i = 0
	position = p
	hp = max_hp
	wstate = st


func _draw() -> void:
	super._draw()
	if wstate == WState.STRANDED:
		var b := sin(t * 4.0) * 2.0
		draw_string(GameState.world_font, Vector2(-40, -34 + b), "도와줘요!", HORIZONTAL_ALIGNMENT_CENTER, 80, 8, Color("f2d28b"))
	if wstate == WState.FOLLOW or wstate == WState.WAIT:
		var tag := "따라오는 중" if wstate == WState.FOLLOW else "대기 중"
		draw_string_outline(GameState.world_font, Vector2(-40, -34), tag, HORIZONTAL_ALIGNMENT_CENTER, 80, 7, 3, Color(0, 0, 0, 0.6))
		draw_string(GameState.world_font, Vector2(-40, -34), tag, HORIZONTAL_ALIGNMENT_CENTER, 80, 7, Color("9be7a0"))
	if wstate != WState.STRANDED:
		draw_rect(Rect2(-12, -30, 24, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-12, -30, 24.0 * hp / max_hp, 3), Color("9be7a0") if hurt_t <= 0.0 else Color("ff795f"))
	if wstate == WState.DOWN:
		draw_line(Vector2(-6, -6), Vector2(6, 6), Color("d9514b"), 2.0)
		draw_line(Vector2(6, -6), Vector2(-6, 6), Color("d9514b"), 2.0)
