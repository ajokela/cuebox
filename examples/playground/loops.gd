extends RefCounted
# Puts guard.gd's check at the top of every while and for loop in a visitor's file. The page keeps
# their own text; "lines" maps each line of the result back to theirs, so errors still name their
# line numbers. An inline body (while x: y) moves to its own line under the check.
const CHECK := 'if not preload("res://examples/playground/guard.gd").ok("%s", %d): break'
static var _header := RegEx.create_from_string("^([ \\t]*)(while|for)(?![A-Za-z0-9_])")

static func guard(text: String, file: String) -> Dictionary:
	var lines := text.split("\n")
	var out := PackedStringArray()
	var map: Array = []
	var i := 0
	while i < lines.size():
		var m := _header.search(lines[i])
		var end = _header_end(lines, i, m.get_end(), m.get_string(2) == "for") if m != null else null
		if end == null:
			out.append(lines[i])
			map.append(i + 1)
			i += 1
			continue
		var indent := m.get_string(1)
		var check := CHECK % [file, i + 1]
		for k in range(i, end[0]):
			out.append(lines[k])
			map.append(k + 1)
		var last: String = lines[end[0]]
		var rest := last.substr(end[1] + 1)
		if _code(rest).strip_edges() != "":
			var step := "    " if " " in indent else "\t"
			out.append(last.substr(0, end[1] + 1))
			map.append(end[0] + 1)
			out.append(indent + step + check)
			map.append(i + 1)
			out.append(indent + step + rest.strip_edges())
			map.append(end[0] + 1)
			i = end[0] + 1
			continue
		out.append(last)
		map.append(end[0] + 1)
		var j: int = end[0] + 1
		while j < lines.size() and _code(lines[j]).strip_edges() == "":
			out.append(lines[j])
			map.append(j + 1)
			j += 1
		if j < lines.size():
			var body := lines[j].substr(0, lines[j].length() - lines[j].strip_edges(true, false).length())
			if body.length() > indent.length() and body.begins_with(indent):
				out.append(body + check)
				map.append(i + 1)
		i = j   # the body's first line is read next: it may be a loop too
	return {"text": "\n".join(out), "lines": map}

# Where a loop header's own colon is ([line, column]), past brackets, strings, comments, continued
# lines and a for loop's typed variable (for i: int in ...); null when there isn't one.
static func _header_end(lines: PackedStringArray, i: int, col: int, is_for: bool):
	var depth := 0
	var quote := ""
	var need_in := is_for
	var line := i
	var p := col
	while line < lines.size():
		var s: String = lines[line]
		while p < s.length():
			var c := s[p]
			if quote != "":
				if c == "\\":
					p += 2
					continue
				if s.substr(p, quote.length()) == quote:
					p += quote.length()
					quote = ""
					continue
				p += 1
				continue
			if c == "#": break
			if c == '"' or c == "'":
				quote = c.repeat(3) if s.substr(p, 3) == c.repeat(3) else c
				p += quote.length()
				continue
			if c in "([{": depth += 1
			elif c in ")]}": depth -= 1
			elif depth == 0 and need_in and s.substr(p, 2) == "in" and (p == 0 or not _word(s[p - 1])) and (p + 2 >= s.length() or not _word(s[p + 2])):
				need_in = false
				p += 2
				continue
			elif c == ":" and depth == 0 and not need_in:
				return [line, p]
			p += 1
		if quote.length() == 1: quote = ""   # an unclosed string ends with its line
		if depth <= 0 and quote == "" and not _code(s).strip_edges(false, true).ends_with("\\"): return null
		line += 1
		p = 0
	return null

static func _code(s: String) -> String:
	var quote := ""
	var p := 0
	while p < s.length():
		var c := s[p]
		if quote != "":
			if c == "\\":
				p += 2
				continue
			if c == quote: quote = ""
		elif c == '"' or c == "'": quote = c
		elif c == "#": return s.substr(0, p)
		p += 1
	return s

static func _word(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")
