#include "speech_input.hpp"

#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

@interface ChessSpeechInputController : NSObject <SFSpeechRecognizerDelegate>
@property(nonatomic, strong) SFSpeechRecognizer *recognizer;
@property(nonatomic, strong) AVAudioEngine *audioEngine;
@property(nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *request;
@property(nonatomic, strong) SFSpeechRecognitionTask *task;
@property(nonatomic, copy) NSString *transcript;
@property(nonatomic, copy) NSString *finalTranscript;
@property(nonatomic, copy) NSString *errorText;
@property(nonatomic, assign) BOOL listening;
@property(nonatomic, assign) float audioLevel;
@end

@implementation ChessSpeechInputController

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        _recognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
        _recognizer.delegate = self;
        _audioEngine = [[AVAudioEngine alloc] init];
        _transcript = @"";
        _finalTranscript = @"";
        _errorText = @"";
        _listening = NO;
        _audioLevel = 0.0f;
    }
    return self;
}

- (BOOL)isAvailable {
    return self.recognizer != nil;
}

- (void)setError:(NSString *)message {
    @synchronized (self) {
        self.errorText = message ?: @"";
    }
}

// Hands-free design: the AVAudioEngine (mic tap) stays running for the whole
// voice session. Each utterance gets its own SFSpeechRecognitionRequest; when
// a request finishes (final result, silence timeout, benign error) only the
// request is torn down and `listening` flips to NO so the game layer can
// re-arm instantly with start() — no engine churn between moves.
- (BOOL)start {
    if (![self isAvailable]) {
        [self setError:@"Speech recognition is not available right now."];
        return NO;
    }
    @synchronized (self) {
        self.transcript = @"";
        self.finalTranscript = @"";
        self.errorText = @"";
    }
    // Fast path: engine already capturing — just arm a fresh recognition request.
    if (self.audioEngine.isRunning &&
        [SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusAuthorized) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self armRequest];
        });
        return YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
            if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
                [self setError:@"Speech recognition permission was not granted."];
                return;
            }
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
                if (!granted) {
                    [self setError:@"Microphone permission was not granted."];
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (![self ensureEngine]) return;
                    [self armRequest];
                });
            }];
        }];
    });
    return YES;
}

- (BOOL)ensureEngine {
    if (self.audioEngine.isRunning) return YES;

    AVAudioInputNode *input = self.audioEngine.inputNode;
    AVAudioFormat *format = [input outputFormatForBus:0];
    [input removeTapOnBus:0];
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        (void)when;
        // self.request is re-created per utterance; nil between arms is a no-op.
        [self.request appendAudioPCMBuffer:buffer];

        // Calculate RMS audio level
        float level = 0.0f;
        if (buffer.format.commonFormat == AVAudioPCMFormatFloat32) {
            float *samples = buffer.floatChannelData[0];
            float sum = 0.0f;
            for (int i = 0; i < (int)buffer.frameLength; i++) {
                sum += samples[i] * samples[i];
            }
            level = sqrtf(sum / (float)buffer.frameLength);
        }
        @synchronized(self) {
            self.audioLevel = level;
        }
    }];

    NSError *engineError = nil;
    [self.audioEngine prepare];
    [self.audioEngine startAndReturnError:&engineError];
    if (engineError) {
        [self setError:engineError.localizedDescription];
        [self stop];
        return NO;
    }
    return YES;
}

- (void)armRequest {
    // Drop any previous utterance's task without touching the audio engine.
    [self endTask];

    SFSpeechAudioBufferRecognitionRequest *req = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    req.shouldReportPartialResults = YES;
    if (@available(macOS 13.0, *)) {
        req.requiresOnDeviceRecognition = NO;
    }
    self.request = req;

    __weak ChessSpeechInputController *weakSelf = self;
    self.task = [self.recognizer recognitionTaskWithRequest:req resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        ChessSpeechInputController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.request != req) return;   // stale callback from a cancelled task
        if (result) {
            NSString *text = result.bestTranscription.formattedString ?: @"";
            @synchronized (strongSelf) {
                strongSelf.transcript = text;
                if (result.isFinal) {
                    strongSelf.finalTranscript = text;
                }
            }
        }
        if (error || (result && result.isFinal)) {
            if (error && ![ChessSpeechInputController isBenignError:error]) {
                [strongSelf setError:error.localizedDescription];
            }
            [strongSelf endTask];
        }
    }];
    @synchronized (self) {
        self.listening = YES;
    }
}

