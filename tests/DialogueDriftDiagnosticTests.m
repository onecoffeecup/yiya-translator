// Regression: calls the production timer/OCR-routing pipeline with
// synthetic images, predetermined OCR and a mock translator. No NSApplication,
// windows, real capture, network, preferences or user store are used.
#import "LearningAppTestSupport.h"

@interface DriftSwitch : NSObject
@property NSInteger state;
@end
@implementation DriftSwitch
@end

@interface DriftDiagnosticApp : AppDelegate
@property NSArray<OCRTextItem *> *fixture;
@property NSMutableArray<NSString *> *requests;
@property NSMutableArray<NSString *> *captions;
@end
@implementation DriftDiagnosticApp
- (uint32_t)selectedWindowID { return 42; }
- (WindowItem *)selectedWindowItem { return nil; }
- (BOOL)autoContentModeEnabled { return NO; }
- (NSInteger)effectiveModeSegment { return ContentModeDialogue; }
- (NSString *)systemPrompt { return @"fixed diagnostic prompt"; }
- (void)updateRunState {}
- (void)setStatus:(NSString *)s {}
- (void)updatePreviewFromImage:(CGImageRef)i generation:(NSInteger)g {}
- (void)refreshLearningSource {}
- (void)refreshLearningStatus {}
- (void)clearInlineTranslationPanels {}
- (void)setCaptionPanelVisibleForUIMode:(BOOL)m {}
- (void)showError:(NSString *)s { Require(s.length == 0, @"unexpected production error"); }
- (void)updateTranslationCount {}
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status { [self.captions addObject:text]; }
- (NSString *)recognizeTextBlocksInImage:(CGImageRef)i fastOCR:(BOOL)f languageSegment:(NSInteger)l blocks:(NSArray<OCRTextItem *> **)blocks error:(NSError **)e {
    *blocks = self.fixture; return [[self.fixture valueForKey:@"text"] componentsJoinedByString:@"\n"];
}
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)b inImage:(CGImageRef)i normalizedExclusions:(NSArray<NSValue *> *)e { return b; }
- (void)translateTextRealtime:(NSString *)text systemPrompt:(NSString *)p maxTokens:(NSInteger)m completion:(void (^)(NSString *, NSError *))done {
    [self.requests addObject:text];
    done([NSString stringWithFormat:@"模拟译文%lu", (unsigned long)self.requests.count], nil);
}
@end

static OCRTextItem *Line(NSString *text, CGFloat y, CGFloat w) {
    OCRTextItem *b = [OCRTextItem new]; b.text = text;
    b.boundingBox = CGRectMake(.20, y, w, .055); return b;
}
static DriftDiagnosticApp *NewApp(void) {
    DriftDiagnosticApp *a = [DriftDiagnosticApp new];
    a.requests = [NSMutableArray new]; a.captions = [NSMutableArray new]; a.running = YES;
    DriftSwitch *stable = [DriftSwitch new]; stable.state = NSControlStateValueOn;
    DriftSwitch *fit = [DriftSwitch new]; fit.state = NSControlStateValueOff;
    a.stableTextCheckbox = (id)stable; a.autoFitRegionCheckbox = (id)fit;
    // Coordinator uses real identity logic; nil persistence avoids any DB I/O.
    a.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:nil analyzer:nil tokenizer:nil catalog:nil];
    return a;
}
static void Cycle(DriftDiagnosticApp *a, NSArray *frame) {
    a.fixture = frame; [a timerFired:nil]; Pump(^BOOL { return !a.inFlight; });
}
static void StableFrame(DriftDiagnosticApp *a, NSArray *frame) { Cycle(a, frame); Cycle(a, frame); Cycle(a, frame); }

