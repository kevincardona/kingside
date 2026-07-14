extends Node

func _ready():
    print("=== TEST START ===")
    print("Has class ChessEngine: ", ClassDB.class_exists("ChessEngine"))
    if ClassDB.class_exists("ChessEngine"):
        var s = ClassDB.instantiate("ChessEngine")
        print("Instance created: ", s != null)
        if s != null:
            var ok = s.call("start")
            print("start() returned: ", ok)
            if ok:
                var mv = s.call("bestmove", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 800)
                print("bestmove: ", mv)
                s.call("shutdown")
    print("=== TEST END ===")
    get_tree().quit()
