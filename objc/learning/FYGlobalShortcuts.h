#import <Foundation/Foundation.h>
@interface FYGlobalShortcuts : NSObject
@property(nonatomic,copy) void (^onAction)(NSInteger action);
@property(nonatomic,copy,readonly) NSArray<NSString *> *unavailable;
- (void)start;
- (void)stop;
@end
