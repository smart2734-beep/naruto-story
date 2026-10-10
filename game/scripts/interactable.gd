extends Node2D
## 상호작용 대상(NPC·물건). 가까이 가면 HUD에 action_label 버튼이 뜬다.

var display_name := ""
var kind := "npc"  # "npc" 또는 "crate"
var action_label := "대화"
var body_color := Color("8a6a4a")
var accent := Color("e8c070")
var hair := Color("3a2a20")
var interactable := true
var marked := false
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
	else:
		draw_circle(Vector2(0, 2), 8.0, body_color)
		draw_line(Vector2(-7, -2), Vector2(7, 6), accent, 2.0)
		draw_circle(Vector2(0, -7), 6.0, Color("f0d2b0"))
		draw_arc(Vector2(0, -8), 6.0, PI, TAU, 10, hair, 3.0)

	var f := GameState.world_font
	if display_name != "":
		draw_string_outline(f, Vector2(-40, -18), display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 8, 3, Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(-40, -18), display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 8, Color.WHITE)
	if marked:
		var y := -32.0 + sin(t * 5.0) * 2.5
		draw_circle(Vector2(0, y - 4), 7.0, Color("ffcc33"))
		draw_string(f, Vector2(-10, y), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 11, Color("402000"))
