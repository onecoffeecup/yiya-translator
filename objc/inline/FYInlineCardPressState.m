#import "FYInlineCardPressState.h"
@implementation FYInlineCardPressState
- (void)beginPressAtPoint:(NSPoint)point stateSource:(id<FYInlineCardPressStateSource>)source {
    source.pressPoint = point;
    source.pressMovedBeyondThreshold = NO;
}
- (void)dragPressToPoint:(NSPoint)point stateSource:(id<FYInlineCardPressStateSource>)source nativeActions:(id<FYInlineCardPressNativeActions>)actions {
    CGFloat distance = hypot(point.x - source.pressPoint.x, point.y - source.pressPoint.y);
    if (distance > 4.0) {
        source.pressMovedBeyondThreshold = YES;
        if (source.collapsePressed) {
            // 按下后又拖走：取消这次收起（按钮不误触）。
            source.collapsePressed = NO;
            [actions setCollapseControlHighlighted:NO];
        }
    }
}
- (void)releasePressAtPoint:(NSPoint)point stateSource:(id<FYInlineCardPressStateSource>)source nativeActions:(id<FYInlineCardPressNativeActions>)actions {
    if (source.collapsePressed) {
        source.collapsePressed = NO;
        [actions setCollapseControlHighlighted:NO];
        if (!source.pressMovedBeyondThreshold && [actions pointIsInCollapseControl:point]) {
            [actions performCollapseAfterPressRelease];
        }
        return;
    }
    if (source.pressMovedBeyondThreshold) { return; }   // 拖动结束不触发学习
    if ([actions pointIsInTitleBar:point]) { return; }
    [actions performClickAfterPressRelease];
}
- (BOOL)pointIsInTitleBar:(NSPoint)point stateSource:(id<FYInlineCardPressStateSource>)source {
    return point.y >= 0 && point.y <= source.titleBarHeight;
}
@end
