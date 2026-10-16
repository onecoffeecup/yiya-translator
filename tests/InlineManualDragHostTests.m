#import "presentation/FYInlineOverlayController.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface HostDragContentFact : NSObject
@property(nonatomic) BOOL longCard,patch,dragEnabled,showsDragHint;
@property(nonatomic) CGFloat titleBarHeight;
@property(nonatomic,copy) void (^onDragBegan)(void);
@property(nonatomic,copy) void (^onDragEnded)(void);
@end
@implementation HostDragContentFact
- (BOOL)isKindOfClass:(Class)cls{if(cls==FYInlineLongCardView.class)return self.longCard;if(cls==FYInlinePatchView.class)return self.patch;return [super isKindOfClass:cls];}
@end
@interface HostDragPanelFact : NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic) CGRect frame;
@property(nonatomic,strong) HostDragContentFact *contentView;
@property(nonatomic) BOOL ignoresMouseEvents,lastDisplay;
@property(nonatomic) NSUInteger frameWrites;
@end
@implementation HostDragPanelFact
- (void)setFrame:(CGRect)frame display:(BOOL)display{_frame=frame;self.lastDisplay=display;self.frameWrites++;}
@end
@interface ManualDragPeer : NSObject
@property(nonatomic) NSUInteger ticks;
@end
@implementation ManualDragPeer
- (BOOL)inlinePlacementRect:(NSRect *)rect reason:(NSString **)reason{if(rect)*rect=CGRectMake(0,0,300,200);return YES;}
- (void)inlineModifierTick:(NSTimer *)timer{self.ticks++;}
@end
static FYInlinePlacement *Placement(void){FYInlinePlacement *p=[FYInlinePlacement new];p.blockID=@"stable";p.block=[FYInlineTextBlock new];p.block.text=@" A　B ";p.block.boundingBox=CGRectMake(0,0,.02,.02);p.sourceFrame=CGRectMake(100,100,160,40);p.translationFrame=CGRectMake(112,108,160,40);p.panelPadding=18;p.titleBandHeight=24;return p;}
int main(void){@autoreleasepool{
    Check(NSApp==nil,@"exact native manual/drag host fixture creates no application or window");
    ManualDragPeer *peer=[ManualDragPeer new];FYInlineOverlayController *p=[[FYInlineOverlayController alloc]initWithHost:(id<FYInlineOverlayControllerHost>)peer];p.inlineManualOffsets=[NSMutableDictionary new];p.inlineManualOffsetAge=[NSMutableDictionary new];p.inlineTranslationPanels=[NSMutableArray new];FYInlinePlacement *placement=Placement();p.lastInlineLayoutResult=[FYInlineLayoutResult new];p.lastInlineLayoutResult.placements=@[placement];
    Check([[p inlineManualOffsetKeyForText:@" A　B " normalizedBox:placement.block.boundingBox]isEqual:@"AB|1,1"],@"actual host key normalization/quantization matches original");
    NSValue *early=@(NSMakeSize(2,3)),*center=@(NSMakeSize(4,5));p.inlineManualOffsets[@"AB|0,0"]=early;p.inlineManualOffsets[@"AB|1,1"]=center;Check([p inlineManualOffsetForText:@"AB" normalizedBox:placement.block.boundingBox]==early,@"actual host keeps neighbor-before-own-bucket lookup order");
    HostDragPanelFact *panel=[HostDragPanelFact new];panel.identifier=@"stable";panel.frame=CGRectMake(.2,-2.1,120.4,50.4);panel.contentView=[HostDragContentFact new];panel.contentView.longCard=YES;p.inlineDraggingPanel=(NSPanel *)panel;
    [p recordInlineManualOffsetForPanel:(NSPanel *)panel];Check(!p.inlineDraggingPanel&&CGRectEqualToRect(panel.frame,CGRectMake(4,4,121,51))&&panel.frameWrites==1&&panel.lastDisplay,@"actual native record clears drag,clamps/integralizes and applies display:YES");
    Check(NSEqualSizes(p.inlineManualOffsets[@"AB|1,1"].sizeValue,NSMakeSize(-96,-96))&&[p.inlineManualOffsetAge[@"AB|1,1"]isEqual:@0],@"actual host stores offset from same placement/source identity");
    p.inlineDraggingPanel=(NSPanel *)panel;[p recordInlineManualOffsetForPanel:nil];Check(!p.inlineDraggingPanel&&panel.frameWrites==1,@"nil record preserves early reset without native frame update");
    [p wireInlinePanelDrag:(NSPanel *)panel placement:placement];Check(panel.contentView.titleBarHeight==42&&panel.contentView.onDragBegan&&panel.contentView.onDragEnded,@"actual native long-card wiring keeps geometry and both weak callbacks");
    panel.contentView.onDragBegan();Check(p.inlineDraggingPanel==(NSPanel *)panel,@"actual native begin callback uses original concrete source");panel.contentView.onDragEnded();Check(!p.inlineDraggingPanel&&panel.frameWrites==1,@"actual native end callback records same already-clamped panel");
    placement.compactEntry=YES;[p wireInlinePanelDrag:(NSPanel *)panel placement:placement];Check(panel.contentView.titleBarHeight==0,@"actual compact wiring keeps zero title drag region");
    HostDragPanelFact *patch=[HostDragPanelFact new];patch.contentView=[HostDragContentFact new];patch.contentView.patch=YES;patch.ignoresMouseEvents=YES;[p.inlineTranslationPanels addObject:(NSPanel *)patch];[p applyInlineDragMode:YES];Check(p.inlineOptionDragArmed&&!patch.ignoresMouseEvents&&patch.contentView.dragEnabled&&patch.contentView.showsDragHint,@"actual native arm updates patch passthrough/drag/hint");
    p.inlineDraggingPanel=(NSPanel *)patch;[p applyInlineDragMode:NO];Check(!p.inlineOptionDragArmed&&!patch.ignoresMouseEvents&&patch.contentView.dragEnabled,@"actual native disarm skips the panel currently dragged");p.inlineDraggingPanel=nil;[p applyInlineDragMode:NO];Check(patch.ignoresMouseEvents&&!patch.contentView.dragEnabled&&!patch.contentView.showsDragHint,@"actual native released panel follows disarmed state");
    [p startInlineModifierMonitor];NSTimer *timer=p.inlineModifierTimer;Check(timer&&timer.valid&&fabs(timer.timeInterval-.1)<.00001,@"actual original/extracted monitor uses real scheduled0.1s native timer");[p startInlineModifierMonitor];Check(p.inlineModifierTimer==timer,@"actual native repeated start retains same timer");
    [p applyInlineDragMode:YES];[p stopInlineModifierMonitor];Check(!p.inlineModifierTimer&&!timer.valid&&!p.inlineOptionDragArmed&&patch.ignoresMouseEvents,@"actual native stop invalidates timer,releases owner and disarms patch");
    __weak FYInlineOverlayController *weak;HostDragContentFact *kept;@autoreleasepool{FYInlineOverlayController *temporary=[[FYInlineOverlayController alloc]initWithHost:nil];HostDragPanelFact *q=[HostDragPanelFact new];q.contentView=[HostDragContentFact new];q.contentView.longCard=YES;kept=q.contentView;weak=temporary;[temporary wireInlinePanelDrag:(NSPanel *)q placement:placement];}Check(!weak,@"actual native copied callbacks do not retain concrete controller");kept.onDragBegan();kept.onDragEnded();
    Check(NSApp==nil,@"all actual native manual/drag/timer checks remain headless with synthetic UI facts");
    printf("PASS InlineManualDragHostTests: %lu checks;exact source original/extracted native controller,actual timer/callback/manual algorithms,no UI objects\n",(unsigned long)checks);
}return 0;}
