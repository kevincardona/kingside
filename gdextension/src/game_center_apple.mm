// Apple frameworks must come BEFORE game_center.hpp: the Godot header does
// `using namespace godot;`, and godot::Key collides with the GameController
// framework's `Key` type that GameKit pulls in.
#import <Foundation/Foundation.h>
#import <GameKit/GameKit.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#include "game_center.hpp"

// ─────────────────────────────────────────────────────────────────────────────
//  Obj-C controller: owns the event queue and all GameKit callbacks.
// ─────────────────────────────────────────────────────────────────────────────
@interface ChessGameCenterController : NSObject <GKLocalPlayerListener, GKGameCenterControllerDelegate,
                                                 GKTurnBasedMatchmakerViewControllerDelegate,
                                                 GKMatchmakerViewControllerDelegate, GKMatchDelegate>
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *events;
@property(nonatomic, assign) BOOL authenticated;
@property(nonatomic, weak) GKTurnBasedMatchmakerViewController *matchmakerVC;
// Real-time (GKMatch) state. One live match at a time.
@property(nonatomic, strong) GKMatch *liveMatch;
@property(nonatomic, weak) GKMatchmakerViewController *liveMatchmakerVC;
@property(nonatomic, assign) BOOL liveStarted;
@end

@implementation ChessGameCenterController

- (instancetype)init {
    self = [super init];
    if (self) {
        _events = [NSMutableArray array];
        _authenticated = NO;
    }
    return self;
}

- (void)pushEvent:(NSDictionary *)event {
    @synchronized (self.events) {
        [self.events addObject:event];
    }
}

- (NSDictionary *)popEvent {
    @synchronized (self.events) {
        if (self.events.count == 0) return nil;
        NSDictionary *e = self.events.firstObject;
        [self.events removeObjectAtIndex:0];
        return e;
    }
}

- (BOOL)hasEvent {
    @synchronized (self.events) {
        return self.events.count > 0;
    }
}

// ── Presentation helpers ──
#if TARGET_OS_IPHONE
- (UIViewController *)rootViewController {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window.rootViewController;
        }
    }
    return nil;
}

- (void)presentViewController:(UIViewController *)vc {
    UIViewController *root = [self rootViewController];
    if (root) [root presentViewController:vc animated:YES completion:nil];
}
#else
- (void)presentViewController:(NSViewController *)vc {
    GKDialogController *dialog = [GKDialogController sharedDialogController];
    dialog.parentWindow = NSApplication.sharedApplication.mainWindow;
    [dialog presentViewController:(NSViewController<GKViewController> *)vc];
}
#endif

// ── Auth ──
- (void)authenticate {
    GKLocalPlayer *player = [GKLocalPlayer localPlayer];
    __weak ChessGameCenterController *weakSelf = self;
#if TARGET_OS_IPHONE
    player.authenticateHandler = ^(UIViewController *vc, NSError *error) {
#else
    player.authenticateHandler = ^(NSViewController *vc, NSError *error) {
#endif
        ChessGameCenterController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (vc) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf presentViewController:vc];
            });
            return;
        }
        BOOL ok = [GKLocalPlayer localPlayer].isAuthenticated;
        strongSelf.authenticated = ok;
        if (ok) {
            [[GKLocalPlayer localPlayer] registerListener:strongSelf];
        }
        [strongSelf pushEvent:@{
            @"type": @"auth",
            @"ok": @(ok),
            @"player": [GKLocalPlayer localPlayer].displayName ?: @"",
            @"error": error ? (error.localizedDescription ?: @"") : @"",
        }];
    };
}

// ── Leaderboards ──
- (void)submitScore:(NSInteger)value leaderboard:(NSString *)leaderboardID {
    __weak ChessGameCenterController *weakSelf = self;
    [GKLeaderboard submitScore:value
                       context:0
                        player:[GKLocalPlayer localPlayer]
                leaderboardIDs:@[leaderboardID]
             completionHandler:^(NSError *error) {
        [weakSelf pushEvent:@{
            @"type": @"score",
            @"ok": @(error == nil),
            @"error": error ? (error.localizedDescription ?: @"") : @"",
        }];
    }];
}