int main(void) { @autoreleasepool {
    unsetenv("FUYI_DIAG");
    NSArray<OCRTextItem *> *full = @[Line(@"明日はみんなで図書館に行きましょう。", .20, .65)];
    NSArray<OCRTextItem *> *clipped = @[Line(@"明日はみんなで", .20, .31)];
    DriftDiagnosticApp *control = NewApp();
    for (NSUInteger i=0; i<8; i++) StableFrame(control, full);
    Require(control.requests.count == 1, @"unchanged OCR must request once");
    NSLog(@"CONTROL unchanged frames: requests=%lu", (unsigned long)control.requests.count);

    DriftDiagnosticApp *a = NewApp();
    StableFrame(a, full);
    for (NSUInteger i=0; i<8; i++) { StableFrame(a, clipped); StableFrame(a, full); }
    Require(a.requests.count == 1, @"complete/partial/complete must reuse the full translation");
    Require([a.learningCoordinator.currentSourceText isEqualToString:full[0].text], @"learning retains the complete source");
    for (NSString *caption in a.captions) { Require([caption isEqual:a.captions.firstObject], @"clipping must never change the visible translation"); }
    NSLog(@"FIXED complete/partial/complete: requests=%lu", (unsigned long)a.requests.count);

    // Text-only clipping evidence must be conservative: punctuation, short
    // replies, complete predicates, different speakers and negation survive.
    for (NSString *distinct in @[@"明日はみんなで。", @"明日はみんなで？", @"明日はみんなで…", @"明日は", @"明日はみんなと", @"明日はみんなで行かない。"])
        Require(!FYDialogueIsIncompleteFrame(distinct, full[0].text), @"real new wording must not be held as a clipped prefix");
    Require(FYDialogueIsIncompleteFrame(@"花椿\n明日はみんなで", @"花椿\n明日はみんなで図書館に行きましょう。"), @"two-line speaker/body clipping is covered");
    Require(!FYDialogueIsIncompleteFrame(@"別人\n明日はみんなで", @"花椿\n明日はみんなで図書館に行きましょう。"), @"changed speaker is a new utterance");
    for(NSArray *pair in @[@[@"私は犬より猫が好きなの",@"私は犬より猫が好きなので毎日写真を見る。"],
                          @[@"そろそろ図書館に行きたいんだけど",@"そろそろ図書館に行きたいんだけど、一緒に来る？"],
                          @[@"明日は仕事で行けないから",@"明日は仕事で行けないから、今日は一緒に行こう。"]])
        Require(!FYDialogueIsIncompleteFrame(pair[0],pair[1]),@"natural spoken sentence endings are not evidence of clipping");

    NSString *longSource=@"明日の午後はみんなで駅前の図書館まで歩いて行くつもりです。";
    NSString *changedNumber=@"明日の午後は二人で駅前の図書館まで歩いて行くつもりです。";
    Require(![a isSameSubtitleText:longSource comparedTo:changedNumber], @"high character similarity cannot hide a real word change");
    Require(![a isSameSubtitleText:@"明日の午後はみんなで駅前の図書館まで歩いて行きません。" comparedTo:@"明日の午後はみんなで駅前の図書館まで歩いて行きます。"], @"negation must pass the frame gate");
    DriftDiagnosticApp *genuine=NewApp();
    StableFrame(genuine,@[Line(longSource,.20,.8)]);
    // Near-identical OCR noise that comes and goes for only two frames should
    // not become an accepted correction, even when it recurs later.
    for(NSUInteger i=0;i<3;i++) {
        Cycle(genuine,@[Line(changedNumber,.20,.8)]);Cycle(genuine,@[Line(changedNumber,.20,.8)]);
        Cycle(genuine,@[Line(longSource,.20,.8)]);
    }
    Require(genuine.requests.count==1,@"two-frame near-text oscillations must not accumulate stability across restored frames");
    StableFrame(genuine,@[Line(changedNumber,.20,.8)]);
    StableFrame(genuine,@[Line(longSource,.20,.8)]);
    Require(genuine.requests.count==3, @"genuine A/B/A dialogue changes must still translate all three occurrences");
    DriftDiagnosticApp *typing=NewApp();
    StableFrame(typing,clipped);StableFrame(typing,full);
    Require(typing.requests.count==2 && [typing.requests.lastObject isEqual:full[0].text], @"a newly completed line replaces its initial partial read");

    DriftDiagnosticApp *mode = NewApp();
    StableFrame(mode, full);
    // Mirrors the coordinator effect of actual UI-route recording. This is a
    // component sequence, not proof that QuickTime triggers auto classification.
    [mode.learningCoordinator recordItems:@[@"設定メニュー"] kind:FYSentenceKindUI];
    mode.lastTranslatedNormalizedText = nil; mode.lastSubmittedNormalizedText = nil;
    StableFrame(mode, full);
    Require(mode.requests.count == 2, @"UI context invalidates the original dialogue identity");
    NSLog(@"REPRO dialogue/UI-context/same-dialogue: requests=%lu", (unsigned long)mode.requests.count);
    Require(NSApp == nil, @"diagnostic must never initialize the application UI");
    NSLog(@"PASS: clipped-frame stability, new dialogue, source completion and mode boundaries; no application UI or real network/capture");
} return 0; }
