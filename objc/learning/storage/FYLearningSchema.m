#import "FYLearningSchema.h"
#import "FYLearningSQLite.h"

NSError *FYLearningMigrate(sqlite3 *db) {
    int userVersion = 0;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, NULL) == SQLITE_OK) {
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
        int rc = sqlite3_exec(db, schema, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            NSError *error = [NSError errorWithDomain:@"FYLearningStore" code:rc
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"建表失败：%s", errMsg ?: "unknown"]}];
            if (errMsg) { sqlite3_free(errMsg); }
            return error;
        }
        if (errMsg) { sqlite3_free(errMsg); }

        char setVersion[64];
        snprintf(setVersion, sizeof(setVersion), "PRAGMA user_version = 1;");
        sqlite3_exec(db, setVersion, NULL, NULL, NULL);
    }
    if(userVersion<2){
        const char *upgrade="BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS sentence_bookmarks (sentence_id TEXT NOT NULL, version INTEGER NOT NULL, source TEXT NOT NULL, translation TEXT, bookmarked_at REAL, PRIMARY KEY(sentence_id,version)); PRAGMA user_version=2; COMMIT;";
        if(sqlite3_exec(db,upgrade,NULL,NULL,NULL)!=SQLITE_OK){NSError *error=FYStoreError(db,@"升级句子收藏数据表失败");sqlite3_exec(db,"ROLLBACK",NULL,NULL,NULL);return error;}
    }
    if (userVersion < 3) {
        const char *upgrade = "BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS sentence_speaker_exclusions ("
            "sentence_id TEXT NOT NULL, version INTEGER NOT NULL, labels_json TEXT NOT NULL, "
            "PRIMARY KEY(sentence_id,version), FOREIGN KEY(sentence_id,version) "
            "REFERENCES sentence_versions(sentence_id,version) ON DELETE CASCADE); PRAGMA user_version=3; COMMIT;";
        if (sqlite3_exec(db, upgrade, NULL, NULL, NULL) != SQLITE_OK) {
            NSError *error=FYStoreError(db,@"升级对白姓名栏记录失败");
            sqlite3_exec(db,"ROLLBACK;",NULL,NULL,NULL); return error;
        }
    }
    return nil;
}
