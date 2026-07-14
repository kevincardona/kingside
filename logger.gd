extends Node
func _ready():
    var f = FileAccess.open("user://test_output.txt", FileAccess.WRITE)
    f.store_string("HELLO FROM LOGGER\n")
    f.store_string("Has singleton ChessEngine: " + str(Engine.has_singleton("ChessEngine")) + "\n")
    if Engine.has_singleton("ChessEngine"):
        var s = Engine.get_singleton("ChessEngine")
        f.store_string("Singleton class: " + str(s.get_class()) + "\n")
        var ok = s.call("start")
        f.store_string("start() returned: " + str(ok) + "\n")
        if ok:
            var mv = s.call("bestmove", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 800)
            f.store_string("bestmove: " + str(mv) + "\n")
            s.call("shutdown")
    f.close()
    get_tree().quit()
