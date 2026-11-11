extends RefCounted
const Ink=preload("res://engine/reading_ink.gd")

# A 5x7 capitals font drawn from a texture built at startup, so text is as
# chunky as the art. Each glyph is five pixels wide and seven rows tall, rows
# 0-6, written as its rows from the top. An accented capital is a "tall"
# glyph of eight rows, -1 to 6: its accent sits in rows -1 and 0 and its body
# is squashed into rows 1-6. Nothing goes above row -1, so at LINE apart an
# accent and its outline stay clear of the letters on the line above. canvas
# is a CanvasItem, or for tests anything with its draw_texture_rect_region.

const ADVANCE := 6
const LINE := 9
const OUTLINE := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

const GLYPHS := {
	"A": ".###. #...# #...# ##### #...# #...# #...#",
	"B": "####. #...# #...# ####. #...# #...# ####.",
	"C": ".###. #...# #.... #.... #.... #...# .###.",
	"D": "####. #...# #...# #...# #...# #...# ####.",
	"E": "##### #.... #.... ####. #.... #.... #####",
	"F": "##### #.... #.... ####. #.... #.... #....",
	"G": ".###. #...# #.... #.### #...# #...# .###.",
	"H": "#...# #...# #...# ##### #...# #...# #...#",
	"I": ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
	"J": "..### ...#. ...#. ...#. #..#. #..#. .##..",
	"K": "#...# #..#. #.#.. ##... #.#.. #..#. #...#",
	"L": "#.... #.... #.... #.... #.... #.... #####",
	"M": "#...# ##.## #.#.# #.#.# #...# #...# #...#",
	"N": "#...# ##..# #.#.# #..## #...# #...# #...#",
	"O": ".###. #...# #...# #...# #...# #...# .###.",
	"P": "####. #...# #...# ####. #.... #.... #....",
	"Q": ".###. #...# #...# #...# #.#.# #..#. .##.#",
	"R": "####. #...# #...# ####. #.#.. #..#. #...#",
	"S": ".#### #.... #.... .###. ....# ....# ####.",
	"T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
	"U": "#...# #...# #...# #...# #...# #...# .###.",
	"V": "#...# #...# #...# #...# #...# .#.#. ..#..",
	"W": "#...# #...# #...# #.#.# #.#.# #.#.# .#.#.",
	"X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
	"Y": "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..",
	"Z": "##### ....# ...#. ..#.. .#... #.... #####",
	"0": ".###. #...# #..## #.#.# ##..# #...# .###.",
	"1": "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
	"2": ".###. #...# ....# ...#. ..#.. .#... #####",
	"3": "####. ....# ....# .###. ....# ....# ####.",
	"4": "...#. ..##. .#.#. #..#. ##### ...#. ...#.",
	"5": "##### #.... ####. ....# ....# #...# .###.",
	"6": "..##. .#... #.... ####. #...# #...# .###.",
	"7": "##### ....# ...#. ..#.. .#... .#... .#...",
	"8": ".###. #...# #...# .###. #...# #...# .###.",
	"9": ".###. #...# #...# .#### ....# ...#. .##..",
	".": "..... ..... ..... ..... ..... .##.. .##..",
	",": "..... ..... ..... ..... .##.. ..#.. .#...",
	"'": "..#.. ..#.. .#... ..... ..... ..... .....",
	"!": "..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..",
	"?": ".###. #...# ....# ...#. ..#.. ..... ..#..",
	"-": "..... ..... ..... .###. ..... ..... .....",
	"—": "..... ..... ..... ##### ..... ..... .....",
	":": "..... .##.. .##.. ..... .##.. .##.. .....",
	"←": "..... ..#.. .#... ##### .#... ..#.. .....",
	"→": "..... ..#.. ...#. ##### ...#. ..#.. .....",
	";": "..... .##.. .##.. ..... .##.. ..#.. .#...",
	"\"": ".#.#. .#.#. ..... ..... ..... ..... .....",
	"(": "...#. ..#.. .#... .#... .#... ..#.. ...#.",
	")": ".#... ..#.. ...#. ...#. ...#. ..#.. .#...",
	"/": "....# ...#. ...#. ..#.. .#... .#... #....",
	"%": "##..# ##.#. ...#. ..#.. .#... .#.## #..##",
	"@": ".###. #...# #.### #.#.# #.### #.... .####",
	# Typographic quotes use the same seven-row box, including low German quotes.
	"„": "..... ..... ..... ..... .#.#. .#.#. #.#..",
	"“": ".#.#. #.#.. #.#.. ..... ..... ..... .....",
	"”": ".#.#. .#.#. #.#.. ..... ..... ..... .....",
	"‚": "..... ..... ..... ..... ..#.. ..#.. .#...",
	"‘": "..#.. .#... .#... ..... ..... ..... .....",
	"’": "..#.. ..#.. .#... ..... ..... ..... .....",
	# Accented capitals: eight rows, -1 to 6, the accent over a body squashed into rows 1-6.
	"À": ".#... ..#.. .###. #...# ##### #...# #...# #...#",
	"Á": "...#. ..#.. .###. #...# ##### #...# #...# #...#",
	"Â": "..#.. .#.#. .###. #...# ##### #...# #...# #...#",
	"Ã": ".##.# #.##. .###. #...# ##### #...# #...# #...#",
	"Ä": ".#.#. ..... .###. #...# ##### #...# #...# #...#",
	"È": ".#... ..#.. ##### #.... ####. #.... #.... #####",
	"É": "...#. ..#.. ##### #.... ####. #.... #.... #####",
	"Ê": "..#.. .#.#. ##### #.... ####. #.... #.... #####",
	"Ë": ".#.#. ..... ##### #.... ####. #.... #.... #####",
	"Ì": ".#... ..#.. .###. ..#.. ..#.. ..#.. ..#.. .###.",
	"Í": "...#. ..#.. .###. ..#.. ..#.. ..#.. ..#.. .###.",
	"Î": "..#.. .#.#. .###. ..#.. ..#.. ..#.. ..#.. .###.",
	"Ï": ".#.#. ..... .###. ..#.. ..#.. ..#.. ..#.. .###.",
	"Ñ": ".##.# #.##. #...# ##..# #.#.# #..## #...# #...#",
	"Ò": ".#... ..#.. .###. #...# #...# #...# #...# .###.",
	"Ó": "...#. ..#.. .###. #...# #...# #...# #...# .###.",
	"Ô": "..#.. .#.#. .###. #...# #...# #...# #...# .###.",
	"Õ": ".##.# #.##. .###. #...# #...# #...# #...# .###.",
	"Ö": ".#.#. ..... .###. #...# #...# #...# #...# .###.",
	"Ù": ".#... ..#.. #...# #...# #...# #...# #...# .###.",
	"Ú": "...#. ..#.. #...# #...# #...# #...# #...# .###.",
	"Û": "..#.. .#.#. #...# #...# #...# #...# #...# .###.",
	"Ü": ".#.#. ..... #...# #...# #...# #...# #...# .###.",
	"Ÿ": ".#.#. ..... #...# #...# .#.#. ..#.. ..#.. ..#..",
	# Seven rows like the rest.
	"Ç": ".###. #...# #.... #...# .###. ..#.. .##..",
	"Œ": ".#### #.#.. #.#.. #.### #.#.. #.#.. .####",
	"¿": "..#.. ..... ..#.. .#... #.... #...# .###.",
	"¡": "..#.. ..... ..#.. ..#.. ..#.. ..#.. ..#..",
	"«": "..... ..... .#.#. #.#.. .#.#. ..... .....",
	"»": "..... ..... .#.#. ..#.# .#.#. ..... .....",
}

