extends Node2D
## 줄비 검의 직선 파동 연출.

var dir := Vector2.RIGHT
var length := 84.0
var width := 26.0
var life := 0.3


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - life / 0.3
	var side := dir.orthogonal() * width * 0.5
	var front := dir * length * minf(k * 1.6, 1.0)
	var a := clampf(life / 0.3, 0.0, 1.0)
	draw_colored_polygon(PackedVector2Array([side * 0.4, front + side, front - side, -side * 0.4]), Color(0.37, 0.77, 0.79, 0.45 * a))
	draw_line(front + side, front - side, Color(0.8, 1.0, 1.0, a), 3.0)
