#import "FYLearningStore.h"
#import <sqlite3.h>

const NSUInteger FYRecentSentenceLimit = 5;

static NSError *FYStoreError(sqlite3 *db, NSString *message) {
    return [NSError errorWithDomain:@"FYLearningStore"
                               code:db ? sqlite3_errcode(db) : 0
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *FYSQLiteStringOrEmpty(sqlite3_stmt *stmt, int column) {
    const unsigned char *value = sqlite3_column_text(stmt, column);
    return value ? ([NSString stringWithUTF8String:(const char *)value] ?: @"") : @"";
}

static NSDate *FYDateFromNumber(NSNumber *number) {
    if (!number) { return nil; }
    return [NSDate dateWithTimeIntervalSince1970:number.doubleValue];
}

static NSString *FYTrimmed(NSString *value) {
    return value ?: @"";
}

// 把 FYAnalysisResult 序列化成可存库的 JSON 字典；反向解析用于读取缓存。
static NSDictionary *FYDictionaryFromAnalysisResult(FYAnalysisResult *result) {
    NSMutableArray *grammar = [NSMutableArray arrayWithCapacity:result.grammar.count];
    for (FYGrammarItem *item in result.grammar) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"catalog_id"] = item.catalogID ?: [NSNull null];
        dict[@"name"] = item.name ?: @"";
        dict[@"matched_text"] = item.matchedText ?: @"";
        dict[@"connection"] = item.connection ?: [NSNull null];
        dict[@"meaning_zh"] = item.meaning ?: [NSNull null];
        dict[@"explanation_zh"] = item.explanation ?: [NSNull null];
        dict[@"register_note"] = item.registerNote ?: [NSNull null];
        dict[@"reference_level"] = item.referenceLevel ?: [NSNull null];
        dict[@"level_source_title"] = item.levelSourceTitle ?: [NSNull null];
        dict[@"level_source_url"] = item.levelSourceURL ?: [NSNull null];
        dict[@"level_verified"] = @(item.levelVerified);
        dict[@"matched_range_location"] = @(item.matchedRange.location == NSNotFound ? -1 : (NSInteger)item.matchedRange.location);
        dict[@"matched_range_length"] = @(item.matchedRange.length);
        [grammar addObject:dict];
    }

    NSMutableArray *vocabulary = [NSMutableArray arrayWithCapacity:result.vocabulary.count];
    for (FYVocabularyEntry *entry in result.vocabulary) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"surface"] = entry.surface ?: @"";
        dict[@"lemma"] = entry.lemma ?: [NSNull null];
        dict[@"reading"] = entry.reading ?: [NSNull null];
        dict[@"meaning_zh"] = entry.meaning ?: [NSNull null];
        [vocabulary addObject:dict];
    }

    return @{
        @"schema_version": @(result.schemaVersion),
        @"grammar": grammar,
        @"vocabulary": vocabulary,
        @"sentence_note_zh": result.sentenceNote ?: [NSNull null],
        @"structure_parts": result.structureParts ?: @[],
        @"structure_title_zh": result.structureTitle ?: [NSNull null],
    };
}

static NSString *FYStringOrEmpty(id value) {
    if ([value isKindOfClass:NSString.class]) { return value; }
    return @"";
}

static NSString *FYOptionalString(id value) {
    if ([value isKindOfClass:NSString.class]) { return value; }
    return nil;
}

static FYAnalysisResult *FYAnalysisResultFromDictionary(NSDictionary *dict) {
    // Corrupt/old cache data is a cache miss, not an exception or a fabricated no-result.
    if (![dict[@"schema_version"] isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)dict[@"schema_version"]) == CFBooleanGetTypeID() || [dict[@"schema_version"] doubleValue] != 1 ||
        ![dict[@"grammar"] isKindOfClass:NSArray.class] || ![dict[@"vocabulary"] isKindOfClass:NSArray.class]) { return nil; }
    for (id raw in dict[@"grammar"]) {
        if (![raw isKindOfClass:NSDictionary.class]) { return nil; }
        NSDictionary *g = raw;
        if (![g[@"name"] isKindOfClass:NSString.class] || ![g[@"matched_text"] isKindOfClass:NSString.class] ||
            [g[@"name"] length] == 0 || [g[@"matched_text"] length] == 0 ||
            ![g[@"level_verified"] isKindOfClass:NSNumber.class] ||
            ![g[@"matched_range_location"] isKindOfClass:NSNumber.class] ||
            ![g[@"matched_range_length"] isKindOfClass:NSNumber.class] ||
            [g[@"matched_range_location"] integerValue] < -1 || [g[@"matched_range_length"] integerValue] < 0) { return nil; }
    }
    for (id raw in dict[@"vocabulary"]) {
        if (![raw isKindOfClass:NSDictionary.class] || ![raw[@"surface"] isKindOfClass:NSString.class] || [raw[@"surface"] length] == 0) { return nil; }
    }
    FYAnalysisResult *result = [[FYAnalysisResult alloc] init];
    result.status = FYAnalysisStatusSuccess;
    result.schemaVersion = [dict[@"schema_version"] integerValue];
    result.sentenceNote = FYOptionalString(dict[@"sentence_note_zh"]);
    NSArray *parts=[dict[@"structure_parts"] isKindOfClass:NSArray.class]?dict[@"structure_parts"]:@[];
    BOOL validParts=parts.count>=2 && parts.count<=8;
    for(id part in parts){
        if(![part isKindOfClass:NSDictionary.class] || ![part[@"text"] isKindOfClass:NSString.class] || ![part[@"meaning"] isKindOfClass:NSString.class] || ![part[@"role"] isKindOfClass:NSString.class] || ![part[@"location"] isKindOfClass:NSNumber.class] || ![part[@"length"] isKindOfClass:NSNumber.class] || [part[@"location"] integerValue]<0 || [part[@"length"] integerValue]<=0){validParts=NO;break;}
    }
    result.structureParts=validParts?parts:@[];result.structureTitle=validParts?FYOptionalString(dict[@"structure_title_zh"]):nil;

    NSMutableArray<FYGrammarItem *> *grammar = [NSMutableArray array];
    for (id raw in dict[@"grammar"]) {
        if (![raw isKindOfClass:NSDictionary.class]) { continue; }
        NSDictionary *g = raw;
        FYGrammarItem *item = [[FYGrammarItem alloc] init];
        item.catalogID = FYOptionalString(g[@"catalog_id"]);
        item.name = FYStringOrEmpty(g[@"name"]);
        item.matchedText = FYStringOrEmpty(g[@"matched_text"]);
        item.connection = FYOptionalString(g[@"connection"]);
        item.meaning = FYOptionalString(g[@"meaning_zh"]);
        item.explanation = FYOptionalString(g[@"explanation_zh"]);
        item.registerNote = FYOptionalString(g[@"register_note"]);
        item.referenceLevel = FYOptionalString(g[@"reference_level"]);
        item.levelSourceTitle = FYOptionalString(g[@"level_source_title"]);
        item.levelSourceURL = FYOptionalString(g[@"level_source_url"]);
        item.levelVerified = [g[@"level_verified"] boolValue];
        NSInteger location = [g[@"matched_range_location"] isKindOfClass:NSNumber.class] ? [g[@"matched_range_location"] integerValue] : NSNotFound;
        NSInteger length = [g[@"matched_range_length"] isKindOfClass:NSNumber.class] ? [g[@"matched_range_length"] integerValue] : 0;
        item.matchedRange = location >= 0 ? NSMakeRange(location, length) : NSMakeRange(NSNotFound, 0);
        [grammar addObject:item];
    }
    result.grammar = grammar;

    NSMutableArray<FYVocabularyEntry *> *vocabulary = [NSMutableArray array];
    for (id raw in dict[@"vocabulary"]) {
        if (![raw isKindOfClass:NSDictionary.class]) { continue; }
        NSDictionary *v = raw;
        FYVocabularyEntry *entry = [[FYVocabularyEntry alloc] init];
        entry.kind = FYVocabularyKindWord;
        entry.surface = FYStringOrEmpty(v[@"surface"]);
        entry.lemma = FYOptionalString(v[@"lemma"]);
        entry.reading = FYOptionalString(v[@"reading"]);
        entry.meaning = FYOptionalString(v[@"meaning_zh"]);
        entry.completionSource = FYCompletionSourceAI;
        [vocabulary addObject:entry];
    }
    result.vocabulary = vocabulary;

    return result;
}

