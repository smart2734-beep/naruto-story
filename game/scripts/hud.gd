extends CanvasLayer
## 세로 화면 HUD와 터치 입력. 배치는 아트·UI 명세 6장을 따른다.
##   상단(약 160px): 작은 초상화·체력·결력·재화 / 한 줄 목표(누르면 펼침)
##   안내: 한 번에 한 행동, 상단 아래의 작은 띠. 완료하면 사라진다.
##   하단: 왼쪽 이동 패드, 오른쪽 회피·기술·상호작용, 아래 가운데 영물 초상화.
## PC 테스트용 키: WASD/방향키 이동, Space 회피, Q 사선베기, F 되받기,
##   R 영물 동행↔장비, T 활성 영물 교체, E 상호작용·대사 넘기기, Tab 정보 펼치기, Esc 닫기.

signal interact_pressed
signal portrait_pressed
signal portrait_long_pressed
signal craft_picked(id: String)

const JOY_R := 90.0
const TYPE_SPEED := 45.0
const TOAST_TIME := 1.7
const LONG_PRESS := 0.45
const TOP_H := 160.0  ## 상시 정보 높이 (명세: 180px 이내)
const C_PANEL := Color("202833")
const C_PANEL_DEEP := Color("14202b")
const C_TEXT := Color("f2ead6")
const C_GOLD := Color("d2ad62")
const C_GOLD_LIGHT := Color("f2d28b")
const C_GYEOL := Color("5fc5c9")
const C_DANGER := Color("d9514b")

var player  # player.gd
var objective_title := ""
var objective_text := ""
var target_world = null  ## 목표 위치(화면 밖이면 가장자리 화살표)
var interact_label := ""
var spirit_name := ""  ## 활성 영물 이름. "" 이면 초상화를 숨긴다 (계약 전)
var spirit_form := ""  ## "동행", "신발", "검"
var spirit_cd := 0.0  ## 전환 대기 비율 0~1
var spirit_can_swap := false
var spirit_status := ""  ## 초상화 아래 상태 문구: 한 걸음 준비 / N초 / 결력 부족, 동행 효과 등

var hint_text := ""
var hint_time := -1.0  ## < 0 이면 지울 때까지 유지
var toasts: Array = []  ## [text, life] — 한 번에 하나씩 차례로 보여준다
var info_open := false
var info_time := 0.0

var dialogue: Array = []  ## [[speaker, text], ...]
var dialogue_index := 0
var dialogue_chars := 0.0
var dialogue_done: Callable

var choice_title := ""
var choice_options: Array = []  ## [[제목, 설명], ...]
var choice_cb: Callable
var choice_note := ""
var end_lines: Array = []  ## 시제품 끝 카드 (비어 있으면 숨김)

var craft_title := ""
var craft_rows: Array = []  ## [{id, title, desc, cost: [[이름, 보유, 필요]], button, can}]

var fade := 0.0
var fade_text := ""

var joy_index := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var joy_vec := Vector2.ZERO
var forced_move = null  ## 자동 점검용 이동 입력 (Vector2 또는 null)
var pressed_flash: Dictionary = {}
var _portrait_index := -1
var _portrait_held := 0.0
var _portrait_long_sent := false

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
	info_open = false


func dialogue_active() -> bool:
	return dialogue_index < dialogue.size()


## 테스트용: 남은 대사를 모두 넘긴다.
func skip_dialogue() -> void:
	while dialogue_active():
		dialogue_chars = 9999.0
		_advance_dialogue()


func open_craft(title: String, rows: Array) -> void:
	craft_title = title
	craft_rows = rows
	joy_index = -1
	joy_vec = Vector2.ZERO
	info_open = false


func close_craft() -> void:
	craft_rows = []


func craft_open() -> bool:
	return not craft_rows.is_empty()


## 이야기 선택지. 고르면 cb.call(인덱스).
func start_choice(title: String, options: Array, cb: Callable, note: String = "") -> void:
	choice_title = title
	choice_note = note
	choice_options = options
	choice_cb = cb
	joy_index = -1
	joy_vec = Vector2.ZERO
	info_open = false


func choice_active() -> bool:
	return not choice_options.is_empty()


func pick_choice(i: int) -> void:
	if i < 0 or i >= choice_options.size():
		return
	var cb := choice_cb
	choice_options = []
	choice_cb = Callable()
	if cb.is_valid():
		cb.call(i)


