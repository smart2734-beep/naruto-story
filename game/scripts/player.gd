extends CharacterBody2D
## 검무사 견습생. 이동·회피·자동 기본 공격·사선베기·되받기, 도톰 신발의 추가 한 걸음.
## 수치는 기획서 2·3·5·6장의 초기 가설을 따른다 (결력 100, 행동 없을 때 초당 6 회복).

signal died
signal dodged
signal skill_used
signal fell
signal extra_step_used
signal guard_success
signal transform_done
signal transform_cancelled

const SPEED := 120.0
const DODGE_SPEED := 470.0
const DODGE_TIME := 0.2
const DODGE_CD := 0.6
const ATTACK_RANGE := 46.0
const ATTACK_CD := 0.55
const ATTACK_DMG := 10.0
const SKILL_NAME := "사선베기"
const SKILL_COST := 15.0
const SKILL_CD := 3.0
const SKILL_TIME := 0.18
const SKILL_SPEED := 520.0
const SKILL_DMG := 24.0
const SKILL_HIT_RADIUS := 34.0
const GUARD_NAME := "되받기"
const GUARD_COST := 12.0
const GUARD_CD := 3.0
const GUARD_TIME := 0.4
const COUNTER_DMG := 30.0
const GYEOL_REGEN := 6.0
const GYEOL_REGEN_DELAY := 1.0
## 도톰 신발 (기획서 6장): 이동속도 +5%, 회피 뒤 추가 한 걸음 — 결력 10, 8초 대기
const SHOE_SPEED_MULT := 1.05
const STEP_COST := 10.0
const STEP_CD := 8.0
const STEP_TIME := 0.13
const STEP_SPEED := 500.0
const MASK_NORMAL := 1 | 2
const MASK_AIRBORNE := 1

var world  # world.gd — 진흙·틈 판정
var move_input := Vector2.ZERO
var locked := false
var facing := Vector2.UP
var max_hp := 100.0
var hp := 100.0
var max_gyeol := 100.0
var gyeol := 100.0
var carrying := false
var dead := false
var falling := false
var shoe := false

var dodge_t := 0.0
var dodge_cd := 0.0
var dodge_dir := Vector2.ZERO
var step_t := 0.0
var step_cd := 0.0
var invuln := 0.0
var attack_cd := 0.0
var slash_t := 0.0
var slash_dir := Vector2.UP
var skill_t := 0.0
var skill_cd := 0.0
var skill_dir := Vector2.ZERO
var skill_side := 1.0
var skill_hit: Array = []
var guard_t := 0.0
var guard_cd := 0.0
var transform_t := 0.0
var transform_total := 0.0
var transform_fx := 0.0  ## 전투 밖 즉시 변신의 연출 시간 (조작은 막지 않음)
var since_action := 99.0
var hurt_flash := 0.0
var walk_t := 0.0
var fall_t := 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_mask = MASK_NORMAL
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	add_to_group("player")


func airborne() -> bool:
	return dodge_t > 0.0 or step_t > 0.0