- (void)showLeaderboard:(NSString *)leaderboardID {
    dispatch_async(dispatch_get_main_queue(), ^{
        GKGameCenterViewController *vc =
            [[GKGameCenterViewController alloc] initWithLeaderboardID:leaderboardID
                                                      playerScope:GKLeaderboardPlayerScopeGlobal
                                                        timeScope:GKLeaderboardTimeScopeAllTime];
        vc.gameCenterDelegate = self;
        [self presentViewController:vc];
    });
}

- (void)gameCenterViewControllerDidFinish:(GKGameCenterViewController *)gameCenterViewController {
#if TARGET_OS_IPHONE
    [gameCenterViewController dismissViewControllerAnimated:YES completion:nil];
#else
    [[GKDialogController sharedDialogController] dismiss:gameCenterViewController];
#endif
}

// ── Turn-based matches ──
- (NSDictionary *)matchSummary:(GKTurnBasedMatch *)match {
    NSString *data = @"";
    if (match.matchData.length > 0) {
        data = [[NSString alloc] initWithData:match.matchData encoding:NSUTF8StringEncoding] ?: @"";
    }
    NSString *myID = [GKLocalPlayer localPlayer].gamePlayerID;
    BOOL myTurn = [match.currentParticipant.player.gamePlayerID isEqualToString:myID];
    // The match creator is always participants[0]; the game seats the
    // creator as White.
    BOOL iCreated = [match.participants.firstObject.player.gamePlayerID isEqualToString:myID];
    NSString *opponent = @"";
    for (GKTurnBasedParticipant *p in match.participants) {
        if (p.player && ![p.player.gamePlayerID isEqualToString:myID]) {
            opponent = p.player.displayName ?: @"";
        }
    }
    return @{
        @"match_id": match.matchID ?: @"",
        @"my_turn": @(myTurn),
        @"status": @((int)match.status),
        @"data": data,
        @"i_created": @(iCreated),
        @"opponent": opponent,
    };
}

- (void)findMatch {
    GKMatchRequest *request = [[GKMatchRequest alloc] init];
    request.minPlayers = 2;
    request.maxPlayers = 2;
    __weak ChessGameCenterController *weakSelf = self;
    [GKTurnBasedMatch findMatchForRequest:request
                    withCompletionHandler:^(GKTurnBasedMatch *match, NSError *error) {
        ChessGameCenterController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || !match) {
            [strongSelf pushEvent:@{@"type": @"error", @"op": @"find_match",
                                    @"error": error.localizedDescription ?: @"No match returned."}];
            return;
        }
        NSMutableDictionary *e = [[strongSelf matchSummary:match] mutableCopy];
        e[@"type"] = @"match_found";
        [strongSelf pushEvent:e];
    }];
}

- (void)showMatchmaker {
    dispatch_async(dispatch_get_main_queue(), ^{
        GKMatchRequest *request = [[GKMatchRequest alloc] init];
        request.minPlayers = 2;
        request.maxPlayers = 2;
        request.inviteMessage = @"Let's play chess!";
        GKTurnBasedMatchmakerViewController *vc =
            [[GKTurnBasedMatchmakerViewController alloc] initWithMatchRequest:request];
        vc.turnBasedMatchmakerDelegate = self;
        self.matchmakerVC = vc;
        [self presentViewController:vc];
    });
}

- (void)dismissMatchmaker {
    GKTurnBasedMatchmakerViewController *vc = self.matchmakerVC;
    if (!vc) return;
    self.matchmakerVC = nil;
#if TARGET_OS_IPHONE
    [vc dismissViewControllerAnimated:YES completion:nil];
#else
    [[GKDialogController sharedDialogController] dismiss:vc];
#endif
}

// ── GKTurnBasedMatchmakerViewControllerDelegate ──
// Selecting a match doesn't come through the delegate on modern GameKit; it
// arrives via the GKLocalPlayerListener turn event with didBecomeActive=YES,
// where we dismiss the sheet.
- (void)turnBasedMatchmakerViewControllerWasCancelled:(GKTurnBasedMatchmakerViewController *)viewController {
    [self dismissMatchmaker];
    [self pushEvent:@{@"type": @"matchmaker_cancelled"}];
}