func show_end(lines: Array) -> void:
	end_lines = lines


func _choice_rect(i: int) -> Rect2:
	var s := _size()
	var top := s.y * 0.5 - choice_options.size() * 70.0
	return Rect2(40, top + 70 + i * 140, s.x - 80, 120)


func show_fade(text: String) -> void:
	fade = 1.0
	fade_text = text


func hide_fade() -> void:
	fade = 0.0


func busy() -> bool:
	return dialogue_active() or craft_open() or choice_active() or not end_lines.is_empty() or fade > 0.0


# ── 레이아웃 ─────────────────────────────────────────────

func _size() -> Vector2:
	return _canvas.get_viewport_rect().size


func _quest_rect() -> Rect2:
	return Rect2(12, 104, _size().x - 24, 52)


func _dodge_c() -> Vector2:
	return Vector2(_size().x - 118, _size().y - 170)


func _skill_c() -> Vector2:
	return Vector2(_size().x - 268, _size().y - 112)


func _guard_c() -> Vector2:
	return Vector2(_size().x - 252, _size().y - 270)


func _interact_c() -> Vector2:
	return Vector2(_size().x - 130, _size().y - 352)


## 명세 6장의 영물 칸 가설: 720×1280 기준 (296, 1020)
func _portrait_c() -> Vector2:
	return Vector2(296, _size().y - 260)


func _skill_visible() -> bool:
	return GameState.has_skill("사선베기")


func _guard_visible() -> bool:
	return GameState.has_skill("되받기")


func _craft_panel_rect() -> Rect2:
	var s := _size()
	var h := 120.0 + craft_rows.size() * 168.0
	return Rect2(20, maxf(TOP_H + 20.0, s.y * 0.5 - h * 0.5 - 80.0), s.x - 40, h)


func _craft_button_rect(i: int) -> Rect2:
	var pr := _craft_panel_rect()
	return Rect2(pr.end.x - 172, pr.position.y + 96 + i * 168 + 44, 148, 96)


func _craft_close_c() -> Vector2:
	var pr := _craft_panel_rect()
	return Vector2(pr.end.x - 44, pr.position.y + 44)


# ── 입력 ─────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_touch_down(e)
		else:
			if e.index == joy_index:
				joy_index = -1
				joy_vec = Vector2.ZERO
			if e.index == _portrait_index:
				_portrait_index = -1
				if not _portrait_long_sent:
					portrait_pressed.emit()
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
		_key(event as InputEventKey)


func _touch_down(e: InputEventScreenTouch) -> void:
	if dialogue_active():
		_advance_dialogue()
		return
	if choice_active():
		for i in choice_options.size():
			if _choice_rect(i).has_point(e.position):
				_flash("choice%d" % i)
				pick_choice(i)
				return
		return
	if not end_lines.is_empty():
		end_lines = []
		return
	if craft_open():
		_craft_touch(e.position)
		return
	if fade > 0.0 or player == null:
		return
	if info_open:
		info_open = false
		return
	if _quest_rect().has_point(e.position) and objective_title != "":
		info_open = true
		info_time = 6.0
	elif e.position.distance_to(_dodge_c()) < 82.0:
		_flash("dodge")
		player.try_dodge()
	elif _skill_visible() and e.position.distance_to(_skill_c()) < 64.0:
		_flash("skill")
		player.try_skill()
	elif _guard_visible() and e.position.distance_to(_guard_c()) < 60.0:
		_flash("guard")
		player.try_guard()
	elif spirit_name != "" and e.position.distance_to(_portrait_c()) < 58.0:
		_flash("portrait")
		_portrait_index = e.index
		_portrait_held = 0.0
		_portrait_long_sent = false
	elif interact_label != "" and e.position.distance_to(_interact_c()) < 66.0:
		_flash("interact")
		interact_pressed.emit()
	elif joy_index == -1 and e.position.x < _size().x * 0.6 and e.position.y > _size().y * 0.4:
		joy_index = e.index
		joy_origin = e.position
		joy_pos = e.position
		joy_vec = Vector2.ZERO


func _craft_touch(p: Vector2) -> void:
	if p.distance_to(_craft_close_c()) < 48.0 or not _craft_panel_rect().has_point(p):
		close_craft()
		return
	for i in craft_rows.size():
		if _craft_button_rect(i).grow(8).has_point(p) and craft_rows[i]["can"]:
			_flash("craft%d" % i)
			craft_picked.emit(String(craft_rows[i]["id"]))
			return