@interface FYLearningStore ()
@property(nonatomic, copy) NSString *databasePath;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) dispatch_queue_t deliveryQueue;
@property(nonatomic) sqlite3 *db;
@property(nonatomic) BOOL opened;
@property(nonatomic) NSUInteger historyRetentionLimit;
@property(nonatomic, copy) NSString *preservedHistorySentenceID;
@end

@implementation FYLearningStore

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (self) {
        _databasePath = [path copy];
        _queue = dispatch_queue_create("com.nanami.fuyi.learning-store", DISPATCH_QUEUE_SERIAL);
        _deliveryQueue = dispatch_get_main_queue();
        _db = NULL;
        _opened = NO;
    }
    return self;
}

- (dispatch_queue_t)completionQueue {
    return self.deliveryQueue;
}

- (void)setCompletionQueue:(dispatch_queue_t)queue {
    self.deliveryQueue = queue ?: dispatch_get_main_queue();
}

- (void)deliverError:(NSError *)error completion:(void (^)(NSError *))completion {
    if (!completion) { return; }
    dispatch_async(self.deliveryQueue, ^{ completion(error); });
}

- (NSError *)ensureOpened {
    if (self.opened && self.db) { return nil; }
    NSString *dir = [self.databasePath stringByDeletingLastPathComponent];
    if (dir.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    int rc = sqlite3_open_v2(self.databasePath.UTF8String, &_db,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL);
    if (rc != SQLITE_OK) {
        NSError *error = FYStoreError(_db, @"无法打开学习数据库");
        if (_db) { sqlite3_close(_db); _db = NULL; }
        return error;
    }
    // A second app/process may hold a brief write lock; wait off the main thread.
    sqlite3_busy_timeout(_db, 1500);
    sqlite3_exec(_db, "PRAGMA foreign_keys = ON;", NULL, NULL, NULL);
    NSError *migrationError = [self migrate];
    if (migrationError) {
        sqlite3_close(_db);
        _db = NULL;
        return migrationError;
    }
    self.opened = YES;
    return nil;
}

- (NSError *)migrate {
    int userVersion = 0;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, "PRAGMA user_version;", -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            userVersion = sqlite3_column_int(stmt, 0);
        }
        sqlite3_finalize(stmt);
        stmt = NULL;
    }

    if (userVersion < 1) {
        const char *schema =
            "CREATE TABLE IF NOT EXISTS sessions ("
            "  session_id TEXT PRIMARY KEY,"
            "  display_name TEXT,"
            "  started_at REAL,"
            "  language TEXT"
            ");"
            "CREATE TABLE IF NOT EXISTS sentences ("
            "  sentence_id TEXT PRIMARY KEY,"
            "  session_id TEXT,"
            "  kind INTEGER,"
            "  original_text TEXT,"
            "  latest_version INTEGER,"
            "  latest_translation TEXT,"
            "  occurred_at REAL,"
            "  display_name TEXT,"
            "  FOREIGN KEY(session_id) REFERENCES sessions(session_id)"
            ");"
            "CREATE TABLE IF NOT EXISTS sentence_versions ("
            "  sentence_id TEXT,"
            "  version INTEGER,"
            "  text TEXT,"
            "  translation TEXT,"
            "  created_at REAL,"
            "  PRIMARY KEY(sentence_id, version),"
            "  FOREIGN KEY(sentence_id) REFERENCES sentences(sentence_id) ON DELETE CASCADE"
            ");"
            "CREATE TABLE IF NOT EXISTS analyses ("
            "  sentence_id TEXT,"
            "  version INTEGER,"
            "  text_hash TEXT,"
            "  prompt_version INTEGER,"
            "  catalog_version INTEGER,"
            "  model_config TEXT,"
            "  status INTEGER,"
            "  result_json TEXT,"
            "  PRIMARY KEY(sentence_id, version),"
            "  FOREIGN KEY(sentence_id) REFERENCES sentences(sentence_id) ON DELETE CASCADE"
            ");"
            "CREATE TABLE IF NOT EXISTS vocabulary ("
            "  vocabulary_id TEXT PRIMARY KEY,"
            "  kind INTEGER,"
            "  surface TEXT,"
            "  lemma TEXT,"
            "  reading TEXT,"
            "  meaning TEXT,"
            "  completion_source INTEGER,"
            "  review_status INTEGER,"
            "  bookmarked_at REAL"
            ");"
            "CREATE TABLE IF NOT EXISTS vocabulary_examples ("
            "  vocabulary_id TEXT,"
            "  sentence_id TEXT,"
            "  version INTEGER,"
            "  source_text_snapshot TEXT,"
            "  translation_snapshot TEXT,"
            "  selected_range_text TEXT,"
            "  PRIMARY KEY(vocabulary_id, sentence_id, version),"
            "  FOREIGN KEY(vocabulary_id) REFERENCES vocabulary(vocabulary_id) ON DELETE CASCADE"
            ");"
            "CREATE TABLE IF NOT EXISTS sentence_bookmarks (sentence_id TEXT NOT NULL, version INTEGER NOT NULL, source TEXT NOT NULL, translation TEXT, bookmarked_at REAL, PRIMARY KEY(sentence_id, version));"
            "CREATE TABLE IF NOT EXISTS grammar_bookmarks ("
            "  bookmark_id TEXT PRIMARY KEY,"
            "  catalog_id TEXT,"
            "  name TEXT,"
            "  sentence_id TEXT,"
            "  version INTEGER,"
            "  source_text_snapshot TEXT,"
            "  translation_snapshot TEXT,"
            "  bookmarked_at REAL"
            ");"
            "CREATE INDEX IF NOT EXISTS idx_sentences_occurred ON sentences(occurred_at DESC);"
            "CREATE INDEX IF NOT EXISTS idx_vocab_bookmarked ON vocabulary(bookmarked_at DESC);";

        char *errMsg = NULL;
        int rc = sqlite3_exec(_db, schema, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            NSError *error = [NSError errorWithDomain:@"FYLearningStore" code:rc
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"建表失败：%s", errMsg ?: "unknown"]}];
            if (errMsg) { sqlite3_free(errMsg); }
            return error;
        }
        if (errMsg) { sqlite3_free(errMsg); }

        char setVersion[64];
        snprintf(setVersion, sizeof(setVersion), "PRAGMA user_version = 1;");
        sqlite3_exec(_db, setVersion, NULL, NULL, NULL);
    }
    if(userVersion<2){
        const char *upgrade="BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS sentence_bookmarks (sentence_id TEXT NOT NULL, version INTEGER NOT NULL, source TEXT NOT NULL, translation TEXT, bookmarked_at REAL, PRIMARY KEY(sentence_id,version)); PRAGMA user_version=2; COMMIT;";
        if(sqlite3_exec(_db,upgrade,NULL,NULL,NULL)!=SQLITE_OK){NSError *error=FYStoreError(_db,@"升级句子收藏数据表失败");sqlite3_exec(_db,"ROLLBACK",NULL,NULL,NULL);return error;}
    }
    return nil;
}

