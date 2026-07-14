extends SceneTree

const GREEN := Color("#7FA650")
const GREEN_DARK := Color("#4F7136")
const BG := Color("#111512")
const CARD := Color("#1E241F")
const CARD2 := Color("#293128")
const TEXT := Color("#F0F1EC")
const GOLD := Color("#E9B949")

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/brand")
	DirAccess.make_dir_recursive_absolute("res://Chess/Images.xcassets/AppIcon.appiconset")
	DirAccess.make_dir_recursive_absolute("res://Chess/Images.xcassets/SplashImage.imageset")
	_write_icon_set()
	_write_android_icons()
	_write_splash()
	quit()

func _write_icon_set() -> void:
	var sizes = {
		"Icon-40.png": 40, "Icon-58.png": 58, "Icon-60.png": 60,
		"Icon-76.png": 76, "Icon-80.png": 80, "Icon-87.png": 87,
		"Icon-114.png": 114, "Icon-120.png": 120, "Icon-120-1.png": 120,
		"Icon-128.png": 128, "Icon-136.png": 136, "Icon-152.png": 152,
		"Icon-167.png": 167, "Icon-180.png": 180, "Icon-192.png": 192,
		"Icon-1024.png": 1024,
	}
	for name in sizes.keys():
		var img = _make_icon(int(sizes[name]))
		img.save_png("res://Chess/Images.xcassets/AppIcon.appiconset/" + name)
		if name == "Icon-1024.png":
			img.save_png("res://assets/brand/app_icon_1024.png")

func _write_android_icons() -> void:
	_make_icon(192).save_png("res://assets/brand/android_icon_192.png")
	_make_icon(432).save_png("res://assets/brand/android_adaptive_foreground_432.png")
	_make_flat(Color("#121812"), 432).save_png("res://assets/brand/android_adaptive_background_432.png")
	_make_icon(432, true).save_png("res://assets/brand/android_adaptive_monochrome_432.png")

func _write_splash() -> void:
	_make_splash(750, 1334).save_png("res://Chess/Images.xcassets/SplashImage.imageset/splash@2x.png")
	_make_splash(1125, 2001).save_png("res://Chess/Images.xcassets/SplashImage.imageset/splash@3x.png")
	_make_splash(1125, 2001).save_png("res://assets/brand/splash.png")

func _make_flat(color: Color, size: int) -> Image:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img

func _make_icon(size: int, mono: bool = false) -> Image:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE if mono else BG)
	var bg_col = Color.WHITE if mono else BG
	var tile_col = Color.BLACK if mono else GREEN_DARK
	var piece_col = Color.BLACK if mono else TEXT
	_round_rect(img, Rect2i(0, 0, size, size), size * 0.18, bg_col)
	_round_rect(img, Rect2i(size * 0.07, size * 0.07, size * 0.86, size * 0.86), size * 0.13, CARD if not mono else Color.WHITE)
	var board = Rect2i(size * 0.16, size * 0.16, size * 0.68, size * 0.68)
	_round_rect(img, board, size * 0.06, CARD2 if not mono else Color.WHITE)
	var sq = board.size.x / 4.0
	for y in 4:
		for x in 4:
			if (x + y) % 2 == 0:
				_rect(img, Rect2i(board.position.x + int(x * sq), board.position.y + int(y * sq), int(ceil(sq)), int(ceil(sq))), tile_col)
	_draw_knight(img, Vector2(size * 0.50, size * 0.55), size * 0.48, piece_col, mono)
	return img

func _make_splash(w: int, h: int) -> Image:
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for y in h:
		var t = float(y) / float(h)
		var c = BG.lerp(Color("#182018"), t * 0.7)
		for x in w:
			img.set_pixel(x, y, c)
	var icon_size = int(min(w, h) * 0.28)
	var icon = _make_icon(icon_size)
	_blit(img, icon, Vector2i((w - icon_size) / 2, int(h * 0.40) - icon_size / 2))
	_draw_word(img, "CHESS", Vector2i(w / 2, int(h * 0.58)), int(w * 0.075), TEXT)
	_draw_word(img, "STOCKFISH TRAINING", Vector2i(w / 2, int(h * 0.64)), int(w * 0.033), Color("#B7BBAF"))
	return img

