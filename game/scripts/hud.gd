extends CanvasLayer
## 세로 화면 HUD와 터치 입력.
## 왼쪽 아래 이동 패드(누른 자리에 생김), 오른쪽 아래 회피·기술·상호작용 버튼.
## 튜토리얼 안내는 한 번에 한 동작만 보여준다 (기획서 10장).
## PC 테스트용 키: WASD/방향키 이동, Space 회피, Q 기술, E 상호작용·대사 넘기기.

signal interact_pressed

const JOY_R := 90.0
const TYPE_SPEED := 45.0
const TOAST_TIME := 1.7

var player  # player.gd
var objective_title := ""
var objective_text := ""
var target_world = null  ## 목표 위치(화면 밖이면 가장자리 화살표)
var interact_label := ""

var hint_text := ""
var hint_time := -1.0  ## < 0 이면 지울 때까지 유지
var toasts: Array = []  ## [text, life] — 한 번에 하나씩 차례로 보여준다

var dialogue: Array = []  ## [[speaker, text], ...]
var dialogue_index := 0
var dialogue_chars := 0.0
var dialogue_done: Callable

var fade := 0.0
var fade_text := ""

var joy_index := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var joy_vec := Vector2.ZERO
var pressed_flash: Dictionary = {}

var _canvas: Control


func _ready() -> void:
	layer = 10
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)


# ── 공개 API ─────────────────────────────────────────────

func set_objective(title: String, text: String, target = null) -> void:
	objective_title = title
	objective_text = text
	target_world = target


func show_hint(text: String, duration: float = -1.0) -> void:
	hint_text = text
	hint_time = duration


func clear_hint(text: String = "") -> void:
	if text == "" or hint_text == text:
		hint_text = ""


func toast(text: String) -> void:
	toasts.append([text, TOAST_TIME])


func start_dialogue(lines: Array, on_done: Callable = Callable()) -> void:
	dialogue = lines
	dialogue_index = 0
	dialogue_chars = 0.0
	dialogue_done = on_done
	joy_index = -1
	joy_vec = Vector2.ZERO


func dialogue_active() -> bool:
	return dialogue_index < dialogue.size()


## 테스트용: 남은 대사를 모두 넘긴다.
func skip_dialogue() -> void:
	while dialogue_active():
		dialogue_chars = 9999.0
		_advance_dialogue()


func show_fade(text: String) -> void:
	fade = 1.0
	fade_text = text


func hide_fade() -> void:
	fade = 0.0


# ── 레이아웃 ─────────────────────────────────────────────

func _size() -> Vector2:
	return _canvas.get_viewport_rect().size


func _dodge_c() -> Vector2:
	return Vector2(_size().x - 118, _size().y - 170)


func _skill_c() -> Vector2:
	return Vector2(_size().x - 268, _size().y - 112)


func _interact_c() -> Vector2:
	return Vector2(_size().x - 130, _size().y - 352)


func _skill_visible() -> bool:
	return GameState.has_skill("사선베기")


# ── 입력 ─────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if dialogue_active():
				_advance_dialogue()
				return
			if fade > 0.0 or player == null:
				return
			if e.position.distance_to(_dodge_c()) < 82.0:
				_flash("dodge")
				player.try_dodge()
			elif _skill_visible() and e.position.distance_to(_skill_c()) < 64.0:
				_flash("skill")
				player.try_skill()
			elif interact_label != "" and e.position.distance_to(_interact_c()) < 66.0:
				_flash("interact")
				interact_pressed.emit()
			elif joy_index == -1 and e.position.x < _size().x * 0.6 and e.position.y > _size().y * 0.4:
				joy_index = e.index
				joy_origin = e.position
				joy_pos = e.position
				joy_vec = Vector2.ZERO
		elif e.index == joy_index:
			joy_index = -1
			joy_vec = Vector2.ZERO
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == joy_index:
			joy_pos = d.position
			var off := joy_pos - joy_origin
			if off.length() > JOY_R:
				# 손가락이 멀리 가면 패드가 따라온다.
				joy_origin = joy_pos - off.limit_length(JOY_R)
				off = off.limit_length(JOY_R)
			joy_vec = off / JOY_R
			if joy_vec.length() < 0.15:
				joy_vec = Vector2.ZERO
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if dialogue_active():
			if k.physical_keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
				_advance_dialogue()
			return
		if player == null or fade > 0.0:
			return
		match k.physical_keycode:
			KEY_SPACE:
				player.try_dodge()
			KEY_Q:
				player.try_skill()
			KEY_E, KEY_ENTER:
				if interact_label != "":
					interact_pressed.emit()


