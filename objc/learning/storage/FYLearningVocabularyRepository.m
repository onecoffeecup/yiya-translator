#import "FYLearningVocabularyRepository.h"
#import "FYLearningDatabaseSession.h"
#import "FYLearningSQLite.h"

@interface FYLearningVocabularyRepository ()
@property(nonatomic, strong) FYLearningDatabaseSession *session;
@end

@implementation FYLearningVocabularyRepository
- (instancetype)initWithSession:(FYLearningDatabaseSession *)session {
    self = [super init];
    if (self) { _session = session; }
    return self;
}

- (NSError *)writeVocabulary:(FYVocabularyEntry *)entry {
        NSError *error = [self.session ensureOpened];
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
            if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
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
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"保存词条失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.session.db, @"准备词条语句失败");
            }
        }
    return error;
}

- (NSError *)writeExample:(FYVocabularyExample *)example {
        NSError *error = [self.session ensureOpened];
        if (!error) {
            const char *sql = "INSERT OR REPLACE INTO vocabulary_examples (vocabulary_id, sentence_id, version, source_text_snapshot, translation_snapshot, selected_range_text) VALUES (?, ?, ?, ?, ?, ?);";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, FYTrimmed(example.vocabularyID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 2, FYTrimmed(example.sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 3, (int)example.version);
                sqlite3_bind_text(stmt, 4, FYTrimmed(example.sourceTextSnapshot).UTF8String, -1, SQLITE_TRANSIENT);
                if (example.translationSnapshot) { sqlite3_bind_text(stmt, 5, example.translationSnapshot.UTF8String, -1, SQLITE_TRANSIENT); }
                else { sqlite3_bind_null(stmt, 5); }
                sqlite3_bind_text(stmt, 6, FYTrimmed(example.selectedRangeText).UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"保存例句关联失败"); }
                sqlite3_finalize(stmt);
            } else {
                error = FYStoreError(self.session.db, @"准备例句关联语句失败");
            }
        }
    return error;
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

- (NSError *)upsertVocabulary:(FYVocabularyEntry *)entry {
    NSError *error = [self writeVocabulary:entry];
    return error;
}

- (NSError *)attachExample:(FYVocabularyExample *)example {
    NSError *error = [self writeExample:example];
    return error;
}

- (NSError *)saveVocabulary:(FYVocabularyEntry *)entry withExample:(FYVocabularyExample *)example {
    NSError *error = [self.session ensureOpened];
    BOOL began = NO;
    if (!error) {
        began = sqlite3_exec(self.session.db, "BEGIN IMMEDIATE;", NULL, NULL, NULL) == SQLITE_OK;
        if (!began) { error = FYStoreError(self.session.db, @"开始词条收藏事务失败"); }
    }
    if (!error) { error = [self writeVocabulary:entry]; }
    if (!error && example) { error = [self writeExample:example]; }
    if (!error && sqlite3_exec(self.session.db, "COMMIT;", NULL, NULL, NULL) != SQLITE_OK) { error = FYStoreError(self.session.db, @"提交词条收藏事务失败"); }
    if (error && began) { sqlite3_exec(self.session.db, "ROLLBACK;", NULL, NULL, NULL); }
    return error;
}

- (NSArray<FYVocabularyEntry *> *)fetchVocabularyListWithError:(NSError **)outError {
    NSError *error = [self.session ensureOpened];
    NSMutableArray<FYVocabularyEntry *> *entries = [NSMutableArray array];
    if (!error) {
        const char *sql = "SELECT vocabulary_id, kind, surface, lemma, reading, meaning, completion_source, review_status, bookmarked_at FROM vocabulary ORDER BY bookmarked_at DESC;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                [entries addObject:[self vocabularyEntryFromStatement:stmt]];
            }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"读取词条列表失败");
        }
    }
    if (outError) { *outError = error; }
    return entries;
}

- (NSError *)updateReviewStatus:(FYReviewStatus)status forVocabulary:(NSString *)vocabularyID {
    NSError *error = [self.session ensureOpened];
    if (!error) {
        const char *sql = "UPDATE vocabulary SET review_status = ? WHERE vocabulary_id = ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, (int)status);
            sqlite3_bind_text(stmt, 2, FYTrimmed(vocabularyID).UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"更新复习状态失败"); }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备复习状态语句失败");
        }
    }
    return error;
}

- (NSError *)deleteVocabulary:(NSString *)vocabularyID {
    NSError *error = [self.session ensureOpened];
    if (!error) {
        const char *sql = "DELETE FROM vocabulary WHERE vocabulary_id = ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(vocabularyID).UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"删除词条失败"); }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备删除词条语句失败");
        }
    }
    return error;
}

- (NSArray<FYVocabularyExample *> *)fetchExamplesForVocabulary:(NSString *)vocabularyID error:(NSError **)outError {
    NSError *error = [self.session ensureOpened];
    NSMutableArray<FYVocabularyExample *> *examples = [NSMutableArray array];
    if (!error) {
        const char *sql = "SELECT vocabulary_id, sentence_id, version, source_text_snapshot, translation_snapshot, selected_range_text FROM vocabulary_examples WHERE vocabulary_id = ? ORDER BY version DESC;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
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
            error = FYStoreError(self.session.db, @"读取例句失败");
        }
    }
    if (outError) { *outError = error; }
    return examples;
}

@end
