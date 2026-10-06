#import "LearningAppTestSupport.h"

@interface DialogueStabilityApp : AppDelegate
@property(nonatomic) NSUInteger requestCount;
@property(nonatomic) BOOL failNextRequest;
@end
@implementation DialogueStabilityApp
- (void)translateTextRealtime:(NSString *)text systemPrompt:(NSString *)prompt maxTokens:(NSInteger)maxTokens completion:(void (^)(NSString *, NSError *))completion {
    self.requestCount++;
    if (self.failNextRequest) {
        self.failNextRequest = NO;
        completion(nil, [NSError errorWithDomain:@"test" code:1 userInfo:nil]);
    } else {
        completion([NSString stringWithFormat:@"译文 %lu", (unsigned long)self.requestCount], nil);
    }
}
@end

static NSString *Translate(DialogueStabilityApp *app, FYRequestIdentity *identity) {
    __block NSString *result;
    [app translateDialogueText:identity.sourceText identity:identity systemPrompt:@"测试提示词" completion:^(NSString *translated, NSError *error) {
        Require(!error, @"translation failed"); result = translated;
        [app.learningCoordinator setTranslation:translated forIdentity:identity];
        [app refreshLearningSource];
    }];
    Require(result.length > 0, @"translation must complete");
    return result;
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    FYLearningStore *store = Store([directory stringByAppendingPathComponent:@"dialogue.sqlite3"]);
    FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
    Require([catalog loadWithError:NULL], @"catalog failed");
    DialogueStabilityApp *app = [DialogueStabilityApp new];
    app.learningStore = store;
    app.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:store analyzer:Analyzer(catalog) tokenizer:[FYJapaneseTokenizer new] catalog:catalog];
    [app createMainWindow];
    app.detectedModeSegment = ContentModeDialogue;
    app.languageControl.selectedSegment = 0;

    // Replay the real source and dot counts seen alternating in the live DB.
    NSString *source = @"そ、そうかな？\n初めて言われた・";
    FYRequestIdentity *first = [app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];
    NSString *translation = Translate(app, first);
    [app pinLearningSentence:nil];
    app.learningSourceTextView.selectedRange = NSMakeRange(8, 3);
    NSArray *variants = @[@"そ、そうかな？\n初めて言われた・・・", @"そ、そうかな？\n初めて言われた…", @"そ、そうかな？\n初めて言われた......", @"そ、そうかな？\n初めて言われた．．．", @"そ、そうかな？\n初めて言われた･", @"そ、そうかな？\n初めて言われた‥", @"そ、そうかな？\n初めて言われた・…．", source];
    for (NSUInteger i = 0; i < 24; i++) {
        NSString *variant = variants[i % variants.count];
        Require([app isSameSubtitleText:NormalizeForComparison(variant) comparedTo:NormalizeForComparison(source)], @"ellipsis OCR variants must stop at the frame gate");
        FYRequestIdentity *identity = [app.learningCoordinator recordText:variant kind:FYSentenceKindDialogue];
        Require([identity.sentenceID isEqualToString:first.sentenceID], @"ellipsis variants must keep one dialogue identity");
        // Even if unrelated OCR changes pass the frame gate, reuse the translation.
        Require([Translate(app, identity) isEqualToString:translation], @"reused dialogue must retain its first successful translation");
    }
    Drain(store);
    Require(app.requestCount == 1, @"stable dialogue must only call the model once");
    Require(app.learningCoordinator.isPinned && !app.learningCoordinator.hasNewerSentence, @"dot fluctuations must not announce a new sentence");
    Require([app.learningSourceTextView.string isEqualToString:source] && app.learningSourceTextView.selectedRange.length == 3, @"source and native text selection must stay intact");
    __block NSArray<FYSentenceRecord *> *rows;
    [store fetchRecentSentencesWithLimit:100 completion:^(NSArray *records, NSError *error) { Require(!error, @"history read failed"); rows = records; }];
    Pump(^BOOL { return rows != nil; });
    Require(rows.count == 1 && [rows[0].latestTranslation isEqualToString:translation], @"fluctuating OCR must persist one stable translation");

    for (NSArray *pair in @[@[@"言われた…", @"言われた？"], @[@"言われた…", @"言われた！"], @[@"言われた…", @"言われた。"], @[@"言われた…", @"言われない…"], @[@"1.5", @"15"], @[@"猫・犬", @"猫犬"]]) {
        Require(![FYDialogueComparisonKey(pair[0]) isEqualToString:FYDialogueComparisonKey(pair[1])], @"meaningful words, punctuation and internal dots must remain distinct");
    }
    app.detectedModeSegment = ContentModeUI;
    Require(![app isSameSubtitleText:@"初めて言われた・" comparedTo:@"初めて言われた・・・"], @"dialogue ellipsis comparison must not change UI mode");
    app.detectedModeSegment = ContentModeDialogue;

    FYRequestIdentity *next = [app.learningCoordinator recordText:@"初めて言われない…" kind:FYSentenceKindDialogue];
    Require(![Translate(app, next) isEqualToString:translation] && app.requestCount == 2, @"a changed dialogue must request its own translation");
    Require([app.learningTranslationLabel.stringValue isEqualToString:translation] && app.learningCoordinator.hasNewerSentence, @"new dialogue results must preserve the pinned reading translation");
    FYRequestIdentity *again = [app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];
    Require(![again.sentenceID isEqualToString:first.sentenceID], @"A/B/A must retain the new occurrence identity");
    Translate(app, again);
    Require(app.requestCount == 3, @"a genuine recurrence must get a fresh request");
    app.translationGeneration++;
    Translate(app, again);
    Require(app.requestCount == 4, @"restart or window change must invalidate the translation cache");
    app.serviceTestGeneration++;
    Translate(app, again);
    Require(app.requestCount == 5, @"changing the service must invalidate the translation cache");

    FYRequestIdentity *retry = [app.learningCoordinator recordText:@"失敗しても再試行する…" kind:FYSentenceKindDialogue];
    app.failNextRequest = YES;
    __block BOOL failed = NO;
    [app translateDialogueText:retry.sourceText identity:retry systemPrompt:@"测试提示词" completion:^(NSString *translated, NSError *error) { failed = error != nil; }];
    Require(failed, @"mock failure must be delivered");
    Translate(app, retry);
    Translate(app, retry);
    Require(app.requestCount == 7, @"failed requests must retry, then reuse success");
    NSLog(@"PASS: live ellipsis replay, request count, pinned translation, native selection, history, genuine changes and cache invalidation");
} return 0; }