static var _texture: ImageTexture
static var _index := {}  # glyph -> its column in the texture
static var _tall := {}  # the glyphs that reach up into row -1


static func has_glyph(ch: String) -> bool:
	return GLYPHS.has(ch)


# True if any glyph in text reaches up into row -1.
static func is_tall(text: String) -> bool:
	_build()
	for ch in text:
		if _tall.has(ch):
			return true
	return false


# Where text's letters can be when drawn at pos: a row higher if it's tall.
static func text_rect(text: String, pos: Vector2, scale: int=1) -> Rect2:
	var up := 1 if is_tall(text) else 0
	return Rect2(pos.x,pos.y-up*scale,maxi(0,text.length()*ADVANCE-1)*scale,(7+up)*scale)


# One line, with a black outline all round unless outline is false.
static func draw_text(canvas, text: String, pos: Vector2, color: Color, outline := true, scale: int=1) -> void:
	draw_lines(canvas, [[text, pos]], color, outline,scale)


# A block of lines, [[text, pos], ...], in two passes: every line's outline,
# then every line's letters, so no outline can cover a neighbour's letters.
static func draw_lines(canvas, placed: Array, color: Color, outline := true, scale: int=1) -> void:
	_build()
	color=Ink.paper(canvas,color)
	if outline:
		for p in placed:
			for offset in OUTLINE:
				_draw_run(canvas,p[0],p[1]+offset*scale,Color.BLACK,scale)
	for p in placed:
		_draw_run(canvas,p[0],p[1],color,scale)


# Breaks text at spaces into lines of at most max_chars. A word longer than a
# whole line (German has plenty) is broken too, every piece but its last
# ending in "-".
static func wrap(text: String, max_chars: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		if word.length() > max_chars:
			if line != "":
				lines.append(line)
			var rest: String = word
			var piece := maxi(max_chars - 1, 1)
			while rest.length() > max_chars:
				lines.append(rest.left(piece) + "-")
				rest = rest.substr(piece)
			line = rest
		elif line == "":
			line = word
		elif line.length() + 1 + word.length() <= max_chars:
			line += " " + word
		else:
			lines.append(line)
			line = word
	if line != "":
		lines.append(line)
	return lines


static func _draw_run(canvas, text: String, pos: Vector2, color: Color, scale: int=1) -> void:
	var x := pos.x
	for ch in text:
		if _index.has(ch):
			var i: int = _index[ch]
			if _tall.has(ch):
				canvas.draw_texture_rect_region(_texture, Rect2(x,pos.y-scale,5*scale,8*scale), Rect2(i * ADVANCE, 0, 5, 8), color)
			else:
				canvas.draw_texture_rect_region(_texture, Rect2(x,pos.y,5*scale,7*scale), Rect2(i * ADVANCE, 1, 5, 7), color)
		x += ADVANCE*scale


# The texture: a column per glyph, eight rows: row -1 on top, then 0-6.
static func _build() -> void:
	if _texture != null:
		return
	var keys := GLYPHS.keys()
	var image := Image.create(keys.size() * ADVANCE, 8, false, Image.FORMAT_RGBA8)
	for i in keys.size():
		var rows: PackedStringArray = GLYPHS[keys[i]].split(" ")
		var top := 8 - rows.size()  # a tall glyph starts in row -1, the others in row 0
		for y in rows.size():
			for x in 5:
				if rows[y][x] == "#":
					image.set_pixel(i * ADVANCE + x, top + y, Color.WHITE)
		_index[keys[i]] = i
		if rows.size() == 8:
			_tall[keys[i]] = true
	_texture = ImageTexture.create_from_image(image)
