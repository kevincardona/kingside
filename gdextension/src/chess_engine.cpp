// chess_engine.cpp
//
// Thin GDExtension wrapper around Stockfish's `Engine` class. We link the
// Stockfish source directly so the engine runs in-process — that works on
// iOS and Android where spawning a child process is forbidden by the
// platform sandbox.
//
// Public API (registered as a Godot class "ChessEngine"):
//   start()                                 -> bool
//   bestmove(fen: String, movetime_ms: int) -> String   ("" on failure)
//   eval_cp(fen: String)                    -> int      (centipawns, side-to-move POV)
//   set_option(name: String, value: String) -> bool
//   shutdown()

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <exception>
#include <fstream>
#include <optional>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <type_traits>
#include <vector>

#include "engine.h"
#include "bitboard.h"
#include "misc.h"
#include "position.h"
#include "score.h"
#include "search.h"
#include "thread.h"
#include "types.h"
#include "speech_input.hpp"
#include "game_center.hpp"

using namespace godot;

class ChessEngine : public RefCounted {
    GDCLASS(ChessEngine, RefCounted)

public:
    ChessEngine() {}
    ~ChessEngine() override { shutdown(); }

    bool start() {
        std::lock_guard<std::mutex> lock(_mu);
        if (_engine) return true;
        try {
            UtilityFunctions::print("ChessEngine: initialising bitboards...");
            _init_stockfish();
            UtilityFunctions::print("ChessEngine: bitboards ready");
            std::string nnue_path = _get_nnue_path();
            UtilityFunctions::print("ChessEngine: NNUE path='", nnue_path.c_str(), "' (empty=embedded)");
            _engine = nnue_path.empty()
                ? std::make_unique<Stockfish::Engine>(std::nullopt)
                : std::make_unique<Stockfish::Engine>(nnue_path);
            UtilityFunctions::print("ChessEngine: Engine constructed OK");
            _set_option("Threads", "1");
            _set_option("Hash", "16");
            if (!nnue_path.empty()) {
                _set_nnue_file(nnue_path);
            }
            _engine->set_on_bestmove([](std::string_view, std::string_view) {});
            _engine->set_on_update_no_moves([](const Stockfish::Engine::InfoShort &) {});
            _engine->set_on_update_full([](const Stockfish::Engine::InfoFull &) {});
            _engine->set_on_iter([](const Stockfish::Engine::InfoIter &) {});
            _engine->set_on_verify_networks([](std::string_view) {});
            UtilityFunctions::print("ChessEngine: start() OK");
            return true;
        } catch (const std::exception &e) {
            UtilityFunctions::push_error("ChessEngine: start() std::exception: ", e.what());
            _engine.reset();
            return false;
        } catch (...) {
            UtilityFunctions::push_error("ChessEngine: start() unknown exception");
            _engine.reset();
            return false;
        }
    }

    void shutdown() {
        std::lock_guard<std::mutex> lock(_mu);
        if (!_engine) return;
        try { _engine->stop(); } catch (...) {}
        try { _engine->wait_for_search_finished(); } catch (...) {}
        try {
            _engine->set_on_bestmove([](std::string_view, std::string_view) {});
            _engine->set_on_update_no_moves([](const Stockfish::Engine::InfoShort &) {});
            _engine->set_on_update_full([](const Stockfish::Engine::InfoFull &) {});
            _engine->set_on_iter([](const Stockfish::Engine::InfoIter &) {});
            _engine->set_on_verify_networks([](std::string_view) {});
        } catch (...) {}
        _engine.reset();
    }

