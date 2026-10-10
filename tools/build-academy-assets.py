"""Author the original pixel assets from blank canvases; Pillow is a build-only dependency.

No existing/generated image is edited. Run from any directory. Outputs have exact
native pixel dimensions; the separate generated portrait remains an unmodified master.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "game/assets"
OUTLINE = "#202833"


def save(im, name):
    p = ASSETS / name
    p.parent.mkdir(parents=True, exist_ok=True)
    im.save(p)


def actor(direction, frame, teacher=False):
    im = Image.new("RGBA", (32, 40))
    d = ImageDraw.Draw(im)
    dark, mid, light = ("#354734", "#4e6650", "#7b8c57") if teacher else ("#303c50", "#52637a", "#788a9a")
    skin, shade, hair = "#bf8359", "#986143", "#302e33"
    stride = [0, -1, 0, 1][frame]
    bob = 1 if frame in (1, 3) else 0
    # Feet stay at y=38; alternate boots produce a readable four-frame walk.
    d.rectangle((10, 30, 14, 36), fill=OUTLINE)
    d.rectangle((18, 30, 22, 36), fill=OUTLINE)
    d.rectangle((9 + stride, 35, 14 + stride, 38), fill="#49352c")
    d.rectangle((18 - stride, 35, 23 - stride, 38), fill="#49352c")
    d.line((9 + stride, 37, 14 + stride, 37), fill="#9a7250")
    d.line((18 - stride, 37, 23 - stride, 37), fill="#9a7250")
    end = 34 if teacher else 30
    d.polygon([(12, 15 + bob), (21, 15 + bob), (25, 21 + bob), (26, end), (7, end), (8, 21 + bob)], fill=OUTLINE)
    d.polygon([(12, 16 + bob), (21, 16 + bob), (24, 22), (24, end - 1), (9, end - 1), (9, 22)], fill=mid)
    d.polygon([(11, 18), (14, 20), (13, end - 1), (9, end - 1)], fill=light)
    d.polygon([(20, 18), (24, 22), (24, end - 1), (20, end - 1)], fill=dark)
    d.rectangle((14, 22 + bob, 19, 29), fill=OUTLINE)
    d.line((12, 27, 21, 27), fill="#75513a", width=2)
    d.rectangle((17, 27, 18, 28), fill="#d2ad62")
    d.rectangle((21, 27, 24, 30), fill="#49352c")
    d.point((22, 28), fill="#d2ad62")
    # Gloved hands and a small tool sheath are separate from the cape silhouette.
    d.rectangle((7, 23 + stride, 9, 27 + stride), fill="#75513a")
    d.rectangle((24, 23 - stride, 26, 27 - stride), fill="#75513a")
    if not teacher:
        d.line((25, 29, 27, 34), fill=OUTLINE, width=2)
        d.point((25, 29), fill="#d2ad62")
    if teacher:
        d.line((11, 30, 14, 32), fill="#a2a58f")
        d.point((11, 32), fill="#a2a58f")
    # Hood collar, original cord clasp, hair and face.
    d.rectangle((11, 15 + bob, 21, 18 + bob), fill=dark)
    d.line((13, 18 + bob, 19, 18 + bob), fill="#d2ad62")
    d.point((16, 19 + bob), fill="#f2d28b")
    d.rectangle((10, 6 + bob, 22, 14 + bob), fill=OUTLINE)
    d.rectangle((11, 8 + bob, 21, 15 + bob), fill=skin)
    d.rectangle((20, 9 + bob, 21, 14 + bob), fill=shade)
    d.rectangle((11, 5 + bob, 21, 9 + bob), fill=hair)
    d.rectangle((9, 7 + bob, 12, 11 + bob), fill=hair)
    d.rectangle((20, 7 + bob, 23, 11 + bob), fill=hair)
    d.rectangle((13, 4 + bob, 17, 5 + bob), fill=hair)
    d.point((19, 5 + bob), fill="#52464a")
    if direction == "down":
        d.rectangle((13, 11 + bob, 14, 12 + bob), fill=OUTLINE)
        d.rectangle((19, 11 + bob, 20, 12 + bob), fill=OUTLINE)
        d.point((17, 14 + bob), fill=shade)
        if teacher:
            d.line((13, 14 + bob, 19, 14 + bob), fill=hair)
            d.point((16, 15 + bob), fill=hair)
    elif direction == "up":
        d.rectangle((11, 8 + bob, 21, 15 + bob), fill=hair)
        d.line((12, 9 + bob, 14, 7 + bob), fill="#52464a")
        d.rectangle((12, 20, 21, end - 1), fill=mid)
        d.line((15, 21, 15, end - 2), fill=light)
    else:
        left = direction == "left"
        eye = 11 if left else 21
        d.point((eye, 11 + bob), fill=OUTLINE)
        d.point((eye - 1 if left else eye + 1, 12 + bob), fill=skin)
        d.rectangle((17 if left else 11, 10 + bob, 21 if left else 15, 14 + bob), fill=hair)
    if not teacher:
        # Teal tied cloth, not a metal headband. Seen on every direction.
        d.line((10, 9 + bob, 12, 9 + bob), fill="#5fc5c9")
        d.line((10, 10 + bob, 7, 13 + bob), fill="#5fc5c9")
        d.point((7, 14 + bob), fill="#5fc5c9")
    return im


def characters():
    for name, teacher in [("apprentice", False), ("danu", True)]:
        sheet = Image.new("RGBA", (128, 160))
        for row, direction in enumerate(["down", "left", "right", "up"]):
            for col in range(4):
                sheet.paste(actor(direction, col, teacher), (col * 32, row * 40))
        save(sheet, f"characters/{name}-walk.png")
        # Hand-written resource metadata leaves movement/collision code to Claude.
        lines = ['[gd_resource type="SpriteFrames" load_steps=18 format=3]', '', f'[ext_resource type="Texture2D" path="res://assets/characters/{name}-walk.png" id="1"]', '']
        for row in range(4):
            for col in range(4):
                i = row * 4 + col
                lines += [f'[sub_resource type="AtlasTexture" id="Frame_{i}"]', 'atlas = ExtResource("1")', f'region = Rect2({col * 32}, {row * 40}, 32, 40)', '']
        lines += ['[resource]', 'animations = [']
        entries = []
        for row, direction in enumerate(["down", "left", "right", "up"]):
            for action in ["idle", "walk"]:
                frames = [row * 4] if action == "idle" else [row * 4 + i for i in range(4)]
                frame_text = ', '.join('{"duration": 1.0, "texture": SubResource("Frame_%d")}' % i for i in frames)
                entries.append('{"frames": [%s], "loop": true, "name": &"%s_%s", "speed": %s}' % (frame_text, action, direction, '6.0' if action == 'walk' else '1.0'))
        lines += [',\n'.join(entries), ']']
        (ASSETS / f"characters/{name}-frames.tres").write_text('\n'.join(lines) + '\n')


TILE_NAMES = ["stone_a", "stone_b", "stone_c", "stone_moss", "wood_a", "wood_b", "earth", "grass", "wall", "wall_base", "water", "water_edge", "path_edge", "brass_inlay", "steps", "dark_floor"]


def tile(index):
    im = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(im)
    if index in [0, 1, 2, 3, 8, 9, 15]:
        base = "#777d78" if index < 4 else "#535d5c" if index in [8, 9] else "#3f4b4a"
        d.rectangle((0, 0, 31, 31), fill=base)
        for y in [0, 16]:
            d.line((0, y, 31, y), fill="#4c5956")
            off = (index * 7 + (8 if y else 0)) % 32
            d.line((off, y, off, min(y + 15, 31)), fill="#4c5956")
        d.line((1, 1, 30, 1), fill="#a2a58f" if index < 4 else "#777d78")
        for j in range(4):
            x, y = (j * 7 + index * 3) % 29 + 1, (j * 11 + index * 5) % 29 + 1
            d.point((x, y), fill="#a2a58f" if index < 4 else "#69736b")
        if index == 3:
            d.rectangle((0, 23, 5, 31), fill="#4e6650")
            d.rectangle((1, 27, 9, 31), fill="#7b8c57")
        if index == 9:
            d.rectangle((0, 23, 31, 31), fill="#35423f")
            d.line((0, 23, 31, 23), fill="#a2a58f")
    elif index in [4, 5]:
        d.rectangle((0, 0, 31, 31), fill="#75513a")
        for x in [0, 10, 21]:
            d.line((x, 0, x, 31), fill="#49352c")
            d.line((x + 1, 0, x + 1, 31), fill="#91684b")
        for x, y in [(4, 11), (16, 23), (27, 6)]:
            d.line((x, y, x + 2, y + 5), fill="#61442f")
        d.point((3, 3), fill="#d2ad62")
        d.point((25, 28), fill="#d2ad62")
    elif index in [6, 7, 12]:
        d.rectangle((0, 0, 31, 31), fill="#8b836b" if index == 6 else "#4e6650")
        for j in range(12):
            x, y = (j * 7 + 4) % 32, (j * 11 + 2) % 32
            d.line((x, y, min(x + 1, 31), y), fill="#a29777" if index == 6 else "#657a58")
        if index == 12:
            d.rectangle((8, 0, 31, 31), fill="#8b836b")
            d.line((8, 0, 8, 31), fill="#777d78")
    elif index in [10, 11]:
        d.rectangle((0, 0, 31, 31), fill="#426d77")
        for j in range(4):
            x, y = (j * 11 + 3) % 24, j * 8 + 3
            d.line((x, y, x + 6, y), fill="#639397")
        if index == 11:
            d.rectangle((0, 0, 31, 5), fill="#777d78")
            d.line((0, 6, 31, 6), fill="#a2a58f")
    elif index == 13:
        im = tile(0)
        d = ImageDraw.Draw(im)
        d.line((0, 16, 31, 16), fill="#d2ad62")
        for x in [6, 22]:
            d.rectangle((x, 14, x + 2, 18), fill="#a28750")
    elif index == 14:
        d.rectangle((0, 0, 31, 31), fill="#777d78")
        for y in [0, 8, 16, 24]:
            d.rectangle((0, y, 31, y + 2), fill="#a2a58f")
            d.line((0, y + 7, 31, y + 7), fill="#4c5956")
    return im


def tiles():
    atlas = Image.new("RGBA", (128, 128))
    for i in range(16):
        atlas.paste(tile(i), (i % 4 * 32, i // 4 * 32))
    save(atlas, "tiles/academy-tiles.png")
    lines = ['[gd_resource type="TileSet" load_steps=3 format=3]', '', '[ext_resource type="Texture2D" path="res://assets/tiles/academy-tiles.png" id="1"]', '', '[sub_resource type="TileSetAtlasSource" id="Atlas"]', 'texture = ExtResource("1")', 'texture_region_size = Vector2i(32, 32)']
    for i in range(16):
        lines += [f'{i % 4}:{i // 4}/0 = 0']
    lines += ['', '[resource]', 'tile_size = Vector2i(32, 32)', 'sources/0 = SubResource("Atlas")', '']
    (ASSETS / "tiles/academy-tileset.tres").write_text('\n'.join(lines))


def props():
    im = Image.new("RGBA", (32, 48))
    d = ImageDraw.Draw(im)
    d.rectangle((14, 17, 17, 42), fill=OUTLINE)
    d.line((15, 18, 15, 42), fill="#75513a")
    d.rectangle((9, 42, 22, 46), fill=OUTLINE)
    d.line((11, 43, 20, 43), fill="#a2a58f")
    d.polygon([(8, 7), (23, 7), (25, 10), (6, 10)], fill=OUTLINE)
    d.rectangle((9, 11, 22, 22), fill="#d2ad62")
    d.rectangle((11, 12, 20, 20), fill="#f2d28b")
    d.line((15, 11, 15, 22), fill="#75513a")
    d.rectangle((8, 22, 23, 24), fill=OUTLINE)
    d.line((10, 23, 21, 23), fill="#d2ad62")
    save(im, "props/brass-lamp.png")

    im = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(im)
    d.rectangle((3, 4, 60, 59), fill=OUTLINE)
    d.rectangle((5, 6, 58, 57), fill="#49352c")
    for y in [7, 22, 37]:
        for j, col in enumerate(["#4e6650", "#75513a", "#52637a", "#7b8c57", "#777d78", "#77545c"]):
            x = 8 + j * 8
            d.rectangle((x, y, x + 5, y + 11 - j % 3), fill=col)
            d.line((x + 1, y + 2, x + 4, y + 2), fill="#d2ad62")
        d.rectangle((5, y + 13, 58, y + 15), fill="#75513a")
        d.line((6, y + 13, 57, y + 13), fill="#a28750")
    save(im, "props/oak-bookshelf.png")

    im = Image.new("RGBA", (96, 96))
    d = ImageDraw.Draw(im)
    d.polygon([(0, 95), (0, 26), (8, 16), (24, 4), (39, 0), (56, 0), (72, 4), (88, 16), (95, 26), (95, 95), (80, 95), (80, 33), (70, 22), (56, 16), (39, 16), (25, 22), (15, 33), (15, 95)], fill=OUTLINE)
    d.polygon([(2, 94), (2, 27), (10, 18), (25, 6), (40, 2), (55, 2), (71, 6), (86, 18), (93, 27), (93, 94), (82, 94), (82, 32), (71, 20), (56, 14), (39, 14), (24, 20), (13, 32), (13, 94)], fill="#777d78")
    for y in [40, 56, 72, 88]:
        d.line((2, y, 13, y), fill="#4c5956")
        d.line((82, y, 93, y), fill="#4c5956")
        d.line((3, y + 1, 12, y + 1), fill="#a2a58f")
    for a, b in [((11, 17), (22, 24)), ((28, 5), (32, 17)), ((48, 2), (48, 13)), ((67, 5), (63, 17)), ((85, 17), (75, 24))]:
        d.line((*a, *b), fill="#4c5956")
    d.rectangle((41, 3, 54, 12), fill="#49352c")
    d.line((43, 6, 52, 9), fill="#d2ad62")
    d.line((43, 9, 52, 6), fill="#d2ad62")
    for x, y in [(3, 22), (3, 31), (87, 52), (90, 59)]:
        d.rectangle((x, y, x + 3, y + 3), fill="#4e6650")
        d.point((x + 1, y), fill="#7b8c57")
    save(im, "props/stone-arch.png")

    im = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(im)
    d.rectangle((3, 7, 28, 27), fill=OUTLINE)
    d.rectangle((4, 8, 27, 25), fill="#75513a")
    d.rectangle((5, 5, 26, 9), fill="#a28750")
    d.line((5, 13, 26, 13), fill="#49352c")
    for x in [7, 23]:
        d.rectangle((x, 7, x + 2, 25), fill="#49352c")
        d.point((x + 1, 11), fill="#d2ad62")
    d.rectangle((14, 12, 17, 16), fill="#d2ad62")
    save(im, "props/parts-crate.png")


def main():
    characters()
    tiles()
    props()
    manifest = {
        "version": "0.1", "tile_size": [32, 32], "filter": "nearest",
        "characters": {"frame": [32, 40], "sheet": [128, 160], "rows": ["down", "left", "right", "up"], "columns": ["idle", "step_a", "neutral", "step_b"], "feet_pixel": [16, 38], "sprite_offset": [0, -10], "walk_fps": 6, "names": ["apprentice", "danu"]},
        "tiles": {name: [i % 4, i // 4] for i, name in enumerate(TILE_NAMES)},
        "props": {"brass-lamp": {"size": [32, 48], "ground_pixel": [16, 46]}, "oak-bookshelf": {"size": [64, 64], "ground_pixel": [32, 58]}, "stone-arch": {"size": [96, 96], "ground_pixel": [48, 95]}, "parts-crate": {"size": [32, 32], "ground_pixel": [16, 27]}},
        "collision": "Existing gameplay geometry remains authoritative; resources add no collision polygons.",
        "portrait": "Unmodified image-generation master, displayed inside a 256px UI region; not used as a sprite sheet.",
    }
    (ASSETS / "academy-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print("Wrote academy pixels, SpriteFrames, TileSet and manifest to", ASSETS)


if __name__ == "__main__":
    main()
