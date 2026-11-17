class_name DlgPrompts
extends RefCounted
## Button-prompt substitution for coach marks and hints. Node-free.
## "{commit}" -> the bound key text for SessionAction 'commit' ("Enter", "A"...), as pushed to
## UiBase.set_bindings. Unknown names render as their spelled-out action ("{dash}" -> "Dash") so a
## missing binding never shows raw braces. "{{" is a literal brace.

static func substitute(text: String, bindings: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var out := ""
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == "{" and i + 1 < n and text[i + 1] == "{":
			out += "{"
			i += 2
			continue
		if c == "{":
			var j := text.find("}", i + 1)
			if j > i:
				out += label_for(text.substr(i + 1, j - i - 1), bindings)
				i = j + 1
				continue
		out += c
		i += 1
	return out


## `action` may carry ONBOARDING.md's "btn:" prefix ("{btn:commit}").
static func label_for(action: String, bindings: Dictionary) -> String:
	action = action.trim_prefix("btn:")
	var key := StringName(action)
	var p: Variant = bindings.get(key, bindings.get(action, null))
	if p is ButtonPrompt and (p as ButtonPrompt).key != "":
		return (p as ButtonPrompt).key
	if p is String and p != "":
		return p
	return action.capitalize()