// Called only on the store queue. A single DELETE atomically removes old sentences,
// versions and analysis caches; saved vocabulary/grammar keep independent snapshots.
- (NSError *)pruneHistory {
    if (self.historyRetentionLimit == 0) { return nil; }
    const char *sql = "DELETE FROM sentences WHERE sentence_id NOT IN "
                      "(SELECT sentence_id FROM sentences ORDER BY occurred_at DESC, rowid DESC LIMIT ?) "
                      "AND sentence_id NOT IN (SELECT sentence_id FROM sentence_bookmarks) "
                      "AND (? IS NULL OR sentence_id != ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return FYStoreError(self.db, @"准备清理历史台词失败");
    }
    sqlite3_bind_int64(stmt, 1, (sqlite3_int64)self.historyRetentionLimit);
    if (self.preservedHistorySentenceID.length) {
        sqlite3_bind_text(stmt, 2, self.preservedHistorySentenceID.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, self.preservedHistorySentenceID.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 2); sqlite3_bind_null(stmt, 3);
    }
    NSError *error = sqlite3_step(stmt) == SQLITE_DONE ? nil : FYStoreError(self.db, @"清理历史台词失败");
    sqlite3_finalize(stmt);
    return error;
}

- (void)configureHistoryRetentionWithLimit:(NSUInteger)limit completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        self.historyRetentionLimit = limit;
        NSError *error = [self ensureOpened];
        if (!error) { error = [self pruneHistory]; }
        [self deliverError:error completion:completion];
    });
}

- (void)preserveSentenceForHistory:(NSString *)sentenceID completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        self.preservedHistorySentenceID = sentenceID;
        NSError *error = [self ensureOpened];
        if (!error) { error = [self pruneHistory]; }
        [self deliverError:error completion:completion];
    });
}

- (void)openWithCompletion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        [self deliverError:error completion:completion];
    });
}

- (void)closeWithCompletion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        if (self.db) {
            int rc = sqlite3_close(self.db);
            if (rc != SQLITE_OK) {
                error = [NSError errorWithDomain:@"FYLearningStore" code:rc userInfo:@{NSLocalizedDescriptionKey: @"关闭数据库失败"}];
            } else {
                self.db = NULL;
                self.opened = NO;
            }
        }
        [self deliverError:error completion:completion];
    });
}