func _key(k: InputEventKey) -> void:
	if dialogue_active():
		if k.physical_keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
			_advance_dialogue()
		return
	if choice_active():
		if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
			pick_choice(int(k.physical_keycode - KEY_1))
		return
	if not end_lines.is_empty():
		if k.physical_keycode in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
			end_lines = []
		return
	if craft_open():
		if k.physical_keycode == KEY_ESCAPE or k.physical_keycode == KEY_E:
			close_craft()
		elif k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
			var i := int(k.physical_keycode - KEY_1)
			if i < craft_rows.size() and craft_rows[i]["can"]:
				craft_picked.emit(String(craft_rows[i]["id"]))
		return
	if player == null or fade > 0.0:
		return
	match k.physical_keycode:
		KEY_SPACE:
			player.try_dodge()
		KEY_Q:
			player.try_skill()
		KEY_F:
			player.try_guard()
		KEY_R:
			if spirit_name != "":
				portrait_pressed.emit()
		KEY_T:
			if spirit_name != "":
				portrait_long_pressed.emit()
		KEY_TAB:
			info_open = not info_open
			info_time = 6.0
		KEY_ESCAPE:
			info_open = false
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
		if forced_move != null:
			player.move_input = forced_move
		elif busy():
			player.move_input = Vector2.ZERO
		elif joy_index != -1:
			player.move_input = joy_vec
		else:
			player.move_input = _keyboard_vector()
	if dialogue_active():
		dialogue_chars += TYPE_SPEED * delta
	if hint_time > 0.0:
		hint_time -= delta
		if hint_time <= 0.0:
			hint_text = ""
	if info_open:
		info_time -= delta
		if info_time <= 0.0:
			info_open = false
	if _portrait_index != -1 and not _portrait_long_sent:
		_portrait_held += delta
		if _portrait_held >= LONG_PRESS:
			_portrait_long_sent = true
			portrait_long_pressed.emit()
	if not toasts.is_empty():
		toasts[0][1] -= delta
		if toasts[0][1] <= 0.0:
			toasts.pop_front()
	for k in pressed_flash.keys():
		pressed_flash[k] -= delta
		if pressed_flash[k] <= 0.0:
			pressed_flash.erase(k)
	_canvas.queue_redraw()


# ── 그리기 도우미 ─────────────────────────────────────────

func _panel(rect: Rect2, bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 14) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(3)
	_canvas.draw_style_box(sb, rect)


func _text(pos: Vector2, text: String, size: int, color: Color = C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_canvas.draw_string(GameState.ui_font, pos, text, align, width, size, color)


func _bar(rect: Rect2, ratio: float, col: Color, label: String) -> void:
	_panel(rect, Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 8)
	if ratio > 0.0:
		_panel(Rect2(rect.position, Vector2(maxf(rect.size.x * clampf(ratio, 0.0, 1.0), 16.0), rect.size.y)), col, Color(0, 0, 0, 0), 8)
	_text(rect.position + Vector2(10, rect.size.y - 6), label, 19)


func _short_title() -> String:
	var dot := objective_title.find(".")
	return objective_title.substr(0, dot) if dot > 0 else objective_title


# ── 그리기 ───────────────────────────────────────────────

func _on_draw() -> void:
	var s := _size()
	_draw_target_arrow(s)
	if dialogue_active():
		_draw_dialogue(s)
	elif not craft_open() and not choice_active() and end_lines.is_empty():
		_draw_controls(s)
	if player:
		_draw_status(s)
	_draw_objective(s)
	_draw_hint(s)
	_draw_toasts(s)
	if info_open:
		_draw_info(s)
	if craft_open():
		_draw_craft(s)
	if choice_active():
		_draw_choice(s)
	if not end_lines.is_empty():
		_draw_end(s)
	if fade > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.75 * fade))
		_canvas.draw_multiline_string(GameState.ui_font, Vector2(40, s.y * 0.42), fade_text, HORIZONTAL_ALIGNMENT_CENTER, s.x - 80, 30, 4, C_TEXT)


