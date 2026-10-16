#import "presentation/FYInlineManualPlacementCoordinator.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface ManualPanelFact : NSObject
@property(nonatomic,copy) NSString *identity;
@property(nonatomic) CGRect frame;
@end
@implementation ManualPanelFact @end
@interface ManualProbe : FYInlineManualPlacementCoordinator <FYInlineManualPlacementNativeActions>
@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic,strong) FYInlineLayoutResult *layout;
@property(nonatomic) CGRect viewport;
@property(nonatomic) BOOL hasViewport,displayFlag,nullReason;
@property(nonatomic) NSUInteger offsetReads,ageReads,keyCalls,frameWrites,clears;
@property(nonatomic) CGSize reportedOffset;
@property(nonatomic,copy) void (^duringFrameWrite)(void);
@end
@implementation ManualProbe
- (instancetype)init{if((self=[super init]))_events=[NSMutableArray new];return self;}
- (NSMutableDictionary *)inlineManualOffsets{self.offsetReads++;[self.events addObject:@"offsets"];return [super inlineManualOffsets];}
- (NSMutableDictionary *)inlineManualOffsetAge{self.ageReads++;[self.events addObject:@"ages"];return [super inlineManualOffsetAge];}
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box{self.keyCalls++;[self.events addObject:@"key"];return [super inlineManualOffsetKeyForText:text normalizedBox:box];}
- (void)clearInlineDraggingPanel{self.clears++;[self.events addObject:@"clear_drag"];}
- (NSString *)identifierForManualInlinePanel:(NSPanel *)panel{[self.events addObject:@"identifier"];return ((ManualPanelFact *)panel).identity;}
- (CGRect)frameForManualInlinePanel:(NSPanel *)panel{[self.events addObject:@"frame"];return ((ManualPanelFact *)panel).frame;}
- (void)setManualInlinePanel:(NSPanel *)panel frame:(CGRect)frame display:(BOOL)display{[self.events addObject:@"set_frame"];((ManualPanelFact *)panel).frame=frame;self.frameWrites++;self.displayFlag=display;if(self.duringFrameWrite)self.duringFrameWrite();}
- (FYInlineLayoutResult *)currentLayoutForManualPlacement{[self.events addObject:@"layout"];return self.layout;}
- (BOOL)inlinePlacementRect:(CGRect *)rect reason:(NSString **)reason{[self.events addObject:@"viewport"];self.nullReason=reason==NULL;if(self.hasViewport&&rect)*rect=self.viewport;return self.hasViewport;}
- (void)recordInlineManualDiagnosticText:(NSString *)text offset:(CGSize)offset{[self.events addObject:@"diagnostic"];self.reportedOffset=offset;}
@end
static FYInlinePlacement *Placement(void){FYInlinePlacement *p=[FYInlinePlacement new];p.blockID=@"stable";p.block=[FYInlineTextBlock new];p.block.text=@" A　B \n";p.block.boundingBox=CGRectMake(0,0,.02,.02);p.sourceFrame=CGRectMake(100,100,160,40);p.translationFrame=CGRectMake(112,108,160,40);p.manuallyPlaced=YES;return p;}
int main(void){@autoreleasepool{
    FYInlineManualPlacementCoordinator *cold=[FYInlineManualPlacementCoordinator new];unsigned int n=0;Ivar *ivars=class_copyIvarList(FYInlineManualPlacementCoordinator.class,&n);free(ivars);Check(n==2&&!cold.inlineManualOffsets&&!cold.inlineManualOffsetAge,@"cold owner has only two nil original dictionaries and no native work");
    Check([[cold inlineManualOffsetKeyForText:@" A　B \n" normalizedBox:CGRectMake(0,0,.02,.02)]isEqual:@"AB|1,1"],@"key keeps canonical whitespace normalization and center floor bucket");
    Check([[cold inlineManualOffsetKeyForText:@"" normalizedBox:CGRectMake(-.02,-.02,.02,.02)]isEqual:@"|-1,-1"],@"negative center retains floor rather than truncation");
    ManualProbe *p=[ManualProbe new];NSMutableDictionary<NSString *,NSValue *> *offsets=[NSMutableDictionary new];NSMutableDictionary<NSString *,NSNumber *> *ages=[NSMutableDictionary new];p.inlineManualOffsets=offsets;p.inlineManualOffsetAge=ages;
    NSValue *first=@(CGSizeMake(3,4)),*center=@(CGSizeMake(5,6)),*last=@(CGSizeMake(7,8));offsets[@"AB|0,0"]=first;offsets[@"AB|1,1"]=center;p.offsetReads=0;
    Check([p inlineManualOffsetForText:@"AB" normalizedBox:CGRectMake(0,0,.02,.02) stateSource:p]==first&&p.offsetReads==1,@"dx/dy order intentionally finds earlier neighbor before own bucket");
    [offsets removeAllObjects];offsets[@"AB|2,2"]=last;p.offsetReads=0;Check([p inlineManualOffsetForText:@"AB" normalizedBox:CGRectMake(0,0,.02,.02) stateSource:p]==last&&p.offsetReads==9,@"last neighbor retains all nine original dictionary getter reads");
    p.offsetReads=0;Check(![p inlineManualOffsetForText:@"different" normalizedBox:CGRectMake(0,0,.02,.02) stateSource:p]&&p.offsetReads==9,@"text identity prevents other block offset reuse without changing search order");
    p.inlineManualOffsets=nil;p.offsetReads=0;Check(![p inlineManualOffsetForText:@"AB" normalizedBox:CGRectMake(0,0,.02,.02) stateSource:p]&&p.offsetReads==9,@"nil dictionary preserves original silent lookup and getter count");p.inlineManualOffsets=offsets;
    [p.events removeAllObjects];[p recordInlineManualOffsetForPanel:nil stateSource:p nativeActions:p];Check([p.events isEqual:@[@"clear_drag"]],@"nil panel still releases drag lock before any other work");
    ManualPanelFact *panel=[ManualPanelFact new];panel.identity=@"";[p.events removeAllObjects];[p recordInlineManualOffsetForPanel:(NSPanel *)panel stateSource:p nativeActions:p];Check([p.events isEqual:@[@"clear_drag",@"identifier"]],@"empty identifier guard follows drag reset and does not read layout/frame");
    panel.identity=@"missing";[p.events removeAllObjects];[p recordInlineManualOffsetForPanel:(NSPanel *)panel stateSource:p nativeActions:p];Check([p.events isEqual:@[@"clear_drag",@"identifier",@"layout",@"identifier"]],@"missing layout retains original two identifier reads and no frame work");
    FYInlinePlacement *placement=Placement();p.layout=[FYInlineLayoutResult new];p.layout.placements=@[placement];panel.identity=@"stable";panel.frame=CGRectMake(.2,-2.1,120.4,50.4);p.hasViewport=YES;p.viewport=CGRectMake(0,0,300,200);[p.events removeAllObjects];
    [p recordInlineManualOffsetForPanel:(NSPanel *)panel stateSource:p nativeActions:p];
    Check(CGRectEqualToRect(panel.frame,CGRectMake(4,4,121,51))&&p.frameWrites==1&&p.displayFlag&&p.nullReason,@"actual clamp keeps four-point edge and integral expansion,display:YES,NULL reason");
    Check([p.events isEqual:@[@"clear_drag",@"identifier",@"layout",@"identifier",@"frame",@"viewport",@"frame",@"set_frame",@"key",@"offsets",@"ages",@"diagnostic"]],@"record keeps original identifier/layout/frame/viewport/apply/key/cache/diagnostic order");
    Check(offsets[@"AB|1,1"]&&NSEqualSizes(offsets[@"AB|1,1"].sizeValue,CGSizeMake(-96,-96))&&[ages[@"AB|1,1"]isEqual:@0]&&CGSizeEqualToSize(p.reportedOffset,CGSizeMake(-96,-96)),@"record stores original offset from source and resets age before reporting");
    [p recordInlineManualOffsetForPanel:(NSPanel *)panel stateSource:p nativeActions:p];Check(p.frameWrites==1,@"unchanged integral frame does not trigger another native apply");
    p.hasViewport=NO;panel.frame=CGRectMake(11.25,12.5,120.4,50.4);[p recordInlineManualOffsetForPanel:(NSPanel *)panel stateSource:p nativeActions:p];Check(CGRectEqualToRect(panel.frame,CGRectMake(11.25,12.5,120.4,50.4))&&p.frameWrites==1&&CGSizeEqualToSize(p.reportedOffset,CGSizeMake(-88.75,-87.5)),@"missing viewport retains unrounded original frame and fractional offset");
    p.hasViewport=YES;p.viewport=CGRectMake(10,20,80,60);panel.frame=CGRectMake(900,900,200,100);[p recordInlineManualOffsetForPanel:(NSPanel *)panel stateSource:p nativeActions:p];Check(CGRectEqualToRect(panel.frame,CGRectMake(14,24,200,100)),@"oversize panel clamps to original near edge instead of shrinking");
    placement.translationFrame=CGRectMake(112,108,160,40);[offsets removeAllObjects];[ages removeAllObjects];offsets[@"recent"]=first;ages[@"recent"]=@0;offsets[@"old"]=last;ages[@"old"]=@2;p.keyCalls=0;
    [p maintainOffsetsForPlacements:@[placement] stateSource:p];Check(NSEqualSizes(offsets[@"AB|1,1"].sizeValue,CGSizeMake(12,8))&&[ages[@"AB|1,1"]isEqual:@0]&&p.keyCalls==1,@"per-frame maintenance uses concrete key helper and current source/translation anchor");
    Check(offsets[@"recent"]&&[ages[@"recent"]isEqual:@1]&&!offsets[@"old"]&&!ages[@"old"],@"original age>2 boundary expires both dictionaries and retains recent offset");
    [p maintainOffsetsForPlacements:@[] stateSource:p];Check([ages[@"recent"]isEqual:@2]&&offsets[@"recent"],@"two missing frames remain within original retention window");
    [p maintainOffsetsForPlacements:@[] stateSource:p];Check(!offsets[@"recent"]&&!ages[@"recent"],@"third missing frame removes only expired manual entry");
    [offsets removeAllObjects];[ages removeAllObjects];FYInlinePlacement *automatic=Placement();automatic.manuallyPlaced=NO;FYInlinePlacement *empty=Placement();empty.block.text=@"";p.keyCalls=0;[p maintainOffsetsForPlacements:@[automatic,empty] stateSource:p];Check(!offsets.count&&!ages.count&&p.keyCalls==0,@"automatic and empty-source placements never introduce manual keys");
    placement.block.boundingBox=CGRectMake(.02,.02,.02,.02);[p maintainOffsetsForPlacements:@[placement] stateSource:p];Check(offsets[@"AB|3,3"]&&[p inlineManualOffsetForText:@"AB" normalizedBox:CGRectMake(.01,.01,.02,.02) stateSource:p],@"current-frame rekey follows block movement and neighboring bucket can recover it");
    p.inlineManualOffsets=nil;p.inlineManualOffsetAge=nil;[p maintainOffsetsForPlacements:@[placement] stateSource:p];Check(!p.inlineManualOffsets&&!p.inlineManualOffsetAge,@"nil dictionary maintenance does not fabricate state or change old no-op semantics");
    FYInlineManualPlacementCoordinator *independent=[FYInlineManualPlacementCoordinator new];__weak ManualProbe *weak;@autoreleasepool{ManualProbe *temporary=[ManualProbe new];weak=temporary;[independent recordInlineManualOffsetForPanel:nil stateSource:temporary nativeActions:temporary];Check(temporary.clears==1,@"synchronous native source receives actual early reset");}Check(!weak&&!independent.inlineManualOffsets,@"completed operation retains no idle native/source context or duplicate dictionary");
    p.inlineManualOffsets=offsets;p.inlineManualOffsetAge=ages;Check([p inlineManualOffsets]==offsets&&[p inlineManualOffsetAge]==ages,@"dictionary setters keep original mutable alias identity");
    printf("PASS InlineManualPlacementTests: %lu checks;actual key/lookup/record/clamp/rekey/age,source getter order,nil aliases and lifecycle\n",(unsigned long)checks);
}return 0;}