- (void)ensureSessionWithID:(NSString *)sessionID
                displayName:(NSString *)displayName
                   language:(NSString *)language
                 completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        if (!error) {
            const char *sql = "INSERT OR IGNORE INTO sessions (session_id, display_name, started_at, language) VALUES (?, ?, ?, ?);";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(sessionID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 2, FYTrimmed(displayName).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_double(stmt, 3, NSDate.date.timeIntervalSince1970);
                sqlite3_bind_text(stmt, 4, FYTrimmed(language).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) != SQLITE_DONE) {
                    error = FYStoreError(self.db, @"保存会话失败");
                }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备会话语句失败");
            }
        }
        [self deliverError:error completion:completion];
    });
}

- (void)insertSentenceWithID:(NSString *)sentenceID
                   sessionID:(NSString *)sessionID
                        kind:(FYSentenceKind)kind
                originalText:(NSString *)originalText
                  occurredAt:(NSDate *)occurredAt
                  completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        if (!error) {
            if (sqlite3_exec(self.db, "BEGIN IMMEDIATE;", NULL, NULL, NULL) != SQLITE_OK) {
                [self deliverError:FYStoreError(self.db, @"开始保存句子事务失败") completion:completion];
                return;
            }

            const char *sentenceSQL = "INSERT OR IGNORE INTO sentences (sentence_id, session_id, kind, original_text, latest_version, latest_translation, occurred_at, display_name) VALUES (?, ?, ?, ?, 1, NULL, ?, NULL);";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sentenceSQL, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 2, FYTrimmed(sessionID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 3, (int)kind);
                sqlite3_bind_text(stmt, 4, FYTrimmed(originalText).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_double(stmt, 5, (occurredAt ?: NSDate.date).timeIntervalSince1970);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"保存句子失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备句子语句失败");
            }

            if (!error) {
                const char *versionSQL = "INSERT OR IGNORE INTO sentence_versions (sentence_id, version, text, translation, created_at) VALUES (?, 1, ?, NULL, ?);";
                sqlite3_stmt *vstmt = NULL;
                if (sqlite3_prepare_v2(self.db, versionSQL, -1, &vstmt, NULL) == SQLITE_OK) {
                    sqlite3_bind_text(vstmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(vstmt, 2, FYTrimmed(originalText).UTF8String, -1, SQLITE_TRANSIENT);
                    sqlite3_bind_double(vstmt, 3, (occurredAt ?: NSDate.date).timeIntervalSince1970);
                    if (sqlite3_step(vstmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"保存句子版本失败"); }
                    sqlite3_finalize(vstmt);
                } else {
                    error = FYStoreError(self.db, @"准备句子版本语句失败");
                }
            }

            if (!error) { error = [self pruneHistory]; }
            if (error) {
                sqlite3_exec(self.db, "ROLLBACK;", NULL, NULL, NULL);
            } else {
                if (sqlite3_exec(self.db, "COMMIT;", NULL, NULL, NULL) != SQLITE_OK) {
                    error = FYStoreError(self.db, @"提交保存句子事务失败");
                    sqlite3_exec(self.db, "ROLLBACK;", NULL, NULL, NULL);
                }
            }
        }
        [self deliverError:error completion:completion];
    });
}

- (void)updateTranslation:(NSString *)translation
              forSentence:(NSString *)sentenceID
                  version:(NSInteger)version
               completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        BOOL began = NO;
        if (!error) {
            began = sqlite3_exec(self.db, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK;
            if (!began) { error = FYStoreError(self.db, @"开始回填译文事务失败"); }
        }
        if (!error) {
            const char *vSQL = "UPDATE sentence_versions SET translation = ? WHERE sentence_id = ? AND version = ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, vSQL, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(translation).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 2, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 3, (int)version);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"回填译文失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备回填译文语句失败");
            }

            if (!error) {
                const char *sSQL = "UPDATE sentences SET latest_translation = ? WHERE sentence_id = ? AND latest_version = ?;";
                sqlite3_stmt *sstmt = NULL;
                if (sqlite3_prepare_v2(self.db, sSQL, -1, &sstmt, NULL) == SQLITE_OK) {
                    sqlite3_bind_text(sstmt, 1, FYTrimmed(translation).UTF8String, -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(sstmt, 2, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                    sqlite3_bind_int(sstmt, 3, (int)version);
                    if (sqlite3_step(sstmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"回填最新译文失败"); }
                    sqlite3_finalize(sstmt);
                } else {
                    error = FYStoreError(self.db, @"准备最新译文语句失败");
                }
            }
        }
        if (began) {
            if (!error && sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK) {
                error = FYStoreError(self.db, @"提交回填译文事务失败");
            }
            if (error) { sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL); }
        }
        [self deliverError:error completion:completion];
    });
}

