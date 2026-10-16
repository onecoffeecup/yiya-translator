#import "inline/FYInlineCardPressState.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
// Probe only native actions and original getter/setter access. All gesture
// decisions execute the inherited production implementation and its state.
@interface PressProbe : FYInlineCardPressState <FYInlineCardPressNativeActions>
@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic) BOOL hitCollapse;
@property(nonatomic) NSUInteger clicks,collapses;
@property(nonatomic,copy) void (^onClickAction)(void);
@end
@implementation PressProbe
- (instancetype)init{self=[super init];if(self)_events=[NSMutableArray new];return self;}
- (NSPoint)pressPoint{[self.events addObject:@"get_point"];return [super pressPoint];}
- (void)setPressPoint:(NSPoint)value{[self.events addObject:@"set_point"];[super setPressPoint:value];}
- (BOOL)pressMovedBeyondThreshold{[self.events addObject:@"get_moved"];return [super pressMovedBeyondThreshold];}
- (void)setPressMovedBeyondThreshold:(BOOL)value{[self.events addObject:value?@"set_moved:1":@"set_moved:0"];[super setPressMovedBeyondThreshold:value];}
- (BOOL)collapsePressed{[self.events addObject:@"get_collapse"];return [super collapsePressed];}
- (void)setCollapsePressed:(BOOL)value{[self.events addObject:value?@"set_collapse:1":@"set_collapse:0"];[super setCollapsePressed:value];}
- (CGFloat)titleBarHeight{[self.events addObject:@"get_title"];return [super titleBarHeight];}
- (BOOL)pointIsInCollapseControl:(NSPoint)point{[self.events addObject:@"hit_collapse"];return self.hitCollapse;}
- (BOOL)pointIsInTitleBar:(NSPoint)point{[self.events addObject:@"hit_title"];return [super pointIsInTitleBar:point stateSource:self];}
- (void)setCollapseControlHighlighted:(BOOL)value{[self.events addObject:value?@"highlight:1":@"highlight:0"];}
- (void)performCollapseAfterPressRelease{[self.events addObject:@"collapse"];self.collapses++;}
- (void)performClickAfterPressRelease{[self.events addObject:@"click"];self.clicks++;if(self.onClickAction)self.onClickAction();}
@end
int main(void){@autoreleasepool{
    FYInlineCardPressState *cold=[FYInlineCardPressState new];unsigned int n=0;Ivar *ivars=class_copyIvarList(FYInlineCardPressState.class,&n);free(ivars);
    Check(n==4&&NSEqualPoints(cold.pressPoint,NSZeroPoint)&&!cold.pressMovedBeyondThreshold&&!cold.collapsePressed&&cold.titleBarHeight==0,@"cold state owns only four original zero scalars, without native work");
    PressProbe *p=[PressProbe new];p.titleBarHeight=55;p.collapsePressed=YES;p.pressMovedBeyondThreshold=YES;[p.events removeAllObjects];
    [p beginPressAtPoint:NSMakePoint(10,20) stateSource:p];
    Check([p.events isEqual:@[@"set_point",@"set_moved:0"]],@"press begins with original point then moved reset setter order");
    Check(NSEqualPoints(p.pressPoint,NSMakePoint(10,20))&&!p.pressMovedBeyondThreshold&&p.collapsePressed,@"press begin deliberately retains preexisting collapse state");
    [p.events removeAllObjects];[p dragPressToPoint:NSMakePoint(14,20) stateSource:p nativeActions:p];
    Check([p.events isEqual:@[@"get_point",@"get_point"]],@"exact four-point movement reads original point twice without marking drag");
    Check(!p.pressMovedBeyondThreshold&&p.collapsePressed,@"strict threshold leaves collapse press active at four points");
    [p.events removeAllObjects];[p dragPressToPoint:NSMakePoint(14.001,20) stateSource:p nativeActions:p];
    Check([p.events isEqual:@[@"get_point",@"get_point",@"set_moved:1",@"get_collapse",@"set_collapse:0",@"highlight:0"]],@"drag above threshold marks moved then clears collapse before native highlight");
    Check(p.pressMovedBeyondThreshold&&!p.collapsePressed,@"drag suppresses collapse state");
    [p.events removeAllObjects];[p releasePressAtPoint:NSMakePoint(14.001,20) stateSource:p nativeActions:p];
    Check([p.events isEqual:@[@"get_collapse",@"get_moved"]]&&p.clicks==0&&p.collapses==0,@"drag release neither queries controls nor invokes learning/collapse");
    [p beginPressAtPoint:NSMakePoint(10,100) stateSource:p];p.collapsePressed=YES;p.hitCollapse=YES;[p.events removeAllObjects];
    [p releasePressAtPoint:NSMakePoint(10,100) stateSource:p nativeActions:p];
    Check([p.events isEqual:@[@"get_collapse",@"set_collapse:0",@"highlight:0",@"get_moved",@"hit_collapse",@"collapse"]],@"collapse release clears state/highlight before moved and hit checks, then native callback");
    Check(p.collapses==1&&p.clicks==0&&!p.collapsePressed,@"collapse release does not fall through to learning");
    p.collapsePressed=YES;p.hitCollapse=NO;[p.events removeAllObjects];[p releasePressAtPoint:NSMakePoint(100,100) stateSource:p nativeActions:p];
    Check([p.events isEqual:@[@"get_collapse",@"set_collapse:0",@"highlight:0",@"get_moved",@"hit_collapse"]]&&p.collapses==1&&p.clicks==0,@"release outside collapse clears highlight and does not trigger learning");
    p.collapsePressed=YES;p.pressMovedBeyondThreshold=YES;[p.events removeAllObjects];[p releasePressAtPoint:NSMakePoint(10,100) stateSource:p nativeActions:p];
    Check([p.events isEqual:@[@"get_collapse",@"set_collapse:0",@"highlight:0",@"get_moved"]],@"moved collapse release short-circuits native hit query");
    p.pressMovedBeyondThreshold=NO;[p.events removeAllObjects];[p releasePressAtPoint:NSMakePoint(10,55) stateSource:p nativeActions:p];
    Check([p.events isEqual:@[@"get_collapse",@"get_moved",@"hit_title",@"get_title"]]&&p.clicks==0,@"title-bar release includes exact upper boundary and suppresses learning");
    [p.events removeAllObjects];[p releasePressAtPoint:NSMakePoint(10,55.001) stateSource:p nativeActions:p];
    Check([p.events isEqual:@[@"get_collapse",@"get_moved",@"hit_title",@"get_title",@"click"]]&&p.clicks==1,@"body release keeps native title query before click callback");
    [p.events removeAllObjects];Check(![p pointIsInTitleBar:NSMakePoint(10,-.01) stateSource:p]&&p.events.count==0,@"negative local Y short-circuits title-height getter");
    Check([p pointIsInTitleBar:NSMakePoint(10,0) stateSource:p]&&[p pointIsInTitleBar:NSMakePoint(10,55) stateSource:p],@"title-bar zero and upper boundaries remain inclusive");
    p.collapsePressed=NO;[p beginPressAtPoint:NSMakePoint(0,0) stateSource:p];[p dragPressToPoint:NSMakePoint(3,3) stateSource:p nativeActions:p];Check(p.pressMovedBeyondThreshold,@"drag distance retains true Euclidean diagonal threshold");
    [p beginPressAtPoint:NSMakePoint(0,0) stateSource:p];[p dragPressToPoint:NSMakePoint(-4,0) stateSource:p nativeActions:p];Check(!p.pressMovedBeyondThreshold,@"negative movement at threshold remains a click");
    [p dragPressToPoint:NSMakePoint(-4.1,0) stateSource:p nativeActions:p];Check(p.pressMovedBeyondThreshold,@"negative movement beyond threshold is a drag");
    [p beginPressAtPoint:NSMakePoint(0,0) stateSource:p];[p dragPressToPoint:NSMakePoint(NAN,0) stateSource:p nativeActions:p];Check(!p.pressMovedBeyondThreshold,@"nonfinite distance retains original comparison behavior");
    [p beginPressAtPoint:NSMakePoint(0,0) stateSource:p];[p dragPressToPoint:NSMakePoint(INFINITY,0) stateSource:p nativeActions:p];Check(p.pressMovedBeyondThreshold,@"infinite distance follows original strict comparison");
    FYInlineCardPressState *algorithm=[FYInlineCardPressState new];__weak PressProbe *weakSource;
    @autoreleasepool{PressProbe *temporary=[PressProbe new];weakSource=temporary;temporary.titleBarHeight=55;[algorithm beginPressAtPoint:NSMakePoint(10,100) stateSource:temporary];[algorithm releasePressAtPoint:NSMakePoint(10,100) stateSource:temporary nativeActions:temporary];Check(temporary.clicks==1&&NSEqualPoints(algorithm.pressPoint,NSZeroPoint),@"synchronous explicit source holds sole state; algorithm retains no duplicate values");}
    Check(!weakSource,@"operation completion releases explicit state/native source with no idle lease");
    __weak PressProbe *weak=p;__block BOOL nested=NO;p.onClickAction=^{PressProbe *active=weak;[active beginPressAtPoint:NSMakePoint(2,3) stateSource:active];nested=YES;};[p beginPressAtPoint:NSMakePoint(10,100) stateSource:p];[p releasePressAtPoint:NSMakePoint(10,100) stateSource:p nativeActions:p];
    Check(nested&&NSEqualPoints(p.pressPoint,NSMakePoint(2,3))&&!p.pressMovedBeyondThreshold,@"native callback reentry writes the original owner without a late state reset");
    p.onClickAction=^{@throw [NSException exceptionWithName:@"synthetic-click" reason:@"fixture" userInfo:nil];};BOOL threw=NO;@try{[p releasePressAtPoint:NSMakePoint(10,100) stateSource:p nativeActions:p];}@catch(NSException *e){threw=[e.name isEqual:@"synthetic-click"];}
    Check(threw,@"native callback exception retains original propagation");
    printf("PASS InlineCardPressStateTests: %lu checks; actual gesture decisions, getter/action order, thresholds, reentry and source lifetime\n",(unsigned long)checks);
}return 0;}
