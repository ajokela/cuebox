extends RefCounted

# A data-only checkpoint format. No Object, resource, script or engine-native
# deserializer is used here. Product validators own gameplay semantics.
# `state.fields` is ordinary JSON (positions are [x,y]); `state.types` records
# only exceptional numeric/point types at exact paths, without reserved keys
# in the player's world dictionaries. An integer never silently becomes float.
const SCHEMA := 2
# A host chooses its own namespace. Exact equality on decode still prevents
# one game's checkpoints being accepted by another; unsafe path segments fail.
static func valid_scope(value: String) -> bool:
	if value.is_empty() or value.length()>64: return false
	for c in value:
		if not (c in "abcdefghijklmnopqrstuvwxyz0123456789_-"): return false
	return true
const MAX_BYTES := 2097152
const MAX_NODES := 60000
const MAX_DEPTH := 48
const SAFE_INT := 9007199254740991
const MAX_GENERATION := 2147483647
var error := ""
var _nodes := 0
var _types := {}
var _used := {}

func _reset() -> void:
	error = ""
	_nodes = 0
	_types = {}
	_used = {}

func _bad(message := "unreadable"):
	if error.is_empty(): error = message
	return null

func _visit(depth: int) -> bool:
	_nodes += 1
	if depth > MAX_DEPTH or _nodes > MAX_NODES:
		_bad()
		return false
	return error.is_empty()

