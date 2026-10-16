#import <Foundation/Foundation.h>
#import <sqlite3.h>

// Internal conversions shared by the repositories; no queue or connection ownership.
static inline NSError *FYStoreError(sqlite3 *db, NSString *message) {
    return [NSError errorWithDomain:@"FYLearningStore"
                               code:db ? sqlite3_errcode(db) : 0
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static inline NSString *FYSQLiteStringOrEmpty(sqlite3_stmt *stmt, int column) {
    const unsigned char *value = sqlite3_column_text(stmt, column);
    return value ? ([NSString stringWithUTF8String:(const char *)value] ?: @"") : @"";
}

static inline NSDate *FYDateFromNumber(NSNumber *number) {
    if (!number) { return nil; }
    return [NSDate dateWithTimeIntervalSince1970:number.doubleValue];
}

static inline NSString *FYTrimmed(NSString *value) {
    return value ?: @"";
}

