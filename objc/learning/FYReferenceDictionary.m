#import "FYReferenceDictionary.h"
#import <sqlite3.h>
@implementation FYReferenceDictionary {
    NSURL *_url;
    dispatch_queue_t _queue;
    sqlite3 *_db;
}
- (instancetype)initWithURL:(NSURL *)url {
    if ((self=[super init])) { _url=url; _queue=dispatch_queue_create("com.nanami.fuyi.reference",DISPATCH_QUEUE_SERIAL); }
    return self;
}
- (void)dealloc { if (_db) { sqlite3_close(_db); } }
- (void)lookupWord:(NSString *)word reading:(NSString *)reading completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSString *query=[[word precomposedStringWithCompatibilityMapping] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *requestedReading=[reading precomposedStringWithCompatibilityMapping];
    dispatch_async(_queue, ^{
        NSError *error=nil; NSMutableArray *records=[NSMutableArray array];
        if (!self->_db) {
            if (!self->_url || sqlite3_open_v2(self->_url.path.UTF8String,&self->_db,SQLITE_OPEN_READONLY|SQLITE_OPEN_NOMUTEX,NULL)!=SQLITE_OK) {
                if(self->_db){sqlite3_close(self->_db);self->_db=NULL;}
                error=[NSError errorWithDomain:@"FYReferenceDictionary" code:1 userInfo:@{NSLocalizedDescriptionKey:@"离线词典缺失或无法打开，请重新安装资料包。"}];
            }
        }
        sqlite3_stmt *stmt=NULL;
        if (!error && query.length) {
            if (sqlite3_prepare_v2(self->_db,"SELECT e.payload FROM forms f JOIN entries e ON e.id=f.entry_id WHERE f.form=? ORDER BY e.id;",-1,&stmt,NULL)!=SQLITE_OK) {
                error=[NSError errorWithDomain:@"FYReferenceDictionary" code:2 userInfo:@{NSLocalizedDescriptionKey:@"离线词典格式无法读取，请重新安装资料包。"}];
            } else {
                sqlite3_bind_text(stmt,1,query.UTF8String,-1,SQLITE_TRANSIENT);
                int status;
                while ((status=sqlite3_step(stmt))==SQLITE_ROW) {
                    const char *raw=(const char *)sqlite3_column_text(stmt,0);
                    NSData *data=raw ? [[NSString stringWithUTF8String:raw] dataUsingEncoding:NSUTF8StringEncoding] : nil;
                    NSDictionary *record=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
                    if (![record isKindOfClass:NSDictionary.class] || ![record[@"readings"] isKindOfClass:NSArray.class] || ![record[@"senses"] isKindOfClass:NSArray.class]) {
                        error=[NSError errorWithDomain:@"FYReferenceDictionary" code:3 userInfo:@{NSLocalizedDescriptionKey:@"词典记录损坏，请更新资料包。"}];break;
                    }
                    if (requestedReading.length && ![record[@"readings"] containsObject:requestedReading]) {continue;}
                    NSMutableDictionary *matched=[record mutableCopy];
                    NSMutableOrderedSet *levels=[NSMutableOrderedSet orderedSet];
                    for(NSDictionary *evidence in record[@"reference_level_matches"]){
                        NSString *form=[evidence[@"word"] precomposedStringWithCompatibilityMapping];
                        if([form isEqualToString:query]){[levels addObject:evidence[@"level"]];}
                    }
                    // Reading-only matches are ambiguous across written forms: do not merge their grades.
                    matched[@"reference_levels"]=levels.array;
                    matched[@"queried_form"]=query;
                    [records addObject:matched];
                }
                if (status!=SQLITE_DONE && !error) {error=[NSError errorWithDomain:@"FYReferenceDictionary" code:4 userInfo:@{NSLocalizedDescriptionKey:@"读取离线词典失败。"}];}
            }
        }
        if(stmt){sqlite3_finalize(stmt);}
        dispatch_async(dispatch_get_main_queue(),^{completion(error?@[]:[records copy],error);});
    });
}
@end
