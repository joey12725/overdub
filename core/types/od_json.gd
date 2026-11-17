class_name ODJson
extends RefCounted
## Lenient, typed readers and writers for JSON-shaped Variants (the result of JSON.parse_string).
##
## Every from_dict() in core/types uses these, so a missing key or a value of the wrong type yields
## the documented default instead of a runtime error. Godot parses every JSON number as float; the
## int readers round. Writers produce plain Variants for JSON.stringify; use ODJson.stringify() (full
## float precision) rather than JSON.stringify directly, which rounds doubles to 14 digits.


## d[key] as float, or `def` when absent / not a number.
static func num(d: Dictionary, key: String, def: float = 0.0) -> float:
	var v: Variant = d.get(key)
	if v is float or v is int:
		return float(v)
	return def


## d[key] as int (JSON numbers arrive as float and are rounded), or `def`.
static func integer(d: Dictionary, key: String, def: int = 0) -> int:
	var v: Variant = d.get(key)
	if v is float or v is int:
		return roundi(float(v))
	return def


static func boolean(d: Dictionary, key: String, def: bool = false) -> bool:
	var v: Variant = d.get(key)
	if v is bool:
		return v
	return def


static func string(d: Dictionary, key: String, def: String = "") -> String:
	var v: Variant = d.get(key)
	if v is String or v is StringName:
		return String(v)
	return def


static func sname(d: Dictionary, key: String, def: StringName = &"") -> StringName:
	var v: Variant = d.get(key)
	if v is String or v is StringName:
		return StringName(v)
	return def


## d[key] when it is a Dictionary, else an empty one.
static func dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key)
	if v is Dictionary:
		return v
	return {}


## d[key] when it is an Array, else an empty one.
static func array(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key)
	if v is Array:
		return v
	return []


static func is_number(v: Variant) -> bool:
	return v is float or v is int


