extends Button

# This helper script ensures that drag gestures (scrolling) are passed up to 
# the ScrollContainer even if the touch starts on a Button.

var _pressed_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false
const DRAG_THRESHOLD = 10.0

func _ready() -> void:
	# Ensure the button itself doesn't stop events by default
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	# Handle both Mouse and Touch events for cross-platform reliability
	var pos = Vector2.ZERO
	var is_drag_event = false
	var is_press_event = false
	var is_release_event = false

	if event is InputEventMouseButton:
		pos = event.position
		is_press_event = event.pressed
		is_release_event = not event.pressed
	elif event is InputEventMouseMotion:
		pos = event.position
		is_drag_event = (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	elif event is InputEventScreenTouch:
		pos = event.position
		is_press_event = event.pressed
		is_release_event = not event.pressed
	elif event is InputEventScreenDrag:
		pos = event.position
		is_drag_event = true

	if is_press_event:
		_pressed_pos = pos
		_dragging = false

	if is_drag_event and not _dragging:
		if pos.distance_to(_pressed_pos) > DRAG_THRESHOLD:
			_dragging = true
			# We are scrolling: cancel the in-progress press so releasing the
			# finger over the button doesn't click it. Toggling disabled resets
			# BaseButton's internal press attempt; re-enable next frame.
			disabled = true
			set_deferred("disabled", false)

	if is_release_event:
		_dragging = false
	# Note: no super call — Button's own input handling runs natively in
	# addition to this script override (and super._gui_input() does not
	# compile for native virtuals in Godot 4).
