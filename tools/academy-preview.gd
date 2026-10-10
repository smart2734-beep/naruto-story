extends Node2D
## Standalone visual inspection and resource import check; never replaces the game scene.
var textures := {}
var frames := {}
var tile_set: TileSet
var font := SystemFont.new()

func _ready() -> void:
	get_window().size = Vector2i(1200, 900)
	get_window().content_scale_size = Vector2i(1200, 900)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font.font_names = PackedStringArray(["Noto Sans", "sans-serif"])
	for id in ["apprentice", "danu"]:
		textures[id] = load("res://assets/characters/%s-walk.png" % id)
		frames[id] = load("res://assets/characters/%s-frames.tres" % id)
		assert(frames[id] is SpriteFrames)
		assert(frames[id].get_animation_names().size() == 8)
		assert(frames[id].get_frame_count("walk_down") == 4)
	tile_set = load("res://assets/tiles/academy-tileset.tres")
	assert(tile_set != null and tile_set.get_source(0).get_tiles_count() == 16)
	textures["tiles"] = load("res://assets/tiles/academy-tiles.png")
	textures["portrait"] = load("res://assets/portraits/apprentice-master.png")
	for id in ["brass-lamp", "stone-arch", "oak-bookshelf", "parts-crate"]:
		textures[id] = load("res://assets/props/%s.png" % id)
	print("ASSET CHECK: SpriteFrames 2 x 8 animations; atlas 16 tiles; PNGs loaded")
	if OS.get_cmdline_user_args().has("--check"):
		get_tree().quit(0)
		return
	queue_redraw()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/naruto-academy-assets-preview.png")
	print("Saved /tmp/naruto-academy-assets-preview.png")
	get_tree().quit(0)

func label(at: Vector2, text: String, size := 18) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("f2ead6"))

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1200, 900), Color("14202b"))
	label(Vector2(28, 40), "ACADEMY ART v0.1  |  exact native pixel assets + original portrait", 24)
	label(Vector2(28, 76), "Apprentice / 32 x 40 / idle + walk")
	draw_texture_rect(textures["apprentice"], Rect2(28, 94, 384, 480), false)
	label(Vector2(438, 76), "Danu / olive coat + repair stitching")
	draw_texture_rect(textures["danu"], Rect2(438, 94, 384, 480), false)
	label(Vector2(854, 76), "Portrait / displayed at 256 x 256")
	draw_texture_rect(textures["portrait"], Rect2(854, 94, 256, 256), false)
	label(Vector2(854, 380), "Original portrait master")
	label(Vector2(854, 410), "Not a sprite sheet")
	label(Vector2(28, 624), "16 tiles / 32 x 32")
	draw_texture_rect(textures["tiles"], Rect2(28, 642, 256, 256), false)
	label(Vector2(282, 624), "Independent transparent props / no collision changes")
	draw_texture_rect(textures["stone-arch"], Rect2(282, 642, 192, 192), false)
	draw_texture_rect(textures["oak-bookshelf"], Rect2(510, 642, 128, 128), false)
	draw_texture_rect(textures["brass-lamp"], Rect2(700, 642, 64, 96), false)
	draw_texture_rect(textures["parts-crate"], Rect2(820, 642, 64, 64), false)
	label(Vector2(282, 866), "Nearest filtering. Keep the existing world scale and gameplay geometry.")
