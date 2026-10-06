#pragma once
#define main FuyiMainForRound3Review
#import "LiveCaptionTranslator.m"
#undef main
#import <sqlite3.h>

// Independent review: real AppKit actions, temporary stores, fictional text,
// mock requests. Never load preferences, start capture or use the user's DB/key.
static void Require(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"HARNESS ERROR: %@", message); exit(2); }
}
static void Pump(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && limit.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    Require(done(), @"callback timed out");
}
static void Tick(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static NSData *Envelope(NSString *content) {
    return [NSJSONSerialization dataWithJSONObject:@{@"choices": @[@{@"message": @{@"content": content}, @"finish_reason": @"stop"}]} options:0 error:NULL];
}
static NSHTTPURLResponse *Response(void) {
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/v1"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
}
static FYLearningAnalyzer *Analyzer(FYGrammarCatalog *catalog) {
    FYLearningAnalyzer *a = [FYLearningAnalyzer new]; a.catalog = catalog;
    a.baseURL = @"https://example.invalid/v1"; a.model = @"review-model"; a.apiKey = @"review-dummy-key";
    a.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) {
        done(Envelope(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"), Response(), nil);
    };
    return a;
}
static FYLearningStore *Store(NSString *path) {
    FYLearningStore *s = [[FYLearningStore alloc] initWithDatabasePath:path]; __block BOOL done = NO;
    [s openWithCompletion:^(NSError *error) { Require(!error, @"opening temporary store failed"); done = YES; }];
    Pump(^BOOL { return done; }); return s;
}
static AppDelegate *App(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    AppDelegate *app = [AppDelegate new]; app.learningStore = store; app.learningAnalyzer = analyzer;
    app.grammarCatalog = catalog; app.japaneseTokenizer = [FYJapaneseTokenizer new];
    app.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:store analyzer:analyzer tokenizer:app.japaneseTokenizer catalog:catalog];
    [app createMainWindow]; return app;
}
static NSArray<FYVocabularyEntry *> *Words(FYLearningStore *store) {
    __block NSArray *words = nil;
    [store fetchVocabularyListWithCompletion:^(NSArray *value, NSError *error) { Require(!error, @"reading vocabulary failed"); words = value; }];
    Pump(^BOOL { return words != nil; }); return words;
}
static FYVocabularyEntry *Bookmark(AppDelegate *app, NSString *surface, NSString *lemma, NSString *reading, NSString *meaning) {
    FYVocabularyEntry *entry = [FYVocabularyEntry new]; entry.surface = surface; entry.lemma = lemma; entry.reading = reading; entry.meaning = meaning;
    __block FYVocabularyEntry *saved = nil;
    [app.learningCoordinator bookmarkVocabulary:entry selectedText:surface completion:^(FYVocabularyEntry *value, BOOL duplicate, NSError *error) {
        Require(!error && value != nil, @"control bookmark failed"); saved = value;
    }]; Pump(^BOOL { return saved != nil; }); return saved;
}
static void Drain(FYLearningStore *store) {
    __block BOOL done = NO;
    [store fetchRecentSentencesWithLimit:50 completion:^(NSArray *records, NSError *error) { Require(!error, @"draining store failed"); done = YES; }];
    Pump(^BOOL { return done; });
}
static void Trigger(NSString *path, NSString *sql) {
    sqlite3 *db = NULL; Require(sqlite3_open(path.UTF8String, &db) == SQLITE_OK, @"fault database open failed");
    Require(sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK, @"fault trigger failed"); sqlite3_close(db);
}

