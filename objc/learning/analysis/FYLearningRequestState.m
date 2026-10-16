#import "FYLearningRequestState.h"
#import "FYLearningAnalysisSupport.h"
@interface FYLearningRequestState ()
@property(nonatomic, readwrite) NSInteger generation;
@property(nonatomic, strong, readwrite) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *activeTasks;
@property(nonatomic, strong, readwrite) NSMutableDictionary<NSString *, id> *pendingCompletions;
@end
@implementation FYLearningRequestState
- (instancetype)init {
    self = [super init];
    if (self) {
        _activeTasks = [NSMutableDictionary dictionary];
        _pendingCompletions = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)cancelAll {
    self.generation += 1;
    for (NSURLSessionDataTask *task in self.activeTasks.allValues) {
        [task cancel];
    }
    [self.activeTasks removeAllObjects];
    NSArray *callbacks = self.pendingCompletions.allValues;
    [self.pendingCompletions removeAllObjects];
    for (void (^finish)(NSString *, NSError *) in callbacks) { finish(nil, FYCanceledError()); }
}

- (NSString *)registerCompletion:(FYLearningContentCompletion)completion {
    NSString *requestID = NSUUID.UUID.UUIDString;
    self.pendingCompletions[requestID] = [completion copy];
    return requestID;
}
- (BOOL)resumeTask:(NSURLSessionDataTask *)task requestID:(NSString *)requestID generation:(NSInteger)generation {
    if (generation != self.generation) { return NO; }
    self.activeTasks[requestID] = task;
    [task resume];
    return YES;
}
- (FYLearningContentCompletion)takeCompletionForRequestID:(NSString *)requestID {
    FYLearningContentCompletion completion = self.pendingCompletions[requestID];
    if (!completion) { return nil; }
    [self.pendingCompletions removeObjectForKey:requestID];
    [self.activeTasks removeObjectForKey:requestID];
    return completion;
}
@end
