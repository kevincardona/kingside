#pragma once

// Game Center bridge ("GameCenter" Godot class). Apple platforms get the real
// GameKit implementation (game_center_apple.mm); everything else gets the
// stub. Async results (auth changes, matchmaking, turn events) are queued and
// drained from GDScript with poll_event(), the same polling pattern used by
// SpeechInput.
//
// Event dictionaries (all have "type"):
//   {type:"auth",        ok:bool, player:String, error:String}
//   {type:"match_found", match_id:String, my_turn:bool, data:String, i_created:bool, opponent:String}
//   {type:"turn",        match_id:String, my_turn:bool, data:String, ended:bool, outcome:String,
//                        active:bool, i_created:bool, opponent:String}
//                        ("active" = the player opened this match from the
//                        matchmaker UI or an invite notification)
//   {type:"matches",     matches:Array[{match_id,my_turn,status,data,i_created,opponent}]}
//   {type:"matchmaker_cancelled"}
//   {type:"score",       ok:bool, error:String}
//   {type:"error",       op:String, error:String}
//
// Real-time matches (GKMatch — both players live at once):
//   {type:"rt_match_found", opponent:String, my_white:bool}
//   {type:"rt_data",        data:String}             (a move/state from the opponent)
//   {type:"rt_state",       connected:bool, opponent:String}
//   {type:"rt_cancelled"}

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

class GameCenter : public RefCounted {
    GDCLASS(GameCenter, RefCounted)

public:
    GameCenter();
    ~GameCenter() override;

    bool is_supported() const;
    void authenticate();
    bool is_authenticated() const;
    String local_player_name() const;
    String local_player_id() const;

    // Leaderboards
    void submit_score(const String &leaderboard_id, int value);
    void show_leaderboard(const String &leaderboard_id);

    // Turn-based matches (2-player auto-match). Match data is a UTF-8 string
    // (the game serializes FEN + move history as JSON).
    void find_match();
    // Apple's matchmaker sheet: shows active matches and lets the player
    // invite Game Center friends/contacts (invites are delivered over
    // iMessage). Selected matches arrive as "turn" events with active=true.
    void show_matchmaker();
    void load_matches();
    void end_turn(const String &match_id, const String &data);
    void end_match(const String &match_id, const String &data, const String &outcome); // outcome: "won"|"lost"|"tied"
    void resign_match(const String &match_id);

    // Real-time matches (GKMatch). Both players are live; moves are sent
    // immediately and applied as they arrive. The native side holds the single
    // active match, so send/leave take no match id. Seats (who plays White) are
    // assigned deterministically from the two player ids so both sides agree.
    void show_realtime_matchmaker();
    void send_realtime(const String &data);
    void leave_realtime();

    // Event queue
    bool has_event() const;
    Dictionary poll_event();

protected:
    static void _bind_methods();

private:
    void *_impl = nullptr;
};