func _draw_status(s: Vector2) -> void:
	_panel(Rect2(12, 12, s.x - 24, 84), Color(C_PANEL, 0.85))
	# 작은 초상화와 레벨
	var c := Vector2(52, 54)
	_canvas.draw_circle(c, 30.0, Color("3a4a5c"))
	_canvas.draw_circle(c + Vector2(0, 4), 15.0, Color("f0d2b0"))
	_canvas.draw_arc(c + Vector2(0, 2), 15.0, PI, TAU, 12, Color("2d3e5c"), 6.0)
	_canvas.draw_line(c + Vector2(-15, -2), c + Vector2(15, -2), Color("7fd6c2"), 3.0)
	_canvas.draw_arc(c, 30.0, 0, TAU, 32, C_GOLD, 2.0)
	_panel(Rect2(c.x - 26, c.y + 18, 52, 24), C_PANEL_DEEP, C_GOLD, 8)
	_text(Vector2(c.x - 26, c.y + 37), "Lv.%d" % GameState.level, 18, C_GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, 52)
	var x0 := 96.0
	var bw := s.x - x0 - 150.0
	_bar(Rect2(x0, 22, bw, 28), player.hp / player.max_hp, C_DANGER, "체력 %d" % roundi(player.hp))
	_bar(Rect2(x0, 58, bw, 28), player.gyeol / player.max_gyeol, Color(C_GYEOL, 0.85), "결력 %d" % roundi(player.gyeol))
	_text(Vector2(s.x - 144, 46), "재화", 18, Color(C_TEXT, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 120)
	_text(Vector2(s.x - 144, 80), str(GameState.currency), 26, C_GOLD_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT, 120)


func _draw_objective(s: Vector2) -> void:
	if objective_title == "" or info_open:
		return
	var r := _quest_rect()
	_panel(r, Color(C_PANEL, 0.72))
	var tag := _short_title()
	_panel(Rect2(r.position + Vector2(8, 8), Vector2(56, 36)), Color("2d4a4a"), Color(0, 0, 0, 0), 8)
	_text(r.position + Vector2(8, 34), tag, 20, Color("7fd6c2"), HORIZONTAL_ALIGNMENT_CENTER, 56)
	_text(r.position + Vector2(76, 35), objective_text, 23, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 120)
	_text(Vector2(r.end.x - 40, r.position.y + 34), "▾", 22, Color(C_TEXT, 0.6))


func _draw_info(s: Vector2) -> void:
	var lines: Array = []
	lines.append(["목표", objective_text])
	lines.append(["장비", GameState.weapon_label()])
	var trait_text := GameState.weapon_trait()
	if trait_text != "":
		lines.append(["특성", trait_text])
	var mats: Array[String] = []
	for k in GameState.items:
		if int(GameState.items[k]) > 0:
			mats.append("%s %d" % [k, GameState.items[k]])
	lines.append(["재료", ", ".join(mats) if not mats.is_empty() else "없음"])
	if not GameState.spirits.is_empty():
		var sp: Array[String] = []
		for id in GameState.spirits:
			sp.append(id + (" (활성)" if id == GameState.active_spirit else " (휴식)"))
		lines.append(["영물", ", ".join(sp)])
	var r := Rect2(12, 104, s.x - 24, 76 + lines.size() * 44)
	_panel(r, Color(C_PANEL_DEEP, 0.95), Color("7fd6c2"))
	_text(r.position + Vector2(20, 40), objective_title, 25, Color("7fd6c2"))
	for i in lines.size():
		var y := r.position.y + 84 + i * 44
		_text(Vector2(r.position.x + 20, y), String(lines[i][0]), 20, Color(C_TEXT, 0.6))
		_text(Vector2(r.position.x + 92, y), String(lines[i][1]), 21, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 110)
	_text(Vector2(r.end.x - 200, r.end.y - 12), "눌러서 접기", 17, Color(C_TEXT, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 180)


func _draw_target_arrow(s: Vector2) -> void:
	if target_world == null or busy():
		return
	var sp: Vector2 = _canvas.get_viewport().get_canvas_transform() * (target_world as Vector2)
	var margin := Rect2(40, TOP_H + 40, s.x - 80, s.y - TOP_H - 460)
	if margin.has_point(sp):
		return
	var center := Vector2(s.x * 0.5, s.y * 0.56)
	var dir := (sp - center).normalized()
	var p := center
	for i in 400:
		var np := p + dir * 4.0
		if not margin.has_point(np):
			break
		p = np
	var side := dir.orthogonal()
	_canvas.draw_colored_polygon(PackedVector2Array([p + dir * 26.0, p - dir * 10.0 + side * 18.0, p - dir * 10.0 - side * 18.0]), Color(C_GOLD_LIGHT, 0.9))


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
	var base := joy_origin if joy_index != -1 else Vector2(150, s.y - 190)
	var knob := base + joy_vec * JOY_R
	_canvas.draw_circle(base, JOY_R, Color(1, 1, 1, 0.12 if joy_index == -1 else 0.2))
	_canvas.draw_arc(base, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	_canvas.draw_circle(knob, 40.0, Color(1, 1, 1, 0.35 if joy_index == -1 else 0.6))

	var dodge_ratio: float = player.dodge_cd / (player.DODGE_CD + player.DODGE_TIME)
	_round_button(_dodge_c(), 72.0, "회피", Color(0.2, 0.45, 0.75, 0.85), "dodge", dodge_ratio)
	if _skill_visible():
		_round_button(_skill_c(), 56.0, "사선베기", Color(0.15, 0.55, 0.5, 0.85), "skill", player.skill_cd / player.SKILL_CD, "결력 15", player.gyeol >= player.SKILL_COST)
	if _guard_visible():
		_round_button(_guard_c(), 52.0, "되받기", Color(0.45, 0.4, 0.7, 0.85), "guard", player.guard_cd / player.GUARD_CD, "결력 12", player.gyeol >= player.GUARD_COST)
	if interact_label != "":
		_round_button(_interact_c(), 58.0, interact_label, Color(0.8, 0.6, 0.15, 0.9), "interact")
	if spirit_name != "":
		_draw_portrait()


## 활성 영물 초상화: 누르면 동행 ↔ 장비, 길게 누르면 활성 영물 교체.
func _draw_portrait() -> void:
	var c := _portrait_c()
	var r := 48.0
	var bg := Color(0.18, 0.28, 0.14, 0.9) if spirit_name == "도톰" else Color(0.14, 0.24, 0.3, 0.9)
	if pressed_flash.has("portrait"):
		bg = bg.lightened(0.3)
	_canvas.draw_circle(c, r, bg)
	_canvas.draw_arc(c, r, 0, TAU, 40, Color("8fdc5a") if spirit_name == "도톰" else C_GYEOL, 3.0)
	if spirit_name == "도톰":
		if spirit_form == "신발":
			_canvas.draw_circle(c + Vector2(-12, -2), 13.0, Color("6a8a40"))
			_canvas.draw_circle(c + Vector2(12, -2), 13.0, Color("6a8a40"))
			_canvas.draw_circle(c + Vector2(-12, -4), 4.0, Color("b0e070"))
			_canvas.draw_circle(c + Vector2(12, -4), 4.0, Color("b0e070"))
		else:
			_canvas.draw_circle(c + Vector2(0, -2), 22.0, Color("6a8a40"))
			_canvas.draw_circle(c + Vector2(-13, -20), 6.0, Color("5a7a34"))
			_canvas.draw_circle(c + Vector2(13, -20), 6.0, Color("5a7a34"))
			_canvas.draw_circle(c + Vector2(-7, -4), 3.0, Color("1a1a10"))
			_canvas.draw_circle(c + Vector2(7, -4), 3.0, Color("1a1a10"))
	else:
		if spirit_form == "검":
			_canvas.draw_line(c + Vector2(-20, 22), c + Vector2(20, -22), Color("c8d0d8"), 7.0)
			for i in 4:
				var p := c + Vector2(-12 + i * 9, 12 - i * 10)
				_canvas.draw_circle(p, 3.5, C_GYEOL)
			_canvas.draw_line(c + Vector2(-26, 14), c + Vector2(-12, 28), C_GOLD, 5.0)
		else:
			var pts := PackedVector2Array()
			for i in 12:
				pts.append(c + Vector2(-26 + i * 4.8, sin(i * 0.8) * 9.0))
			_canvas.draw_polyline(pts, Color("7aa8b0"), 9.0)
			_canvas.draw_circle(c + Vector2(28, 2), 8.0, Color("8ab8c0"))
			_canvas.draw_circle(c + Vector2(30, 0), 2.5, Color("102028"))
	if spirit_cd > 0.0:
		var pts2 := PackedVector2Array([c])
		for i in 33:
			var a := -PI / 2.0 + TAU * spirit_cd * i / 32.0
			pts2.append(c + Vector2(cos(a), sin(a)) * r)
		_canvas.draw_colored_polygon(pts2, Color(0, 0, 0, 0.5))
	if player and player.transform_t > 0.0 and player.transform_total > 0.0:
		var p2: float = 1.0 - player.transform_t / player.transform_total
		_canvas.draw_arc(c, r + 8.0, -PI / 2.0, -PI / 2.0 + TAU * p2, 40, Color("b0ff70"), 6.0)
	if spirit_form == "신발" and player and player.step_cd > 0.0:
		_canvas.draw_arc(c, r - 6.0, -PI / 2.0, -PI / 2.0 + TAU * player.step_cd / player.STEP_CD, 30, Color(1, 1, 1, 0.5), 4.0)
	if spirit_form == "검" and player and player.wave_cd > 0.0:
		_canvas.draw_arc(c, r - 6.0, -PI / 2.0, -PI / 2.0 + TAU * player.wave_cd / player.WAVE_CD, 30, Color(1, 1, 1, 0.5), 4.0)
	if _portrait_index != -1 and spirit_can_swap and not _portrait_long_sent:
		_canvas.draw_arc(c, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * _portrait_held / LONG_PRESS, 40, C_GOLD_LIGHT, 4.0)
	_text(Vector2(c.x - 80, c.y + r + 26), spirit_name + " · " + spirit_form, 20, Color("d8f0b0"), HORIZONTAL_ALIGNMENT_CENTER, 160)
	if spirit_status != "":
		var ready := spirit_status.ends_with("준비") or not (spirit_status.contains("초") or spirit_status.contains("부족"))
		_text(Vector2(c.x - 90, c.y + r + 50), spirit_status, 18, Color("9be7a0") if ready else Color("ffb08a"), HORIZONTAL_ALIGNMENT_CENTER, 180)
	if spirit_can_swap:
		_text(Vector2(c.x - 80, c.y + r + 72), "길게 눌러 교체", 16, Color(C_TEXT, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 160)


func _draw_dialogue(s: Vector2) -> void:
	var line: Array = dialogue[dialogue_index]
	var full := String(line[1])
	var text_w := s.x - 96
	var th := GameState.ui_font.get_multiline_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, text_w, 28).y
	var h := clampf(th + 104.0, 160.0, 360.0)
	var rect := Rect2(16, s.y - 96 - h, s.x - 32, h)
	_panel(rect, Color(C_PANEL_DEEP, 0.94), Color("7fd6c2"))
	_panel(Rect2(rect.position + Vector2(24, -26), Vector2(180, 52)), Color("2d3e5c"), Color("7fd6c2"), 12)
	_text(rect.position + Vector2(24, 10), String(line[0]), 26, C_GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, 180)
	var shown := full.substr(0, int(dialogue_chars))
	_canvas.draw_multiline_string(GameState.ui_font, rect.position + Vector2(32, 70), shown, HORIZONTAL_ALIGNMENT_LEFT, text_w, 28, 8, C_TEXT)
	if dialogue_chars >= full.length():
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		_text(Vector2(rect.end.x - 260, rect.end.y - 16), "터치해서 계속 ▼", 19, Color(1, 1, 1, 0.5 + 0.4 * blink), HORIZONTAL_ALIGNMENT_RIGHT, 236)


func _draw_hint(s: Vector2) -> void:
	if hint_text == "" or busy() or info_open:
		return
	var tw := GameState.ui_font.get_multiline_string_size(hint_text, HORIZONTAL_ALIGNMENT_CENTER, s.x - 120, 22).y
	var rect := Rect2(36, TOP_H + 8, s.x - 72, tw + 22)
	_panel(rect, Color(0.12, 0.09, 0.03, 0.82), Color(C_GOLD, 0.9), 12)
	_canvas.draw_multiline_string(GameState.ui_font, rect.position + Vector2(24, 32), hint_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 48, 22, 3, C_GOLD_LIGHT)


func _draw_toasts(s: Vector2) -> void:
	if toasts.is_empty() or craft_open():
		return
	var tst: Array = toasts[0]
	var life := float(tst[1])
	var a := clampf(minf(life / 0.3, (TOAST_TIME - life) / 0.15), 0.0, 1.0)
	var tw := GameState.ui_font.get_string_size(String(tst[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var w := clampf(tw + 56.0, 300.0, s.x - 32.0)
	var y := TOP_H + 76.0 if hint_text != "" else TOP_H + 12.0
	var rect := Rect2(s.x * 0.5 - w * 0.5, y - (1.0 - a) * 12.0, w, 50)
	_panel(rect, Color(0.05, 0.2, 0.18, 0.9 * a), Color(0.5, 0.85, 0.76, a))
	_text(rect.position + Vector2(0, 34), String(tst[0]), 24, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	if toasts.size() > 1:
		_text(rect.position + Vector2(0, 70), "+%d" % (toasts.size() - 1), 18, Color(1, 1, 1, 0.6 * a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


## 작업대: 한 화면에 제작·강화 목록. 재료는 (보유/필요)로 표시하고 부족하면 붉게.
func _draw_craft(s: Vector2) -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.45))
	var pr := _craft_panel_rect()
	_panel(pr, Color(C_PANEL_DEEP, 0.97), C_GOLD)
	_text(pr.position + Vector2(28, 52), craft_title, 28, C_GOLD_LIGHT)
	var cc := _craft_close_c()
	_canvas.draw_circle(cc, 26.0, Color("3a4250"))
	_text(Vector2(cc.x - 26, cc.y + 10), "✕", 26, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 52)
	for i in craft_rows.size():
		var row: Dictionary = craft_rows[i]
		var y := pr.position.y + 96 + i * 168
		_panel(Rect2(pr.position.x + 16, y, pr.size.x - 32, 156), Color(C_PANEL, 0.9), Color(0, 0, 0, 0), 12)
		_text(Vector2(pr.position.x + 36, y + 38), String(row["title"]), 25, C_TEXT)
		_text(Vector2(pr.position.x + 36, y + 72), String(row["desc"]), 19, Color(C_TEXT, 0.7), HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 240)
		var cx := pr.position.x + 36
		for cost in row["cost"]:
			var ok: bool = int(cost[1]) >= int(cost[2])
			var label := "%s %d/%d" % [cost[0], cost[1], cost[2]]
			_text(Vector2(cx, y + 116), label, 20, Color("9be7a0") if ok else Color("ff8a70"))
			cx += GameState.ui_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 22
		var br := _craft_button_rect(i)
		var can: bool = row["can"]
		var col := Color(C_GOLD, 0.95) if can else Color(0.3, 0.3, 0.3, 0.8)
		if pressed_flash.has("craft%d" % i):
			col = col.lightened(0.3)
		_panel(br, col, Color(0, 0, 0, 0), 14)
		_text(Vector2(br.position.x, br.position.y + 60), String(row["button"]), 26, Color("1a1408") if can else Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, br.size.x)


func _draw_choice(s: Vector2) -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.5))
	var r0 := _choice_rect(0)
	_text(Vector2(40, r0.position.y - 24), choice_title, 28, C_GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, s.x - 80)
	for i in choice_options.size():
		var r := _choice_rect(i)
		var col := Color(C_PANEL, 0.96)
		if pressed_flash.has("choice%d" % i):
			col = col.lightened(0.2)
		_panel(r, col, C_GOLD)
		var opt: Array = choice_options[i]
		_text(Vector2(r.position.x + 28, r.position.y + 50), "%d. %s" % [i + 1, String(opt[0])], 26, C_TEXT)
		if opt.size() > 1:
			_text(Vector2(r.position.x + 28, r.position.y + 90), String(opt[1]), 19, Color(C_TEXT, 0.7), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56)
	if choice_note != "":
		var last := _choice_rect(choice_options.size() - 1)
		_canvas.draw_multiline_string(GameState.ui_font, Vector2(48, last.end.y + 44), choice_note, HORIZONTAL_ALIGNMENT_CENTER, s.x - 96, 20, 3, Color(C_TEXT, 0.75))


func _draw_end(s: Vector2) -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(C_PANEL_DEEP, 0.93))
	var y := s.y * 0.26
	for i in end_lines.size():
		var line := String(end_lines[i])
		var size := 34 if i == 0 else 22
		var col := C_GOLD_LIGHT if i == 0 else C_TEXT
		_canvas.draw_multiline_string(GameState.ui_font, Vector2(48, y), line, HORIZONTAL_ALIGNMENT_CENTER, s.x - 96, size, 3, col)
		y += 62.0 if i == 0 else 44.0
	_text(Vector2(0, s.y - 120), "터치해서 계속 둘러보기", 20, Color(C_TEXT, 0.6), HORIZONTAL_ALIGNMENT_CENTER, s.x)