- (void)turnBasedMatchmakerViewController:(GKTurnBasedMatchmakerViewController *)viewController
                         didFailWithError:(NSError *)error {
    [self dismissMatchmaker];
    [self pushEvent:@{@"type": @"error", @"op": @"matchmaker",
                      @"error": error.localizedDescription ?: @""}];
}

- (void)loadMatches {
    __weak ChessGameCenterController *weakSelf = self;
    [GKTurnBasedMatch loadMatchesWithCompletionHandler:^(NSArray<GKTurnBasedMatch *> *matches, NSError *error) {
        ChessGameCenterController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            [strongSelf pushEvent:@{@"type": @"error", @"op": @"load_matches",
                                    @"error": error.localizedDescription ?: @""}];
            return;
        }
        NSMutableArray *list = [NSMutableArray array];
        for (GKTurnBasedMatch *m in matches) {
            [list addObject:[strongSelf matchSummary:m]];
        }
        [strongSelf pushEvent:@{@"type": @"matches", @"matches": list}];
    }];
}

- (void)withMatch:(NSString *)matchID do:(void (^)(GKTurnBasedMatch *match))action op:(NSString *)op {
    __weak ChessGameCenterController *weakSelf = self;
    [GKTurnBasedMatch loadMatchWithID:matchID
                withCompletionHandler:^(GKTurnBasedMatch *match, NSError *error) {
        ChessGameCenterController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || !match) {
            [strongSelf pushEvent:@{@"type": @"error", @"op": op,
                                    @"error": error.localizedDescription ?: @"Match not found."}];
            return;
        }
        action(match);
    }];
}

- (NSArray<GKTurnBasedParticipant *> *)nextParticipants:(GKTurnBasedMatch *)match {
    NSMutableArray *next = [NSMutableArray array];
    for (GKTurnBasedParticipant *p in match.participants) {
        if (![p.player.gamePlayerID isEqualToString:[GKLocalPlayer localPlayer].gamePlayerID]) {
            [next addObject:p];
        }
    }
    return next;
}