func _physics_process(delta: float) -> void:
	var was_dodging := dodge_t > 0.0
	dodge_t = maxf(dodge_t - delta, 0.0)
	dodge_cd = maxf(dodge_cd - delta, 0.0)
	step_t = maxf(step_t - delta, 0.0)
	step_cd = maxf(step_cd - delta, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	attack_cd = maxf(attack_cd - delta, 0.0)
	slash_t = maxf(slash_t - delta, 0.0)
	skill_t = maxf(skill_t - delta, 0.0)
	skill_cd = maxf(skill_cd - delta, 0.0)
	guard_t = maxf(guard_t - delta, 0.0)
	guard_cd = maxf(guard_cd - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	fall_t = maxf(fall_t - delta, 0.0)
	transform_fx = maxf(transform_fx - delta, 0.0)

	if was_dodging and dodge_t <= 0.0:
		_try_extra_step()

	if transform_t > 0.0:
		transform_t = maxf(transform_t - delta, 0.0)
		if transform_t <= 0.0:
			transform_done.emit()

	collision_mask = MASK_AIRBORNE if airborne() else MASK_NORMAL

	if dead or falling:
		velocity = Vector2.ZERO
	elif dodge_t > 0.0:
		velocity = dodge_dir * DODGE_SPEED
	elif step_t > 0.0:
		velocity = dodge_dir * STEP_SPEED
	elif skill_t > 0.0:
		velocity = skill_dir * SKILL_SPEED
		_skill_hits()
	elif locked or guard_t > 0.0 or transform_t > 0.0:
		velocity = Vector2.ZERO
	else:
		var v := move_input.limit_length(1.0)
		velocity = v * SPEED * (SHOE_SPEED_MULT if shoe else 1.0)
		if v.length() > 0.2:
			facing = v.normalized()
			walk_t += delta * 10.0
		_auto_attack()
	move_and_slide()

	if not airborne() and world and world.is_pit(global_position):
		start_fall()

	since_action += delta
	if since_action > GYEOL_REGEN_DELAY:
		gyeol = minf(max_gyeol, gyeol + GYEOL_REGEN * delta)
	queue_redraw()


func start_fall() -> void:
	if dead or falling:
		return
	falling = true
	fall_t = 0.5
	fell.emit()


func try_dodge() -> bool:
	if dead or falling or locked or dodge_cd > 0.0 or airborne() or skill_t > 0.0:
		return false
	if transform_t > 0.0:
		transform_t = 0.0
		transform_cancelled.emit()
	guard_t = 0.0
	dodge_dir = move_input.normalized() if move_input.length() > 0.2 else facing
	dodge_t = DODGE_TIME
	dodge_cd = DODGE_CD + DODGE_TIME
	invuln = maxf(invuln, DODGE_TIME + 0.06)
	dodged.emit()
	return true


## 신발 상태에서 회피가 틈 위나 적 근처에서 끝나면 한 걸음 더 나간다.
func _try_extra_step() -> void:
	if not shoe or step_cd > 0.0 or gyeol < STEP_COST:
		return
	var over_pit: bool = world != null and world.is_pit(global_position)
	if not over_pit and _nearest_enemy(120.0) == null:
		return
	gyeol -= STEP_COST
	since_action = 0.0
	step_t = STEP_TIME
	step_cd = STEP_CD
	invuln = maxf(invuln, STEP_TIME + 0.05)
	extra_step_used.emit()


func can_use_skill() -> bool:
	return GameState.has_skill(SKILL_NAME) and gyeol >= SKILL_COST and skill_cd <= 0.0


func can_guard() -> bool:
	return GameState.has_skill(GUARD_NAME) and gyeol >= GUARD_COST and guard_cd <= 0.0


func _busy() -> bool:
	return dead or falling or locked or airborne() or skill_t > 0.0 or transform_t > 0.0


func try_skill() -> bool:
	if _busy() or not can_use_skill():
		return false
	gyeol -= SKILL_COST
	since_action = 0.0
	var target = _nearest_enemy(140.0)
	var base := facing
	if target:
		base = (target.global_position - global_position).normalized()
	skill_side = -skill_side
	skill_dir = base.rotated(deg_to_rad(20.0) * skill_side)
	skill_t = SKILL_TIME
	skill_cd = SKILL_CD
	skill_hit.clear()
	slash_t = 0.25
	slash_dir = skill_dir
	facing = skill_dir
	skill_used.emit()
	return true


## 되받기: 짧게 막는 자세. 그 사이에 맞으면 피해 없이 반격한다.
func try_guard() -> bool:
	if _busy() or not can_guard():
		return false
	gyeol -= GUARD_COST
	since_action = 0.0
	guard_t = GUARD_TIME
	guard_cd = GUARD_CD
	var target = _nearest_enemy(140.0)
	if target:
		facing = (target.global_position - global_position).normalized()
	return true


func start_transform(duration: float) -> void:
	transform_t = duration
	transform_total = duration


func take_damage(amount: float, from_pos: Vector2, attacker = null) -> bool:
	if dead or falling:
		return false
	if guard_t > 0.0:
		guard_t = 0.0
		invuln = maxf(invuln, 0.4)
		slash_dir = (from_pos - global_position).normalized()
		slash_t = 0.3
		if attacker != null and is_instance_valid(attacker) and attacker.alive:
			attacker.take_hit(COUNTER_DMG * GameState.weapon_multiplier(), global_position)
		guard_success.emit()
		return false
	if invuln > 0.0:
		return false
	if transform_t > 0.0:
		transform_t = 0.0
		transform_cancelled.emit()
	hp = maxf(hp - amount, 0.0)
	hurt_flash = 0.3
	invuln = 0.7
	var push := (global_position - from_pos).normalized() * 12.0
	move_and_collide(push)
	if hp <= 0.0:
		dead = true
		died.emit()
	return true


func respawn(at: Vector2, refill_gyeol := true) -> void:
	global_position = at
	hp = max_hp if dead else hp
	if refill_gyeol:
		gyeol = max_gyeol
	dead = false
	falling = false
	invuln = 1.0
	dodge_t = 0.0
	step_t = 0.0
	skill_t = 0.0
	guard_t = 0.0
	transform_t = 0.0
	velocity = Vector2.ZERO


func _nearest_enemy(max_dist: float):
	var best = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemy"):
		var d := global_position.distance_to(e.global_position)
		if e.alive and d <= best_d:
			best = e
			best_d = d
	return best


func _auto_attack() -> void:
	if attack_cd > 0.0:
		return
	var target = _nearest_enemy(ATTACK_RANGE)
	if target == null:
		return
	slash_dir = (target.global_position - global_position).normalized()
	facing = slash_dir
	slash_t = 0.15
	attack_cd = ATTACK_CD
	target.take_hit(ATTACK_DMG * GameState.weapon_multiplier(), global_position)


func _skill_hits() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.alive and not skill_hit.has(e) and global_position.distance_to(e.global_position) < SKILL_HIT_RADIUS:
			skill_hit.append(e)
			e.take_hit(SKILL_DMG * GameState.weapon_multiplier(), global_position)


func _draw() -> void:
	if falling:
		# 빠지는 중: 점점 작아진다
		var s := clampf(fall_t / 0.5, 0.1, 1.0)
		draw_circle(Vector2.ZERO, 8.0 * s, Color("2d3e5c"))
		draw_arc(Vector2.ZERO, 14.0 * (1.0 - s) + 6.0, 0, TAU, 16, Color(1, 1, 1, 0.5 * s), 1.5)
		return

	# 그림자
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if airborne() or skill_t > 0.0:
		var dir := dodge_dir if airborne() else skill_dir
		var trail := Color(0.55, 0.85, 1.0) if step_t <= 0.0 else Color(0.55, 0.95, 0.45)
		for i in range(1, 4):
			trail.a = 0.35 - i * 0.08
			draw_circle(-dir * 9.0 * i, 9.0 - i, trail)

	var visible_now := invuln <= 0.0 or airborne() or guard_t > 0.0 or int(invuln * 20.0) % 2 == 0
	var body := Color("2d3e5c")
	if hurt_flash > 0.0:
		body = Color("e05050")
	if visible_now:
		var bob := sin(walk_t) * 1.0 if velocity.length() > 1.0 else 0.0
		# 신발 (도톰 변신이면 이끼 무늬)
		var shoe_col := Color("6a8a40") if shoe else Color("3a2a20")
		draw_circle(Vector2(-4, 9), 3.0, shoe_col)
		draw_circle(Vector2(4, 9), 3.0, shoe_col)
		if shoe:
			draw_circle(Vector2(-4, 8), 1.2, Color("b0e070"))
			draw_circle(Vector2(4, 8), 1.2, Color("b0e070"))
		draw_circle(Vector2(0, 2 + bob), 8.0, body)
		draw_circle(Vector2(0, -7 + bob), 6.0, Color("f0d2b0"))
		# 머리띠(조합 표식 색) — 특정 작품의 이마 보호대처럼 보이지 않도록 천 끈으로 표현
		draw_line(Vector2(-6, -9 + bob), Vector2(6, -9 + bob), Color("7fd6c2"), 2.0)
		draw_line(Vector2(-6, -9 + bob), Vector2(-10, -6 + bob), Color("7fd6c2"), 1.5)
		var tip := facing * 13.0 + Vector2(0, 2)
		var side := facing.orthogonal() * 3.0
		draw_colored_polygon(PackedVector2Array([tip, facing * 8.0 + side + Vector2(0, 2), facing * 8.0 - side + Vector2(0, 2)]), Color("e8c070"))
		if carrying:
			draw_rect(Rect2(-6, -24 + bob, 12, 9), Color("9a6a3a"))
			draw_rect(Rect2(-6, -24 + bob, 12, 9), Color("5a3a1a"), false, 1.0)
			draw_line(Vector2(0, -24 + bob), Vector2(0, -15 + bob), Color("5a3a1a"), 1.0)

	if guard_t > 0.0:
		var a := facing.angle()
		draw_arc(Vector2.ZERO, 16.0, a - 1.2, a + 1.2, 14, Color(0.9, 0.95, 1.0, 0.9), 3.0)
	if transform_t > 0.0 and transform_total > 0.0:
		var p := 1.0 - transform_t / transform_total
		draw_arc(Vector2.ZERO, 18.0, -PI / 2.0, -PI / 2.0 + TAU * p, 24, Color("8fdc5a"), 2.5)

	if transform_fx > 0.0:
		# 발치에서 잎이 감겨 오르는 짧은 연출
		var k := 1.0 - transform_fx / 0.8
		for i in 6:
			var ang := k * TAU + i * TAU / 6.0
			draw_circle(Vector2(cos(ang) * 12.0, 8.0 - k * 14.0 + sin(ang) * 4.0), 2.0, Color(0.56, 0.86, 0.35, 1.0 - k))

	if slash_t > 0.0:
		var a := slash_dir.angle()
		var r := 22.0 if skill_t <= 0.0 and slash_t <= 0.15 else 28.0
		var col := Color(1, 1, 1, clampf(slash_t * 6.0, 0.0, 0.9))
		if skill_t > 0.0 or slash_t > 0.15:
			col = Color(0.5, 1.0, 0.9, clampf(slash_t * 5.0, 0.0, 0.95))
		draw_arc(Vector2.ZERO, r, a - 1.0, a + 1.0, 12, col, 3.0)
