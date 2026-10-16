#import "inline/FYInlineOverlayViews.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
// Same fixture compiles against exact original and extracted native views.
// Running it requires a separately authorized desktop period.
static NSEvent *Event(FYInlineLongCardView *card,NSEventType type,NSPoint local){return [NSEvent mouseEventWithType:type location:[card convertPoint:local toView:nil] modifierFlags:0 timestamp:0 windowNumber:card.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];}
int main(void){@autoreleasepool{
    if(!getenv("FY_TEST_ALLOW_UI")||strcmp(getenv("FY_TEST_ALLOW_UI"),"1")!=0){fprintf(stderr,"BLOCKED: requires current desktop authorization and FY_TEST_ALLOW_UI=1\n");return 86;}
    [NSApplication sharedApplication];NSPanel *panel=[[NSPanel alloc]initWithContentRect:NSMakeRect(0,0,300,200) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];panel.releasedWhenClosed=NO;
    FYInlineLongCardView *card=[[FYInlineLongCardView alloc]initWithFrame:NSMakeRect(0,0,300,200)];[panel.contentView addSubview:card];card.windowDragEnabled=NO;
    __block NSUInteger clicks=0,collapses=0,begins=0,ends=0;card.onClick=^{clicks++;};card.onCollapse=^{collapses++;};card.onDragBegan=^{begins++;};card.onDragEnded=^{ends++;};
    Check(card.titleBarHeight==55&&!card.pressMovedBeyondThreshold&&!card.collapsePressed,@"actual native constructor retains default title height and press zero state");
    NSPoint body=NSMakePoint(10,100);[card mouseDown:Event(card,NSEventTypeLeftMouseDown,body)];[card mouseUp:Event(card,NSEventTypeLeftMouseUp,body)];Check(clicks==1&&collapses==0,@"actual body event opens learning once");
    [card mouseDown:Event(card,NSEventTypeLeftMouseDown,body)];[card mouseDragged:Event(card,NSEventTypeLeftMouseDragged,NSMakePoint(14,100))];[card mouseUp:Event(card,NSEventTypeLeftMouseUp,NSMakePoint(14,100))];Check(clicks==2&&!card.pressMovedBeyondThreshold,@"actual four-point movement retains click");
    [card mouseDown:Event(card,NSEventTypeLeftMouseDown,body)];[card mouseDragged:Event(card,NSEventTypeLeftMouseDragged,NSMakePoint(14.01,100))];[card mouseUp:Event(card,NSEventTypeLeftMouseUp,NSMakePoint(14.01,100))];Check(clicks==2&&card.pressMovedBeyondThreshold,@"actual movement beyond threshold suppresses click");
    NSPoint title=NSMakePoint(10,10);[card mouseDown:Event(card,NSEventTypeLeftMouseDown,title)];[card mouseUp:Event(card,NSEventTypeLeftMouseUp,title)];Check(begins==1&&ends==1&&clicks==2,@"title events keep begin/end native drag callbacks without learning");
    [card installCollapseControl];NSPoint collapse=NSMakePoint(NSMidX(card.collapseButton.frame),NSMidY(card.collapseButton.frame));[card mouseDown:Event(card,NSEventTypeLeftMouseDown,collapse)];Check(card.collapsePressed&&card.collapseButton.highlighted,@"native collapse press highlights actual control");
    [card mouseUp:Event(card,NSEventTypeLeftMouseUp,collapse)];Check(collapses==1&&clicks==2&&!card.collapsePressed&&!card.collapseButton.highlighted,@"native collapse release clears highlight and invokes only collapse");
    [card mouseDown:Event(card,NSEventTypeLeftMouseDown,collapse)];[card mouseDragged:Event(card,NSEventTypeLeftMouseDragged,NSMakePoint(collapse.x+5,collapse.y))];Check(!card.collapsePressed&&!card.collapseButton.highlighted&&card.pressMovedBeyondThreshold,@"native collapse drag cancels control before release");
    [card mouseUp:Event(card,NSEventTypeLeftMouseUp,collapse)];Check(collapses==1&&clicks==2,@"cancelled collapse drag does not invoke either callback");
    card.titleBarHeight=18;Check([card pointIsInTitleBar:NSMakePoint(10,18)]&&![card pointIsInTitleBar:NSMakePoint(10,18.01)],@"native title compatibility setter is read by actual hit helper");
    [panel close];printf("PASS InlineCardPressUITests: %lu checks; actual native view/event/control behavior\n",(unsigned long)checks);
}return 0;}
