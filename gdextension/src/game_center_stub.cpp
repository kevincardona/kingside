#include "game_center.hpp"

GameCenter::GameCenter() {}
GameCenter::~GameCenter() {}

bool GameCenter::is_supported() const { return false; }
void GameCenter::authenticate() {}
bool GameCenter::is_authenticated() const { return false; }
String GameCenter::local_player_name() const { return String(); }
String GameCenter::local_player_id() const { return String(); }
void GameCenter::submit_score(const String &, int) {}
void GameCenter::show_leaderboard(const String &) {}
void GameCenter::find_match() {}
void GameCenter::show_matchmaker() {}
void GameCenter::load_matches() {}
void GameCenter::end_turn(const String &, const String &) {}
void GameCenter::end_match(const String &, const String &, const String &) {}
void GameCenter::resign_match(const String &) {}
void GameCenter::show_realtime_matchmaker() {}
void GameCenter::send_realtime(const String &) {}
void GameCenter::leave_realtime() {}
bool GameCenter::has_event() const { return false; }
Dictionary GameCenter::poll_event() { return Dictionary(); }

void GameCenter::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_supported"), &GameCenter::is_supported);
    ClassDB::bind_method(D_METHOD("authenticate"), &GameCenter::authenticate);
    ClassDB::bind_method(D_METHOD("is_authenticated"), &GameCenter::is_authenticated);
    ClassDB::bind_method(D_METHOD("local_player_name"), &GameCenter::local_player_name);
    ClassDB::bind_method(D_METHOD("local_player_id"), &GameCenter::local_player_id);
    ClassDB::bind_method(D_METHOD("submit_score", "leaderboard_id", "value"), &GameCenter::submit_score);
    ClassDB::bind_method(D_METHOD("show_leaderboard", "leaderboard_id"), &GameCenter::show_leaderboard);
    ClassDB::bind_method(D_METHOD("find_match"), &GameCenter::find_match);
    ClassDB::bind_method(D_METHOD("show_matchmaker"), &GameCenter::show_matchmaker);
    ClassDB::bind_method(D_METHOD("load_matches"), &GameCenter::load_matches);
    ClassDB::bind_method(D_METHOD("end_turn", "match_id", "data"), &GameCenter::end_turn);
    ClassDB::bind_method(D_METHOD("end_match", "match_id", "data", "outcome"), &GameCenter::end_match);
    ClassDB::bind_method(D_METHOD("resign_match", "match_id"), &GameCenter::resign_match);
    ClassDB::bind_method(D_METHOD("show_realtime_matchmaker"), &GameCenter::show_realtime_matchmaker);
    ClassDB::bind_method(D_METHOD("send_realtime", "data"), &GameCenter::send_realtime);
    ClassDB::bind_method(D_METHOD("leave_realtime"), &GameCenter::leave_realtime);
    ClassDB::bind_method(D_METHOD("has_event"), &GameCenter::has_event);
    ClassDB::bind_method(D_METHOD("poll_event"), &GameCenter::poll_event);
}
