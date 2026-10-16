#import "FYServiceTestController.h"

@implementation FYServiceTestController
- (void)invalidateWhileRunning:(BOOL)running status:(void (^)(NSString *))status {
    BOOL pending = self.pending;
    self.generation++;
    [self.taskOwner cancelActiveTask];
    self.pending = NO;
    if (pending && !running) { status(@"服务未测试"); }
}
- (void)testSample:(NSString *)sample transport:(FYServiceTestTransport)transport
         isRunning:(BOOL (^)(void))isRunning status:(void (^)(NSString *))status
           present:(FYServiceTestPresentationHandler)present
          sanitize:(NSString *(^)(NSString *, NSString *))sanitize {
    [self invalidateWhileRunning:isRunning() status:status];
    if (!isRunning()) { status(@"正在测试翻译"); }
    NSInteger generation = self.generation;
    self.pending = YES;
    present(@"pending", nil, nil);
    transport(sample, ^(NSString *translated, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) { return; }
            self.pending = NO;
            BOOL showStatus = !isRunning();
            if (error) {
                if (showStatus) { status(@"翻译测试失败"); }
                present(@"error", error.localizedDescription ?: @"未知错误", nil);
            } else {
                if (showStatus) { status(@"翻译测试完成"); }
                NSString *result = [NSString stringWithFormat:@"测试原文：%@\n译文：%@", sample, sanitize(translated, sample)];
                present(@"success", nil, result);
            }
        });
    });
}
@end
