extends SceneTree
## Regenerates res://default_bus_layout.tres from AudioBusSetup.build():
##     bash tools/gd script res://audio/tools/make_bus_layout.gd


func _initialize() -> void:
	var err := AudioBusSetup.save_layout()
	if err != OK:
		push_error("make_bus_layout: save failed (%s)" % error_string(err))
		quit(1)
		return
	var names: Array[String] = []
	for i: int in AudioServer.bus_count:
		names.append("%s->%s[%d fx]" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i), AudioServer.get_bus_effect_count(i)])
	print("wrote res://default_bus_layout.tres: ", ", ".join(names))
	quit(0)
