#import "LearningAppTestSupport.h"

static NSArray<FYSentenceRecord *> *History(FYLearningStore *store) {
    __block NSArray *rows;
    [store fetchRecentSentencesWithLimit:100 completion:^(NSArray *records, NSError *error) {
        Require(!error, @"history read failed"); rows = records;
    }];
    Pump(^BOOL { return rows != nil; }); return rows;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        FYLearningStore *store = Store([directory stringByAppendingPathComponent:@"dedup.sqlite3"]);
        __block BOOL configured = NO;
        [store configureHistoryRetentionWithLimit:5 completion:^(NSError *error) { Require(!error, @"retention failed"); configured = YES; }];
        Pump(^BOOL { return configured; });
        FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
        Require([catalog loadWithError:NULL], @"catalog failed");
        AppDelegate *app = App(store, Analyzer(catalog), catalog);
        FYLearningCoordinator *coordinator = app.learningCoordinator;
        NSString *source = @"ルード\nやれやれ\n世話が焼けますね";
        FYRequestIdentity *first = [coordinator recordText:source kind:FYSentenceKindDialogue];
        for (NSString *variant in @[@"ルード\n-やれやれ\n世話が焼けますね", @"ルード\nーやれやれ\n世話が焼けますね", @"ルード\n—やれやれ.\n世話が焼けますね", @"ルード\nーやれやれ。\n世話が焼けますね。", @" ルード \n－ やれやれ\n 世話が焼けますね ", @"ルード やれやれ 世話が焼けますね", source]) {
            FYRequestIdentity *identity = [coordinator recordText:variant kind:FYSentenceKindDialogue];
            Require([identity.sentenceID isEqualToString:first.sentenceID], @"OCR dash/spacing fluctuation must reuse the dialogue identity");
        }
        NSArray *rows = History(store);
        Require(rows.count == 1 && [[rows[0] latestText] isEqualToString:source], @"alternating OCR must persist one sentence without rewriting its source");
        NSArray *options = [coordinator recordItems:@[@"はい", @"いいえ"] kind:FYSentenceKindOption];
        FYRequestIdentity *afterOptions = [coordinator recordText:source kind:FYSentenceKindDialogue];
        Require([afterOptions.sentenceID isEqualToString:first.sentenceID], @"option recording must not break dialogue deduplication");
        Require(![[options[0] sentenceID] isEqualToString:first.sentenceID] && History(store).count == 3, @"options must keep separate identities and translations");
        [coordinator pinCurrent];
        __block BOOL corrected = NO;
        [coordinator correctCurrentSentenceText:@"ルード\nやれやれ。世話が焼けますね。" completion:^(NSError *error) { Require(!error, @"correction failed"); corrected = YES; }];
        Pump(^BOOL { return corrected; });
        [coordinator recordText:@"ルード\n-やれやれ\n世話が焼けますね" kind:FYSentenceKindDialogue];
        [coordinator setTranslation:@"旧版译文" forIdentity:first];
        Drain(store);
        Require(coordinator.currentVersion == 2 && [coordinator.currentSourceText hasSuffix:@"ね。"] && coordinator.currentTranslation == nil, @"OCR reuse and old translation callbacks must preserve the corrected version");
        NSString *different = @"ルード\nやれやれ\n世話が焼けませんね";
        FYRequestIdentity *next = [coordinator recordText:different kind:FYSentenceKindDialogue];
        Require(![next.sentenceID isEqualToString:first.sentenceID], @"a real character change must create a new sentence");
        FYRequestIdentity *recurrence = [coordinator recordText:source kind:FYSentenceKindDialogue];
        Require(![recurrence.sentenceID isEqualToString:first.sentenceID], @"A then B then A must preserve the genuine repeated occurrence");
        [coordinator recordText:@"メニュー" kind:FYSentenceKindUI];
        FYRequestIdentity *afterUI = [coordinator recordText:source kind:FYSentenceKindDialogue];
        Require(![afterUI.sentenceID isEqualToString:recurrence.sentenceID], @"returning from another content context must create a new occurrence");
        for (NSArray<NSString *> *pair in @[@[@"ルード", @"ルド"], @[@"行く。", @"行く？"], @[@"-1人", @"1人"], @[@"猫-犬", @"猫犬"], @[@"1.5", @"15"], @[@"猫！", @"猫"]]) {
            FYRequestIdentity *a = [coordinator recordText:pair[0] kind:FYSentenceKindDialogue];
            FYRequestIdentity *b = [coordinator recordText:pair[1] kind:FYSentenceKindDialogue];
            Require(![a.sentenceID isEqualToString:b.sentenceID], @"long vowels, punctuation, negative numbers and internal dashes must remain meaningful");
        }
        FYRequestIdentity *evicted = [coordinator recordText:@"選択肢が多い場面。" kind:FYSentenceKindDialogue];
        [coordinator recordItems:@[@"一番", @"二番", @"三番", @"四番", @"五番"] kind:FYSentenceKindOption];
        FYRequestIdentity *restored = [coordinator recordText:@"選択肢が多い場面。" kind:FYSentenceKindDialogue];
        Require(![restored.sentenceID isEqualToString:evicted.sentenceID], @"an evicted dialogue identity must not be reused");
        Require([[[History(store) firstObject] sentenceID] isEqualToString:restored.sentenceID], @"dialogue after many options must exist in persistent history");
        [coordinator followLatest]; Drain(store);
        Require(History(store).count == 5, @"deduplication must retain the five-record history policy");

        // Replay the actual five rows from the user's screenshot, including
        // old app sessions. The list must group them without deleting records.
        NSArray<NSString *> *legacy = @[@"ルード\n-やれやれ\n世話が焼けますね", source,
                                       @"ルード\nーやれやれ\n世話が焼けますね",
                                       @"ルード\n—やれやれ.\n世話が焼けますね",
                                       @"ルード\nーやれやれ\n世話が焼けますね"];
        for (NSString *session in @[@"legacy-old", @"legacy-new"]) {
            [store ensureSessionWithID:session displayName:@"" language:@"日文" completion:^(NSError *error) { Require(!error, @"legacy session failed"); }];
        }
        for (NSUInteger i = 0; i < legacy.count; i++) {
            NSString *sid = [NSString stringWithFormat:@"legacy-%lu", (unsigned long)i];
            [store insertSentenceWithID:sid sessionID:i < 2 ? @"legacy-old" : @"legacy-new" kind:FYSentenceKindDialogue originalText:legacy[i]
                              occurredAt:[NSDate dateWithTimeIntervalSinceNow:100 + i] completion:^(NSError *error) { Require(!error, @"legacy insert failed"); }];
        }
        Drain(store);
        NSArray *legacyRows = History(store);
        Require(legacyRows.count == 5, @"legacy fixture must have all five duplicate rows");
        [app refreshHistory];
        Pump(^BOOL { return app.historyRecords.count == 1; });
        Require([app.historyRecords.firstObject.sentenceID isEqualToString:@"legacy-4"], @"history must show the latest stable identity for equivalent old text");
        Require(History(store).count == 5, @"history grouping must preserve old versions and source snapshots in the database");
        NSButton *action = [NSButton new]; action.tag = 0; action.identifier = @"legacy-4";
        [app openHistoryAnalysis:action];
        Require([coordinator.currentSentenceID isEqualToString:@"legacy-4"], @"analysis action must use the representative sentence's stable identity");
        [coordinator followLatest];
        NSString *complete = @"ルード\n無事ですか？\nそれなら、結構です";
        NSArray<NSString *> *partialFrames = @[@"ルード\n無事です。_\nそれなら、", @"ルード\n無事です。。\nそれなら、", @"ルード\n無事です\nそれなり"];
        FYRequestIdentity *completeIdentity = [coordinator recordText:complete kind:FYSentenceKindDialogue];
        for (NSUInteger i = 0; i < 10; i++) {
            FYRequestIdentity *partial = [coordinator recordText:partialFrames[i % partialFrames.count] kind:FYSentenceKindDialogue];
            Require([partial.sentenceID isEqualToString:completeIdentity.sentenceID] && [partial.sourceText isEqualToString:complete], @"degraded frames must reuse the complete source and translation identity");
            Require([[coordinator recordText:complete kind:FYSentenceKindDialogue].sentenceID isEqualToString:completeIdentity.sentenceID], @"complete/partial oscillation must not create new history");
        }
        for (NSString *distinct in @[@"ルード\n無事です。\nそれなら、結構です", @"ルード\n無事ではない\nそれなら、", @"別人\n無事です。。\nそれなら、", @"ルード\n無事ですか？\nそれなら、無理です"]) {
            Require(!FYDialogueIsIncompleteFrame(distinct, complete), @"meaningful punctuation, negation, speaker and continuation changes must remain distinct");
        }
        // Even when the newest frame is degraded, show the complete record.
        NSArray *actual = @[partialFrames[1], complete, partialFrames[0], complete, partialFrames[2]];
        for (NSUInteger i = 0; i < actual.count; i++) {
            [store insertSentenceWithID:[NSString stringWithFormat:@"actual-%lu", (unsigned long)i] sessionID:@"legacy-new" kind:FYSentenceKindDialogue originalText:actual[i] occurredAt:[NSDate dateWithTimeIntervalSinceNow:200 + i] completion:^(NSError *error) { Require(!error, @"actual OCR fixture insert failed"); }];
        }
        Drain(store);
        [app refreshHistory];
        Pump(^BOOL { return [app.historyRecords.firstObject.sentenceID isEqualToString:@"actual-3"]; });
        Require(app.historyRecords.count == 1 && History(store).count == 5, @"actual five rows must show one complete dialogue without rewriting stored history");
        // Live rows from 2026-10-04: one dialogue read three times (variable
        // leading dot run, missed speaker box, clipped last line) next to a
        // genuine option. All three reads must collapse into one list row.
        NSString *body = @"返す言葉もない、な\n鬼の潜入、読みきれなかった\n我の手落ちだ";
        NSString *dotRun = [NSString stringWithFormat:@"%@%@", [@"" stringByPaddingToLength:11 withString:@"・" startingAtIndex:0], body];
        NSString *mixedRun = [NSString stringWithFormat:@"…••••%@", body];
        NSString *withSpeaker = [NSString stringWithFormat:@"萩尾九段\n%@", body];
        Require([FYDialogueComparisonKey(dotRun) isEqualToString:FYDialogueComparisonKey(mixedRun)], @"variable leading dot runs must share one comparison key");
        Require(FYDialogueIsFragmentOfDialogue(body, withSpeaker), @"a missed speaker box reads as the tail of the same box");
        Require(FYDialogueIsFragmentOfDialogue(@"我の手落ちだ", body), @"a clipped last line reads as a fragment");
        Require(!FYDialogueIsFragmentOfDialogue(withSpeaker, body), @"the complete frame must not be treated as the fragment");
        Require(!FYDialogueTextsAreEquivalent(@"はい", @"はい\nそうか\nなるほど"), @"a lone first line must not merge into a longer dialogue");
        NSString *changedBody = @"返す言葉もない、な\n鬼の潜入、読みきれなかった\n我の手落ちだった";
        Require(!FYDialogueTextsAreEquivalent(body, changedBody), @"a changed word must stay a separate dialogue");
        Require(!FYDialogueTextsAreEquivalent(@"我の手落ちだ", changedBody), @"a lone line must not merge with an unrelated dialogue");

        FYLearningStore *liveStore = Store([directory stringByAppendingPathComponent:@"live.sqlite3"]);
        __block BOOL liveConfigured = NO;
        [liveStore configureHistoryRetentionWithLimit:5 completion:^(NSError *error) { Require(!error, @"live retention failed"); liveConfigured = YES; }];
        Pump(^BOOL { return liveConfigured; });
        AppDelegate *liveApp = App(liveStore, Analyzer(catalog), catalog);
        [liveStore ensureSessionWithID:@"live-session" displayName:@"" language:@"日文" completion:^(NSError *error) { Require(!error, @"live session failed"); }];
        NSArray *liveRows = @[@{@"kind": @(FYSentenceKindDialogue), @"text": withSpeaker},
                              @{@"kind": @(FYSentenceKindDialogue), @"text": @"我の手落ちだ"},
                              @{@"kind": @(FYSentenceKindOption), @"text": @"萩尾九段"},
                              @{@"kind": @(FYSentenceKindDialogue), @"text": dotRun},
                              @{@"kind": @(FYSentenceKindDialogue), @"text": mixedRun},
                              @{@"kind": @(FYSentenceKindDialogue), @"text": dotRun}];
        for (NSUInteger i = 0; i < liveRows.count; i++) {
            [liveStore insertSentenceWithID:[NSString stringWithFormat:@"live-%lu", (unsigned long)i] sessionID:@"live-session"
                                       kind:(FYSentenceKind)[liveRows[i][@"kind"] integerValue] originalText:liveRows[i][@"text"]
                                 occurredAt:[NSDate dateWithTimeIntervalSinceNow:i] completion:^(NSError *error) { Require(!error, @"live insert failed"); }];
        }
        Drain(liveStore);
        Require(History(liveStore).count == 5, @"five-record retention must prune the oldest live row");
        [liveApp refreshHistory];
        Pump(^BOOL { return liveApp.historyRecords.count > 0; });
        Require(liveApp.historyRecords.count == 2, @"three live reads of one dialogue plus one option must show two rows");
        Require([liveApp.historyRecords.firstObject.latestText isEqualToString:dotRun], @"the newest equivalent read represents the dialogue");
        Require([liveApp.historyRecords.lastObject.latestText isEqualToString:@"萩尾九段"], @"the option keeps its own row");
        // Reading a complete frame first must absorb the degraded frames that follow.
        FYRequestIdentity *completeRead = [liveApp.learningCoordinator recordText:withSpeaker kind:FYSentenceKindDialogue];
        for (NSString *degraded in @[body, @"我の手落ちだ", mixedRun, dotRun]) {
            FYRequestIdentity *identity = [liveApp.learningCoordinator recordText:degraded kind:FYSentenceKindDialogue];
            Require([identity.sentenceID isEqualToString:completeRead.sentenceID], @"degraded reads must reuse the complete dialogue identity");
            Require([identity.sourceText isEqualToString:withSpeaker], @"the saved source must remain the complete frame");
        }
        FYRequestIdentity *changedRead = [liveApp.learningCoordinator recordText:changedBody kind:FYSentenceKindDialogue];
        Require(![changedRead.sentenceID isEqualToString:completeRead.sentenceID], @"a changed word must still create a new occurrence");
        // Actual screenshot: the name box survives, but the first body line
        // disappears. It is not a contiguous substring of the complete box.
        NSString *introduction=@"花椿\nなんだ、お初か。\nこの子、宇賀神みよちゃん。\nね？";
        NSString *missingFirstLine=@"花椿\nこの子、宇賀神みよちゃん。\nね？";
        Require(FYDialogueIsFragmentOfDialogue(missingFirstLine,introduction),@"retained speaker with a missing first body line is a degraded frame");
        FYRequestIdentity *introductionIdentity=[liveApp.learningCoordinator recordText:introduction kind:FYSentenceKindDialogue];
        [liveApp.learningCoordinator setTranslation:@"什么嘛，是小初啊。\n这孩子，是宇贺神美代。\n对吧？" forIdentity:introductionIdentity];
        for(NSUInteger i=0;i<8;i++){
            FYRequestIdentity *frame=[liveApp.learningCoordinator recordText:i%2?introduction:missingFirstLine kind:FYSentenceKindDialogue];
            Require([frame.sentenceID isEqualToString:introductionIdentity.sentenceID] && [frame.sourceText isEqualToString:introduction],@"complete and missing-first-line frames keep one complete source identity");
        }
        Drain(liveStore);
        __block FYRequestIdentity *popupIdentity=nil;
        [liveApp resolveLatestStudyIdentity:^(FYRequestIdentity *identity){popupIdentity=identity;}];
        Pump(^BOOL{return popupIdentity!=nil;});
        Require([popupIdentity.sourceText isEqualToString:introduction] && [popupIdentity.translation containsString:@"小初"],@"quick sentence resolves the complete source and its matching translation");
        for(NSString *distinct in @[@"別人\nこの子、宇賀神みよちゃん。\nね？",@"花椿\nこの子、宇賀神みよちゃん。\nね！",@"花椿\nこの子、宇賀神みよちゃんじゃない。\nね？",@"花椿\nね？",@"花椿\nはい\nね？"]){
            Require(!FYDialogueIsFragmentOfDialogue(distinct,introduction),@"changed speaker, wording, question and insufficient anchors stay distinct");
        }
        FYRequestIdentity *otherIntroduction=[liveApp.learningCoordinator recordText:@"花椿\nなんだ、お初か。\nこの子、別の子だよ。\nね？" kind:FYSentenceKindDialogue];
        Require(![otherIntroduction.sentenceID isEqualToString:introductionIdentity.sentenceID],@"a new introduction with a changed child keeps its own identity");
        Require(![[liveApp.learningCoordinator recordText:introduction kind:FYSentenceKindDialogue].sentenceID isEqualToString:introductionIdentity.sentenceID],@"returning to the complete introduction after another dialogue is a new occurrence");
        // 2026-10-05 screenshot: just the second line is severely clipped,
        // with a misread edge glyph, while the two following lines are exact.
        NSString *consultation=@"よかったぁ！\nじゃあさ、なんか相談あったら\n何でも聞いて？ お店に来て\nくれたらサービスしちゃう！";
        NSArray *consultationClips=@[@"よかったぁ！\nじゃあこ\n何でも聞いて？ お店に来て\nくれたらサービスしちゃう！",@"よかったぁ！\nじゃあi\n何でも聞いて？ お店に来て\nくれたらサービスしちゃう！"];
        for(NSString *clip in consultationClips){Require(FYDialogueIsIncompleteFrame(clip,consultation),@"one clipped interior line with two intact anchors must be recognized");}
        for(NSString *distinct in @[[consultation stringByReplacingOccurrencesOfString:@"相談" withString:@"質問"],[consultation stringByReplacingOccurrencesOfString:@"聞いて？" withString:@"聞かないで！"],[consultation stringByReplacingOccurrencesOfString:@"じゃあさ、なんか相談あったら" withString:@"じゃあさ、相談はなかった"]]){Require(!FYDialogueTextsAreEquivalent(distinct,consultation),@"genuine wording and negation changes must not merge with consultation");}
        FYRequestIdentity *consultationIdentity=[liveApp.learningCoordinator recordText:consultation kind:FYSentenceKindDialogue];
        for(NSUInteger i=0;i<8;i++){FYRequestIdentity *clipIdentity=[liveApp.learningCoordinator recordText:consultationClips[i%2] kind:FYSentenceKindDialogue];Require([clipIdentity.sentenceID isEqualToString:consultationIdentity.sentenceID] && [clipIdentity.sourceText isEqualToString:consultation],@"interior clipped OCR oscillation must retain the complete identity");}
        NSArray *consultationRows=@[consultationClips[1],consultationClips[0],consultation,consultationClips[1],consultationClips[0]];
        for(NSUInteger i=0;i<consultationRows.count;i++){[liveStore insertSentenceWithID:[NSString stringWithFormat:@"consultation-%lu",(unsigned long)i] sessionID:@"live-session" kind:FYSentenceKindDialogue originalText:consultationRows[i] occurredAt:[NSDate dateWithTimeIntervalSinceNow:500+i] completion:^(NSError *error){Require(!error,@"consultation fixture insert");}];}
        Drain(liveStore);[liveApp refreshHistory];Pump(^BOOL{return [liveApp.historyRecords.firstObject.sentenceID isEqualToString:@"consultation-2"];});
        Require(liveApp.historyRecords.count==1 && History(liveStore).count==5,@"existing clipped rows group into one complete dialogue without rewriting snapshots");
        __block BOOL liveClosed = NO;
        [liveStore closeWithCompletion:^(NSError *error) { Require(!error, @"live close failed"); liveClosed = YES; }];
        Pump(^BOOL { return liveClosed; });
        __block BOOL closed = NO;
        [store closeWithCompletion:^(NSError *error) { Require(!error, @"close failed"); closed = YES; }];
        Pump(^BOOL { return closed; });
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
        NSLog(@"PASS: OCR dialogue deduplication, options, corrections, genuine changes and five-record retention.");
    }
    return 0;
}
