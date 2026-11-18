extends ODTest
## WebCompat: the world shaders' instance uniforms become plain uniforms that still compile.


func test_demotes_instance_uniforms_and_keeps_hints_and_defaults() -> void:
	var src := "instance uniform vec4 instance_tint : source_color, instance_index(0) = vec4(1.0);\ninstance uniform float instance_energy : instance_index(5) = 1.0;\n"
	var out := WebCompat.demote_instance_uniforms(src)
	assert_false(out.contains("instance"+" uniform"), "no instance uniforms left")
	assert_false(out.contains("instance_index"), "no instance_index hints left")
	assert_true(out.contains("uniform vec4 instance_tint : source_color = vec4(1.0);"), out)
	assert_true(out.contains("uniform float instance_energy = 1.0;"), out)


func test_every_world_shader_still_compiles_after_demotion() -> void:
	for path: String in WebCompat.WORLD_SHADERS:
		var orig := load(path) as Shader
		assert_true(orig != null, path)
		var sh := Shader.new()
		sh.code = WebCompat.demote_instance_uniforms(WebCompat.inline_includes(orig.code))
		var decl := RegEx.create_from_string(r"(?m)^\s*instance\s+uniform\s")
		assert_true(decl.search(sh.code) == null, "%s has no instance uniform declarations left" % path)
		assert_true(sh.get_shader_uniform_list().size() > 0, "%s exposes its uniforms after demotion" % path)


func test_set_param_on_desktop_is_an_instance_parameter() -> void:
	var mi := MeshInstance3D.new()
	WebCompat.set_param(mi, &"instance_tint", Color.RED)
	assert_eq(mi.get_instance_shader_parameter(&"instance_tint"), Color.RED)
	mi.free()