    String bestmove(const String &p_fen, int p_movetime_ms) {
        std::lock_guard<std::mutex> engine_lock(_mu);
        if (!_engine) return String();
        std::string fen = p_fen.utf8().get_data();
        std::mutex result_mu;
        std::string bestmove;

        try {
            _engine->set_on_bestmove([&result_mu, &bestmove](std::string_view best, std::string_view) {
                std::lock_guard<std::mutex> result_lock(result_mu);
                bestmove = std::string(best);
            });
            // Capture the score of the deepest completed iteration so callers
            // can read it via last_eval_cp() (side-to-move POV, centipawns).
            _engine->set_on_update_full([this](const Stockfish::Engine::InfoFull &info) {
                int parsed = info.score.visit([](auto &&arg) -> int {
                    using T = std::decay_t<decltype(arg)>;
                    if constexpr (std::is_same_v<T, Stockfish::Score::InternalUnits>) {
                        return arg.value;
                    } else if constexpr (std::is_same_v<T, Stockfish::Score::Mate>) {
                        return (arg.plies > 0) ? 30000 : -30000;
                    } else if constexpr (std::is_same_v<T, Stockfish::Score::Tablebase>) {
                        return arg.win ? 30000 : -30000;
                    } else {
                        return 0;
                    }
                });
                _last_eval.store(parsed);
            });
            Stockfish::Search::LimitsType limits;
            limits.startTime = Stockfish::now();
            limits.movetime = (p_movetime_ms > 0) ? p_movetime_ms : 500;
            limits.depth    = 0;  // movetime is the only thing that matters
            _engine->set_position(fen, std::vector<std::string>{});
            _engine->go(limits);
            _engine->wait_for_search_finished();
            _engine->set_on_bestmove([](std::string_view, std::string_view) {});
            _engine->set_on_update_full([](const Stockfish::Engine::InfoFull &) {});
            std::lock_guard<std::mutex> result_lock(result_mu);
            return bestmove.empty() ? String() : String(bestmove.c_str());
        } catch (const std::exception &e) {
            try {
                _engine->set_on_bestmove([](std::string_view, std::string_view) {});
                _engine->set_on_update_full([](const Stockfish::Engine::InfoFull &) {});
            } catch (...) {}
            UtilityFunctions::push_error("ChessEngine: bestmove failed: ", e.what());
            return String();
        }
    }

    // Score reported by the most recent bestmove() search, in centipawns from
    // the side-to-move's point of view. Mate scores saturate at ±30000.
    int last_eval_cp() {
        return _last_eval.load();
    }

    bool set_option(const String &p_name, const String &p_value) {
        std::lock_guard<std::mutex> lock(_mu);
        if (!_engine) return false;
        try {
            _set_option(std::string(p_name.utf8().get_data()), std::string(p_value.utf8().get_data()));
            return true;
        } catch (const std::exception &e) {
            UtilityFunctions::push_error("ChessEngine: set_option failed: ", e.what());
            return false;
        }
    }

    int eval_cp(const String &p_fen) {
        std::lock_guard<std::mutex> engine_lock(_mu);
        if (!_engine) return 0;
        std::string fen = p_fen.utf8().get_data();
        std::mutex result_mu;
        int score_cp = 0;
        try {
            _engine->set_on_update_full([&result_mu, &score_cp](const Stockfish::Engine::InfoFull &info) {
                int parsed = info.score.visit([](auto &&arg) -> int {
                    using T = std::decay_t<decltype(arg)>;
                    if constexpr (std::is_same_v<T, Stockfish::Score::InternalUnits>) {
                        return arg.value;
                    } else if constexpr (std::is_same_v<T, Stockfish::Score::Mate>) {
                        return (arg.plies > 0) ? 30000 : -30000;
                    } else if constexpr (std::is_same_v<T, Stockfish::Score::Tablebase>) {
                        return arg.win ? 30000 : -30000;
                    } else {
                        return 0;
                    }
                });
                std::lock_guard<std::mutex> result_lock(result_mu);
                score_cp = parsed;
            });
            Stockfish::Search::LimitsType limits;
            limits.startTime = Stockfish::now();
            limits.depth = 0;  // static eval only, fast
            _engine->set_position(fen, std::vector<std::string>{});
            _engine->go(limits);
            _engine->wait_for_search_finished();
            _engine->set_on_update_full([](const Stockfish::Engine::InfoFull &) {});
            std::lock_guard<std::mutex> result_lock(result_mu);
            return score_cp;
        } catch (...) {
            try { _engine->set_on_update_full([](const Stockfish::Engine::InfoFull &) {}); } catch (...) {}
            return 0;
        }
    }

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("start"), &ChessEngine::start);
        ClassDB::bind_method(D_METHOD("bestmove", "fen", "movetime_ms"), &ChessEngine::bestmove);
        ClassDB::bind_method(D_METHOD("last_eval_cp"), &ChessEngine::last_eval_cp);
        ClassDB::bind_method(D_METHOD("eval_cp", "fen"), &ChessEngine::eval_cp);
        ClassDB::bind_method(D_METHOD("set_option", "name", "value"), &ChessEngine::set_option);
        ClassDB::bind_method(D_METHOD("shutdown"), &ChessEngine::shutdown);
    }

