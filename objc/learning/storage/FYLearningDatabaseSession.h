#import <Foundation/Foundation.h>
#import <sqlite3.h>

// One session per FYLearningStore. All synchronous repository operations must run
// on queue. Repositories neither open independent connections nor dispatch work.
@interface FYLearningDatabaseSession : NSObject
- (instancetype)initWithDatabasePath:(NSString *)path;
@property(nonatomic, copy, readonly) NSString *databasePath;
@property(nonatomic, strong, readonly) dispatch_queue_t queue;
@property(nonatomic, strong) dispatch_queue_t completionQueue;
@property(nonatomic, readonly) sqlite3 *db;
- (NSError *)ensureOpened;
- (NSError *)close;
- (void)deliverError:(NSError *)error completion:(void (^)(NSError *))completion;
@end
