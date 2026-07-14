#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

class SpeechInput : public RefCounted {
    GDCLASS(SpeechInput, RefCounted)

public:
    SpeechInput();
    ~SpeechInput() override;

    bool is_available() const;
    bool start();
    void stop();
    void clear();
    bool is_listening() const;
    String get_transcript() const;
    bool has_final_transcript() const;
    String consume_final_transcript();
    String get_error() const;
    float get_audio_level() const;

protected:
    static void _bind_methods();

private:
    void *_impl = nullptr;
};
