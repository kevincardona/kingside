#include <iostream>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include "bitboard.h"
#include "engine.h"
#include "position.h"
#include "search.h"
#include "ucioption.h"

int main(int argc, char **argv) {
    Stockfish::Bitboards::init();
    Stockfish::Position::init();

    const std::string nnue = argc > 1 ? std::string(argv[1])
        : std::string("gdextension/bin/nn-37f18f62d772.nnue");
    auto engine = std::make_unique<Stockfish::Engine>(nnue);
    std::istringstream threads("name Threads value 1");
    engine->get_options().setoption(threads);
    std::istringstream eval_file("name EvalFile value " + nnue);
    engine->get_options().setoption(eval_file);
    std::istringstream eval_file_small("name EvalFileSmall value " + nnue);
    engine->get_options().setoption(eval_file_small);

    engine->set_position(
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        std::vector<std::string>{});

    std::string bestmove;
    engine->set_on_bestmove([&bestmove](std::string_view best, std::string_view) {
        bestmove = std::string(best);
    });
    engine->set_on_update_no_moves([](const Stockfish::Engine::InfoShort&) {});
    engine->set_on_update_full([](const Stockfish::Engine::InfoFull&) {});
    engine->set_on_iter([](const Stockfish::Engine::InfoIter&) {});
    engine->set_on_verify_networks([](std::string_view m) { std::cerr << m << std::endl; });

    Stockfish::Search::LimitsType limits;
    limits.startTime = Stockfish::now();
    limits.movetime  = 100;
    engine->go(limits);
    engine->wait_for_search_finished();
    std::cout << "bestmove=" << bestmove << std::endl;
    return bestmove.empty() ? 1 : 0;
}
