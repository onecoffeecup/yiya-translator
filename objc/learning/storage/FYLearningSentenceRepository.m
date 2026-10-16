#import "FYLearningSentenceRepository.h"
#import "FYLearningDatabaseSession.h"
#import "FYLearningSQLite.h"

@interface FYLearningSentenceRepository ()
@property(nonatomic, strong) FYLearningDatabaseSession *session;
@property(nonatomic, copy) NSString *preservedHistorySentenceID;
@end

@implementation FYLearningSentenceRepository
- (instancetype)initWithSession:(FYLearningDatabaseSession *)session {
    self = [super init];
    if (self) { _session = session; }
    return self;
}

- (NSError *)pruneHistory {
    if (self.historyRetentionLimit == 0) { return nil; }
    // Keep translated history independently from the existing bounded working
    // set. Pending identities still support retries, pinning and corrections,
    // but cannot evict a successful translation or enter the recent list.
    const char *sql = "DELETE FROM sentences WHERE sentence_id NOT IN "
                      "(SELECT sentence_id FROM sentences WHERE fy_has_translation(latest_translation) "
                      "ORDER BY occurred_at DESC, rowid DESC LIMIT ?) "
                      "AND sentence_id NOT IN "
                      "(SELECT sentence_id FROM sentences ORDER BY occurred_at DESC, rowid DESC LIMIT ?) "
                      "AND sentence_id NOT IN (SELECT sentence_id FROM sentence_bookmarks) "
                      "AND (? IS NULL OR sentence_id != ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return FYStoreError(self.session.db, @"准备清理历史台词失败");
    }
    sqlite3_bind_int64(stmt, 1, (sqlite3_int64)self.historyRetentionLimit);
    sqlite3_bind_int64(stmt, 2, (sqlite3_int64)self.historyRetentionLimit);
    if (self.preservedHistorySentenceID.length) {
        sqlite3_bind_text(stmt, 3, self.preservedHistorySentenceID.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, self.preservedHistorySentenceID.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3); sqlite3_bind_null(stmt, 4);
    }
    NSError *error = sqlite3_step(stmt) == SQLITE_DONE ? nil : FYStoreError(self.session.db, @"清理历史台词失败");
    sqlite3_finalize(stmt);
    return error;
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
    NSData *data=[FYSQLiteStringOrEmpty(stmt,9) dataUsingEncoding:NSUTF8StringEncoding];
    id labels=data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSMutableArray<NSString *> *keys=[NSMutableArray new];
    if ([labels isKindOfClass:NSArray.class]) {
        for (id label in labels) {
            if ([label isKindOfClass:NSString.class] && [label length]) [keys addObject:label];
        }
    }
    record.excludedSpeakerLabels=keys;
    return record;
}

- (NSError *)configureHistoryRetentionWithLimit:(NSUInteger)limit {
    self.historyRetentionLimit = limit;
    NSError *error = [self.session ensureOpened];
    if (!error) { error = [self pruneHistory]; }
    return error;
}

- (NSError *)preserveSentenceForHistory:(NSString *)sentenceID {
    self.preservedHistorySentenceID = sentenceID;
    NSError *error = [self.session ensureOpened];
    if (!error) { error = [self pruneHistory]; }
    return error;
}

- (NSError *)ensureSessionWithID:(NSString *)sessionID displayName:(NSString *)displayName language:(NSString *)language {
    NSError *error = [self.session ensureOpened];
    if (!error) {
        const char *sql = "INSERT OR IGNORE INTO sessions (session_id, display_name, started_at, language) VALUES (?, ?, ?, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(sessionID).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, FYTrimmed(displayName).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_double(stmt, 3, NSDate.date.timeIntervalSince1970);
            sqlite3_bind_text(stmt, 4, FYTrimmed(language).UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) != SQLITE_DONE) {
                error = FYStoreError(self.session.db, @"保存会话失败");
            }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备会话语句失败");
        }
    }
    return error;
}

