#include "speech_input.hpp"

SpeechInput::SpeechInput() {}
SpeechInput::~SpeechInput() { stop(); }

bool SpeechInput::is_available() const { return false; }
bool SpeechInput::start() { return false; }
void SpeechInput::stop() {}
void SpeechInput::clear() {}
bool SpeechInput::is_listening() const { return false; }
String SpeechInput::get_transcript() const { return String(); }
bool SpeechInput::has_final_transcript() const { return false; }
String SpeechInput::consume_final_transcript() { return String(); }
String SpeechInput::get_error() const { return String("Native speech recognition is not available on this platform."); }
float SpeechInput::get_audio_level() const { return 0.0f; }

void SpeechInput::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_available"), &SpeechInput::is_available);
    ClassDB::bind_method(D_METHOD("start"), &SpeechInput::start);
    ClassDB::bind_method(D_METHOD("stop"), &SpeechInput::stop);
    ClassDB::bind_method(D_METHOD("clear"), &SpeechInput::clear);
    ClassDB::bind_method(D_METHOD("is_listening"), &SpeechInput::is_listening);
    ClassDB::bind_method(D_METHOD("get_transcript"), &SpeechInput::get_transcript);
    ClassDB::bind_method(D_METHOD("has_final_transcript"), &SpeechInput::has_final_transcript);
    ClassDB::bind_method(D_METHOD("consume_final_transcript"), &SpeechInput::consume_final_transcript);
    ClassDB::bind_method(D_METHOD("get_error"), &SpeechInput::get_error);
    ClassDB::bind_method(D_METHOD("get_audio_level"), &SpeechInput::get_audio_level);
}
