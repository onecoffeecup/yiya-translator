#import "LearningAppTestSupport.h"

static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { Require(ok, message); checks++; NSLog(@"PASS: %@", message); }
static NSArray<FYSentenceRecord *> *History(FYLearningStore *store) {
    __block NSArray *rows;
    [store fetchRecentSentencesWithLimit:100 completion:^(NSArray *records, NSError *error) { Require(!error, @"history read failed"); rows = records; }];
    Pump(^BOOL { return rows != nil; }); return rows;
}
static NSInteger Count(NSString *path, NSString *table) {
    sqlite3 *db = NULL; Require(sqlite3_open(path.UTF8String, &db) == SQLITE_OK, @"count open failed");
    sqlite3_stmt *statement = NULL;
    NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@;", table];
    Require(sqlite3_prepare_v2(db, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK, @"count prepare failed");
    Require(sqlite3_step(statement) == SQLITE_ROW, @"count read failed");
    NSInteger count = sqlite3_column_int(statement, 0); sqlite3_finalize(statement); sqlite3_close(db); return count;
}
static void Insert(FYLearningStore *store, NSString *sid, NSTimeInterval time) {
    __block BOOL done = NO;
    NSString *text = [sid isEqualToString:@"s1"] ? @"猫です。" : [NSString stringWithFormat:@"猫です。%@", sid];
    [store insertSentenceWithID:sid sessionID:@"session" kind:FYSentenceKindDialogue originalText:text occurredAt:[NSDate dateWithTimeIntervalSince1970:time] completion:^(NSError *error) { Require(!error, @"insert failed"); done = YES; }];
    Pump(^BOOL { return done; });
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *path = [directory stringByAppendingPathComponent:@"history.sqlite3"];
        FYLearningStore *store = Store(path);
        [store ensureSessionWithID:@"session" displayName:@"" language:@"日文" completion:^(NSError *error) { Require(!error, @"session failed"); }];
        for (NSUInteger i = 1; i <= 8; i++) { Insert(store, [NSString stringWithFormat:@"s%lu", (unsigned long)i], i); }
        FYVocabularyEntry *word = [FYVocabularyEntry new]; word.vocabularyID = @"word"; word.surface = @"猫"; word.meaning = @"猫";
        FYVocabularyExample *example = [FYVocabularyExample new]; example.vocabularyID = word.vocabularyID;
        example.sentenceID = @"s1"; example.version = 1; example.sourceTextSnapshot = @"猫です。"; example.translationSnapshot = @"是猫。"; example.selectedRangeText = @"猫";
        [store saveVocabulary:word withExample:example completion:^(NSError *error) { Require(!error, @"save word failed"); }];
        FYGrammarBookmark *bookmark = [FYGrammarBookmark new]; bookmark.bookmarkID = @"grammar"; bookmark.name = @"です";
        bookmark.sentenceID = @"s1"; bookmark.version = 1; bookmark.sourceTextSnapshot = example.sourceTextSnapshot; bookmark.translationSnapshot = example.translationSnapshot;
        [store addGrammarBookmark:bookmark completion:^(NSError *error) { Require(!error, @"save grammar failed"); }];
        FYAnalysisResult *analysis = [FYAnalysisResult new]; analysis.schemaVersion = 1; analysis.status = FYAnalysisStatusNoResult; analysis.grammar = @[]; analysis.vocabulary = @[];
        [store saveAnalysisResult:analysis sentenceID:@"s1" version:1 textHash:@"h" promptVersion:2 catalogVersion:1 modelConfig:@"test" completion:^(NSError *error) { Require(!error, @"cache failed"); }];
        __block BOOL configured = NO;
        [store configureHistoryRetentionWithLimit:FYRecentSentenceLimit completion:^(NSError *error) { Require(!error, @"prune failed"); configured = YES; }]; Pump(^BOOL { return configured; });
        NSArray *rows = History(store);
        Check(rows.count == 5 && [[rows[0] sentenceID] isEqualToString:@"s8"] && [[rows[4] sentenceID] isEqualToString:@"s4"], @"existing history keeps exactly the latest five in descending order");
        Check(Count(path, @"sentence_versions") == 5 && Count(path, @"analyses") == 0, @"old versions and analysis caches are removed with their sentences");
        __block NSArray *examples;
        [store fetchExamplesForVocabulary:@"word" completion:^(NSArray *value, NSError *error) { Require(!error, @"examples failed"); examples = value; }]; Pump(^BOOL { return examples != nil; });
        Check(Words(store).count == 1 && examples.count == 1 && [[[examples firstObject] sourceTextSnapshot] isEqualToString:@"猫です。"] && [[[examples firstObject] translationSnapshot] isEqualToString:@"是猫。"], @"saved vocabulary and its original/translated example survive history cleanup");
        __block NSArray *bookmarks;
        [store fetchGrammarBookmarksWithCompletion:^(NSArray *value, NSError *error) { Require(!error, @"bookmarks failed"); bookmarks = value; }]; Pump(^BOOL { return bookmarks != nil; });
        Check(bookmarks.count == 1 && [[[bookmarks firstObject] sourceTextSnapshot] isEqualToString:@"猫です。"], @"saved grammar keeps its source snapshot after history cleanup");
        FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]]; Require([catalog loadWithError:NULL], @"catalog failed");
        AppDelegate *app = App(store, Analyzer(catalog), catalog);
        [app.learningCoordinator selectHistorySentence:rows[4]]; Drain(store);
        Insert(store, @"s9", 9); Insert(store, @"s10", 10);
        Check(History(store).count == 6, @"pinned old sentence remains usable outside the five recent entries");
        __block BOOL edited = NO;
        [app.learningCoordinator correctCurrentSentenceText:@"猫でした。" completion:^(NSError *error) { Require(!error, @"pinned correction failed"); edited = YES; }]; Pump(^BOOL { return edited; });
        Check(app.learningCoordinator.currentVersion == 2, @"pinned sentence can still be edited while newer sentences arrive");
        [app refreshHistory]; Pump(^BOOL { return app.historyRecords.count == 5 && [[app.historyRecords[0] sentenceID] isEqualToString:@"s10"]; });
        Check([[app.historyRecords[0] sentenceID] isEqualToString:@"s10"] && [[app.historyRecords[4] sentenceID] isEqualToString:@"s6"], @"native recent-dialogue UI shows only five even with a pinned old sentence");
        [app.learningCoordinator followLatest]; Drain(store);
        Check(History(store).count == 5 && Count(path, @"sentence_versions") == 5, @"releasing the pinned sentence removes its old history and versions");
        Insert(store, @"same-time-a", 20); Insert(store, @"same-time-b", 20);
        rows = History(store);
        Check(rows.count == 5 && [[rows[0] sentenceID] isEqualToString:@"same-time-b"] && [[rows[1] sentenceID] isEqualToString:@"same-time-a"], @"timestamp ties use insertion order consistently for pruning and display");
        Trigger(path, @"CREATE TRIGGER fail_prune BEFORE DELETE ON sentences BEGIN SELECT RAISE(ABORT, 'injected cleanup failure'); END;");
        __block BOOL failed = NO;
        [store insertSentenceWithID:@"rollback" sessionID:@"session" kind:FYSentenceKindDialogue originalText:@"失敗" occurredAt:[NSDate dateWithTimeIntervalSince1970:21] completion:^(NSError *error) { failed = error != nil; }]; Pump(^BOOL { return failed; });
        Check(History(store).count == 5 && Count(path, @"sentence_versions") == 5 && [[[History(store) firstObject] sentenceID] isEqualToString:@"same-time-b"], @"failed cleanup rolls back the new sentence and preserves previous history");
        Trigger(path, @"DROP TRIGGER fail_prune;");
        __block BOOL closed = NO; [store closeWithCompletion:^(NSError *error) { Require(!error, @"close failed"); closed = YES; }]; Pump(^BOOL { return closed; });
        store = Store(path); configured = NO;
        [store configureHistoryRetentionWithLimit:FYRecentSentenceLimit completion:^(NSError *error) { Require(!error, @"reopen configure failed"); configured = YES; }]; Pump(^BOOL { return configured; });
        Check(History(store).count == 5 && Words(store).count == 1, @"five-record retention and saved words persist after restart");
        closed = NO; [store closeWithCompletion:^(NSError *error) { Require(!error, @"final close failed"); closed = YES; }]; Pump(^BOOL { return closed; });
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
        NSLog(@"History retention tests passed (%lu checks)", (unsigned long)checks);
    }
    return 0;
}
