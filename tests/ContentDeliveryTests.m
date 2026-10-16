#import "FYContentTranslationState.h"
#import "FYRuntimeDeliveryChecks.h"

static NSUInteger checks;
static void Check(BOOL value, const char *message) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(2); }
}

@interface DeliveryProbe : NSObject <FYInlinePlacementDeliverySource>
@property NSInteger generation;
@property BOOL running;
@property uint32_t windowID;
@property NSUInteger epoch;
@property NSInteger mode;
@property NSUInteger revision;
@property NSInteger geometry;
@property(nonatomic, strong) NSMutableArray<NSString *> *reads;
@end
@implementation DeliveryProbe
- (instancetype)init {
    if ((self = [super init])) { _generation = 5; _running = YES; _windowID = 42; _epoch = 7; _mode = 0; _revision = 9; _geometry = 3; _reads = [NSMutableArray new]; }
    return self;
}
- (NSInteger)deliveryGeneration { [self.reads addObject:@"generation"]; return self.generation; }
- (BOOL)deliveryIsRunning { [self.reads addObject:@"running"]; return self.running; }
- (uint32_t)deliveryWindowID { [self.reads addObject:@"window"]; return self.windowID; }
- (NSUInteger)deliveryInputEpoch { [self.reads addObject:@"epoch"]; return self.epoch; }
- (NSInteger)deliveryMode { [self.reads addObject:@"mode"]; return self.mode; }
- (NSUInteger)deliveryContentRevision { [self.reads addObject:@"revision"]; return self.revision; }
- (NSInteger)deliveryGeometryGeneration { [self.reads addObject:@"geometry"]; return self.geometry; }
@end

