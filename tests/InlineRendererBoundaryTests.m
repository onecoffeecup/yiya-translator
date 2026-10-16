#import "inline/FYInlineOverlayViews.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
int main(void){@autoreleasepool{
    Check(NSApp==nil,@"minimum native renderer consumer has no application or window before cold access");
    FYInlineCardPressState *state=[FYInlineCardPressState new];
    Check(NSApp==nil&&!state.collapsePressed&&!state.pressMovedBeyondThreshold,@"cold owner creates no native application, font, control or window");
    Check(class_getSuperclass(FYInlineLongCardView.class)==NSView.class&&class_getSuperclass(FYInlinePatchView.class)==NSView.class,@"native renderer classes link without calculator/grouping/model/host");
    Check(!class_getInstanceVariable(FYInlineLongCardView.class,"_pressPoint")&&!class_getInstanceVariable(FYInlineLongCardView.class,"_pressMovedBeyondThreshold")&&!class_getInstanceVariable(FYInlineLongCardView.class,"_collapsePressed")&&!class_getInstanceVariable(FYInlineLongCardView.class,"_titleBarHeight"),@"native long card has no duplicate press state scalars");
    Check(class_getInstanceVariable(FYInlineLongCardView.class,"_pressState")&&class_getInstanceVariable(FYInlineCardPressState.class,"_pressPoint")&&class_getInstanceVariable(FYInlineCardPressState.class,"_pressMovedBeyondThreshold")&&class_getInstanceVariable(FYInlineCardPressState.class,"_collapsePressed")&&class_getInstanceVariable(FYInlineCardPressState.class,"_titleBarHeight"),@"pure press owner has all original fields and native card owns only that component");
    Check(class_conformsToProtocol(FYInlineLongCardView.class,@protocol(FYInlineCardPressStateSource))&&class_conformsToProtocol(FYInlineLongCardView.class,@protocol(FYInlineCardPressNativeActions)),@"actual native renderer explicitly implements small state and event action contracts");
    Check([FYInlineLongCardView instancesRespondToSelector:@selector(performCollapseAfterPressRelease)]&&[FYInlineLongCardView instancesRespondToSelector:@selector(setCollapseControlHighlighted:)]&&[FYInlineLongCardView instancesRespondToSelector:@selector(performClickAfterPressRelease)],@"native event actions remain available on actual class");
    Check(NSApp==nil,@"native dependency and class ownership checks do not create UI objects");
    printf("PASS InlineRendererBoundaryTests: %lu checks; actual native classes/minimum link/cold state, no UI object initialization\n",(unsigned long)checks);
}return 0;}
