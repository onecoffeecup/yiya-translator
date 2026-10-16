#import "FYLearningStore.h"
#import "FYReferenceDictionary.h"
#import <sqlite3.h>

@interface FYLearningStore (ResilienceProbe)
- (sqlite3 *)db;
@end
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL %@", message); exit(1); } }
static void Pump(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && deadline.timeIntervalSinceNow > 0) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]]; }
    Check(done(), @"isolated store callback finishes");
}
static void AwaitWrite(void (^operation)(void (^)(NSError *))) {
    __block BOOL done = NO; __block NSError *failure;
    operation(^(NSError *error) { failure = error; done = YES; });
    Pump(^BOOL { return done; }); Check(!failure, @"synthetic fixture write succeeds");
}
static FYLearningStore *FixtureStore(void) {
    NSString *path = [FYTestTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite"]];
    FYLearningStore *store = [[FYLearningStore alloc] initWithDatabasePath:path];
    AwaitWrite(^(void (^done)(NSError *)) { [store openWithCompletion:done]; });
    AwaitWrite(^(void (^done)(NSError *)) { [store ensureSessionWithID:@"session" displayName:@"fixture" language:@"ja" completion:done]; });
    AwaitWrite(^(void (^done)(NSError *)) { [store insertSentenceWithID:@"sentence" sessionID:@"session" kind:FYSentenceKindDialogue originalText:@"合成原文" occurredAt:NSDate.date completion:done]; });
    AwaitWrite(^(void (^done)(NSError *)) { [store updateTranslation:@"原译文" forSentence:@"sentence" version:1 completion:done]; });
    return store;
}
static void OnStore(FYLearningStore *store, void (^work)(sqlite3 *)) {
    dispatch_sync([store valueForKey:@"queue"], ^{ work(store.db); });
}
static NSArray<FYSentenceRecord *> *Recent(FYLearningStore *store, NSUInteger limit) {
    __block NSArray *rows;
    [store fetchRecentSentencesWithLimit:limit completion:^(NSArray *records, NSError *error) {
        Check(!error, @"read synthetic recent history"); rows = records;
    }];
    Pump(^BOOL { return rows != nil; }); return rows;
}
static void InsertHistory(FYLearningStore *store, NSString *sid, NSTimeInterval time) {
    AwaitWrite(^(void (^done)(NSError *)) {
        [store insertSentenceWithID:sid sessionID:@"session" kind:FYSentenceKindDialogue
                       originalText:[@"合成原文 " stringByAppendingString:sid]
                         occurredAt:[NSDate dateWithTimeIntervalSince1970:time] completion:done];
    });
}
static void TranslateHistory(FYLearningStore *store, NSString *sid, NSInteger version, NSString *translation) {
    AwaitWrite(^(void (^done)(NSError *)) { [store updateTranslation:translation forSentence:sid version:version completion:done]; });
}
static void HistoryEligibility(void) {
    NSString *path = [FYTestTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite"]];
    FYLearningStore *store = [[FYLearningStore alloc] initWithDatabasePath:path];
    AwaitWrite(^(void (^done)(NSError *)) { [store ensureSessionWithID:@"session" displayName:@"fixture" language:@"ja" completion:done]; });
    InsertHistory(store, @"pending", 1);
    Check(Recent(store, 5).count == 0, @"pending original must not appear in recent history");
    TranslateHistory(store, @"pending", 1, @" \t\r\n\u3000\u00a0 ");
    Check(Recent(store, 5).count == 0, @"whitespace-only translation must not appear in recent history");
    TranslateHistory(store, @"pending", 1, @"合成译文");
    Check(Recent(store, 5).count == 1, @"successful nonempty translation admits the original to recent history");
    for (NSUInteger i = 2; i <= 5; i++) {
        NSString *sid = [NSString stringWithFormat:@"translated-%lu", (unsigned long)i];
        InsertHistory(store, sid, i); TranslateHistory(store, sid, 1, @"已翻译");
    }
    AwaitWrite(^(void (^done)(NSError *)) { [store configureHistoryRetentionWithLimit:5 completion:done]; });
    for (NSUInteger i = 6; i <= 13; i++) { InsertHistory(store, [NSString stringWithFormat:@"waiting-%lu", (unsigned long)i], i); }
    NSArray<FYSentenceRecord *> *rows = Recent(store, 5);
    Check(rows.count == 5 && [rows.firstObject.sentenceID isEqual:@"translated-5"] && [rows.lastObject.sentenceID isEqual:@"pending"],
          @"failed, cancelled or waiting requests cannot consume the five translated history slots");
    __block FYSentenceRecord *waiting; __block BOOL fetched = NO;
    [store fetchSentence:@"waiting-13" completion:^(FYSentenceRecord *record, NSError *error) { Check(!error, @"fetch pending identity"); waiting = record; fetched = YES; }];
    Pump(^BOOL { return fetched; });
    Check(waiting != nil, @"latest pending source remains available for retry and learning");
    OnStore(store, ^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL; sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sentences", -1, &stmt, NULL);
        Check(sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) <= 10, @"pending staging remains bounded separately from translated history");
        sqlite3_finalize(stmt);
    });
    // A failed promotion must roll back both translations and retention cleanup.
    OnStore(store, ^(sqlite3 *db) { Check(sqlite3_exec(db, "CREATE TEMP TRIGGER fail_history_prune BEFORE DELETE ON sentences BEGIN SELECT RAISE(ABORT,'fixture'); END", NULL, NULL, NULL) == SQLITE_OK, @"install history cleanup fault"); });
    __block BOOL done = NO; __block NSError *failure;
    [store updateTranslation:@"应回滚" forSentence:@"waiting-13" version:1 completion:^(NSError *error) { failure = error; done = YES; }];
    Pump(^BOOL { return done; }); Check(failure != nil, @"failed history promotion reports cleanup failure");
    rows = Recent(store, 5);
    Check(rows.count == 5 && [rows.firstObject.sentenceID isEqual:@"translated-5"], @"failed promotion preserves all five previous translated records");
    OnStore(store, ^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL; sqlite3_prepare_v2(db, "SELECT v.translation,s.latest_translation FROM sentence_versions v JOIN sentences s USING(sentence_id) WHERE s.sentence_id='waiting-13'", -1, &stmt, NULL);
        Check(sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) == SQLITE_NULL && sqlite3_column_type(stmt, 1) == SQLITE_NULL,
              @"failed promotion rolls back version and latest translations together"); sqlite3_finalize(stmt);
        sqlite3_exec(db, "DROP TRIGGER fail_history_prune", NULL, NULL, NULL);
    });
    TranslateHistory(store, @"waiting-13", 1, @"重试成功");
    rows = Recent(store, 5);
    Check(rows.count == 5 && [rows.firstObject.sentenceID isEqual:@"waiting-13"] && [rows.lastObject.sentenceID isEqual:@"translated-2"],
          @"retry success enters history and evicts only the oldest translated record");
    OnStore(store, ^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL; sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sentences WHERE sentence_id='pending'", -1, &stmt, NULL);
        Check(sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) == 0, @"successful translation triggers persistent history pruning"); sqlite3_finalize(stmt);
    });
    __block NSInteger version = 0;
    [store appendVersionForSentence:@"waiting-13" text:@"修正原文" translation:nil completion:^(NSInteger value, NSError *error) { Check(!error, @"append corrected source"); version = value; }];
    Pump(^BOOL { return version != 0; });
    TranslateHistory(store, @"waiting-13", 1, @"迟到的旧版本译文");
    Check(Recent(store, 5).count == 4, @"old version callback cannot qualify the untranslated corrected version");
    TranslateHistory(store, @"waiting-13", version, @"修正后译文");
    Check(Recent(store, 5).count == 5, @"matching corrected-version translation restores history eligibility");
    AwaitWrite(^(void (^done)(NSError *)) { [store closeWithCompletion:done]; });
    store = [[FYLearningStore alloc] initWithDatabasePath:path];
    AwaitWrite(^(void (^done)(NSError *)) { [store configureHistoryRetentionWithLimit:5 completion:done]; });
    rows = Recent(store, 5);
    Check(rows.count == 5 && [rows.firstObject.latestTranslation isEqual:@"修正后译文"], @"translated-only history survives restart alongside pending records");
    // Old releases could store blank translations verbatim. Filter before LIMIT.
    OnStore(store, ^(sqlite3 *db) { Check(sqlite3_exec(db, "UPDATE sentences SET latest_translation=' \n\t　  ' WHERE sentence_id LIKE 'waiting-%'", NULL, NULL, NULL) == SQLITE_OK, @"inject legacy whitespace translations"); });
    rows = Recent(store, 1);
    Check(rows.count == 1 && [rows.firstObject.sentenceID isEqual:@"translated-5"], @"legacy blank rows are excluded before applying the requested limit");
    AwaitWrite(^(void (^done)(NSError *)) { [store closeWithCompletion:done]; });
}
static void TransactionFailure(void) {
    FYLearningStore *store = FixtureStore();
    OnStore(store, ^(sqlite3 *db) { Check(sqlite3_exec(db, "CREATE TEMP TRIGGER fail_latest BEFORE UPDATE OF latest_translation ON sentences BEGIN SELECT RAISE(ABORT,'fixture'); END", NULL, NULL, NULL) == SQLITE_OK, @"install second-write fault"); });
    __block BOOL done = NO; __block NSError *failure;
    [store updateTranslation:@"不应提交" forSentence:@"sentence" version:1 completion:^(NSError *error) { failure = error; done = YES; }];
    Pump(^BOOL { return done; }); Check(failure != nil, @"second UPDATE failure reaches caller");
    OnStore(store, ^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        Check(sqlite3_prepare_v2(db, "SELECT v.translation,s.latest_translation FROM sentence_versions v JOIN sentences s USING(sentence_id)", -1, &stmt, NULL) == SQLITE_OK, @"read both translation records");
        Check(sqlite3_step(stmt) == SQLITE_ROW, @"fixture translation exists");
        Check(strcmp((const char *)sqlite3_column_text(stmt, 0), "原译文") == 0 && strcmp((const char *)sqlite3_column_text(stmt, 1), "原译文") == 0, @"both records roll back together");
        sqlite3_finalize(stmt); sqlite3_exec(db, "DROP TRIGGER fail_latest", NULL, NULL, NULL);
    });
    AwaitWrite(^(void (^done)(NSError *)) { [store updateTranslation:@"恢复译文" forSentence:@"sentence" version:1 completion:done]; });
    AwaitWrite(^(void (^done)(NSError *)) { [store closeWithCompletion:done]; });
}
static void BusyClose(void) {
    FYLearningStore *store = FixtureStore(); __block sqlite3 *original; __block sqlite3_stmt *held;
    OnStore(store, ^(sqlite3 *db) { original = db; Check(sqlite3_prepare_v2(db, "SELECT * FROM sentences", -1, &held, NULL) == SQLITE_OK, @"hold unfinished statement"); });
    __block BOOL done = NO; __block NSError *failure;
    [store closeWithCompletion:^(NSError *error) { failure = error; done = YES; }];
    Pump(^BOOL { return done; }); Check(failure.code == SQLITE_BUSY, @"unfinished statement rejects close");
    OnStore(store, ^(sqlite3 *db) { Check(db == original, @"failed close retains the usable handle"); sqlite3_finalize(held); });
    AwaitWrite(^(void (^done)(NSError *)) { [store closeWithCompletion:done]; });
}
static void TemporaryWriteLock(void) {
    FYLearningStore *store = FixtureStore(); sqlite3 *other = NULL;
    NSString *path = [store valueForKey:@"databasePath"];
    Check(sqlite3_open_v2(path.UTF8String, &other, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, NULL) == SQLITE_OK, @"open isolated competing connection");
    Check(sqlite3_exec(other, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK, @"hold short-lived write lock");
    dispatch_semaphore_t released = dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        sqlite3_exec(other, "ROLLBACK", NULL, NULL, NULL); dispatch_semaphore_signal(released);
    });
    __block BOOL done = NO; __block NSError *failure;
    [store updateTranslation:@"锁释放后的译文" forSentence:@"sentence" version:1 completion:^(NSError *error) { failure = error; done = YES; }];
    Pump(^BOOL { return done; });
    Check(dispatch_semaphore_wait(released, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0, @"competing transaction releases");
    sqlite3_close(other); Check(!failure, @"brief external lock does not lose translation write");
    AwaitWrite(^(void (^done)(NSError *)) { [store closeWithCompletion:done]; });
}
static void OptionalCompletions(void) {
    FYLearningStore *store = FixtureStore();
    FYRequestIdentity *identity = [FYRequestIdentity identityWithSentenceID:@"sentence" version:1 requestID:@"fixture" sourceText:@"合成原文" translation:@"合成译文"];
    [store toggleSentenceBookmark:identity completion:nil]; [store fetchSentenceBookmarks:nil];
    __block NSArray *bookmarks;
    [store fetchSentenceBookmarks:^(NSArray *values, NSError *error) { Check(!error, @"read after omitted callback"); bookmarks = values; }];
    Pump(^BOOL { return bookmarks != nil; }); Check(bookmarks.count == 1, @"optional callback preserves bookmark operation");
    AwaitWrite(^(void (^done)(NSError *)) { [store closeWithCompletion:done]; });
}
static void DamagedReference(void) {
    NSString *path = [FYTestTemporaryDirectory() stringByAppendingPathComponent:@"damaged-reference.sqlite"];
    sqlite3 *db = NULL; Check(sqlite3_open(path.UTF8String, &db) == SQLITE_OK, @"open synthetic reference");
    Check(sqlite3_exec(db, "CREATE TABLE entries(id INTEGER PRIMARY KEY,payload TEXT);CREATE TABLE forms(form TEXT,entry_id INTEGER);INSERT INTO forms VALUES('合成',1)", NULL, NULL, NULL) == SQLITE_OK, @"prepare synthetic reference schema");
    NSDictionary *payload = @{@"readings":@[@"ごうせい"], @"senses":@[], @"reference_level_matches":@[@{@"word":@"合成"}]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    sqlite3_stmt *stmt = NULL; sqlite3_prepare_v2(db, "INSERT INTO entries VALUES(1,?)", -1, &stmt, NULL);
    sqlite3_bind_text(stmt, 1, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String, -1, SQLITE_TRANSIENT);
    Check(sqlite3_step(stmt) == SQLITE_DONE, @"insert reference with absent level"); sqlite3_finalize(stmt); sqlite3_close(db);
    FYReferenceDictionary *dictionary = [[FYReferenceDictionary alloc] initWithURL:[NSURL fileURLWithPath:path]];
    __block BOOL done = NO; __block NSError *failure;
    [dictionary lookupWord:@"合成" reading:nil completion:^(NSArray *records, NSError *error) { failure = error; Check(records.count == 0, @"damaged reference does not fabricate grades"); done = YES; }];
    Pump(^BOOL { return done; }); Check(failure != nil, @"damaged level returns error instead of exception");
    [dictionary lookupWord:@"合成" reading:nil completion:nil];
    // Drain the reference queue through a normal follow-up lookup.
    done = NO;
    [dictionary lookupWord:@"合成" reading:nil completion:^(NSArray *records, NSError *error) { done = YES; }];
    Pump(^BOOL { return done; });
}
// Exercise the public facade across storage domains on the actual SQLite connection.
static void StorageOrderingAndLifetime(void) {
    FYLearningStore *store = FixtureStore();
    dispatch_queue_t callbacks = dispatch_queue_create("fixture.storage-completions", DISPATCH_QUEUE_SERIAL);
    static char callbackKey;
    dispatch_queue_set_specific(callbacks, &callbackKey, &callbackKey, NULL);
    [store setCompletionQueue:callbacks];
    __block NSUInteger completions = 0;
    void (^written)(NSUInteger, NSError *) = ^(NSUInteger sequence, NSError *error) {
        Check(!error && dispatch_get_specific(&callbackKey), @"writes deliver on selected completion queue");
        Check(completions == sequence, @"mixed-domain completions keep submission order");
        completions++;
    };
    FYVocabularyEntry *entry = [FYVocabularyEntry new];
    entry.vocabularyID = @"ordered-word"; entry.surface = @"合成词";
    FYVocabularyExample *example = [FYVocabularyExample new];
    example.vocabularyID = entry.vocabularyID; example.sentenceID = @"sentence";
    example.version = 1; example.sourceTextSnapshot = @"合成原文";
    [store saveVocabulary:entry withExample:example completion:^(NSError *error) { written(0, error); }];
    [store updateReviewStatus:FYReviewStatusLearning forVocabulary:entry.vocabularyID completion:^(NSError *error) { written(1, error); }];
    [store updateTranslation:@"顺序译文" forSentence:@"sentence" version:1 completion:^(NSError *error) { written(2, error); }];
    FYAnalysisResult *analysis = [FYAnalysisResult new];
    analysis.status = FYAnalysisStatusSuccess; analysis.schemaVersion = 1;
    analysis.grammar = @[]; analysis.vocabulary = @[]; analysis.sentenceNote = @"合成分析";
    [store saveAnalysisResult:analysis sentenceID:@"sentence" version:1 textHash:@"synthetic-hash"
               promptVersion:1 catalogVersion:1 modelConfig:@"synthetic-model" completion:^(NSError *error) { written(3, error); }];
    [store fetchAnalysisForSentence:@"sentence" version:1 completion:^(FYAnalysisResult *result, NSString *model, NSError *error) {
        Check([result.sentenceNote isEqual:@"合成分析"] && [model isEqual:@"synthetic-model"], @"cache read observes preceding shared-session write"); written(4, error);
    }];
    FYRequestIdentity *identity = [FYRequestIdentity identityWithSentenceID:@"sentence" version:1 requestID:@"ordering"
                                                               sourceText:@"合成原文" translation:@"顺序译文"];
    [store toggleSentenceBookmark:identity completion:^(BOOL saved, NSError *error) {
        Check(saved, @"bookmark queued after sentence write succeeds"); written(5, error);
    }];
    [store fetchSentence:@"sentence" completion:^(FYSentenceRecord *record, NSError *error) {
        Check([record.latestTranslation isEqual:@"顺序译文"], @"read observes prior write across repositories"); written(6, error);
    }];
    [store closeWithCompletion:^(NSError *error) { written(7, error); }];
    // This implicitly reopens the same file after the queued close.
    [store fetchVocabularyListWithCompletion:^(NSArray<FYVocabularyEntry *> *entries, NSError *error) {
        Check(entries.count == 1 && entries.firstObject.reviewStatus == FYReviewStatusLearning, @"close/reopen preserves queued review update"); written(8, error);
    }];
    dispatch_sync([store valueForKey:@"queue"], ^{});
    dispatch_sync(callbacks, ^{});
    Check(completions == 9, @"all callbacks arrive exactly once in a mixed-domain batch");
    [store setCompletionQueue:dispatch_get_main_queue()];
    AwaitWrite(^(void (^done)(NSError *)) { [store closeWithCompletion:done]; });

    // A queued operation owns the facade until work finishes, without retaining it for callback delivery.
    dispatch_queue_t workQueue;
    __weak FYLearningStore *weakStore;
    __block BOOL delivered = NO;
    @autoreleasepool {
        FYLearningStore *pending = [[FYLearningStore alloc] initWithDatabasePath:[FYTestTemporaryDirectory() stringByAppendingPathComponent:@"lifetime.sqlite"]];
        workQueue = [pending valueForKey:@"queue"];
        dispatch_suspend(workQueue); dispatch_suspend(callbacks);
        [pending setCompletionQueue:callbacks]; weakStore = pending;
        [pending closeWithCompletion:^(NSError *error) { Check(!error, @"queued close succeeds"); delivered = YES; }];
        pending = nil;
    }
    Check(weakStore != nil, @"queued operation retains original facade");
    dispatch_resume(workQueue); dispatch_sync(workQueue, ^{});
    Check(weakStore == nil && !delivered, @"facade releases after work even while completion is held");
    dispatch_resume(callbacks); dispatch_sync(callbacks, ^{});
    Check(delivered, @"completion survives facade release");
}

static void HistoryCompatibilityAccessor(void) {
    FYLearningStore *store = FixtureStore();
    [store setValue:@1 forKey:@"historyRetentionLimit"];
    InsertHistory(store, @"kvc-new", NSDate.date.timeIntervalSince1970 + 10);
    TranslateHistory(store, @"kvc-new", 1, @"合成新译文");
    __block BOOL done = NO;
    [store fetchSentence:@"sentence" completion:^(FYSentenceRecord *record, NSError *error) {
        Check(!error && !record, @"legacy KVC retention setting affects actual sentence pruning"); done = YES;
    }];
    Pump(^BOOL { return done; });
    AwaitWrite(^(void (^completion)(NSError *)) { [store configureHistoryRetentionWithLimit:0 completion:completion]; });
    Check([[store valueForKey:@"historyRetentionLimit"] unsignedIntegerValue] == 0, @"public retention configuration and compatibility getter share one state");
    AwaitWrite(^(void (^completion)(NSError *)) { [store closeWithCompletion:completion]; });
}

static void VocabularyTransactionFailure(void) {
    FYLearningStore *store = FixtureStore();
    FYVocabularyEntry *entry = [FYVocabularyEntry new]; entry.vocabularyID = @"atomic-word"; entry.surface = @"合成词";
    FYVocabularyExample *example = [FYVocabularyExample new]; example.vocabularyID = entry.vocabularyID;
    example.sentenceID = @"sentence"; example.version = 1; example.sourceTextSnapshot = @"合成原文";
    OnStore(store, ^(sqlite3 *db) {
        Check(sqlite3_exec(db, "CREATE TEMP TRIGGER fail_example BEFORE INSERT ON vocabulary_examples BEGIN SELECT RAISE(ABORT,'fixture'); END", NULL, NULL, NULL) == SQLITE_OK, @"install example write fault on shared connection");
    });
    __block BOOL done = NO; __block NSError *failure;
    [store saveVocabulary:entry withExample:example completion:^(NSError *error) { failure = error; done = YES; }];
    Pump(^BOOL { return done; }); Check(failure != nil, @"example failure reaches facade caller");
    OnStore(store, ^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        sqlite3_prepare_v2(db, "SELECT (SELECT COUNT(*) FROM vocabulary), (SELECT COUNT(*) FROM vocabulary_examples)", -1, &stmt, NULL);
        Check(sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) == 0 && sqlite3_column_int(stmt, 1) == 0, @"entry and example roll back together");
        sqlite3_finalize(stmt); sqlite3_exec(db, "DROP TRIGGER fail_example", NULL, NULL, NULL);
    });
    AwaitWrite(^(void (^completion)(NSError *)) { [store saveVocabulary:entry withExample:example completion:completion]; });
    AwaitWrite(^(void (^completion)(NSError *)) { [store closeWithCompletion:completion]; });
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *mode = argc > 1 ? @(argv[1]) : @"all";
    if ([mode isEqual:@"all"] || [mode isEqual:@"transaction"]) TransactionFailure();
    if ([mode isEqual:@"all"] || [mode isEqual:@"close"]) BusyClose();
    if ([mode isEqual:@"all"] || [mode isEqual:@"lock"]) TemporaryWriteLock();
    if ([mode isEqual:@"all"] || [mode isEqual:@"nil"]) OptionalCompletions();
    if ([mode isEqual:@"all"] || [mode isEqual:@"reference"]) DamagedReference();
    if ([mode isEqual:@"all"] || [mode isEqual:@"history"]) HistoryEligibility();
    if ([mode isEqual:@"all"] || [mode isEqual:@"ordering"]) StorageOrderingAndLifetime();
    if ([mode isEqual:@"all"] || [mode isEqual:@"vocabulary"]) VocabularyTransactionFailure();
    if ([mode isEqual:@"all"] || [mode isEqual:@"compatibility"]) HistoryCompatibilityAccessor();
    NSLog(@"PASS LearningStoreResilienceTests %@: isolated database faults, no UI/network/user data", mode);
} return 0; }