int main(void) { @autoreleasepool {
    FYContentTranslationState *state = [FYContentTranslationState new];
    Check(state.revision == 0 && state.operations == 0 && !state.text && !state.items && state.mode == 0 &&
          state.geometryGeneration == 0 && state.displayTarget == 0, "content construction is empty and needs no host, UI, queue, request or device");
    __block NSUInteger equivalenceCalls = 0;
    BOOL (^equivalent)(NSString *, NSString *) = ^BOOL(NSString *a, NSString *b) { equivalenceCalls++; return [a isEqualToString:b]; };
    Check(![state matchesText:@"synthetic" mode:0 equivalent:equivalent] && equivalenceCalls == 0, "idle content does not consult the comparison dependency");
    // Fixture observations are strings with explicit stable keys. Production
    // integration also exercises real OCR items and the original key function.
    NSString *(^key)(OCRTextItem *) = ^NSString *(OCRTextItem *item) { return (id)item; };
    Check([state matchesItems:nil key:key], "empty observation sets retain the original count-based match contract");
    [state invalidate];
    NSMutableString *text = [@"synthetic source" mutableCopy];
    NSUInteger first = [state beginText:text mode:FYContentModeDialogue];
    [state updateGeometryGeneration:3 displayTarget:42];
    [text appendString:@" changed input"];
    Check(first == 1 && state.operations == 1 && [state.text isEqual:@"synthetic source"], "begin uses the existing revision and copies submitted text");
    Check([state matchesText:@"synthetic source" mode:0 equivalent:equivalent] && equivalenceCalls == 1, "dialogue comparison uses only its explicit dependency");
    Check(![state matchesText:@"synthetic source" mode:1 equivalent:equivalent] && equivalenceCalls == 1, "different mode does not consult dialogue comparison");
    [state addOperation];
    Check(state.operations == 2, "dialogue and option work share their content revision with separate operation leases");
    [state finishRevision:first]; Check(state.operations == 1, "current completion releases only one operation");
    NSMutableArray *items = [NSMutableArray arrayWithObjects:@"first", @"second", nil]; state.items = items;
    FYContentTranslationSnapshot *old = [state snapshot];
    Check(![old respondsToSelector:NSSelectorFromString(@"setText:")] && ![old respondsToSelector:NSSelectorFromString(@"setRevision:")],
          "immutable snapshot exposes no mutation selectors");
    [items removeLastObject];
    Check(old.items.count == 2 && state.items.count == 2 && old.items[0] == (id)@"first", "copied observation container preserves source identities and order");
    Check([state matchesItems:(id)@[@"first", @"second"] key:key] &&
          ![state matchesItems:(id)@[@"second", @"first"] key:key] &&
          ![state matchesItems:(id)@[@"first"] key:key], "pending matching preserves key order and count");
    [state invalidate]; NSUInteger second = [state beginText:@"new occurrence" mode:FYContentModeUI];
    [state updateGeometryGeneration:4 displayTarget:43];
    [state finishRevision:first];
    Check(second > first && state.operations == 1, "old completion cannot release a new content lease");
    Check(old.revision == first && old.operations == 1 && old.geometryGeneration == 3 && old.displayTarget == 42 &&
          [old.text isEqual:@"synthetic source"] && old.items.count == 2, "immutable snapshot keeps original revision, geometry, text and observations");
    NSUInteger beforeCalls = equivalenceCalls;
    Check([state matchesText:@"new occurrence" mode:1 equivalent:equivalent] &&
          ![state matchesText:@"new occurrence." mode:1 equivalent:equivalent] && equivalenceCalls == beforeCalls,
          "UI content uses exact equality and never dialogue normalization");
    NSUInteger retained = [state replacePendingText:@"same long body; new short field"];
    [state updateGeometryGeneration:5 displayTarget:44];
    Check(retained == second && state.operations == 1 && state.mode == 1 && state.geometryGeneration == 5 && state.displayTarget == 44,
          "retained transport revision replaces content/geometry without changing mode or adding a lease");
    [state finishRevision:second]; [state finishRevision:second];
    Check(state.operations == 0, "extra current completions do not underflow operation count");
    [state invalidate];
    Check(!state.text && !state.items && state.operations == 0 && state.mode == 1 && state.geometryGeneration == 5 && state.displayTarget == 44,
          "invalidation clears pending payload while retaining original inactive mode and geometry fields");
    __weak FYContentTranslationState *released;
    @autoreleasepool { FYContentTranslationState *temporary = [FYContentTranslationState new]; released = temporary; [temporary beginText:@"fixture" mode:0]; }
    Check(!released, "content owner has no observer, callback or host cycle");

    Check(FYContentRevisionIsCurrent(2, 2) && !FYContentRevisionIsCurrent(1, 2), "content revision gate rejects old work");
    Check(FYInlinePlanIsCurrent(2, 2, 3, 3) && !FYInlinePlanIsCurrent(1, 2, 3, 3) && !FYInlinePlanIsCurrent(2, 2, 2, 3),
          "plan gate requires both revision and serial");
    FYRealtimeDeliveryTicket *live = [[FYRealtimeDeliveryTicket alloc] initWithGeneration:5 windowID:42 inputEpoch:7 mode:0];
    NSArray *reasons = @[@"generation_changed", @"stopped", @"window_changed", @"input_session_changed", @"mode_changed"];
    NSArray *readOrder = @[@"generation", @"running", @"window", @"epoch", @"mode"];
    for (NSUInteger boundary = 0; boundary < reasons.count; boundary++) {
        DeliveryProbe *source = [DeliveryProbe new];
        if (boundary == 0) source.generation++;
        if (boundary == 1) source.running = NO;
        if (boundary == 2) source.windowID++;
        if (boundary == 3) source.epoch++;
        if (boundary == 4) source.mode++;
        Check([[live dropReasonWithSource:source] isEqual:reasons[boundary]], "realtime drop reason preserves the exact boundary");
        Check([source.reads isEqual:[readOrder subarrayWithRange:NSMakeRange(0, boundary + 1)]], "realtime rejection preserves lazy read order and skips later dependencies");
    }
    DeliveryProbe *source = [DeliveryProbe new];
    Check(![live dropReasonWithSource:source] && [source.reads isEqual:readOrder], "current realtime identity is accepted after all gates");
    source.generation++; source.running = NO; source.windowID++; source.epoch++; source.mode++;
    Check([[live dropReasonWithSource:source] isEqual:@"generation_changed"], "multiple invalid fields preserve generation priority");

    FYInlinePlacementDeliveryTicket *placement = [[FYInlinePlacementDeliveryTicket alloc] initWithContentRevision:9
        generation:5 inputEpoch:7 mode:0 geometryGeneration:3 displayTarget:42];
    NSArray *placementReasons = @[@"content_changed", @"generation_changed", @"input_session_changed", @"mode_changed", @"geometry_changed", @"geometry_changed"];
    for (NSUInteger boundary = 0; boundary < placementReasons.count; boundary++) {
        source = [DeliveryProbe new];
        if (boundary == 0) source.revision++;
        if (boundary == 1) source.generation++;
        if (boundary == 2) source.epoch++;
        if (boundary == 3) source.mode++;
        if (boundary == 4) source.geometry++;
        if (boundary == 5) source.windowID++;
        Check([[placement dropReasonWithSource:source] isEqual:placementReasons[boundary]], "placement drop reasons preserve content/run/geometry identity");
        if (boundary == 0) Check([source.reads isEqual:@[@"revision"]], "old content does not read any run or UI-derived environment");
        if (boundary <= 2) Check(![source.reads containsObject:@"mode"] && ![source.reads containsObject:@"geometry"], "old generation/epoch never reads current mode or placement");
        if (boundary == 4) Check(![source.reads containsObject:@"window"], "old geometry skips the target lookup");
    }
    source = [DeliveryProbe new]; source.running = NO; source.mode = 1;
    Check(![placement dropReasonWithSource:source] && ![source.reads containsObject:@"mode"], "paused single-frame placement retains its original mode-independent acceptance");
    Check([[live dropReasonWithSource:source] isEqual:@"stopped"], "realtime still refuses the same paused environment");
    FYInlinePlacementDeliveryTicket *unknown = [[FYInlinePlacementDeliveryTicket alloc] initWithContentRevision:9
        generation:5 inputEpoch:7 mode:0 geometryGeneration:3 displayTarget:0];
    source = [DeliveryProbe new]; source.windowID = 88;
    Check(![unknown dropReasonWithSource:source] && ![source.reads containsObject:@"window"], "unknown submitted placement target keeps the original target-match exemption");
    __weak DeliveryProbe *sourceLifetime;
    @autoreleasepool { DeliveryProbe *temporary = [DeliveryProbe new]; sourceLifetime = temporary; [live dropReasonWithSource:temporary]; }
    Check(!sourceLifetime, "immutable ticket never stores the delivery source");
    Check(live.generation == 5 && live.windowID == 42 && live.inputEpoch == 7 && live.mode == 0 && placement.contentRevision == 9,
          "tickets keep submitting identities independent of later source changes");
    __block NSInteger generation = 7;
    __block BOOL delivered = NO, dropped = NO;
    FYDeliverTranslationOnMain(7, ^NSInteger { Check(NSThread.isMainThread, "generation provider is read on main"); return generation; },
        @"synthetic", nil, ^(NSString *value, NSError *error) { (void)value; (void)error; delivered = YES; }, ^{ dropped = YES; });
    generation = 8;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!dropped && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
    }
    Check(dropped && !delivered, "generation changes before the main-queue turn discard stale transport delivery");
    FYDeliverTranslationOnMain(8, ^NSInteger { return generation; }, @"synthetic", nil,
        ^(NSString *value, NSError *error) { Check(NSThread.isMainThread && [value isEqual:@"synthetic"] && !error, "current transport delivery keeps payload and main affinity"); delivered = YES; }, nil);
    deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!delivered && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
    }
    Check(delivered, "current transport delivery arrives within deadline");
    printf("PASS ContentDeliveryTests: %lu checks; content leases, immutable snapshots, lazy delivery policies and minimal dependencies\n", (unsigned long)checks);
} return 0; }
