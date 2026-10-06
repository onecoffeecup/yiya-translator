#import "LearningAppTestSupport.h"

static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { Require(ok, message); checks++; NSLog(@"PASS: %@", message); }
static NSString *RenderedText(NSView *view) {
    NSMutableString *text = [NSMutableString string];
    if ([view isKindOfClass:NSTextField.class]) { [text appendString:[(NSTextField *)view stringValue]]; }
    for (NSView *child in view.subviews) { [text appendString:RenderedText(child)]; }
    return text;
}
static FYGrammarItem *Grammar(NSString *name, NSString *match, NSString *text) {
    FYGrammarItem *g = [FYGrammarItem new]; g.name = name; g.matchedText = match; g.matchedRange = [text rangeOfString:match]; return g;
}
static void SetAnalysis(AppDelegate *app) {
    NSString *text = app.learningCoordinator.currentSourceText;
    FYAnalysisResult *r = [FYAnalysisResult new]; r.status = FYAnalysisStatusSuccess;
    r.sentenceID = app.learningCoordinator.currentSentenceID; r.version = app.learningCoordinator.currentVersion;
    r.grammar = @[Grammar(@"〜ざるを得ない", @"ざるを得ない", text), Grammar(@"〜ために", @"ために", text)];
    app.currentAnalysis = r; [app refreshGrammarResults];
}
static NSArray *Examples(FYLearningStore *store, NSString *wordID) {
    __block NSArray *value;
    [store fetchExamplesForVocabulary:wordID completion:^(NSArray *examples, NSError *error) { Require(!error, @"examples read failed"); value = examples; }];
    Pump(^BOOL { return value != nil; }); return value;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        Require([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL], @"temporary directory failed");
        NSString *path = [directory stringByAppendingPathComponent:@"test.sqlite3"];
        FYLearningStore *store = Store(path);
        FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]]; Require([catalog loadWithError:NULL], @"catalog failed");
        FYLearningAnalyzer *analyzer = Analyzer(catalog); AppDelegate *app = App(store, analyzer, catalog);
        [app.learningCoordinator recordText:@"猫です。" kind:FYSentenceKindDialogue]; [app refreshLearningSource]; Drain(store);

        // Follow callback must never rewind OCR that arrived after the database read started.
        __block BOOL followed = NO;
        [app.learningCoordinator followLatestWithCompletion:^{ followed = YES; }];
        FYRequestIdentity *newest = [app.learningCoordinator recordText:@"新しい台詞。" kind:FYSentenceKindDialogue];
        Pump(^BOOL { return followed; });
        Check(!app.learningCoordinator.isPinned && [app.learningCoordinator.currentSentenceID isEqualToString:newest.sentenceID], @"late follow callback keeps newest incoming OCR");
        [app.learningCoordinator pinCurrent]; __block BOOL corrected = NO;
        [app.learningCoordinator correctCurrentSentenceText:@"新しい台詞（修正）。" completion:^(NSError *error) { Require(!error, @"correct failed"); corrected = YES; }]; Pump(^BOOL { return corrected; });
        followed = NO; [app.learningCoordinator followLatestWithCompletion:^{ followed = YES; }]; Pump(^BOOL { return followed; });
        [app.learningCoordinator recordText:@"新しい台詞。" kind:FYSentenceKindDialogue];
        Check(app.learningCoordinator.currentVersion == 2 && [app.learningCoordinator.currentSourceText containsString:@"修正"], @"repeated OCR retains corrected version while following");

        [app.learningCoordinator recordText:@"救うために、進まざるを得ない。" kind:FYSentenceKindDialogue];
        [app.learningCoordinator pinCurrent]; [app refreshLearningSource]; SetAnalysis(app);
        [app bookmarkSelectedGrammar:nil]; Pump(^BOOL { return app.grammarBookmarks.count == 1; });
        Check([app.grammarDetailBookmarkButton.title containsString:@"已收藏"] && [RenderedText(app.savedGrammarCardStack) containsString:app.learningCoordinator.currentSourceText], @"grammar bookmark shows saved state and full source snapshot");
        [app bookmarkSelectedGrammar:nil]; Pump(^BOOL { return app.grammarBookmarks.count == 0; });
        Check([app.grammarDetailBookmarkButton.title isEqualToString:@"收藏此语法"], @"grammar bookmark toggle removes saved grammar");
        NSMutableArray *callbacks = [NSMutableArray array];
        analyzer.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) { [callbacks addObject:[done copy]]; };
        [app simplerExplanationForGrammar:nil]; NSButton *choice = [NSButton new]; choice.tag = 1; [app selectGrammarItem:choice];
        void (^oldAnswer)(NSData *, NSURLResponse *, NSError *) = callbacks[0]; oldAnswer(Envelope(@"旧语法的回答"), Response(), nil); Tick();
        Check(app.selectedGrammarIndex == 1 && ![app.grammarFollowupResultLabel.stringValue containsString:@"旧语法"], @"switching grammar discards previous followup answer");
        [app simplerExplanationForGrammar:nil]; [app exampleSentenceForGrammar:nil];
        void (^first)(NSData *, NSURLResponse *, NSError *) = callbacks[1], (^second)(NSData *, NSURLResponse *, NSError *) = callbacks[2];
        second(Envelope(@"新的例句回答"), Response(), nil); Tick(); first(nil, nil, [NSError errorWithDomain:@"test" code:1 userInfo:nil]); Tick();
        Check([app.grammarFollowupResultLabel.stringValue containsString:@"新的例句"], @"older followup failure cannot overwrite newer answer");
        [app.learningCoordinator selectSentenceID:newest.sentenceID version:2 sourceText:@"新しい台詞（修正）。" translation:nil]; [app refreshLearningSource];
        Check(app.currentAnalysis == nil && app.grammarFollowupResultLabel.stringValue.length == 0, @"sentence switch clears old analysis and followup");

        [app analyzeCurrentSentence:nil]; Pump(^BOOL { return callbacks.count == 4; });
        FYRequestIdentity *busySource = [app.learningCoordinator recordText:@"別の分析対象。" kind:FYSentenceKindDialogue];
        [app.learningCoordinator selectSentenceID:busySource.sentenceID version:1 sourceText:busySource.sourceText translation:nil]; [app refreshLearningSource];
        [app analyzeCurrentSentence:nil]; Pump(^BOOL { return callbacks.count == 5; });
        void (^oldAnalysis)(NSData *, NSURLResponse *, NSError *) = callbacks[3];
        oldAnalysis(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"), Response(), nil); Tick();
        Check(!app.analyzeButton.enabled && !app.grammarPageAnalyzeButton.enabled, @"old analysis completion cannot end a newer request's busy state");
        void (^newAnalysis)(NSData *, NSURLResponse *, NSError *) = callbacks[4];
        newAnalysis(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"), Response(), nil);
        Pump(^BOOL { return app.currentAnalysis != nil; });
        Check(app.analyzeButton.enabled && app.currentAnalysis.status == FYAnalysisStatusNoResult && [app.currentAnalysis.sentenceID isEqualToString:busySource.sentenceID], @"new analysis ends busy state with only its own result");

        // Pending entries merge, differing known readings/senses remain separate.
        FYRequestIdentity *wordSource = [app.learningCoordinator recordText:@"救う、猫、失敗という言葉。" kind:FYSentenceKindDialogue];
        [app.learningCoordinator selectSentenceID:wordSource.sentenceID version:1 sourceText:wordSource.sourceText translation:nil]; [app refreshLearningSource];
        FYVocabularyEntry *pending = Bookmark(app, @"救う", @"", @"", @"");
        FYVocabularyEntry *completed = Bookmark(app, @"救う", @"救う", @"すくう", @"拯救");
        Check(Words(store).count == 1 && [pending.vocabularyID isEqualToString:completed.vocabularyID] && [completed.reading isEqualToString:@"すくう"], @"completed word merges into pending bookmark and keeps ID");
        FYRequestIdentity *otherSource = [app.learningCoordinator recordText:@"仲間を救う。" kind:FYSentenceKindDialogue];
        [app.learningCoordinator selectSentenceID:otherSource.sentenceID version:1 sourceText:otherSource.sourceText translation:@"救助同伴。"]; [app refreshLearningSource];
        Bookmark(app, @"救う", @"救う", @"すくう", @"拯救");
        Check(Examples(store, completed.vocabularyID).count == 2, @"merged vocabulary preserves both source examples");
        [app refreshVocabularyList]; Pump(^BOOL { return app.reviewList.count == 1; });
        Pump(^BOOL { return [RenderedText(app.wordCardStack) containsString:@"来源例句 1 / 2"]; });
        NSString *firstExample = RenderedText(app.wordCardStack);
        NSButton *cycle = [NSButton new]; cycle.identifier = completed.vocabularyID; [app nextWordExample:cycle];
        Pump(^BOOL { return [RenderedText(app.wordCardStack) containsString:@"来源例句 2 / 2"]; });
        NSArray<FYVocabularyExample *> *allExamples = Examples(store, completed.vocabularyID);
        Check([firstExample containsString:allExamples[0].sourceTextSnapshot] && [RenderedText(app.wordCardStack) containsString:allExamples[1].sourceTextSnapshot] && ![allExamples[0].sourceTextSnapshot isEqualToString:allExamples[1].sourceTextSnapshot], @"word card cycles through all associated examples");
        Bookmark(app, @"救う", @"救う", @"すくう", @"其他义项");
        Check(Words(store).count == 2, @"same spelling and reading with different known sense stays distinct");
        __block NSUInteger savedCount = 0;
        for (NSUInteger i = 0; i < 2; i++) {
            FYVocabularyEntry *entry = [FYVocabularyEntry new]; entry.surface = @"猫";
            [app.learningCoordinator bookmarkVocabulary:entry selectedText:@"猫" completion:^(FYVocabularyEntry *saved, BOOL duplicate, NSError *error) { Require(!error, @"concurrent bookmark failed"); savedCount++; }];
        }
        Pump(^BOOL { return savedCount == 2; }); Check(Words(store).count == 3, @"simultaneous repeated saves produce one word");
        Trigger(path, @"CREATE TRIGGER abort_example BEFORE INSERT ON vocabulary_examples BEGIN SELECT RAISE(ABORT, 'injected example failure'); END;");
        FYVocabularyEntry *failed = [FYVocabularyEntry new]; failed.surface = @"失敗";
        __block BOOL finished = NO; __block NSError *failedError;
        [app.learningCoordinator bookmarkVocabulary:failed selectedText:failed.surface completion:^(FYVocabularyEntry *saved, BOOL duplicate, NSError *error) { failedError = error; finished = YES; }]; Pump(^BOOL { return finished; });
        Check(failedError != nil && Words(store).count == 3, @"example write failure rolls back vocabulary entry atomically"); Trigger(path, @"DROP TRIGGER abort_example;");
        [app refreshVocabularyList]; Pump(^BOOL { return app.reviewList.count == 3; }); [app nextReviewWord:nil];
        NSButton *remove = [NSButton new]; remove.identifier = app.reviewingEntry.vocabularyID; [app removeWordCard:remove];
        Pump(^BOOL { return app.reviewList.count == 2; }); [app revealReviewMeaning:nil];
        Check(app.reviewingEntry == nil && app.reviewWordLabel.stringValue.length == 0 && app.reviewMeaningLabel.stringValue.length == 0, @"deleting review word clears review even with other words remaining");
        // Old card must not mutate whatever happens to occupy its former list index.
        [app removeWordCard:remove]; Drain(store); Check(Words(store).count == 2, @"stale card action cannot delete a different word");

        // Malformed schema responses fail, are never cached, and a valid empty response can still cache.
        NSString *schemaPath = [directory stringByAppendingPathComponent:@"schema.sqlite3"];
        FYLearningStore *schemaStore = Store(schemaPath); FYLearningAnalyzer *schemaAnalyzer = Analyzer(catalog);
        AppDelegate *schema = App(schemaStore, schemaAnalyzer, catalog);
        [schema.learningCoordinator recordText:@"テスト。" kind:FYSentenceKindDialogue];
        __block NSUInteger requests = 0;
        schemaAnalyzer.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) { requests++; done(Envelope(@"{\"schema_version\":1,\"grammar\":[42],\"vocabulary\":[42]}"), Response(), nil); };
        for (NSUInteger i = 0; i < 2; i++) {
            __block BOOL done = NO; __block NSError *error; __block FYAnalysisResult *result;
            [schema.learningCoordinator analyzeCurrent:^(FYAnalysisResult *value, NSError *e) { error = e; result = value; done = YES; }]; Pump(^BOOL { return done; });
            Check(error != nil && result == nil, @"malformed array entry is a failure, not empty grammar");
        }
        Check(requests == 2, @"malformed responses do not poison analysis cache");
        NSArray *invalid = @[@"{\"schema_version\":true,\"grammar\":[],\"vocabulary\":[]}", @"{\"schema_version\":2,\"grammar\":[],\"vocabulary\":[]}", @"{\"schema_version\":1,\"grammar\":[{\"name\":\"X\"}],\"vocabulary\":[]}"];
        for (NSString *json in invalid) {
            schemaAnalyzer.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) { done(Envelope(json), Response(), nil); };
            __block NSError *error; [schemaAnalyzer analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *result, NSError *e) { error = e; }]; Pump(^BOOL { return error != nil; }); Check(error != nil, @"unsupported or incomplete analysis schema rejected");
        }
        schemaAnalyzer.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) { requests++; done(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"), Response(), nil); };
        for (NSUInteger i = 0; i < 2; i++) {
            __block FYAnalysisResult *result; [schema.learningCoordinator analyzeCurrent:^(FYAnalysisResult *r, NSError *error) { Require(!error, @"valid empty response failed"); result = r; }]; Pump(^BOOL { return result != nil; }); Drain(schemaStore);
            Check(result.status == FYAnalysisStatusNoResult, @"valid empty arrays preserve no-result behavior");
        }
        Check(requests == 3, @"valid no-result analysis is cached");
        // Corrupt cache JSON must be a miss, with a new request rather than a crash/false no-result.
        Trigger(schemaPath, @"UPDATE analyses SET result_json = '{\"schema_version\":null,\"grammar\":{},\"vocabulary\":[]}' WHERE 1;");
        __block FYAnalysisResult *recovered = nil;
        [schema.learningCoordinator analyzeCurrent:^(FYAnalysisResult *r, NSError *error) { Require(!error, @"cache recovery failed"); recovered = r; }]; Pump(^BOOL { return recovered != nil; });
        Check(requests == 4 && recovered.status == FYAnalysisStatusNoResult, @"corrupt cache safely falls back to fresh analysis");
        schemaAnalyzer.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) { done(Envelope(@"{\"schema_version\":1,\"grammar\":[{\"name\":\"X\",\"matched_text\":\"不存在\"}],\"vocabulary\":[]}"), Response(), nil); };
        __block NSError *inventedError = nil;
        [schemaAnalyzer analyzeSentence:@"テスト。" translation:nil completion:^(FYAnalysisResult *r, NSError *error) { inventedError = error; }]; Pump(^BOOL { return inventedError != nil; });
        Check(inventedError != nil, @"invented grammar match is rejected rather than saved as a result");
        __block void (^late)(NSData *, NSURLResponse *, NSError *); __block NSUInteger delivered = 0;
        schemaAnalyzer.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) { late = done; };
        [schemaAnalyzer analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *result, NSError *error) { Require(!result && error.code == 499, @"cancellation must be an error"); delivered++; }];
        [schemaAnalyzer cancelAll]; Check(delivered == 1, @"cancel ends pending request immediately");
        late(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"), Response(), nil); Tick(); Check(delivered == 1, @"late transport callback cannot deliver cancellation twice");

        for (FYLearningStore *s in @[store, schemaStore]) {
            __block BOOL closed = NO; [s closeWithCompletion:^(NSError *error) { Require(!error, @"close failed"); closed = YES; }]; Pump(^BOOL { return closed; });
        }
        [app.mainWindow orderOut:nil]; [schema.mainWindow orderOut:nil];
        Require([[NSFileManager defaultManager] removeItemAtPath:directory error:NULL], @"temporary cleanup failed");
        NSLog(@"PASS: %lu native application/data regression checks; no real API, capture, preferences or user database used.", checks);
    }
    return 0;
}