- (void)endTurn:(NSString *)matchID data:(NSString *)data {
    __weak ChessGameCenterController *weakSelf = self;
    [self withMatch:matchID do:^(GKTurnBasedMatch *match) {
        NSData *payload = [data dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        [match endTurnWithNextParticipants:[weakSelf nextParticipants:match]
                               turnTimeout:GKTurnTimeoutDefault
                                 matchData:payload
                         completionHandler:^(NSError *error) {
            if (error) {
                [weakSelf pushEvent:@{@"type": @"error", @"op": @"end_turn",
                                      @"error": error.localizedDescription ?: @""}];
            }
        }];
    } op:@"end_turn"];
}

- (void)endMatch:(NSString *)matchID data:(NSString *)data outcome:(NSString *)outcome {
    __weak ChessGameCenterController *weakSelf = self;
    [self withMatch:matchID do:^(GKTurnBasedMatch *match) {
        GKTurnBasedMatchOutcome mine = GKTurnBasedMatchOutcomeTied;
        GKTurnBasedMatchOutcome theirs = GKTurnBasedMatchOutcomeTied;
        if ([outcome isEqualToString:@"won"])  { mine = GKTurnBasedMatchOutcomeWon;  theirs = GKTurnBasedMatchOutcomeLost; }
        if ([outcome isEqualToString:@"lost"]) { mine = GKTurnBasedMatchOutcomeLost; theirs = GKTurnBasedMatchOutcomeWon; }
        NSString *myID = [GKLocalPlayer localPlayer].gamePlayerID;
        for (GKTurnBasedParticipant *p in match.participants) {
            p.matchOutcome = [p.player.gamePlayerID isEqualToString:myID] ? mine : theirs;
        }
        NSData *payload = [data dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        [match endMatchInTurnWithMatchData:payload completionHandler:^(NSError *error) {
            if (error) {
                [weakSelf pushEvent:@{@"type": @"error", @"op": @"end_match",
                                      @"error": error.localizedDescription ?: @""}];
            }
        }];
    } op:@"end_match"];
}

- (void)resignMatch:(NSString *)matchID {
    __weak ChessGameCenterController *weakSelf = self;
    [self withMatch:matchID do:^(GKTurnBasedMatch *match) {
        BOOL myTurn = [match.currentParticipant.player.gamePlayerID
                       isEqualToString:[GKLocalPlayer localPlayer].gamePlayerID];
        if (myTurn) {
            [match participantQuitInTurnWithOutcome:GKTurnBasedMatchOutcomeQuit
                               nextParticipants:[weakSelf nextParticipants:match]
                                    turnTimeout:GKTurnTimeoutDefault
                                      matchData:match.matchData ?: [NSData data]
                              completionHandler:^(NSError *error) { (void)error; }];
        } else {
            [match participantQuitOutOfTurnWithOutcome:GKTurnBasedMatchOutcomeQuit
                                 withCompletionHandler:^(NSError *error) { (void)error; }];
        }
    } op:@"resign_match"];
}

// ── Real-time matches (GKMatch) ──
- (NSString *)liveOpponentName {
    for (GKPlayer *p in self.liveMatch.players) {
        return p.displayName ?: @"";
    }
    return @"";
}

// Deterministic seat: the player whose gamePlayerID sorts first plays White.
// Both clients see the same id pair, so they agree without any handshake.
- (BOOL)amWhite {
    NSString *myID = [GKLocalPlayer localPlayer].gamePlayerID ?: @"";
    NSString *minID = myID;
    for (GKPlayer *p in self.liveMatch.players) {
        NSString *pid = p.gamePlayerID ?: @"";
        if ([pid compare:minID] == NSOrderedAscending) minID = pid;
    }
    return [myID isEqualToString:minID];
}

// Fire rt_match_found exactly once, when every expected player has connected.
- (void)startLiveMatchIfReady {
    if (self.liveStarted || !self.liveMatch) return;
    if (self.liveMatch.expectedPlayerCount != 0) return;
    self.liveStarted = YES;
    [self pushEvent:@{
        @"type": @"rt_match_found",
        @"opponent": [self liveOpponentName],
        @"my_white": @([self amWhite]),
    }];
}

- (void)showRealtimeMatchmaker {
    dispatch_async(dispatch_get_main_queue(), ^{
        GKMatchRequest *request = [[GKMatchRequest alloc] init];
        request.minPlayers = 2;
        request.maxPlayers = 2;
        request.inviteMessage = @"Let's play live chess!";
        GKMatchmakerViewController *vc =
            [[GKMatchmakerViewController alloc] initWithMatchRequest:request];
        vc.matchmakerDelegate = self;
        self.liveMatchmakerVC = vc;
        self.liveStarted = NO;
        [self presentViewController:vc];
    });
}

- (void)dismissLiveMatchmaker {
    GKMatchmakerViewController *vc = self.liveMatchmakerVC;
    if (!vc) return;
    self.liveMatchmakerVC = nil;
#if TARGET_OS_IPHONE
    [vc dismissViewControllerAnimated:YES completion:nil];
#else
    [[GKDialogController sharedDialogController] dismiss:vc];
#endif
}

- (void)sendRealtime:(NSString *)data {
    GKMatch *match = self.liveMatch;
    if (!match) return;
    NSData *payload = [data dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSError *error = nil;
    [match sendDataToAllPlayers:payload withDataMode:GKMatchSendDataReliable error:&error];
    if (error) {
        [self pushEvent:@{@"type": @"error", @"op": @"send_realtime",
                          @"error": error.localizedDescription ?: @""}];
    }
}

- (void)leaveRealtime {
    GKMatch *match = self.liveMatch;
    self.liveMatch = nil;
    self.liveStarted = NO;
    match.delegate = nil;
    [match disconnect];
}

// ── GKMatchmakerViewControllerDelegate ──
- (void)matchmakerViewControllerWasCancelled:(GKMatchmakerViewController *)viewController {
    [self dismissLiveMatchmaker];
    [self pushEvent:@{@"type": @"rt_cancelled"}];
}

- (void)matchmakerViewController:(GKMatchmakerViewController *)viewController didFailWithError:(NSError *)error {
    [self dismissLiveMatchmaker];
    [self pushEvent:@{@"type": @"error", @"op": @"realtime_matchmaker",
                      @"error": error.localizedDescription ?: @""}];
}

- (void)matchmakerViewController:(GKMatchmakerViewController *)viewController didFindMatch:(GKMatch *)match {
    [self dismissLiveMatchmaker];
    self.liveMatch = match;
    self.liveStarted = NO;
    match.delegate = self;
    [self startLiveMatchIfReady];
}

// ── GKMatchDelegate ──
- (void)match:(GKMatch *)match didReceiveData:(NSData *)data fromRemotePlayer:(GKPlayer *)player {
    (void)player;
    if (match != self.liveMatch) return;
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    [self pushEvent:@{@"type": @"rt_data", @"data": str}];
}

- (void)match:(GKMatch *)match player:(GKPlayer *)player didChangeConnectionState:(GKPlayerConnectionState)state {
    if (match != self.liveMatch) return;
    if (state == GKPlayerStateConnected) {
        [self startLiveMatchIfReady];
    } else if (state == GKPlayerStateDisconnected) {
        [self pushEvent:@{@"type": @"rt_state", @"connected": @(NO),
                          @"opponent": player.displayName ?: @""}];
    }
}

- (void)match:(GKMatch *)match didFailWithError:(NSError *)error {
    if (match != self.liveMatch) return;
    [self pushEvent:@{@"type": @"error", @"op": @"realtime",
                      @"error": error.localizedDescription ?: @"Match failed."}];
}

// ── GKLocalPlayerListener ──
// An incoming real-time invite (a friend tapped "challenge"): open the
// matchmaker pre-loaded with the invite so the two clients connect.
- (void)player:(GKPlayer *)player didAcceptInvite:(GKInvite *)invite {
    (void)player;
    dispatch_async(dispatch_get_main_queue(), ^{
        GKMatchmakerViewController *vc = [[GKMatchmakerViewController alloc] initWithInvite:invite];
        vc.matchmakerDelegate = self;
        self.liveMatchmakerVC = vc;
        self.liveStarted = NO;
        [self presentViewController:vc];
    });
}

- (void)player:(GKPlayer *)player receivedTurnEventForMatch:(GKTurnBasedMatch *)match didBecomeActive:(BOOL)didBecomeActive {
    (void)player;
    if (didBecomeActive) {
        // The player chose this match in the matchmaker sheet (or tapped an
        // invite notification) — close the sheet and let the game open it.
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissMatchmaker]; });
    }
    NSMutableDictionary *e = [[self matchSummary:match] mutableCopy];
    e[@"type"] = @"turn";
    e[@"active"] = @(didBecomeActive);
    e[@"ended"] = @(match.status == GKTurnBasedMatchStatusEnded);
    NSString *outcome = @"";
    if (match.status == GKTurnBasedMatchStatusEnded) {
        for (GKTurnBasedParticipant *p in match.participants) {
            if ([p.player.gamePlayerID isEqualToString:[GKLocalPlayer localPlayer].gamePlayerID]) {
                switch (p.matchOutcome) {
                    case GKTurnBasedMatchOutcomeWon:  outcome = @"won"; break;
                    case GKTurnBasedMatchOutcomeLost: outcome = @"lost"; break;
                    case GKTurnBasedMatchOutcomeTied: outcome = @"tied"; break;
                    default: outcome = @"ended"; break;
                }
            }
        }
    }
    e[@"outcome"] = outcome;
    [self pushEvent:e];
}