func _flash(id: String) -> void:
	pressed_flash[id] = 0.15


func _keyboard_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	return v.normalized()


func _advance_dialogue() -> void:
	if not dialogue_active():
		return
	var line_len: int = String(dialogue[dialogue_index][1]).length()
	if dialogue_chars < line_len:
		dialogue_chars = line_len
		return
	dialogue_index += 1
	dialogue_chars = 0.0
	if not dialogue_active() and dialogue_done.is_valid():
		var cb := dialogue_done
		dialogue_done = Callable()
		cb.call()


func _process(delta: float) -> void:
	if player:
		var kb := _keyboard_vector()
		if dialogue_active() or fade > 0.0:
			player.move_input = Vector2.ZERO
		elif joy_index != -1:
			player.move_input = joy_vec
		else:
			player.move_input = kb
	if dialogue_active():
		dialogue_chars += TYPE_SPEED * delta
	if hint_time > 0.0:
		hint_time -= delta
		if hint_time <= 0.0:
			hint_text = ""
	if not toasts.is_empty():
		toasts[0][1] -= delta
		if toasts[0][1] <= 0.0:
			toasts.pop_front()
	for k in pressed_flash.keys():
		pressed_flash[k] -= delta
		if pressed_flash[k] <= 0.0:
			pressed_flash.erase(k)
	_canvas.queue_redraw()


# ── 그리기 ───────────────────────────────────────────────

func _panel(rect: Rect2, bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 14) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(3)
	_canvas.draw_style_box(sb, rect)


func _text(pos: Vector2, text: String, size: int, color: Color = Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_canvas.draw_string(GameState.ui_font, pos, text, align, width, size, color)


func _bar(rect: Rect2, ratio: float, col: Color, label: String) -> void:
	_panel(rect, Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 8)
	if ratio > 0.0:
		_panel(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0.0, 1.0), rect.size.y)), col, Color(0, 0, 0, 0), 8)
	_text(rect.position + Vector2(12, rect.size.y - 8), label, 20)


func _on_draw() -> void:
	var s := _size()
	if player:
		_draw_status(s)
	_draw_objective(s)
	_draw_target_arrow(s)
	if dialogue_active():
		_draw_dialogue(s)
	else:
		_draw_controls(s)
	_draw_hint(s)
	_draw_toasts(s)
	if fade > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.75 * fade))
		_text(Vector2(40, s.y * 0.45), fade_text, 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s.x - 80)


func _draw_status(s: Vector2) -> void:
	_panel(Rect2(16, 16, s.x - 32, 112), Color(0.08, 0.1, 0.14, 0.78))
	_text(Vector2(32, 56), "Lv.%d" % GameState.level, 30, Color("e8c070"))
	_text(Vector2(130, 56), GameState.weapon, 22, Color(0.85, 0.85, 0.85))
	_text(Vector2(s.x - 232, 56), "재화 %d" % GameState.currency, 24, Color("ffe08a"), HORIZONTAL_ALIGNMENT_RIGHT, 200)
	var bw := (s.x - 80) * 0.5
	_bar(Rect2(32, 74, bw, 36), player.hp / player.max_hp, Color("d04848"), "체력 %d" % roundi(player.hp))
	_bar(Rect2(48 + bw, 74, bw, 36), player.gyeol / player.max_gyeol, Color("38a89a"), "결력 %d" % roundi(player.gyeol))


func _draw_objective(s: Vector2) -> void:
	if objective_title == "":
		return
	_panel(Rect2(16, 140, s.x - 32, 92), Color(0.08, 0.1, 0.14, 0.62))
	_text(Vector2(32, 176), objective_title, 24, Color("7fd6c2"))
	_text(Vector2(32, 214), "▸ " + objective_text, 24)


func _draw_target_arrow(s: Vector2) -> void:
	if target_world == null or dialogue_active():
		return
	var sp: Vector2 = _canvas.get_viewport().get_canvas_transform() * (target_world as Vector2)
	var margin := Rect2(40, 260, s.x - 80, s.y - 560)
	if margin.has_point(sp):
		return
	var center := s * 0.5
	var dir := (sp - center).normalized()
	var p := center
	# 화면 안쪽 사각형 가장자리까지 이동
	for i in 400:
		var np := p + dir * 4.0
		if not margin.has_point(np):
			break
		p = np
	var side := dir.orthogonal()
	_canvas.draw_colored_polygon(PackedVector2Array([p + dir * 26.0, p - dir * 10.0 + side * 18.0, p - dir * 10.0 - side * 18.0]), Color(1.0, 0.85, 0.3, 0.9))


