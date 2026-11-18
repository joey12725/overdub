extends GameApp
## OVERDUB's main scene (res://game/main.tscn): the running game. All behaviour lives in GameApp
## (game/app.gd); this script only wires the real modules - the world view, audio and UI scenes at
## their fixed facade paths, real input and the user:// save - when the scene enters the tree.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	WebCompat.apply()
	wire_defaults()