- (void)appendVersionForSentence:(NSString *)sentenceID
                            text:(NSString *)text
                     translation:(NSString *)translation
                      completion:(void (^)(NSInteger, NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        NSInteger newVersion = 0;
        if (!error) {
            sqlite3_stmt *latestStmt = NULL;
            if (sqlite3_prepare_v2(self.db, "SELECT latest_version FROM sentences WHERE sentence_id = ?;", -1, &latestStmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(latestStmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(latestStmt) == SQLITE_ROW) {
                    newVersion = sqlite3_column_int(latestStmt, 0) + 1;
                }
                sqlite3_finalize(latestStmt);
            }
            if (newVersion == 0) {
                error = [NSError errorWithDomain:@"FYLearningStore" code:1 userInfo:@{NSLocalizedDescriptionKey: @"句子不存在，无法追加版本"}];
            }
        }
        if (!error) {
            if (sqlite3_exec(self.db, "BEGIN IMMEDIATE;", NULL, NULL, NULL) != SQLITE_OK) {
                error = FYStoreError(self.db, @"开始追加版本事务失败");
            }
        }
        if (!error) {
            const char *vSQL = "INSERT INTO sentence_versions (sentence_id, version, text, translation, created_at) VALUES (?, ?, ?, ?, ?);";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, vSQL, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 2, (int)newVersion);
                sqlite3_bind_text(stmt, 3, FYTrimmed(text).UTF8String, -1, SQLITE_TRANSIENT);
                if (translation) { sqlite3_bind_text(stmt, 4, translation.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(stmt, 4); }
                sqlite3_bind_double(stmt, 5, NSDate.date.timeIntervalSince1970);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"追加句子版本失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备追加版本语句失败");
            }
        }
        if (!error) {
            const char *uSQL = "UPDATE sentences SET latest_version = ?, latest_translation = ? WHERE sentence_id = ?;";
            sqlite3_stmt *ustmt = NULL;
            if (sqlite3_prepare_v2(self.db, uSQL, -1, &ustmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int(ustmt, 1, (int)newVersion);
                if (translation) { sqlite3_bind_text(ustmt, 2, translation.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(ustmt, 2); }
                sqlite3_bind_text(ustmt, 3, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(ustmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"更新主句版本失败"); }
                sqlite3_finalize(ustmt);
            } else {
                error = FYStoreError(self.db, @"准备更新主句版本语句失败");
            }
        }
        if (error) {
            sqlite3_exec(self.db, "ROLLBACK;", NULL, NULL, NULL);
        } else if (sqlite3_exec(self.db, "COMMIT;", NULL, NULL, NULL) != SQLITE_OK) {
            error = FYStoreError(self.db, @"提交追加版本事务失败");
            sqlite3_exec(self.db, "ROLLBACK;", NULL, NULL, NULL);
        }
        if (!completion) { return; }
        // 只有事务成功提交才返回有效新版本；失败一律返回 0 并带 error。
        NSInteger capturedVersion = error ? 0 : newVersion;
        dispatch_async(self.deliveryQueue, ^{ completion(capturedVersion, error); });
    });
}

- (FYSentenceRecord *)sentenceRecordFromStatement:(sqlite3_stmt *)stmt {
    FYSentenceRecord *record = [[FYSentenceRecord alloc] init];
    record.sentenceID = FYSQLiteStringOrEmpty(stmt, 0);
    record.sessionID = FYSQLiteStringOrEmpty(stmt, 1);
    record.kind = (FYSentenceKind)sqlite3_column_int(stmt, 2);
    record.originalText = FYSQLiteStringOrEmpty(stmt, 3);
    record.latestVersion = sqlite3_column_int(stmt, 4);
    const unsigned char *translation = sqlite3_column_text(stmt, 5);
    record.latestTranslation = translation ? [NSString stringWithUTF8String:(const char *)translation] : nil;
    record.occurredAt = FYDateFromNumber(@(sqlite3_column_double(stmt, 6)));
    const unsigned char *displayName = sqlite3_column_text(stmt, 7);
    record.displayName = displayName ? [NSString stringWithUTF8String:(const char *)displayName] : nil;
    const unsigned char *latestText = sqlite3_column_text(stmt, 8);
    record.latestText = latestText ? [NSString stringWithUTF8String:(const char *)latestText] : record.originalText;
    return record;
}

- (void)fetchSentence:(NSString *)sentenceID
           completion:(void (^)(FYSentenceRecord *, NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        FYSentenceRecord *record = nil;
        if (!error) {
            const char *sql = "SELECT s.sentence_id, s.session_id, s.kind, s.original_text, s.latest_version, s.latest_translation, s.occurred_at, s.display_name,"
                              " (SELECT v.text FROM sentence_versions v WHERE v.sentence_id = s.sentence_id AND v.version = s.latest_version) AS latest_text"
                              " FROM sentences s WHERE s.sentence_id = ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    record = [self sentenceRecordFromStatement:stmt];
                }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"读取句子失败");
            }
        }
        if (!completion) { return; }
        dispatch_async(self.deliveryQueue, ^{ completion(record, error); });
    });
}

- (void)fetchRecentSentencesWithLimit:(NSUInteger)limit
                           completion:(void (^)(NSArray<FYSentenceRecord *> *, NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        NSMutableArray<FYSentenceRecord *> *records = [NSMutableArray array];
        if (!error) {
            const char *sql = "SELECT s.sentence_id, s.session_id, s.kind, s.original_text, s.latest_version, s.latest_translation, s.occurred_at, s.display_name,"
                              " (SELECT v.text FROM sentence_versions v WHERE v.sentence_id = s.sentence_id AND v.version = s.latest_version) AS latest_text"
                              " FROM sentences s ORDER BY s.occurred_at DESC, s.rowid DESC LIMIT ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int(stmt, 1, (int)MAX(1, limit));
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    [records addObject:[self sentenceRecordFromStatement:stmt]];
                }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"读取历史失败");
            }
        }
        if (!completion) { return; }
        dispatch_async(self.deliveryQueue, ^{ completion(records, error); });
    });
}

- (void)fetchVersionsForSentence:(NSString *)sentenceID
                      completion:(void (^)(NSArray<FYSentenceVersion *> *, NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        NSMutableArray<FYSentenceVersion *> *versions = [NSMutableArray array];
        if (!error) {
            const char *sql = "SELECT sentence_id, version, text, translation, created_at FROM sentence_versions WHERE sentence_id = ? ORDER BY version ASC;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    FYSentenceVersion *v = [[FYSentenceVersion alloc] init];
                    v.sentenceID = FYSQLiteStringOrEmpty(stmt, 0);
                    v.version = sqlite3_column_int(stmt, 1);
                    v.text = FYSQLiteStringOrEmpty(stmt, 2);
                    const unsigned char *translation = sqlite3_column_text(stmt, 3);
                    v.translation = translation ? [NSString stringWithUTF8String:(const char *)translation] : nil;
                    v.createdAt = FYDateFromNumber(@(sqlite3_column_double(stmt, 4)));
                    [versions addObject:v];
                }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"读取句子版本失败");
            }
        }
        if (!completion) { return; }
        dispatch_async(self.deliveryQueue, ^{ completion(versions, error); });
    });
}

