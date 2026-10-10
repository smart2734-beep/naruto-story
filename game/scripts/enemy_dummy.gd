extends Node2D
## 연습용 허수아비. 쓰러지지 않고 맞은 피해만 띄운다. 전투 판정(변신 준비)에는 포함하지 않는다.

signal aim_started(enemy)
signal defeated(enemy)
signal hit(amount: float)

var alive := true
var home := Vector2.ZERO
var flash := 0.0
var player
var total_damage := 0.0


func _ready() -> void:
	home = position
	add_to_group("enemy")


func reset_to_home() -> void:
	pass


func take_hit(amount: float, _from: Vector2) -> void:
	flash = 0.15
	total_damage += amount
	hit.emit(amount)
	var ft := preload("res://scripts/float_text.gd").new()
	ft.text = str(roundi(amount))
	ft.position = position + Vector2(0, -26)
	get_parent().add_child(ft)


func _process(delta: float) -> void:
	flash = maxf(flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var wood := Color.WHITE if flash > 0.0 else Color("8a6a40")
	draw_rect(Rect2(-2, -6, 4, 14), Color("5a3a20"))
	draw_rect(Rect2(-10, -8, 20, 4), wood)
	draw_circle(Vector2(0, -12), 6.0, Color("c8b080") if flash <= 0.0 else Color.WHITE)
	draw_line(Vector2(-4, -12), Vector2(4, -12), Color("5a3a20"), 1.0)
	draw_string(GameState.world_font, Vector2(-30, -22), "허수아비", HORIZONTAL_ALIGNMENT_CENTER, 60, 7, Color(1, 1, 1, 0.7))
