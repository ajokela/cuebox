extends RefCounted
# A logical source position within one stable authored line. Geometry and
# rendered page numbers never enter the checkpoint. Changed copy/language
# replays only this line's presentation, never its gameplay transaction.
const VERSION:=1
const LIMIT:=1048576

static func start(line: String) -> Dictionary:
	return {"version":VERSION,"line":line,"section":"","offset":0,"locale":"","source":""}

static func valid(value, line: String) -> bool:
	if not value is Dictionary or value.size()!=6: return false
	if not value.get("version") is int or value["version"]!=VERSION or value.get("line")!=line or line=="": return false
	if not value.get("offset") is int or value["offset"]<0 or value["offset"]>LIMIT: return false
	for key in ["line","section","locale","source"]:
		if not value.get(key) is String: return false
	if line.length()>160 or value["section"].length()>96 or value["locale"].length()>64: return false
	if value["source"]=="": return value["section"]=="" and value["offset"]==0 and value["locale"]==""
	if value["source"].length()!=64 or value["section"]=="" or value["locale"]=="": return false
	for c in value["source"]:
		if not c in "0123456789abcdef": return false
	return true

static func at(line: String, position: Dictionary, source: String, locale: String) -> Dictionary:
	if position.is_empty(): return start(line)
	return {"version":VERSION,"line":line,"section":position["id"],"offset":position["offset"],"locale":locale,"source":source.sha256_text()}

static func anchor(value, line: String, source: String, locale: String) -> Dictionary:
	if not valid(value,line) or value["source"]!=source.sha256_text() or value["locale"]!=locale: return {}
	return {"id":value["section"],"offset":value["offset"]}
