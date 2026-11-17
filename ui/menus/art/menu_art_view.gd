class_name MenuArtView
extends Control
## A Control that draws one MenuArt painter scaled (aspect-fit, centred) into its rect. Animated
## painters redraw every frame while visible.

## func(ci: CanvasItem, time: float, view: MenuArtView) -> void
var painter: Callable
var view_box: Vector2 = Vector2(24, 24)
var animated: bool = false
## Transform from view-box units to this Control's local space (valid inside the painter).
var base: Transform2D = Transform2D.IDENTITY

## Painter parameters.
var slot: StringName = &""
var tape: int = 0
var on: bool = true
var patterns: bool = false
var tint: Color = MenuStyle.PAPER

var _time: float = 0.0


static func make(p_painter: Callable, p_box: Vector2, min_size: Vector2, p_animated: bool = false) -> MenuArtView:
	var v := MenuArtView.new()
	v.painter = p_painter
	v.view_box = p_box
	v.animated = p_animated
	v.custom_minimum_size = min_size
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func icon(p_painter: Callable, px: float, col: Color) -> MenuArtView:
	var v := make(p_painter, MenuArt.ICON_BOX, Vector2(px, px))
	v.tint = col
	return v


static func cassette(p_tape: int, p_on: bool, p_patterns: bool, width: float = 30.0) -> MenuArtView:
	var v := make(Callable(MenuArt, "paint_cassette"), MenuArt.CASSETTE_BOX, Vector2(width, width * MenuArt.CASSETTE_BOX.y / MenuArt.CASSETTE_BOX.x))
	v.tape = p_tape
	v.on = p_on
	v.patterns = p_patterns
	return v


func _ready() -> void:
	set_process(animated)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	if not painter.is_valid() or view_box.x <= 0.0 or view_box.y <= 0.0:
		return
	var s := minf(size.x / view_box.x, size.y / view_box.y)
	var off := (size - view_box * s) * 0.5
	base = Transform2D(0.0, Vector2(s, s), 0.0, off)
	draw_set_transform_matrix(base)
	painter.call(self, _time, self)
	draw_set_transform_matrix(Transform2D.IDENTITY)
