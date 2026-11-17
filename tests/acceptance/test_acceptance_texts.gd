extends ODTest
## Guards the acceptance suite itself: every acceptance row quoted in acceptance_kit.gd still occurs,
## word for word, in docs/requirements.txt (chapter 21, Revision 1, Revision 2), and every id has at
## least one test named after it in tests/acceptance/test_acceptance_*.gd.

const K = preload("res://tests/acceptance/acceptance_kit.gd")


func _doc() -> String:
	var text := FileAccess.get_file_as_string("res://docs/requirements.txt")
	return K.norm(text)


## TEST-xx rows are "ID Check Expected" in the table; NEW-xx is "ID text"; APP-TEST-xx is "ID: text".
func test_acceptance_rows_quote_docs_requirements_literally() -> void:
	var doc := _doc()
	if not assert_false(doc.is_empty(), "docs/requirements.txt readable"):
		return
	for id: String in K.ROWS:
		var row: Array = K.ROWS[id]
		var quoted: String
		if id.begins_with("TEST-"):
			quoted = "%s %s %s" % [id, row[0], row[1]]
		elif id.begins_with("APP-TEST-"):
			quoted = "%s: %s" % [id, row[1]]
		else:
			quoted = "%s %s" % [id, row[1]]
		assert_true(doc.contains(K.norm(quoted)), "%s is not quoted literally from docs/requirements.txt: %s" % [id, quoted])


func test_the_kit_lists_every_acceptance_id_in_the_document() -> void:
	var doc := _doc()
	var re := RegEx.create_from_string("\\b(TEST-\\d\\d|NEW-\\d\\d|APP-TEST-\\d\\d)\\b")
	var seen := {}
	for m: RegExMatch in re.search_all(doc):
		seen[m.get_string(1)] = true
	for id: String in seen:
		# Only the acceptance tables; ids referenced elsewhere in prose are the same set.
		assert_true(K.ROWS.has(id), "%s appears in docs/requirements.txt but has no acceptance row" % id)
	assert_eq(K.ROWS.size(), 34 + 11 + 3)


func test_every_acceptance_id_has_a_named_test() -> void:
	var names: Array[String] = []
	var dir := DirAccess.open("res://tests/acceptance")
	if not assert_true(dir != null, "tests/acceptance readable"):
		return
	var re := RegEx.create_from_string("(?m)^func (test_[A-Za-z0-9_]+)\\(")
	for f: String in dir.get_files():
		if not (f.begins_with("test_acceptance_") and f.ends_with(".gd")):
			continue
		var src := FileAccess.get_file_as_string("res://tests/acceptance/" + f)
		for m: RegExMatch in re.search_all(src):
			names.append(m.get_string(1))
	for id: String in K.ROWS:
		var tag := "test_" + id.replace("-", "") + "_"
		var found := false
		for n: String in names:
			if n.begins_with(tag):
				found = true
				break
		assert_true(found, "no test named %s... for %s" % [tag, id])
