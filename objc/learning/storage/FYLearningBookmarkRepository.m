#import "FYLearningBookmarkRepository.h"
#import "FYLearningDatabaseSession.h"
#import "FYLearningSQLite.h"

@interface FYLearningBookmarkRepository ()
@property(nonatomic, strong) FYLearningDatabaseSession *session;
@end

@implementation FYLearningBookmarkRepository
- (instancetype)initWithSession:(FYLearningDatabaseSession *)session {
    self = [super init];
    if (self) { _session = session; }
    return self;
}

- (BOOL)toggleSentenceBookmark:(FYRequestIdentity *)identity error:(NSError **)outError {
    NSError *error=[self.session ensureOpened];BOOL exists=NO;sqlite3_stmt *stmt=NULL;
    if(!error && (!identity.sentenceID.length || !identity.sourceText.length || identity.version<1)){error=[NSError errorWithDomain:@"FYLearningStore" code:400 userInfo:@{NSLocalizedDescriptionKey:@"该句尚无有效学习记录"}];}
    if(!error && sqlite3_exec(self.session.db,"BEGIN IMMEDIATE",NULL,NULL,NULL)!=SQLITE_OK){error=FYStoreError(self.session.db,@"开始句子收藏失败");}
    if(!error){
        if(sqlite3_prepare_v2(self.session.db,"SELECT 1 FROM sentence_bookmarks WHERE sentence_id=? AND version=?",-1,&stmt,NULL)==SQLITE_OK){
            sqlite3_bind_text(stmt,1,identity.sentenceID.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_int64(stmt,2,identity.version);
            int rc=sqlite3_step(stmt);exists=rc==SQLITE_ROW;if(rc!=SQLITE_ROW && rc!=SQLITE_DONE){error=FYStoreError(self.session.db,@"查询句子收藏失败");}sqlite3_finalize(stmt);
        }else{error=FYStoreError(self.session.db,@"准备句子收藏查询失败");}
    }
    if(!error){
        const char *sql=exists?"DELETE FROM sentence_bookmarks WHERE sentence_id=? AND version=?":"INSERT INTO sentence_bookmarks(sentence_id,version,source,translation,bookmarked_at) VALUES(?,?,?,?,?)";
        if(sqlite3_prepare_v2(self.session.db,sql,-1,&stmt,NULL)==SQLITE_OK){
            sqlite3_bind_text(stmt,1,identity.sentenceID.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_int64(stmt,2,identity.version);
            if(!exists){sqlite3_bind_text(stmt,3,identity.sourceText.UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_text(stmt,4,(identity.translation ?: @"").UTF8String,-1,SQLITE_TRANSIENT);sqlite3_bind_double(stmt,5,NSDate.date.timeIntervalSince1970);}
            if(sqlite3_step(stmt)!=SQLITE_DONE){error=FYStoreError(self.session.db,@"更新句子收藏失败");}sqlite3_finalize(stmt);
        }else{error=FYStoreError(self.session.db,@"准备句子收藏失败");}
    }
    if(!error && sqlite3_exec(self.session.db,"COMMIT",NULL,NULL,NULL)!=SQLITE_OK){error=FYStoreError(self.session.db,@"提交句子收藏失败");}
    if(error){sqlite3_exec(self.session.db,"ROLLBACK",NULL,NULL,NULL);}
    if (outError) { *outError = error; }
    return !exists && !error;
}

- (NSArray<FYRequestIdentity *> *)fetchSentenceBookmarksWithError:(NSError **)outError {
    NSError *error=[self.session ensureOpened];NSMutableArray *values=[NSMutableArray new];sqlite3_stmt *stmt=NULL;
    if(!error){
        if(sqlite3_prepare_v2(self.session.db,"SELECT sentence_id,version,source,translation FROM sentence_bookmarks ORDER BY bookmarked_at DESC",-1,&stmt,NULL)==SQLITE_OK){
            int rc;while((rc=sqlite3_step(stmt))==SQLITE_ROW){
                NSString *sid=FYSQLiteStringOrEmpty(stmt,0);NSString *source=FYSQLiteStringOrEmpty(stmt,2);
                const unsigned char *translation=sqlite3_column_text(stmt,3);
                [values addObject:[FYRequestIdentity identityWithSentenceID:sid version:sqlite3_column_int64(stmt,1) requestID:NSUUID.UUID.UUIDString sourceText:source translation:translation?[NSString stringWithUTF8String:(const char *)translation]:@""]];
            }if(rc!=SQLITE_DONE){error=FYStoreError(self.session.db,@"读取句子收藏失败");}sqlite3_finalize(stmt);
        }else{error=FYStoreError(self.session.db,@"准备句子收藏列表失败");}
    }
    if (outError) { *outError = error; }
    return values;
}

- (NSError *)addGrammarBookmark:(FYGrammarBookmark *)bookmark {
    NSError *error = [self.session ensureOpened];
    if (!error) {
        const char *sql = "INSERT OR REPLACE INTO grammar_bookmarks (bookmark_id, catalog_id, name, sentence_id, version, source_text_snapshot, translation_snapshot, bookmarked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
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
            if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"保存语法收藏失败"); }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备语法收藏语句失败");
        }
    }
    return error;
}

- (NSArray<FYGrammarBookmark *> *)fetchGrammarBookmarksWithError:(NSError **)outError {
    NSError *error = [self.session ensureOpened];
    NSMutableArray<FYGrammarBookmark *> *bookmarks = [NSMutableArray array];
    if (!error) {
        const char *sql = "SELECT bookmark_id, catalog_id, name, sentence_id, version, source_text_snapshot, translation_snapshot, bookmarked_at FROM grammar_bookmarks ORDER BY bookmarked_at DESC;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
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
            error = FYStoreError(self.session.db, @"读取语法收藏失败");
        }
    }
    if (outError) { *outError = error; }
    return bookmarks;
}

- (NSError *)deleteGrammarBookmark:(NSString *)bookmarkID {
    NSError *error = [self.session ensureOpened];
    if (!error) {
        const char *sql = "DELETE FROM grammar_bookmarks WHERE bookmark_id = ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(bookmarkID).UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"删除语法收藏失败"); }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备删除语法收藏语句失败");
        }
    }
    return error;
}

@end