- (void)player:(GKPlayer *)player matchEnded:(GKTurnBasedMatch *)match {
    [self player:player receivedTurnEventForMatch:match didBecomeActive:NO];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
//  C++ bridge
// ─────────────────────────────────────────────────────────────────────────────
static ChessGameCenterController *controller_from(void *impl) {
    return (__bridge ChessGameCenterController *)impl;
}

static Dictionary ns_to_dict(NSDictionary *src);

static Variant ns_to_variant(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return Variant(String([(NSString *)value UTF8String]));
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *n = (NSNumber *)value;
        if (strcmp(n.objCType, @encode(BOOL)) == 0 || strcmp(n.objCType, "c") == 0) {
            return Variant((bool)n.boolValue);
        }
        return Variant((int64_t)n.longLongValue);
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        return Variant(ns_to_dict((NSDictionary *)value));
    }
    if ([value isKindOfClass:[NSArray class]]) {
        Array arr;
        for (id item in (NSArray *)value) {
            arr.append(ns_to_variant(item));
        }
        return Variant(arr);
    }
    return Variant();
}

static Dictionary ns_to_dict(NSDictionary *src) {
    Dictionary out;
    for (NSString *key in src) {
        out[String([key UTF8String])] = ns_to_variant(src[key]);
    }
    return out;
}