- (NSError *)writeVocabulary:(FYVocabularyEntry *)entry {
        NSError *error = [self ensureOpened];
        if (!error) {
            // 用 UPSERT 而非 INSERT OR REPLACE：REPLACE 会先 DELETE 旧行并触发
            // vocabulary_examples 的 ON DELETE CASCADE，把该词条的所有例句级联删除。
            const char *sql = "INSERT INTO vocabulary (vocabulary_id, kind, surface, lemma, reading, meaning, completion_source, review_status, bookmarked_at) "
                              "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) "
                              "ON CONFLICT(vocabulary_id) DO UPDATE SET "
                              "  kind=excluded.kind, surface=excluded.surface, lemma=excluded.lemma, reading=excluded.reading, "
                              "  meaning=excluded.meaning, completion_source=excluded.completion_source, "
                              "  review_status=excluded.review_status, bookmarked_at=excluded.bookmarked_at;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(entry.vocabularyID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 2, (int)entry.kind);
                sqlite3_bind_text(stmt, 3, FYTrimmed(entry.surface).UTF8String, -1, SQLITE_TRANSIENT);
                if (entry.lemma) { sqlite3_bind_text(stmt, 4, entry.lemma.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(stmt, 4); }
                if (entry.reading) { sqlite3_bind_text(stmt, 5, entry.reading.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(stmt, 5); }
                if (entry.meaning) { sqlite3_bind_text(stmt, 6, entry.meaning.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(stmt, 6); }
                sqlite3_bind_int(stmt, 7, (int)entry.completionSource);
                sqlite3_bind_int(stmt, 8, (int)entry.reviewStatus);
                sqlite3_bind_double(stmt, 9, (entry.bookmarkedAt ?: NSDate.date).timeIntervalSince1970);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"保存词条失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备词条语句失败");
            }
        }
    return error;
}

- (void)upsertVocabulary:(FYVocabularyEntry *)entry completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self writeVocabulary:entry];
        [self deliverError:error completion:completion];
    });
}

- (NSError *)writeExample:(FYVocabularyExample *)example {
        NSError *error = [self ensureOpened];
        if (!error) {
            const char *sql = "INSERT OR REPLACE INTO vocabulary_examples (vocabulary_id, sentence_id, version, source_text_snapshot, translation_snapshot, selected_range_text) VALUES (?, ?, ?, ?, ?, ?);";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(example.vocabularyID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 2, FYTrimmed(example.sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 3, (int)example.version);
                sqlite3_bind_text(stmt, 4, FYTrimmed(example.sourceTextSnapshot).UTF8String, -1, SQLITE_TRANSIENT);
                if (example.translationSnapshot) { sqlite3_bind_text(stmt, 5, example.translationSnapshot.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(stmt, 5); }
                sqlite3_bind_text(stmt, 6, FYTrimmed(example.selectedRangeText).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"保存例句关联失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备例句关联语句失败");
            }
        }
    return error;
}

- (void)attachExample:(FYVocabularyExample *)example completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self writeExample:example];
        [self deliverError:error completion:completion];
    });
}

- (void)saveVocabulary:(FYVocabularyEntry *)entry withExample:(FYVocabularyExample *)example completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        BOOL began = NO;
        if (!error) {
            began = sqlite3_exec(self.db, "BEGIN IMMEDIATE;", NULL, NULL, NULL) == SQLITE_OK;
            if (!began) { error = FYStoreError(self.db, @"开始词条收藏事务失败"); }
        }
        if (!error) { error = [self writeVocabulary:entry]; }
        if (!error && example) { error = [self writeExample:example]; }
        if (!error && sqlite3_exec(self.db, "COMMIT;", NULL, NULL, NULL) != SQLITE_OK) { error = FYStoreError(self.db, @"提交词条收藏事务失败"); }
        if (error && began) { sqlite3_exec(self.db, "ROLLBACK;", NULL, NULL, NULL); }
        [self deliverError:error completion:completion];
    });
}

- (FYVocabularyEntry *)vocabularyEntryFromStatement:(sqlite3_stmt *)stmt {
    FYVocabularyEntry *entry = [[FYVocabularyEntry alloc] init];
    entry.vocabularyID = FYSQLiteStringOrEmpty(stmt, 0);
    entry.kind = (FYVocabularyKind)sqlite3_column_int(stmt, 1);
    entry.surface = FYSQLiteStringOrEmpty(stmt, 2);
    const unsigned char *lemma = sqlite3_column_text(stmt, 3);
    entry.lemma = lemma ? [NSString stringWithUTF8String:(const char *)lemma] : nil;
    const unsigned char *reading = sqlite3_column_text(stmt, 4);
    entry.reading = reading ? [NSString stringWithUTF8String:(const char *)reading] : nil;
    const unsigned char *meaning = sqlite3_column_text(stmt, 5);
    entry.meaning = meaning ? [NSString stringWithUTF8String:(const char *)meaning] : nil;
    entry.completionSource = (FYCompletionSource)sqlite3_column_int(stmt, 6);
    entry.reviewStatus = (FYReviewStatus)sqlite3_column_int(stmt, 7);
    entry.bookmarkedAt = FYDateFromNumber(@(sqlite3_column_double(stmt, 8)));
    return entry;
}

- (void)fetchVocabularyListWithCompletion:(void (^)(NSArray<FYVocabularyEntry *> *, NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        NSMutableArray<FYVocabularyEntry *> *entries = [NSMutableArray array];
        if (!error) {
            const char *sql = "SELECT vocabulary_id, kind, surface, lemma, reading, meaning, completion_source, review_status, bookmarked_at FROM vocabulary ORDER BY bookmarked_at DESC;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    [entries addObject:[self vocabularyEntryFromStatement:stmt]];
                }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"读取词条列表失败");
            }
        }
        if (!completion) { return; }
        dispatch_async(self.deliveryQueue, ^{ completion(entries, error); });
    });
}

- (void)updateReviewStatus:(FYReviewStatus)status
             forVocabulary:(NSString *)vocabularyID
                completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        if (!error) {
            const char *sql = "UPDATE vocabulary SET review_status = ? WHERE vocabulary_id = ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int(stmt, 1, (int)status);
                sqlite3_bind_text(stmt, 2, FYTrimmed(vocabularyID).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"更新复习状态失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备复习状态语句失败");
            }
        }
        [self deliverError:error completion:completion];
    });
}