- (NSError *)insertSentenceWithID:(NSString *)sentenceID
    sessionID:(NSString *)sessionID
    kind:(FYSentenceKind)kind
    originalText:(NSString *)originalText
    occurredAt:(NSDate *)occurredAt {
    NSError *error = [self.session ensureOpened];
    if (!error) {
        if (sqlite3_exec(self.session.db, "BEGIN IMMEDIATE;", NULL, NULL, NULL) != SQLITE_OK) {
            return FYStoreError(self.session.db, @"开始保存句子事务失败");
        }

        const char *sentenceSQL = "INSERT OR IGNORE INTO sentences (sentence_id, session_id, kind, original_text, latest_version, latest_translation, occurred_at, display_name) VALUES (?, ?, ?, ?, 1, NULL, ?, NULL);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sentenceSQL, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, FYTrimmed(sessionID).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 3, (int)kind);
            sqlite3_bind_text(stmt, 4, FYTrimmed(originalText).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_double(stmt, 5, (occurredAt ?: NSDate.date).timeIntervalSince1970);
            if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"保存句子失败"); }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备句子语句失败");
        }

        if (!error) {
            const char *versionSQL = "INSERT OR IGNORE INTO sentence_versions (sentence_id, version, text, translation, created_at) VALUES (?, 1, ?, NULL, ?);";
            sqlite3_stmt *vstmt = NULL;
            if (sqlite3_prepare_v2(self.session.db, versionSQL, -1, &vstmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(vstmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(vstmt, 2, FYTrimmed(originalText).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_double(vstmt, 3, (occurredAt ?: NSDate.date).timeIntervalSince1970);
                if (sqlite3_step(vstmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"保存句子版本失败"); }
                sqlite3_finalize(vstmt);
            } else {
                error = FYStoreError(self.session.db, @"准备句子版本语句失败");
            }
        }

        if (!error) { error = [self pruneHistory]; }
        if (error) {
            sqlite3_exec(self.session.db, "ROLLBACK;", NULL, NULL, NULL);
        } else {
            if (sqlite3_exec(self.session.db, "COMMIT;", NULL, NULL, NULL) != SQLITE_OK) {
                error = FYStoreError(self.session.db, @"提交保存句子事务失败");
                sqlite3_exec(self.session.db, "ROLLBACK;", NULL, NULL, NULL);
            }
        }
    }
    return error;
}

- (NSError *)updateTranslation:(NSString *)translation forSentence:(NSString *)sentenceID version:(NSInteger)version {
    NSError *error = [self.session ensureOpened];
    BOOL began = NO;
    if (!error) {
        began = sqlite3_exec(self.session.db, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK;
        if (!began) { error = FYStoreError(self.session.db, @"开始回填译文事务失败"); }
    }
    if (!error) {
        const char *vSQL = "UPDATE sentence_versions SET translation = ? WHERE sentence_id = ? AND version = ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, vSQL, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(translation).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 3, (int)version);
            if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"回填译文失败"); }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备回填译文语句失败");
        }

        if (!error) {
            const char *sSQL = "UPDATE sentences SET latest_translation = ? WHERE sentence_id = ? AND latest_version = ?;";
            sqlite3_stmt *sstmt = NULL;
            if (sqlite3_prepare_v2(self.session.db, sSQL, -1, &sstmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(sstmt, 1, FYTrimmed(translation).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(sstmt, 2, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(sstmt, 3, (int)version);
                if (sqlite3_step(sstmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"回填最新译文失败"); }
                sqlite3_finalize(sstmt);
            } else {
                error = FYStoreError(self.session.db, @"准备最新译文语句失败");
            }
        }
    }
    if (!error) { error = [self pruneHistory]; }
    if (began) {
        if (!error && sqlite3_exec(self.session.db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK) {
            error = FYStoreError(self.session.db, @"提交回填译文事务失败");
        }
        if (error) { sqlite3_exec(self.session.db, "ROLLBACK", NULL, NULL, NULL); }
    }
    return error;
}

- (NSInteger)appendVersionForSentence:(NSString *)sentenceID
    text:(NSString *)text
    translation:(NSString *)translation
    error:(NSError **)outError {
    NSError *error = [self.session ensureOpened];
    NSInteger newVersion = 0;
    if (!error) {
        sqlite3_stmt *latestStmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, "SELECT latest_version FROM sentences WHERE sentence_id = ?;", -1, &latestStmt, NULL) == SQLITE_OK) {
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
        if (sqlite3_exec(self.session.db, "BEGIN IMMEDIATE;", NULL, NULL, NULL) != SQLITE_OK) {
            error = FYStoreError(self.session.db, @"开始追加版本事务失败");
        }
    }
    if (!error) {
        const char *vSQL = "INSERT INTO sentence_versions (sentence_id, version, text, translation, created_at) VALUES (?, ?, ?, ?, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, vSQL, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 2, (int)newVersion);
            sqlite3_bind_text(stmt, 3, FYTrimmed(text).UTF8String, -1, SQLITE_TRANSIENT);
            if (translation) { sqlite3_bind_text(stmt, 4, translation.UTF8String, -1, SQLITE_TRANSIENT); }
            else { sqlite3_bind_null(stmt, 4); }
            sqlite3_bind_double(stmt, 5, NSDate.date.timeIntervalSince1970);
            if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"追加句子版本失败"); }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备追加版本语句失败");
        }
    }
    if (!error) {
        const char *uSQL = "UPDATE sentences SET latest_version = ?, latest_translation = ? WHERE sentence_id = ?;";
        sqlite3_stmt *ustmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, uSQL, -1, &ustmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(ustmt, 1, (int)newVersion);
            if (translation) { sqlite3_bind_text(ustmt, 2, translation.UTF8String, -1, SQLITE_TRANSIENT); }
            else { sqlite3_bind_null(ustmt, 2); }
            sqlite3_bind_text(ustmt, 3, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(ustmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"更新主句版本失败"); }
            sqlite3_finalize(ustmt);
        } else {
            error = FYStoreError(self.session.db, @"准备更新主句版本语句失败");
        }
    }
    if (!error) { error = [self pruneHistory]; }
    if (error) {
        sqlite3_exec(self.session.db, "ROLLBACK;", NULL, NULL, NULL);
    } else if (sqlite3_exec(self.session.db, "COMMIT;", NULL, NULL, NULL) != SQLITE_OK) {
        error = FYStoreError(self.session.db, @"提交追加版本事务失败");
        sqlite3_exec(self.session.db, "ROLLBACK;", NULL, NULL, NULL);
    }
    if (outError) { *outError = error; }
    return error ? 0 : newVersion;
}

