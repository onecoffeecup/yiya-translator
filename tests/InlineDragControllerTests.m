#import "presentation/FYInlineDragController.h"
#import "inline/FYInlineOverlayViews.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface DragContentFact : NSObject
@property(nonatomic) BOOL longCard,patch,dragEnabled,showsDragHint;
@property(nonatomic) CGFloat titleBarHeight;
@property(nonatomic,copy) void (^onDragBegan)(void);
@property(nonatomic,copy) void (^onDragEnded)(void);
@end
@implementation DragContentFact
- (BOOL)isKindOfClass:(Class)cls{if(cls==FYInlineLongCardView.class)return self.longCard;if(cls==FYInlinePatchView.class)return self.patch;return [super isKindOfClass:cls];}
@end
@interface DragPanelFact : NSObject
@property(nonatomic,strong) DragContentFact *contentView;
@property(nonatomic) BOOL ignoresMouseEvents;
@end
@implementation DragPanelFact @end
@interface TimerFact : NSObject
@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic) NSUInteger invalidations;
@end
@implementation TimerFact
- (void)invalidate{self.invalidations++;[self.events addObject:@"invalidate"];}
@end
@interface DragProbe : NSObject <FYInlineDragStateSource,FYInlineDragTimerActions>
@property(nonatomic,strong) FYInlineDragController *controller;
@property(nonatomic,strong) NSMutableArray<NSPanel *> *inlineTranslationPanels;
@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic) NSUInteger factories,records;
@property(nonatomic,weak) NSPanel *recordedPanel;
@end
@implementation DragProbe
- (instancetype)init{if((self=[super init])){_controller=[FYInlineDragController new];_events=[NSMutableArray new];_inlineTranslationPanels=[NSMutableArray new];}return self;}
- (NSPanel *)inlineDraggingPanel{return self.controller.inlineDraggingPanel;}
- (void)setInlineDraggingPanel:(NSPanel *)panel{self.controller.inlineDraggingPanel=panel;}
- (NSTimer *)inlineModifierTimer{[self.events addObject:@"get_timer"];return self.controller.inlineModifierTimer;}
- (void)setInlineModifierTimer:(NSTimer *)timer{[self.events addObject:timer?@"set_timer":@"clear_timer"];self.controller.inlineModifierTimer=timer;}
- (BOOL)inlineOptionDragArmed{[self.events addObject:@"get_armed"];return self.controller.inlineOptionDragArmed;}
- (void)setInlineOptionDragArmed:(BOOL)value{[self.events addObject:value?@"arm":@"disarm"];self.controller.inlineOptionDragArmed=value;}
- (NSTimer *)scheduledInlineModifierTimer{[self.events addObject:@"factory"];self.factories++;TimerFact *t=[TimerFact new];t.events=self.events;return (NSTimer *)t;}
- (void)applyInlineDragMode:(BOOL)value{[self.events addObject:@"apply"];[self.controller applyInlineDragMode:value stateSource:self];}
- (void)recordInlineManualOffsetForPanel:(NSPanel *)panel{self.records++;self.recordedPanel=panel;self.inlineDraggingPanel=nil;}
@end
static DragPanelFact *Panel(BOOL longCard,BOOL patch){DragPanelFact *p=[DragPanelFact new];p.contentView=[DragContentFact new];p.contentView.longCard=longCard;p.contentView.patch=patch;p.ignoresMouseEvents=YES;return p;}
int main(void){@autoreleasepool{
    Check(NSApp==nil,@"native drag fixture initializes no app/view/window/control");FYInlineDragController *cold=[FYInlineDragController new];unsigned int n=0;Ivar *ivars=class_copyIvarList(FYInlineDragController.class,&n);free(ivars);Check(n==3&&!cold.inlineModifierTimer&&!cold.inlineDraggingPanel&&!cold.inlineOptionDragArmed,@"cold drag owner has three zero state fields without native work");
    DragProbe *p=[DragProbe new];DragPanelFact *patch=Panel(NO,YES),*longPanel=Panel(YES,NO),*other=Panel(NO,NO);[p.inlineTranslationPanels addObjectsFromArray:@[(NSPanel *)patch,(NSPanel *)longPanel,(NSPanel *)other]];
    [p.controller applyInlineDragMode:YES stateSource:p];Check(p.controller.inlineOptionDragArmed&&!patch.ignoresMouseEvents&&patch.contentView.dragEnabled&&patch.contentView.showsDragHint,@"actual apply arms source and updates native patch interaction/hint");
    Check(!longPanel.ignoresMouseEvents&&!other.ignoresMouseEvents&&!longPanel.contentView.dragEnabled&&!other.contentView.dragEnabled,@"other content types receive only original window passthrough state");
    p.inlineDraggingPanel=(NSPanel *)patch;[p.controller applyInlineDragMode:NO stateSource:p];Check(!p.controller.inlineOptionDragArmed&&!patch.ignoresMouseEvents&&patch.contentView.dragEnabled&&patch.contentView.showsDragHint&&longPanel.ignoresMouseEvents,@"panel being dragged is skipped even when Option disarms others");p.inlineDraggingPanel=nil;
    [p.controller applyInlineDragMode:NO stateSource:p];Check(patch.ignoresMouseEvents&&!patch.contentView.dragEnabled&&!patch.contentView.showsDragHint,@"released panel follows disarmed interaction/hint state");
    FYInlinePlacement *placement=[FYInlinePlacement new];placement.panelPadding=18;placement.titleBandHeight=24;[p.controller wireInlinePanelDrag:(NSPanel *)longPanel placement:placement stateSource:p];Check(longPanel.contentView.titleBarHeight==42&&longPanel.contentView.onDragBegan&&longPanel.contentView.onDragEnded,@"long-card wiring retains original title height and copied callbacks");
    longPanel.contentView.onDragBegan();Check(p.controller.inlineDraggingPanel==(NSPanel *)longPanel,@"actual weak begin callback writes original source dragging panel");longPanel.contentView.onDragEnded();Check(p.records==1&&p.recordedPanel==(NSPanel *)longPanel&&!p.controller.inlineDraggingPanel,@"actual weak end callback invokes source record helper and original panel identity");
    placement.compactEntry=YES;[p.controller wireInlinePanelDrag:(NSPanel *)longPanel placement:placement stateSource:p];Check(longPanel.contentView.titleBarHeight==0,@"compact entry keeps zero title-bar drag area");
    p.controller.inlineOptionDragArmed=YES;[p.controller wireInlinePanelDrag:(NSPanel *)patch placement:placement stateSource:p];Check(patch.contentView.dragEnabled&&patch.contentView.showsDragHint&&patch.contentView.onDragBegan&&patch.contentView.onDragEnded,@"patch wiring reads current armed state and installs weak callbacks");
    [p.events removeAllObjects];[p.controller startInlineModifierMonitorWithSource:p timerActions:p];TimerFact *timer=(TimerFact *)p.controller.inlineModifierTimer;Check([p.events isEqual:@[@"get_timer",@"factory",@"set_timer"]]&&p.factories==1,@"start checks timer before native factory and stores sole resource");
    [p.events removeAllObjects];[p.controller startInlineModifierMonitorWithSource:p timerActions:p];Check([p.events isEqual:@[@"get_timer"]]&&p.factories==1&&p.controller.inlineModifierTimer==(NSTimer *)timer,@"already-started monitor creates no duplicate timer");
    [p.events removeAllObjects];[p.controller stopInlineModifierMonitorWithSource:p];Check([p.events isEqual:@[@"get_timer",@"invalidate",@"clear_timer",@"get_armed",@"apply",@"disarm"]]&&timer.invalidations==1&&!p.controller.inlineModifierTimer&&!p.controller.inlineOptionDragArmed,@"stop preserves invalidate,nil,armed read,concrete apply/disarm order");
    [p.events removeAllObjects];[p.controller stopInlineModifierMonitorWithSource:p];Check([p.events isEqual:@[@"get_timer",@"clear_timer",@"get_armed"]]&&timer.invalidations==1,@"repeated stop keeps original nil-resource behavior without second disarm");
    __weak DragPanelFact *weakPanel;DragContentFact *keptContent;@autoreleasepool{DragPanelFact *temporary=Panel(YES,NO);weakPanel=temporary;keptContent=temporary.contentView;[p.controller wireInlinePanelDrag:(NSPanel *)temporary placement:placement stateSource:p];}Check(!weakPanel,@"copied drag callbacks do not retain panel");NSUInteger before=p.records;keptContent.onDragEnded();Check(p.records==before+1&&!p.recordedPanel,@"released panel is delivered as nil to original source helper");
    __weak DragProbe *weakSource;DragContentFact *afterSource;FYInlineDragController *keptController;@autoreleasepool{DragProbe *temporary=[DragProbe new];weakSource=temporary;keptController=temporary.controller;DragPanelFact *panel=Panel(NO,YES);afterSource=panel.contentView;[keptController wireInlinePanelDrag:(NSPanel *)panel placement:placement stateSource:temporary];}Check(!weakSource,@"idle controller and copied callbacks do not retain concrete source");afterSource.onDragBegan();afterSource.onDragEnded();Check(!keptController.inlineDraggingPanel,@"late callbacks after source release cannot restore stale drag state");
    __weak DragPanelFact *weakDragging;@autoreleasepool{DragPanelFact *temporary=Panel(NO,YES);weakDragging=temporary;p.controller.inlineDraggingPanel=(NSPanel *)temporary;}Check(!weakDragging&&!p.controller.inlineDraggingPanel,@"dragging slot remains weak without hidden panel ownership");
    Check(NSApp==nil,@"all native drag algorithm/resource/weak callback checks create no UI objects");
    printf("PASS InlineDragControllerTests: %lu checks;actual native adapter wiring/apply/timer,synthetic UI facts,unique state and weak lifetimes\n",(unsigned long)checks);
}return 0;}
