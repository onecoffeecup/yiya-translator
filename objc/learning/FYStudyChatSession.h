#import <Foundation/Foundation.h>
#import "FYLearningAnalyzer.h"
NS_ASSUME_NONNULL_BEGIN
@interface FYStudyChatSession : NSObject
@property(nonatomic,strong) FYLearningAnalyzer *analyzer;
@property(nonatomic,copy,readonly) NSString *source;
@property(nonatomic,copy,readonly) NSString *translation;
@property(nonatomic,copy,readonly) NSArray<NSDictionary *> *messages;
@property(nonatomic,readonly) BOOL sending;
@property(nonatomic,copy,nullable) void (^onChange)(void);
- (void)referenceSource:(NSString *)source translation:(NSString *)translation;
- (void)startNewConversationWithSource:(NSString *)source translation:(NSString *)translation;
- (void)send:(NSString *)question;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