func _draw_knight(img: Image, center: Vector2, scale: float, color: Color, mono: bool) -> void:
	var s = scale
	var pts = PackedVector2Array([
		center + Vector2(-0.30*s, 0.36*s),
		center + Vector2(0.30*s, 0.36*s),
		center + Vector2(0.23*s, 0.20*s),
		center + Vector2(0.34*s, 0.02*s),
		center + Vector2(0.15*s, -0.08*s),
		center + Vector2(0.08*s, -0.34*s),
		center + Vector2(-0.22*s, -0.12*s),
		center + Vector2(-0.05*s, 0.07*s),
		center + Vector2(-0.25*s, 0.23*s),
	])
	_poly(img, pts, color)
	_round_rect(img, Rect2i(center.x - 0.38*s, center.y + 0.38*s, 0.76*s, 0.10*s), 0.03*s, color)
	if not mono:
		_circle(img, center + Vector2(0.15*s, -0.10*s), max(2, int(0.035*s)), BG)

func _draw_word(img: Image, text: String, center: Vector2i, px: int, color: Color) -> void:
	var glyphs = _glyphs()
	var tracking = max(2, int(px * 0.22))
	var total = 0
	for ch in text:
		total += (3 * px / 5 if ch != " " else px / 2) + tracking
	var x = center.x - total / 2
	for ch in text:
		if ch == " ":
			x += px / 2 + tracking
			continue
		var pattern = glyphs.get(ch, [])
		for row in pattern.size():
			for col in pattern[row].length():
				if pattern[row][col] == "1":
					_rect(img, Rect2i(x + col * px / 5, center.y - px / 2 + row * px / 7, px / 5 + 1, px / 7 + 1), color)
		x += 3 * px / 5 + tracking

func _glyphs() -> Dictionary:
	return {
		"C": ["111","100","100","100","100","100","111"],
		"H": ["101","101","101","111","101","101","101"],
		"E": ["111","100","100","111","100","100","111"],
		"S": ["111","100","100","111","001","001","111"],
		"T": ["111","010","010","010","010","010","010"],
		"O": ["111","101","101","101","101","101","111"],
		"K": ["101","101","110","100","110","101","101"],
		"F": ["111","100","100","111","100","100","100"],
		"I": ["111","010","010","010","010","010","111"],
		"R": ["110","101","101","110","101","101","101"],
		"A": ["010","101","101","111","101","101","101"],
		"N": ["101","111","111","111","111","111","101"],
		"G": ["111","100","100","101","101","101","111"],
	}

func _rect(img: Image, rect: Rect2i, color: Color) -> void:
	for y in range(max(0, rect.position.y), min(img.get_height(), rect.position.y + rect.size.y)):
		for x in range(max(0, rect.position.x), min(img.get_width(), rect.position.x + rect.size.x)):
			img.set_pixel(x, y, color)

func _round_rect(img: Image, rect: Rect2i, radius: int, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var dx = max(rect.position.x + radius - x, 0, x - (rect.position.x + rect.size.x - radius - 1))
			var dy = max(rect.position.y + radius - y, 0, y - (rect.position.y + rect.size.y - radius - 1))
			if dx * dx + dy * dy <= radius * radius:
				if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
					img.set_pixel(x, y, color)

func _circle(img: Image, c: Vector2, r: int, color: Color) -> void:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if Vector2(x, y).distance_to(c) <= r and x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, color)

func _poly(img: Image, pts: PackedVector2Array, color: Color) -> void:
	var min_x = int(pts[0].x); var max_x = min_x; var min_y = int(pts[0].y); var max_y = min_y
	for p in pts:
		min_x = min(min_x, int(p.x)); max_x = max(max_x, int(p.x))
		min_y = min(min_y, int(p.y)); max_y = max(max_y, int(p.y))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _inside_poly(Vector2(x + 0.5, y + 0.5), pts) and x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, color)

func _inside_poly(p: Vector2, pts: PackedVector2Array) -> bool:
	var inside = false
	var j = pts.size() - 1
	for i in pts.size():
		if ((pts[i].y > p.y) != (pts[j].y > p.y)) and (p.x < (pts[j].x - pts[i].x) * (p.y - pts[i].y) / (pts[j].y - pts[i].y) + pts[i].x):
			inside = not inside
		j = i
	return inside

func _blit(dst: Image, src: Image, pos: Vector2i) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c = src.get_pixel(x, y)
			if c.a > 0.0:
				dst.set_pixel(pos.x + x, pos.y + y, c)
