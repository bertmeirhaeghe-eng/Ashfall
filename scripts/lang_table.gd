class_name LangTable
extends Translation
## Translation used by the coverage test (--langcheck): same lookups as the
## normal table, but it remembers which strings were asked for and are missing.

var table := {}
var misses := {}


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var m = table.get(src_message)
	if m != null:
		return m
	var s := String(src_message)
	# only real text: letters, not numbers / symbols / ids
	if s.length() > 1 and s.to_lower() != s.to_upper() and (s.contains(" ") or s[0] == s[0].to_upper()):
		misses[s] = true
	return &""


func _get_plural_message(src_message: StringName, _src_plural: StringName, _n: int, context: StringName) -> StringName:
	return _get_message(src_message, context)