static func integer(value, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _id(value) -> bool:
	return value is String and value.length() > 0 and value.length() <= 160

func _parse(text: String):
	if text.to_utf8_buffer().size() > MAX_BYTES: return _bad()
	var json := JSON.new()
	if json.parse(text) != OK: return _bad()
	return json.data

func encode(envelope: Dictionary) -> String:
	_reset()
	if not envelope.get("state") is Dictionary:
		_bad(); return ""
	var out := envelope.duplicate(true)
	var fields = _encode_value(out["state"], [], 0)
	if not error.is_empty(): return ""
	out["state"] = {"fields":fields, "types":_types.duplicate(true)}
	var text := JSON.stringify(out, "\t", true, true)
	# The writer and reader share one acceptance contract before any I/O.
	var decoded := decode(text, str(envelope.get("scope", "")), int(envelope.get("content_revision", 0)))
	return text if decoded.get("status") == "ok" else ""

func decode(text: String, scope: String, revision: int) -> Dictionary:
	_reset()
	var envelope = _parse(text)
	if not envelope is Dictionary: return {"status":"unreadable"}
	if not integer(envelope.get("schema_version"), 1, MAX_GENERATION): return {"status":"unreadable"}
	if envelope["schema_version"] > SCHEMA: return {"status":"newer"}
	if envelope["schema_version"] != SCHEMA: return {"status":"unsupported"}
	if not valid_scope(scope) or envelope.get("scope") != scope: return {"status":"wrong_scope"}
	if not integer(envelope.get("content_revision"), 1, MAX_GENERATION): return {"status":"unreadable"}
	if envelope["content_revision"] > revision: return {"status":"newer"}
	if envelope["content_revision"] != revision: return {"status":"unsupported"}
	if not _id(envelope.get("build_id")) or not _id(envelope.get("run_id")) or not integer(envelope.get("generation"), 1, MAX_GENERATION):
		return {"status":"unreadable"}
	if not envelope.get("meta") is Dictionary or not envelope.get("source_revision", {}) is Dictionary:
		return {"status":"unreadable"}
	var state = envelope.get("state")
	if not state is Dictionary or state.size()!=2 or not state.get("fields") is Dictionary or not state.get("types") is Dictionary:
		return {"status":"unreadable"}
	_types = state["types"]
	if _types.size() > MAX_NODES: return {"status":"unreadable"}
	for path in _types:
		if not path is String or _types[path] not in ["point", "float", "int64"]: return {"status":"unreadable"}
	var raw = _decode_value(state["fields"], [], 0)
	if not error.is_empty() or _used.size()!=_types.size(): return {"status":"unreadable"}
	envelope["state"] = raw
	for key in ["schema_version", "content_revision", "generation"]: envelope[key] = int(envelope[key])
	return {"status":"ok", "envelope":envelope}

func _encode_value(value, path: Array, depth: int):
	if not _visit(depth): return null
	var address := JSON.stringify(path)
	if value is Vector2:
		if not value.is_finite(): return _bad()
		_types[address] = "point"
		return [value.x, value.y]
	if value is float:
		if not is_finite(value): return _bad()
		_types[address] = "float"
		return value
	if value is int:
		if value > SAFE_INT or value < -SAFE_INT:
			_types[address] = "int64"
			return str(value)
		return value
	if value is String or value is bool or value == null: return value
	if value is Array:
		var out := []
		for i in value.size(): out.append(_encode_value(value[i], path+[i], depth+1))
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			if not key is String: return _bad()
			out[key] = _encode_value(value[key], path+[key], depth+1)
		return out
	return _bad()

func _decode_value(value, path: Array, depth: int):
	if not _visit(depth): return null
	var address := JSON.stringify(path)
	if _types.has(address):
		_used[address] = true
		match _types[address]:
			"point":
				if not value is Array or value.size()!=2 or not _number(value[0]) or not _number(value[1]): return _bad()
				var point := Vector2(value[0], value[1])
				return point if point.is_finite() else _bad()
			"float":
				return float(value) if _number(value) else _bad()
			"int64":
				return _integer_string(value)
	if value is String or value is bool or value == null: return value
	if value is int or value is float:
		return int(value) if integer(value, -SAFE_INT, SAFE_INT) else _bad()
	if value is Array:
		var out := []
		for i in value.size(): out.append(_decode_value(value[i], path+[i], depth+1))
		return out
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = _decode_value(value[key], path+[key], depth+1)
		return out
	return _bad()

func _integer_string(value):
	if not value is String or not value.is_valid_int(): return _bad()
	var digits: String = value.trim_prefix("-")
	var limit := "9223372036854775808" if value.begins_with("-") else "9223372036854775807"
	if digits.length()>19 or (digits.length()==19 and digits>limit): return _bad()
	var parsed: int = value.to_int()
	return parsed if str(parsed)==value else _bad() # catches overflow and noncanonical integers

# Decode only the historical JSON.from_native forms that saves actually use.
# The embedded state version is mandatory; unknown wrappers never call Godot's
# deserializer. Original bytes remain the migration source, not this dictionary.
func legacy(text: String) -> Dictionary:
	_reset()
	var envelope = _parse(text)
	if not envelope is Dictionary or not envelope.get("state") is Dictionary or not envelope.get("meta", {}) is Dictionary:
		return {"status":"unreadable"}
	var raw = _legacy_value(envelope["state"], 0)
	if not error.is_empty() or not raw is Dictionary: return {"status":"unreadable"}
	if not raw.get("version") is int: return {"status":"unreadable"}
	if raw["version"] > 1: return {"status":"newer"}
	if raw["version"] != 1: return {"status":"unsupported"}
	return {"status":"ok", "state":raw, "meta":envelope.get("meta", {})}

func _legacy_value(value, depth: int):
	if not _visit(depth): return null
	if value is bool or value==null: return value
	if value is String:
		if value.begins_with("s:"): return value.substr(2)
		if value.begins_with("i:"): return _integer_string(value.substr(2))
		if value.begins_with("f:"):
			var number: String = value.substr(2)
			if not number.is_valid_float(): return _bad()
			var parsed: float = number.to_float()
			return parsed if is_finite(parsed) else _bad()
		return _bad()
	if value is Array:
		var out := []
		for entry in value: out.append(_legacy_value(entry, depth+1))
		return out
	if not value is Dictionary or value.size()!=2 or not value.get("args") is Array: return _bad()
	var args: Array = value["args"]
	if value.get("type")=="Vector2":
		if args.size()!=2 or not _number(args[0]) or not _number(args[1]): return _bad()
		var point := Vector2(args[0], args[1])
		return point if point.is_finite() else _bad()
	if value.get("type")!="Dictionary" or args.size()%2!=0: return _bad()
	var out := {}
	for i in range(0, args.size(), 2):
		var key = _legacy_value(args[i], depth+1)
		if not key is String or out.has(key): return _bad()
		out[key] = _legacy_value(args[i+1], depth+1)
	return out
