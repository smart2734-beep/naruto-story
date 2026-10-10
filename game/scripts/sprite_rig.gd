extends Node2D
## 32×40 캐릭터 스프라이트(교육원 아트 v0.1)와 발밑 그림자.
## 부모의 _draw(공격 예고·피격·기술·영물 효과)보다 뒤에 그려지도록 show_behind_parent를 쓴다.
## 발 기준이 프레임 (16,38)이라 오프셋 (0,-10)이면 부모 로컬 (0,8)의 그림자에 맞는다 (game/assets/README.md 3항).

const OFFSET := Vector2(0, -10)

var sprite: AnimatedSprite2D
var dir_name := "down"


func setup(frames: SpriteFrames) -> void:
	show_behind_parent = true
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.centered = true
	sprite.offset = OFFSET
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	sprite.play("idle_down")


## 이동 방향(큰 축)으로 애니메이션을 고르고, 멈추면 마지막 방향의 정지 프레임을 쓴다 (README 4항).
func update_motion(v: Vector2) -> void:
	if v.length() > 1.0:
		if absf(v.x) > absf(v.y):
			dir_name = "right" if v.x > 0.0 else "left"
		else:
			dir_name = "down" if v.y > 0.0 else "up"
		_play("walk_" + dir_name)
	else:
		_play("idle_" + dir_name)


func face(dir: String) -> void:
	dir_name = dir
	_play("idle_" + dir)


func _play(anim: String) -> void:
	if sprite.animation != anim:
		sprite.play(anim)


func _draw() -> void:
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