- (void)deleteVocabulary:(NSString *)vocabularyID
              completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        if (!error) {
            const char *sql = "DELETE FROM vocabulary WHERE vocabulary_id = ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(vocabularyID).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"删除词条失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备删除词条语句失败");
            }
        }
        [self deliverError:error completion:completion];
    });
}

- (void)fetchExamplesForVocabulary:(NSString *)vocabularyID
                        completion:(void (^)(NSArray<FYVocabularyExample *> *, NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        NSMutableArray<FYVocabularyExample *> *examples = [NSMutableArray array];
        if (!error) {
            const char *sql = "SELECT vocabulary_id, sentence_id, version, source_text_snapshot, translation_snapshot, selected_range_text FROM vocabulary_examples WHERE vocabulary_id = ? ORDER BY version DESC;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(vocabularyID).UTF8String, -1, SQLITE_TRANSIENT);
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    FYVocabularyExample *example = [[FYVocabularyExample alloc] init];
                    example.vocabularyID = FYSQLiteStringOrEmpty(stmt, 0);
                    example.sentenceID = FYSQLiteStringOrEmpty(stmt, 1);
                    example.version = sqlite3_column_int(stmt, 2);
                    example.sourceTextSnapshot = FYSQLiteStringOrEmpty(stmt, 3);
                    const unsigned char *translation = sqlite3_column_text(stmt, 4);
                    example.translationSnapshot = translation ? [NSString stringWithUTF8String:(const char *)translation] : nil;
                    example.selectedRangeText = FYSQLiteStringOrEmpty(stmt, 5);
                    [examples addObject:example];
                }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"读取例句失败");
            }
        }
        if (!completion) { return; }
        dispatch_async(self.deliveryQueue, ^{ completion(examples, error); });
    });
}

- (void)saveAnalysisResult:(FYAnalysisResult *)result
                sentenceID:(NSString *)sentenceID
                   version:(NSInteger)version
                  textHash:(NSString *)textHash
              promptVersion:(NSInteger)promptVersion
             catalogVersion:(NSInteger)catalogVersion
               modelConfig:(NSString *)modelConfig
                completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        if (!error) {
            NSDictionary *dict = FYDictionaryFromAnalysisResult(result);
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            const char *sql = "INSERT OR REPLACE INTO analyses (sentence_id, version, text_hash, prompt_version, catalog_version, model_config, status, result_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?);";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 2, (int)version);
                sqlite3_bind_text(stmt, 3, FYTrimmed(textHash).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 4, (int)promptVersion);
                sqlite3_bind_int(stmt, 5, (int)catalogVersion);
                sqlite3_bind_text(stmt, 6, FYTrimmed(modelConfig).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 7, (int)result.status);
                sqlite3_bind_text(stmt, 8, FYTrimmed(jsonString).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"保存分析结果失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备分析结果语句失败");
            }
        }
        [self deliverError:error completion:completion];
    });
}

- (void)fetchAnalysisForSentence:(NSString *)sentenceID
                         version:(NSInteger)version
                      completion:(void (^)(FYAnalysisResult *, NSString *, NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        FYAnalysisResult *result = nil;
        NSString *modelConfig = nil;
        if (!error) {
            const char *sql = "SELECT result_json, model_config, status FROM analyses WHERE sentence_id = ? AND version = ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 2, (int)version);
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    const unsigned char *json = sqlite3_column_text(stmt, 0);
                    const unsigned char *model = sqlite3_column_text(stmt, 1);
                    int status = sqlite3_column_int(stmt, 2);
                    if (json) {
                        NSData *data = [[NSString stringWithUTF8String:(const char *)json] dataUsingEncoding:NSUTF8StringEncoding];
                        NSDictionary *dict = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
                        if ([dict isKindOfClass:NSDictionary.class]) {
                            result = FYAnalysisResultFromDictionary(dict);
                        }
                    }
                    if (result && (status == FYAnalysisStatusSuccess || status == FYAnalysisStatusNoResult)) { result.status = (FYAnalysisStatus)status; }
                    else { result = nil; }
                    if (model) { modelConfig = [NSString stringWithUTF8String:(const char *)model]; }
                }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"读取分析结果失败");
            }
        }
        if (!completion) { return; }
        dispatch_async(self.deliveryQueue, ^{ completion(result, modelConfig, error); });
    });
}

