extends Node2D
## 피해량·보상 등 잠깐 떠올랐다 사라지는 월드 글자.

var text := ""
var color := Color.WHITE
var life := 0.8
var size := 10


func _process(delta: float) -> void:
	life -= delta
	position.y -= 24.0 * delta
	if life <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var c := color
	c.a = clampf(life / 0.4, 0.0, 1.0)
	var f := GameState.world_font
	draw_string_outline(f, Vector2(-40, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 80, size, 3, Color(0, 0, 0, c.a * 0.8))
	draw_string(f, Vector2(-40, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 80, size, c)