- (NSError *)recordExcludedSpeakerJSON:(NSString *)json
    sentenceID:(NSString *)sentenceID
    source:(NSString *)source
    version:(NSInteger)version {
    NSError *error=[self.session ensureOpened];
    if (!error) {
        // A queued correction or pruning must not attach roles to another version/source.
        const char *sql="INSERT INTO sentence_speaker_exclusions (sentence_id,version,labels_json) "
            "SELECT v.sentence_id,v.version,? FROM sentence_versions v JOIN sentences s ON s.sentence_id=v.sentence_id "
            "WHERE v.sentence_id=? AND v.version=? AND v.text=? AND s.kind=0 "
            "ON CONFLICT(sentence_id,version) DO UPDATE SET labels_json=excluded.labels_json;";
        sqlite3_stmt *stmt=NULL;
        if (sqlite3_prepare_v2(self.session.db,sql,-1,&stmt,NULL)==SQLITE_OK) {
            sqlite3_bind_text(stmt,1,json.UTF8String,-1,SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt,2,sentenceID.UTF8String,-1,SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt,3,version);
            sqlite3_bind_text(stmt,4,source.UTF8String,-1,SQLITE_TRANSIENT);
            if (sqlite3_step(stmt)!=SQLITE_DONE) error=FYStoreError(self.session.db,@"保存对白姓名栏记录失败");
            sqlite3_finalize(stmt);
        } else { error=FYStoreError(self.session.db,@"准备对白姓名栏记录失败"); }
    }
    return error;
}

- (FYSentenceRecord *)fetchSentence:(NSString *)sentenceID error:(NSError **)outError {
    NSError *error = [self.session ensureOpened];
    FYSentenceRecord *record = nil;
    if (!error) {
        const char *sql = "SELECT s.sentence_id, s.session_id, s.kind, s.original_text, s.latest_version, s.latest_translation, s.occurred_at, s.display_name,"
                          " (SELECT v.text FROM sentence_versions v WHERE v.sentence_id = s.sentence_id AND v.version = s.latest_version) AS latest_text,"
                          " (SELECT e.labels_json FROM sentence_speaker_exclusions e WHERE e.sentence_id=s.sentence_id AND e.version=s.latest_version)"
                          " FROM sentences s WHERE s.sentence_id = ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                record = [self sentenceRecordFromStatement:stmt];
            }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"读取句子失败");
        }
    }
    if (outError) { *outError = error; }
    return record;
}

- (NSArray<FYSentenceRecord *> *)fetchRecentSentencesWithLimit:(NSUInteger)limit error:(NSError **)outError {
    NSError *error = [self.session ensureOpened];
    NSMutableArray<FYSentenceRecord *> *records = [NSMutableArray array];
    if (!error) {
        const char *sql = "SELECT s.sentence_id, s.session_id, s.kind, s.original_text, s.latest_version, s.latest_translation, s.occurred_at, s.display_name,"
                          " (SELECT v.text FROM sentence_versions v WHERE v.sentence_id = s.sentence_id AND v.version = s.latest_version) AS latest_text,"
                          " (SELECT e.labels_json FROM sentence_speaker_exclusions e WHERE e.sentence_id=s.sentence_id AND e.version=s.latest_version)"
                          " FROM sentences s WHERE fy_has_translation(s.latest_translation) "
                          "ORDER BY s.occurred_at DESC, s.rowid DESC LIMIT ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, (int)MAX(1, limit));
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                [records addObject:[self sentenceRecordFromStatement:stmt]];
            }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"读取历史失败");
        }
    }
    if (outError) { *outError = error; }
    return records;
}

- (NSArray<FYSentenceVersion *> *)fetchVersionsForSentence:(NSString *)sentenceID error:(NSError **)outError {
    NSError *error = [self.session ensureOpened];
    NSMutableArray<FYSentenceVersion *> *versions = [NSMutableArray array];
    if (!error) {
        const char *sql = "SELECT sentence_id, version, text, translation, created_at FROM sentence_versions WHERE sentence_id = ? ORDER BY version ASC;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
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
            error = FYStoreError(self.session.db, @"读取句子版本失败");
        }
    }
    if (outError) { *outError = error; }
    return versions;
}

@end
