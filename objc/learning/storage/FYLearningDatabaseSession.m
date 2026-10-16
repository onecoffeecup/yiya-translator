#import "FYLearningDatabaseSession.h"
#import "FYLearningSchema.h"
#import "FYLearningSQLite.h"

static void FYSQLiteHasTranslation(sqlite3_context *context, int argc, sqlite3_value **values) {
    const unsigned char *bytes = argc == 1 ? sqlite3_value_text(values[0]) : NULL;
    NSString *translation = bytes ? [NSString stringWithUTF8String:(const char *)bytes] : nil;
    sqlite3_result_int(context, [translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0);
}

@interface FYLearningDatabaseSession ()
@property(nonatomic, copy, readwrite) NSString *databasePath;
@property(nonatomic, strong, readwrite) dispatch_queue_t queue;
@property(nonatomic, readwrite) sqlite3 *db;
@property(nonatomic) BOOL opened;
@end

@implementation FYLearningDatabaseSession
- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (self) {
        _databasePath = [path copy];
        _queue = dispatch_queue_create("com.nanami.fuyi.learning-store", DISPATCH_QUEUE_SERIAL);
        _completionQueue = dispatch_get_main_queue();
    }
    return self;
}
- (void)setCompletionQueue:(dispatch_queue_t)queue {
    _completionQueue = queue ?: dispatch_get_main_queue();
}
- (void)deliverError:(NSError *)error completion:(void (^)(NSError *))completion {
    if (!completion) { return; }
    dispatch_async(self.completionQueue, ^{ completion(error); });
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
    rc = sqlite3_create_function_v2(_db, "fy_has_translation", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
                                    NULL, FYSQLiteHasTranslation, NULL, NULL, NULL);
    if (rc != SQLITE_OK) {
        NSError *error = FYStoreError(_db, @"初始化历史译文检查失败");
        sqlite3_close(_db); _db = NULL;
        return error;
    }
    // A second app/process may hold a brief write lock; wait off the main thread.
    sqlite3_busy_timeout(_db, 1500);
    sqlite3_exec(_db, "PRAGMA foreign_keys = ON;", NULL, NULL, NULL);
    NSError *migrationError = FYLearningMigrate(self.db);
    if (migrationError) {
        sqlite3_close(_db);
        _db = NULL;
        return migrationError;
    }
    self.opened = YES;
    return nil;
}

- (NSError *)close {
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
    return error;
}
@end
