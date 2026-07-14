extends SceneTree

func _init():
	call_deferred("_run")

func _run():
	var vp = SubViewport.new()
	vp.size = Vector2(1024, 1024)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false   # App Store icons must be fully opaque
	root.add_child(vp)

	var drawer = Node2D.new()
	drawer.set_script(preload("res://tools/icon_drawer.gd"))
	vp.add_child(drawer)

	await create_timer(0.5).timeout

	var img = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)   # strip the alpha channel (App Store requirement)
	img.save_png("res://assets/brand/app_icon_1024.png")
	img.save_png("res://assets/brand/splash.png")
	
	print("Icons exported successfully.")
	quit()