// Silence timeouts and our own cancellations are part of normal hands-free
// flow — never surface them as user-facing errors.
+ (BOOL)isBenignError:(NSError *)error {
    if (!error) return YES;
    NSInteger c = error.code;
    if (c == 203 || c == 216 || c == 301 || c == 1110) return YES;
    NSString *msg = error.localizedDescription ?: @"";
    if ([msg rangeOfString:@"No speech" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    if ([msg rangeOfString:@"ancel" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

- (void)endTask {
    SFSpeechRecognitionTask *task = self.task;
    SFSpeechAudioBufferRecognitionRequest *req = self.request;
    self.task = nil;
    self.request = nil;
    [req endAudio];
    [task cancel];
    @synchronized (self) {
        self.listening = NO;
    }
}

- (void)stop {
    [self endTask];
    if (self.audioEngine.isRunning) {
        [self.audioEngine stop];
    }
    @try {
        [self.audioEngine.inputNode removeTapOnBus:0];
    } @catch (NSException *) {}
    @synchronized (self) {
        self.audioLevel = 0.0f;
    }
}

- (void)clear {
    @synchronized (self) {
        self.transcript = @"";
        self.finalTranscript = @"";
        self.errorText = @"";
    }
}

- (BOOL)isListening {
    @synchronized (self) {
        return self.listening;
    }
}

- (NSString *)currentTranscript {
    @synchronized (self) {
        return self.transcript ?: @"";
    }
}

- (BOOL)hasFinalTranscript {
    @synchronized (self) {
        return self.finalTranscript.length > 0;
    }
}

- (NSString *)consumeFinalTranscript {
    @synchronized (self) {
        NSString *out = self.finalTranscript ?: @"";
        self.finalTranscript = @"";
        return out;
    }
}

- (NSString *)error {
    @synchronized (self) {
        return self.errorText ?: @"";
    }
}

- (float)currentAudioLevel {
    @synchronized (self) {
        return self.audioLevel;
    }
}

@end

static ChessSpeechInputController *controller_from(void *impl) {
    return (__bridge ChessSpeechInputController *)impl;
}

SpeechInput::SpeechInput() {
    ChessSpeechInputController *controller = [[ChessSpeechInputController alloc] init];
    _impl = (__bridge_retained void *)controller;
}

SpeechInput::~SpeechInput() {
    stop();
    if (_impl) {
        CFBridgingRelease(_impl);
        _impl = nullptr;
    }
}

bool SpeechInput::is_available() const {
    return _impl && [controller_from(_impl) isAvailable];
}

bool SpeechInput::start() {
    return _impl && [controller_from(_impl) start];
}

void SpeechInput::stop() {
    if (_impl) [controller_from(_impl) stop];
}

void SpeechInput::clear() {
    if (_impl) [controller_from(_impl) clear];
}

bool SpeechInput::is_listening() const {
    return _impl && [controller_from(_impl) isListening];
}

String SpeechInput::get_transcript() const {
    if (!_impl) return String();
    NSString *text = [controller_from(_impl) currentTranscript];
    return String([text UTF8String]);
}

bool SpeechInput::has_final_transcript() const {
    return _impl && [controller_from(_impl) hasFinalTranscript];
}

String SpeechInput::consume_final_transcript() {
    if (!_impl) return String();
    NSString *text = [controller_from(_impl) consumeFinalTranscript];
    return String([text UTF8String]);
}

String SpeechInput::get_error() const {
    if (!_impl) return String();
    NSString *text = [controller_from(_impl) error];
    return String([text UTF8String]);
}

float SpeechInput::get_audio_level() const {
    if (!_impl) return 0.0f;
    return [controller_from(_impl) currentAudioLevel];
}

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
