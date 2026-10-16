#import <Foundation/Foundation.h>

// Only service configuration is visible here; no task, database or UI state.
@protocol FYLearningRequestConfiguration <NSObject>
@property(nonatomic, readonly) NSString *baseURL;
@property(nonatomic, readonly) NSString *apiKey;
@property(nonatomic, readonly) NSString *model;
- (BOOL)isDeepSeek;
@end
@interface FYLearningRequestBuilder : NSObject
+ (NSMutableURLRequest *)requestForConfiguration:(id<FYLearningRequestConfiguration>)configuration
    messages:(NSArray<NSDictionary *> *)messages maxTokens:(NSInteger)maxTokens
    grammarAnalysis:(BOOL)grammarAnalysis error:(NSError **)outError;
@end