func _round_button(c: Vector2, r: float, label: String, col: Color, id: String, cd_ratio := 0.0, sub := "", enabled := true) -> void:
	var bg := col
	if not enabled:
		bg = Color(0.3, 0.3, 0.3, 0.6)
	if pressed_flash.has(id):
		bg = bg.lightened(0.35)
	_canvas.draw_circle(c, r, bg)
	_canvas.draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
	if cd_ratio > 0.0:
		var pts := PackedVector2Array([c])
		var steps := 32
		for i in steps + 1:
			var a := -PI / 2.0 + TAU * cd_ratio * i / steps
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		_canvas.draw_colored_polygon(pts, Color(0, 0, 0, 0.5))
	var fs := 28 if label.length() <= 2 else 22
	_text(Vector2(c.x - r, c.y + fs * 0.35), label, fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	if sub != "":
		_text(Vector2(c.x - r, c.y + r - 12), sub, 18, Color(0.85, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)


func _draw_controls(s: Vector2) -> void:
	if player == null or fade > 0.0:
		return
	# 이동 패드
	var base := joy_origin if joy_index != -1 else Vector2(150, s.y - 190)
	var knob := base + joy_vec * JOY_R
	_canvas.draw_circle(base, JOY_R, Color(1, 1, 1, 0.12 if joy_index == -1 else 0.2))
	_canvas.draw_arc(base, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	_canvas.draw_circle(knob, 40.0, Color(1, 1, 1, 0.35 if joy_index == -1 else 0.6))

	var dodge_ratio: float = player.dodge_cd / (player.DODGE_CD + player.DODGE_TIME)
	_round_button(_dodge_c(), 72.0, "회피", Color(0.2, 0.45, 0.75, 0.85), "dodge", dodge_ratio)
	if _skill_visible():
		var ratio: float = player.skill_cd / player.SKILL_CD
		_round_button(_skill_c(), 56.0, "사선베기", Color(0.15, 0.55, 0.5, 0.85), "skill", ratio, "결력 15", player.gyeol >= player.SKILL_COST)
	if interact_label != "":
		_round_button(_interact_c(), 58.0, interact_label, Color(0.8, 0.6, 0.15, 0.9), "interact")


func _draw_dialogue(s: Vector2) -> void:
	var line: Array = dialogue[dialogue_index]
	var rect := Rect2(16, s.y - 400, s.x - 32, 280)
	_panel(rect, Color(0.07, 0.08, 0.11, 0.92), Color("7fd6c2"))
	_panel(Rect2(rect.position + Vector2(24, -26), Vector2(180, 52)), Color("2d3e5c"), Color("7fd6c2"), 12)
	_text(rect.position + Vector2(24, 10), String(line[0]), 26, Color("e8c070"), HORIZONTAL_ALIGNMENT_CENTER, 180)
	var full := String(line[1])
	var shown := full.substr(0, int(dialogue_chars))
	_canvas.draw_multiline_string(GameState.ui_font, rect.position + Vector2(32, 76), shown, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 64, 28, 5, Color.WHITE)
	if dialogue_chars >= full.length():
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		_text(Vector2(rect.end.x - 260, rect.end.y - 22), "터치해서 계속 ▼", 20, Color(1, 1, 1, 0.5 + 0.4 * blink), HORIZONTAL_ALIGNMENT_RIGHT, 236)


func _draw_hint(s: Vector2) -> void:
	if hint_text == "" or dialogue_active():
		return
	var rect := Rect2(40, 252, s.x - 80, 84)
	_panel(rect, Color(0.1, 0.08, 0.02, 0.85), Color("ffcc33"))
	_canvas.draw_multiline_string(GameState.ui_font, rect.position + Vector2(20, 36), hint_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 40, 24, 2, Color("fff2c0"))


func _draw_toasts(s: Vector2) -> void:
	if toasts.is_empty():
		return
	var tst: Array = toasts[0]
	var life := float(tst[1])
	var a := clampf(minf(life / 0.3, (TOAST_TIME - life) / 0.15), 0.0, 1.0)
	var rect := Rect2(s.x * 0.5 - 230, 352 - (1.0 - a) * 12.0, 460, 54)
	_panel(rect, Color(0.05, 0.2, 0.18, 0.9 * a), Color(0.5, 0.85, 0.76, a))
	_text(rect.position + Vector2(0, 37), String(tst[0]), 25, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	if toasts.size() > 1:
		_text(rect.position + Vector2(0, 76), "+%d" % (toasts.size() - 1), 18, Color(1, 1, 1, 0.6 * a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)