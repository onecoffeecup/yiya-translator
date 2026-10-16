#import <Foundation/Foundation.h>
typedef void (^FYLearningContentCompletion)(NSString *, NSError *);
// Analyzer-owned state, using the same main-thread lifecycle as the original implementation.
@interface FYLearningRequestState : NSObject
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *activeTasks;
@property(nonatomic, strong, readonly) NSMutableDictionary<NSString *, id> *pendingCompletions;
- (NSString *)registerCompletion:(FYLearningContentCompletion)completion;
- (BOOL)resumeTask:(NSURLSessionDataTask *)task requestID:(NSString *)requestID generation:(NSInteger)generation;
- (FYLearningContentCompletion)takeCompletionForRequestID:(NSString *)requestID;
- (void)cancelAll;
@end