static func strings(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x: Variant in v:
			if x is String or x is StringName:
				out.append(String(x))
	return out


static func snames(v: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if v is Array:
		for x: Variant in v:
			if x is String or x is StringName:
				out.append(StringName(x))
	return out


static func floats(v: Variant) -> Array[float]:
	var out: Array[float] = []
	if v is Array:
		for x: Variant in v:
			if x is float or x is int:
				out.append(float(x))
	return out


static func ints(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if v is Array:
		for x: Variant in v:
			if x is float or x is int:
				out.append(roundi(float(x)))
	return out


## {x, y} -> Vector2 (sim axes), or `def` when malformed.
static func vec2(v: Variant, def: Vector2 = Vector2.ZERO) -> Vector2:
	if v is Dictionary:
		var d: Dictionary = v
		return Vector2(num(d, "x", def.x), num(d, "y", def.y))
	return def


static func vec2_to_dict(v: Vector2) -> Dictionary:
	return {"x": v.x, "y": v.y}


## {c, r} -> Vector2i (tile cell).
static func cell(v: Variant) -> Vector2i:
	if v is Dictionary:
		var d: Dictionary = v
		return Vector2i(integer(d, "c"), integer(d, "r"))
	return Vector2i.ZERO


static func cell_to_dict(v: Vector2i) -> Dictionary:
	return {"c": v.x, "r": v.y}


static func strings_to_array(list: Array[String]) -> Array:
	var out: Array = []
	for s: String in list:
		out.append(s)
	return out


static func snames_to_array(list: Array[StringName]) -> Array:
	var out: Array = []
	for s: StringName in list:
		out.append(String(s))
	return out


## Parse JSON text. Returns null and appends a message to `errors` on a syntax error.
static func parse(text: String, errors: Array[String] = [], where: String = "json") -> Variant:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		errors.append("%s: JSON parse error at line %d: %s" % [where, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Read and parse a JSON file (res:// or user://). Returns null and appends to `errors` on failure.
static func read_file(path: String, errors: Array[String] = []) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		errors.append("%s: cannot read (error %d)" % [path, FileAccess.get_open_error()])
		return null
	return parse(text, errors, path)


## JSON text in which every float round-trips exactly (Godot 4.4's JSON.stringify rounds nested floats
## to 15 significant digits even with full_precision). Dictionary keys keep insertion order; packed
## arrays become arrays; non-JSON values (vectors, objects) are written with str() as strings.
static func stringify(data: Variant, indent: String = "") -> String:
	var out := PackedStringArray()
	_write(data, indent, "", out)
	return "".join(out)


## Shortest decimal text that parses back to exactly `f` (integral values keep a ".0").
static func format_float(f: float) -> String:
	if is_nan(f) or is_inf(f):
		return "null"
	var s := str(f)
	if s.to_float() == f and not s.contains("e"):
		return s
	return JSON.stringify(f, "", false, true)


static func _write(v: Variant, indent: String, pad: String, out: PackedStringArray) -> void:
	match typeof(v):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			out.append("true" if v else "false")
		TYPE_INT:
			out.append(str(v))
		TYPE_FLOAT:
			out.append(format_float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			out.append(JSON.stringify(String(v)))
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.is_empty():
				out.append("{}")
				return
			var inner := pad + indent
			out.append("{")
			var first := true
			for k: Variant in d:
				if not first:
					out.append(",")
				first = false
				if not indent.is_empty():
					out.append("\n" + inner)
				out.append(JSON.stringify(str(k)))
				out.append(": " if not indent.is_empty() else ":")
				_write(d[k], indent, inner, out)
			if not indent.is_empty():
				out.append("\n" + pad)
			out.append("}")
		_:
			if _is_list(v):
				var a: Array = Array(v)
				if a.is_empty():
					out.append("[]")
					return
				var inner := pad + indent
				out.append("[")
				for i in a.size():
					if i > 0:
						out.append(",")
					if not indent.is_empty():
						out.append("\n" + inner)
					_write(a[i], indent, inner, out)
				if not indent.is_empty():
					out.append("\n" + pad)
				out.append("]")
			else:
				out.append(JSON.stringify(str(v)))


## Deep JSON-value equality: numbers compare by value (int 1 == float 1.0) within `eps`, Strings and
## StringNames compare by content, Dictionaries by key set (as strings) and values, Arrays in order.
static func deep_equal(a: Variant, b: Variant, eps: float = 0.0) -> bool:
	return first_difference(a, b, eps).is_empty()


## "" when deep_equal(a, b, eps), else a short description of the first difference with its path.
static func first_difference(a: Variant, b: Variant, eps: float = 0.0, path: String = "$") -> String:
	if is_number(a) and is_number(b):
		var fa := float(a)
		var fb := float(b)
		if fa == fb or absf(fa - fb) <= eps:
			return ""
		return "%s: %s != %s" % [path, var_to_str(a), var_to_str(b)]
	if (a is String or a is StringName) and (b is String or b is StringName):
		return "" if String(a) == String(b) else "%s: \"%s\" != \"%s\"" % [path, a, b]
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		var kb := {}
		for k: Variant in db.keys():
			kb[str(k)] = db[k]
		var ka := {}
		for k: Variant in da.keys():
			ka[str(k)] = da[k]
		for k: String in ka.keys():
			if not kb.has(k):
				return "%s.%s: missing on the right" % [path, k]
		for k: String in kb.keys():
			if not ka.has(k):
				return "%s.%s: missing on the left" % [path, k]
		for k: String in ka.keys():
			var d := first_difference(ka[k], kb[k], eps, "%s.%s" % [path, k])
			if not d.is_empty():
				return d
		return ""
	if _is_list(a) and _is_list(b):
		var la: Array = Array(a)
		var lb: Array = Array(b)
		if la.size() != lb.size():
			return "%s: length %d != %d" % [path, la.size(), lb.size()]
		for i in la.size():
			var d := first_difference(la[i], lb[i], eps, "%s[%d]" % [path, i])
			if not d.is_empty():
				return d
		return ""
	if typeof(a) == typeof(b) and a == b:
		return ""
	return "%s: %s != %s" % [path, var_to_str(a), var_to_str(b)]


static func _is_list(v: Variant) -> bool:
	var t := typeof(v)
	return t == TYPE_ARRAY or (t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY)