GameCenter::GameCenter() {
    ChessGameCenterController *controller = [[ChessGameCenterController alloc] init];
    _impl = (__bridge_retained void *)controller;
}

GameCenter::~GameCenter() {
    if (_impl) {
        CFBridgingRelease(_impl);
        _impl = nullptr;
    }
}

bool GameCenter::is_supported() const { return true; }

void GameCenter::authenticate() {
    if (_impl) [controller_from(_impl) authenticate];
}

bool GameCenter::is_authenticated() const {
    return _impl && controller_from(_impl).authenticated && [GKLocalPlayer localPlayer].isAuthenticated;
}

String GameCenter::local_player_name() const {
    if (!is_authenticated()) return String();
    return String([[GKLocalPlayer localPlayer].displayName UTF8String]);
}

String GameCenter::local_player_id() const {
    if (!is_authenticated()) return String();
    return String([[GKLocalPlayer localPlayer].gamePlayerID UTF8String]);
}

void GameCenter::submit_score(const String &leaderboard_id, int value) {
    if (!_impl) return;
    NSString *lid = [NSString stringWithUTF8String:leaderboard_id.utf8().get_data()];
    [controller_from(_impl) submitScore:value leaderboard:lid];
}

void GameCenter::show_leaderboard(const String &leaderboard_id) {
    if (!_impl) return;
    NSString *lid = [NSString stringWithUTF8String:leaderboard_id.utf8().get_data()];
    [controller_from(_impl) showLeaderboard:lid];
}

void GameCenter::find_match() {
    if (_impl) [controller_from(_impl) findMatch];
}

void GameCenter::show_matchmaker() {
    if (_impl) [controller_from(_impl) showMatchmaker];
}

void GameCenter::load_matches() {
    if (_impl) [controller_from(_impl) loadMatches];
}

void GameCenter::end_turn(const String &match_id, const String &data) {
    if (!_impl) return;
    [controller_from(_impl) endTurn:[NSString stringWithUTF8String:match_id.utf8().get_data()]
                               data:[NSString stringWithUTF8String:data.utf8().get_data()]];
}

void GameCenter::end_match(const String &match_id, const String &data, const String &outcome) {
    if (!_impl) return;
    [controller_from(_impl) endMatch:[NSString stringWithUTF8String:match_id.utf8().get_data()]
                                data:[NSString stringWithUTF8String:data.utf8().get_data()]
                             outcome:[NSString stringWithUTF8String:outcome.utf8().get_data()]];
}

void GameCenter::resign_match(const String &match_id) {
    if (!_impl) return;
    [controller_from(_impl) resignMatch:[NSString stringWithUTF8String:match_id.utf8().get_data()]];
}

void GameCenter::show_realtime_matchmaker() {
    if (_impl) [controller_from(_impl) showRealtimeMatchmaker];
}

void GameCenter::send_realtime(const String &data) {
    if (!_impl) return;
    [controller_from(_impl) sendRealtime:[NSString stringWithUTF8String:data.utf8().get_data()]];
}

void GameCenter::leave_realtime() {
    if (_impl) [controller_from(_impl) leaveRealtime];
}

bool GameCenter::has_event() const {
    return _impl && [controller_from(_impl) hasEvent];
}

Dictionary GameCenter::poll_event() {
    if (!_impl) return Dictionary();
    NSDictionary *e = [controller_from(_impl) popEvent];
    if (!e) return Dictionary();
    return ns_to_dict(e);
}

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