- (void)toggleSentenceBookmark:(FYRequestIdentity *)identity completion:(void (^)(BOOL,NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error=[self ensureOpened];BOOL exists=NO;sqlite3_stmt *stmt=NULL;
        if(!error && (!identity.sentenceID.length || !identity.sourceText.length || identity.version<1)){error=[NSError errorWithDomain:@"FYLearningStore" code:400 userInfo:@{NSLocalizedDescriptionKey:@"该句尚无有效学习记录"}];}
        if(!error && sqlite3_exec(self.db,"BEGIN IMMEDIATE",NULL,NULL,NULL)!=SQLITE_OK){error=FYStoreError(self.db,@"开始句子收藏失败");}
        if(!error){
            if(sqlite3_prepare_v2(self.db,"SELECT 1 FROM sentence_bookmarks WHERE sentence_id=? AND version=?",-1,&stmt,NULL)==SQLITE_OK){
                sqlite3_bind_text(stmt,1,identity.sentenceID.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_int64(stmt,2,identity.version);
                int rc=sqlite3_step(stmt);exists=rc==SQLITE_ROW;if(rc!=SQLITE_ROW && rc!=SQLITE_DONE){error=FYStoreError(self.db,@"查询句子收藏失败");}sqlite3_finalize(stmt);
            }else{error=FYStoreError(self.db,@"准备句子收藏查询失败");}
        }
        if(!error){
            const char *sql=exists?"DELETE FROM sentence_bookmarks WHERE sentence_id=? AND version=?":"INSERT INTO sentence_bookmarks(sentence_id,version,source,translation,bookmarked_at) VALUES(?,?,?,?,?)";
            if(sqlite3_prepare_v2(self.db,sql,-1,&stmt,NULL)==SQLITE_OK){
                sqlite3_bind_text(stmt,1,identity.sentenceID.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_int64(stmt,2,identity.version);
                if(!exists){sqlite3_bind_text(stmt,3,identity.sourceText.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_text(stmt,4,(identity.translation ?: @"").UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_double(stmt,5,NSDate.date.timeIntervalSince1970);}
                if(sqlite3_step(stmt)!=SQLITE_DONE){error=FYStoreError(self.db,@"更新句子收藏失败");}sqlite3_finalize(stmt);
            }else{error=FYStoreError(self.db,@"准备句子收藏失败");}
        }
        if(!error && sqlite3_exec(self.db,"COMMIT",NULL,NULL,NULL)!=SQLITE_OK){error=FYStoreError(self.db,@"提交句子收藏失败");}
        if(error){sqlite3_exec(self.db,"ROLLBACK",NULL,NULL,NULL);}
        if (completion) { dispatch_async(self.deliveryQueue,^{completion(!exists && !error,error);}); }
    });
}
- (void)fetchSentenceBookmarks:(void (^)(NSArray<FYRequestIdentity *> *,NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error=[self ensureOpened];NSMutableArray *values=[NSMutableArray new];sqlite3_stmt *stmt=NULL;
        if(!error){
            if(sqlite3_prepare_v2(self.db,"SELECT sentence_id,version,source,translation FROM sentence_bookmarks ORDER BY bookmarked_at DESC",-1,&stmt,NULL)==SQLITE_OK){
                int rc;while((rc=sqlite3_step(stmt))==SQLITE_ROW){
                    NSString *sid=FYSQLiteStringOrEmpty(stmt,0);NSString *source=FYSQLiteStringOrEmpty(stmt,2);
                    const unsigned char *translation=sqlite3_column_text(stmt,3);
                    [values addObject:[FYRequestIdentity identityWithSentenceID:sid version:sqlite3_column_int64(stmt,1) requestID:NSUUID.UUID.UUIDString sourceText:source translation:translation?[NSString stringWithUTF8String:(const char *)translation]:@""]];
                }if(rc!=SQLITE_DONE){error=FYStoreError(self.db,@"读取句子收藏失败");}sqlite3_finalize(stmt);
            }else{error=FYStoreError(self.db,@"准备句子收藏列表失败");}
        }
        if (completion) { dispatch_async(self.deliveryQueue,^{completion(values,error);}); }
    });
}

- (void)addGrammarBookmark:(FYGrammarBookmark *)bookmark
                completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        if (!error) {
            const char *sql = "INSERT OR REPLACE INTO grammar_bookmarks (bookmark_id, catalog_id, name, sentence_id, version, source_text_snapshot, translation_snapshot, bookmarked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(bookmark.bookmarkID).UTF8String, -1, SQLITE_TRANSIENT);
                if (bookmark.catalogID) { sqlite3_bind_text(stmt, 2, bookmark.catalogID.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(stmt, 2); }
                sqlite3_bind_text(stmt, 3, FYTrimmed(bookmark.name).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 4, FYTrimmed(bookmark.sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 5, (int)bookmark.version);
                sqlite3_bind_text(stmt, 6, FYTrimmed(bookmark.sourceTextSnapshot).UTF8String, -1, SQLITE_TRANSIENT);
                if (bookmark.translationSnapshot) { sqlite3_bind_text(stmt, 7, bookmark.translationSnapshot.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(stmt, 7); }
                sqlite3_bind_double(stmt, 8, (bookmark.bookmarkedAt ?: NSDate.date).timeIntervalSince1970);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"保存语法收藏失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备语法收藏语句失败");
            }
        }
        [self deliverError:error completion:completion];
    });
}

- (void)fetchGrammarBookmarksWithCompletion:(void (^)(NSArray<FYGrammarBookmark *> *, NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        NSMutableArray<FYGrammarBookmark *> *bookmarks = [NSMutableArray array];
        if (!error) {
            const char *sql = "SELECT bookmark_id, catalog_id, name, sentence_id, version, source_text_snapshot, translation_snapshot, bookmarked_at FROM grammar_bookmarks ORDER BY bookmarked_at DESC;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    FYGrammarBookmark *bookmark = [[FYGrammarBookmark alloc] init];
                    bookmark.bookmarkID = FYSQLiteStringOrEmpty(stmt, 0);
                    const unsigned char *catalogID = sqlite3_column_text(stmt, 1);
                    bookmark.catalogID = catalogID ? [NSString stringWithUTF8String:(const char *)catalogID] : nil;
                    bookmark.name = FYSQLiteStringOrEmpty(stmt, 2);
                    bookmark.sentenceID = FYSQLiteStringOrEmpty(stmt, 3);
                    bookmark.version = sqlite3_column_int(stmt, 4);
                    bookmark.sourceTextSnapshot = FYSQLiteStringOrEmpty(stmt, 5);
                    const unsigned char *translation = sqlite3_column_text(stmt, 6);
                    bookmark.translationSnapshot = translation ? [NSString stringWithUTF8String:(const char *)translation] : nil;
                    bookmark.bookmarkedAt = FYDateFromNumber(@(sqlite3_column_double(stmt, 7)));
                    [bookmarks addObject:bookmark];
                }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"读取语法收藏失败");
            }
        }
        if (!completion) { return; }
        dispatch_async(self.deliveryQueue, ^{ completion(bookmarks, error); });
    });
}

- (void)deleteGrammarBookmark:(NSString *)bookmarkID
                   completion:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NSError *error = [self ensureOpened];
        if (!error) {
            const char *sql = "DELETE FROM grammar_bookmarks WHERE bookmark_id = ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(bookmarkID).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.db, @"删除语法收藏失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.db, @"准备删除语法收藏语句失败");
            }
        }
        [self deliverError:error completion:completion];
    });
}

@end
