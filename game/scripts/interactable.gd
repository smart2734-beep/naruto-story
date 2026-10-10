extends Node2D
## 상호작용 대상(NPC·물건). 가까이 가면 HUD에 action_label 버튼이 뜬다.

var display_name := ""
var kind := "npc"  # npc / crate / rope / spot
var action_label := "대화"
var body_color := Color("8a6a4a")
var accent := Color("e8c070")
var hair := Color("3a2a20")
var interactable := true
var marked := false
var checked := false
var walk_target = null
var t := 0.0


func _ready() -> void:
	add_to_group("interactable")


func _process(delta: float) -> void:
	t += delta
	if walk_target != null:
		position = position.move_toward(walk_target, 70.0 * delta)
		if position.distance_to(walk_target) < 1.0:
			walk_target = null
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if kind == "crate":
		draw_rect(Rect2(-9, -8, 18, 15), Color("9a6a3a"))
		draw_rect(Rect2(-9, -8, 18, 15), Color("5a3a1a"), false, 1.5)
		draw_line(Vector2(-9, -1), Vector2(9, -1), Color("5a3a1a"), 1.5)
		draw_circle(Vector2(0, -1), 2.0, Color("c0c8d0"))
	elif kind == "rope":
		# 느슨한 줄이 걸린 말뚝. 조사하면 checked.
		draw_rect(Rect2(-3, -14, 6, 20), Color("5a3a20"))
		var sag := 4.0 if not checked else 0.0
		var pts := PackedVector2Array()
		for i in 9:
			var x := -2.0 + i * 3.5
			pts.append(Vector2(x, -10 + sin(i / 8.0 * PI) * (6.0 + sag) + sin(t * 3.0 + i) * (1.0 if not checked else 0.0)))
		draw_polyline(pts, Color("d8c090") if not checked else Color("8fdc5a"), 2.0)
	elif kind == "bench":
		# 작업대: 나무 상판, 조율봉, 황동 램프
		draw_rect(Rect2(-14, -6, 28, 12), Color("75513a"))
		draw_rect(Rect2(-14, -6, 28, 3), Color("8a6448"))
		draw_rect(Rect2(-12, 6, 3, 6), Color("49352c"))
		draw_rect(Rect2(9, 6, 3, 6), Color("49352c"))
		draw_line(Vector2(-8, -9), Vector2(4, -7), Color("a2a58f"), 2.0)
		draw_circle(Vector2(10, -10), 3.0, Color("f2d28b"))
	elif kind == "hook":
		# 걸린 연결쇠. 줄비가 찾기 전에는 보이지 않는다(interactable=false면 그리지 않음).
		if interactable or checked:
			var col := Color("8a8a90") if not checked else Color("7fd6c2")
			draw_arc(Vector2(0, -4), 5.0, 0, TAU, 12, col, 2.0)
			draw_line(Vector2(-6, 2), Vector2(6, 2), col, 2.0)
			if not checked:
				var a := sin(t * 6.0) * 2.0
				draw_line(Vector2(9 + a, -4), Vector2(15 + a, -4), Color("5fc5c9"), 2.0)
				draw_line(Vector2(15 + a, -4), Vector2(12 + a, -7), Color("5fc5c9"), 2.0)
				draw_line(Vector2(15 + a, -4), Vector2(12 + a, -1), Color("5fc5c9"), 2.0)
	elif kind == "spot":
		pass  # 월드가 그리는 장치(손잡이 등)의 상호작용 지점
	else:
		draw_circle(Vector2(0, 2), 8.0, body_color)
		draw_line(Vector2(-7, -2), Vector2(7, 6), accent, 2.0)
		draw_circle(Vector2(0, -7), 6.0, Color("f0d2b0"))
		draw_arc(Vector2(0, -8), 6.0, PI, TAU, 10, hair, 3.0)

	var f := GameState.world_font
	if display_name != "" and ((kind != "spot" and kind != "hook") or interactable):
		draw_string_outline(f, Vector2(-40, -18), display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 8, 3, Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(-40, -18), display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 8, Color.WHITE)
	if marked:
		var y := -32.0 + sin(t * 5.0) * 2.5
		draw_circle(Vector2(0, y - 4), 7.0, Color("ffcc33"))
		draw_string(f, Vector2(-10, y), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 11, Color("402000"))