private:
    std::unique_ptr<Stockfish::Engine> _engine;
    std::mutex _mu;
    std::atomic<int> _last_eval{0};

    static void _init_stockfish() {
        static std::once_flag once;
        std::call_once(once, []() {
            Stockfish::Bitboards::init();
            Stockfish::Position::init();
        });
    }

    std::string _get_nnue_path() const {
        constexpr const char* kResPath  = "res://gdextension/bin/nn-37f18f62d772.nnue";
        constexpr const char* kFileName = "nn-37f18f62d772.nnue";

        ProjectSettings* settings = ProjectSettings::get_singleton();
        if (!settings) return std::string();

        // Try the globalized res:// path first. This works in the editor and in
        // desktop exports where the file is not packed into the PCK.
        String global_res = settings->globalize_path(kResPath);
        std::string path = std::string(global_res.utf8().get_data());
        {
            std::ifstream probe(path, std::ios::binary);
            if (probe.good()) return path;
        }

        // The file is not accessible via C file I/O (packed in APK/PCK).
        // On non-MSVC builds, INCBIN already embedded the NNUE in the binary, so
        // returning empty here lets Engine(nullopt) use that embedded copy.
        // On MSVC, INCBIN is disabled, so we must extract the file to user://.
#if defined(_MSC_VER)
        String user_path = String("user://") + kFileName;
        if (!FileAccess::file_exists(user_path)) {
            Ref<FileAccess> src = FileAccess::open(kResPath, FileAccess::READ);
            if (src.is_valid()) {
                Ref<FileAccess> dst = FileAccess::open(user_path, FileAccess::WRITE);
                if (dst.is_valid()) {
                    const int64_t kChunk = 1 << 16;
                    for (int64_t rem = src->get_length(); rem > 0;) {
                        PackedByteArray buf = src->get_buffer(MIN(rem, kChunk));
                        if (buf.is_empty()) break;
                        dst->store_buffer(buf);
                        rem -= (int64_t)buf.size();
                    }
                }
            }
        }
        if (FileAccess::file_exists(user_path)) {
            String g = settings->globalize_path(user_path);
            return std::string(g.utf8().get_data());
        }
#endif

        // Rely on INCBIN-embedded NNUE data (non-MSVC platforms).
        return std::string();
    }

    void _set_nnue_file(const std::string &path) {
        if (path.empty()) return;
        _set_option("EvalFile", path);
        _set_option("EvalFileSmall", path);
    }

    void _set_option(const std::string &name, const std::string &value) {
        std::istringstream command("name " + name + " value " + value);
        _engine->get_options().setoption(command);
    }
};

// Module entry point.

extern "C" {
void initialize_chess_engine_module(ModuleInitializationLevel p_level);
void uninitialize_chess_engine_module(ModuleInitializationLevel p_level);

GDExtensionBool GDE_EXPORT chess_engine_library_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization *r_initialization) {

    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_chess_engine_module);
    init_obj.register_terminator(uninitialize_chess_engine_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}

void initialize_chess_engine_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    GDREGISTER_CLASS(ChessEngine);
    GDREGISTER_CLASS(SpeechInput);
    GDREGISTER_CLASS(GameCenter);
}

void uninitialize_chess_engine_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
}
}
